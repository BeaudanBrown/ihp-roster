import {
    dialogCloseDomAttr,
    dialogDismissedEvent,
    parsePasskeyFlowConfig,
    passkeyActionButtonDomAttr,
    passkeyAdditionalDeviceMode,
    passkeyDeviceNameDomAttr,
    passkeyDismissalDomAttr,
    passkeyFirstPasskeyMode,
    passkeyFlowConfigDomAttr,
    passkeyLoginDomAttr,
    passkeyRecoveryDomAttr,
    passkeyRegistrationDomAttr,
    passkeySetupPromptDomAttr,
    passkeyStatusDomAttr,
    type PasskeyFlowConfig,
} from "./generated/contracts";
import { arrayBufferToBase64Url, base64UrlToArrayBuffer } from "./passkeys/base64url";
import { localStorageKeyForPasskey, type PasskeyStorageKey } from "./passkeys/storage";
import { isDomRoot } from "./shared/dom";
import { assertNever } from "./shared/exhaustive";
import { detailTarget, onAppPageReady } from "./shared/lifecycle";

export { arrayBufferToBase64Url, base64UrlToArrayBuffer, localStorageKeyForPasskey };

type JsonObject = Record<string, any>;
type PasskeyTone = "info" | "success" | "danger" | "warning";
type PasskeyStatusFlowConfig = Extract<PasskeyFlowConfig, { tag: "login" | "registration" }>;
type PasskeyPromptFlowConfig = Extract<PasskeyFlowConfig, { tag: "setup-prompt" }>;

type PasskeyFinishResponse = {
    userId?: string;
    redirectTo?: string;
    recoveryCode?: string;
};

class PasskeyStatusError extends Error {
    constructor(readonly statusMessage: string) {
        super(statusMessage);
    }
}

type RegistrationCredentialPayload = {
    rawId: string;
    response: {
        clientDataJSON: string;
        attestationObject: string;
        transports: string[];
    };
    clientExtensionResults: AuthenticationExtensionsClientOutputs;
    name?: string;
};

type AuthenticationCredentialPayload = {
    rawId: string;
    response: {
        clientDataJSON: string;
        authenticatorData: string;
        signature: string;
        userHandle: string | null;
    };
    clientExtensionResults: AuthenticationExtensionsClientOutputs;
};

export type PasskeyDiagnosticCode =
    | "invalid-flow-config"
    | "invalid-flow-role"
    | "invalid-action-relationship"
    | "invalid-device-name-relationship"
    | "invalid-status-relationship"
    | "invalid-recovery-relationship"
    | "invalid-dismissal-relationship"
    | "invalid-overlay-dismissal-role";

export type PasskeyDiagnostic = {
    code: PasskeyDiagnosticCode;
    elementId: string | null;
    message: string;
};

export type PasskeyDiagnosticReporter = (diagnostic: PasskeyDiagnostic) => void;

type PasskeyStatusControl = {
    message: HTMLElement;
    region: HTMLElement;
    recovery: HTMLElement | null;
    recoveryCode: HTMLElement | null;
};

type PasskeyLoginControl = {
    root: HTMLElement;
    action: HTMLButtonElement;
    config: Extract<PasskeyFlowConfig, { tag: "login" }>;
    status: PasskeyStatusControl;
};

type PasskeyRegistrationControl = {
    root: HTMLElement;
    action: HTMLButtonElement;
    config: Extract<PasskeyFlowConfig, { tag: "registration" }>;
    deviceName: HTMLInputElement;
    status: PasskeyStatusControl;
};

type PasskeyPromptControl = {
    root: HTMLElement;
    config: PasskeyPromptFlowConfig;
    dismissal: HTMLButtonElement;
};

const initializedPasskeyFlows = new WeakSet<HTMLElement>();
const automaticPromptDismissals = new WeakSet<HTMLElement>();
const passkeyFlowSelector = [
    passkeyLoginDomAttr,
    passkeyRegistrationDomAttr,
    passkeySetupPromptDomAttr,
].map(roleSelector).join(",");

export function parsePasskeyFlowConfiguration(raw: string): PasskeyFlowConfig {
    const config = parsePasskeyFlowConfig(JSON.parse(raw) as unknown);
    switch (config.tag) {
        case "login":
        case "registration":
            requirePasskeyConfigText("begin URL", config.beginUrl);
            requirePasskeyConfigText("finish URL", config.finishUrl);
            if (config.successRedirect !== undefined) {
                requirePasskeyConfigText("success redirect", config.successRedirect);
            }
            requirePasskeyConfigText("status relationship", config.statusKey);
            requirePasskeyConfigText("waiting message", config.waitingMessage);
            requirePasskeyConfigText("success message", config.successMessage);
            requirePasskeyConfigText("unsupported message", config.unsupportedMessage);
            requirePasskeyConfigText("failure message", config.failureMessage);
            requirePasskeyConfigText("pending label", config.pendingLabel);
            requirePasskeyConfigText("cancelled message", config.cancelledMessage);
            return config;
        case "setup-prompt":
            requirePasskeyConfigText("prompt user key", config.promptUserKey);
            return config;
        default:
            return assertNever(config, "Unexpected generated passkey flow");
    }
}

function requirePasskeyConfigText(fieldName: string, value: string): void {
    if (value.trim().length === 0) {
        throw new Error(`PasskeyFlowConfig ${fieldName} must not be empty`);
    }
}

function roleSelector(attribute: string): string {
    return `[${attribute}]`;
}

function defaultDiagnosticReporter(diagnostic: PasskeyDiagnostic): void {
    console.error?.("Invalid generated passkey configuration", diagnostic);
}

function diagnostic(
    element: Element,
    code: PasskeyDiagnosticCode,
    message: string,
): PasskeyDiagnostic {
    return {
        code,
        elementId: element.id || null,
        message,
    };
}

function rootsWithRole(root: Document | DocumentFragment | Element, attribute: string): HTMLElement[] {
    const selector = roleSelector(attribute);
    const roots = Array.from(root.querySelectorAll<HTMLElement>(selector));
    if (root instanceof HTMLElement && root.matches(selector)) roots.unshift(root);
    return roots;
}

function ownedElements<T extends Element>(root: HTMLElement, attribute: string): T[] {
    return Array.from(root.querySelectorAll<T>(roleSelector(attribute)))
        .filter((element) => element.closest(passkeyFlowSelector) === root);
}

function roleIsTrue(element: Element, attribute: string): boolean {
    return element.getAttribute(attribute) === "true";
}

function parseFlowForRoot(
    root: HTMLElement,
    report: PasskeyDiagnosticReporter,
): PasskeyFlowConfig | null {
    const rawConfig = root.getAttribute(passkeyFlowConfigDomAttr);
    try {
        if (rawConfig === null) throw new Error(`Missing ${passkeyFlowConfigDomAttr}`);
        return parsePasskeyFlowConfiguration(rawConfig);
    } catch (error) {
        report(diagnostic(
            root,
            "invalid-flow-config",
            error instanceof Error ? error.message : String(error),
        ));
        return null;
    }
}

function expectedFlowRole(config: PasskeyFlowConfig): string {
    switch (config.tag) {
        case "login":
            return passkeyLoginDomAttr;
        case "registration":
            return passkeyRegistrationDomAttr;
        case "setup-prompt":
            return passkeySetupPromptDomAttr;
        default:
            return assertNever(config, "Unexpected generated passkey flow");
    }
}

function validateFlowRole(
    root: HTMLElement,
    config: PasskeyFlowConfig,
    report: PasskeyDiagnosticReporter,
): boolean {
    const expected = expectedFlowRole(config);
    const roleAttributes = [
        passkeyLoginDomAttr,
        passkeyRegistrationDomAttr,
        passkeySetupPromptDomAttr,
    ].filter((attribute) => root.hasAttribute(attribute));
    if (roleAttributes.length !== 1 || roleAttributes[0] !== expected || !roleIsTrue(root, expected)) {
        report(diagnostic(root, "invalid-flow-role", `Passkey flow ${config.tag} must have exactly its generated root role`));
        return false;
    }
    return true;
}

function readAction(
    root: HTMLElement,
    report: PasskeyDiagnosticReporter,
): HTMLButtonElement | null {
    const actions = ownedElements<Element>(root, passkeyActionButtonDomAttr);
    if (actions.length !== 1 || !(actions[0] instanceof HTMLButtonElement) || !roleIsTrue(actions[0], passkeyActionButtonDomAttr)) {
        report(diagnostic(root, "invalid-action-relationship", "Passkey login or registration requires one local generated action button"));
        return null;
    }
    return actions[0];
}

function readStatus(
    root: HTMLElement,
    config: PasskeyStatusFlowConfig,
    expectsRecovery: boolean,
    report: PasskeyDiagnosticReporter,
): PasskeyStatusControl | null {
    const messages = ownedElements<HTMLElement>(root, passkeyStatusDomAttr)
        .filter((element) => element.getAttribute(passkeyStatusDomAttr) === config.statusKey);
    if (messages.length !== 1) {
        report(diagnostic(root, "invalid-status-relationship", "Passkey flow requires one matching local generated status relationship"));
        return null;
    }

    const message = messages[0];
    const region = message.parentElement;
    if (!(region instanceof HTMLElement) || region.getAttribute("role") !== "status" || message.closest(passkeyFlowSelector) !== root) {
        report(diagnostic(message, "invalid-status-relationship", "Passkey status must be inside its local native status region"));
        return null;
    }

    const recoveries = ownedElements<HTMLElement>(root, passkeyRecoveryDomAttr)
        .filter((element) => element.getAttribute(passkeyRecoveryDomAttr) === config.statusKey);
    if (recoveries.length !== (expectsRecovery ? 1 : 0)) {
        report(diagnostic(root, "invalid-recovery-relationship", `Passkey flow requires ${expectsRecovery ? 1 : 0} local recovery region(s)`));
        return null;
    }

    if (!expectsRecovery) {
        return { message, region, recovery: null, recoveryCode: null };
    }

    const recovery = recoveries[0];
    const recoveryCodes = Array.from(recovery.querySelectorAll<HTMLElement>("code"))
        .filter((element) => element.closest(passkeyFlowSelector) === root);
    const recoveryLinks = Array.from(recovery.querySelectorAll<HTMLAnchorElement>("a"))
        .filter((element) => element.closest(passkeyFlowSelector) === root);
    const expectedLinkCount = config.successRedirect === undefined ? 0 : 1;
    if (recoveryCodes.length !== 1 || recoveryLinks.length !== expectedLinkCount) {
        report(diagnostic(recovery, "invalid-recovery-relationship", "Passkey recovery region must contain its server-rendered code and continuation copy"));
        return null;
    }

    return {
        message,
        region,
        recovery,
        recoveryCode: recoveryCodes[0],
    };
}

function readLoginControl(
    root: HTMLElement,
    config: Extract<PasskeyFlowConfig, { tag: "login" }>,
    report: PasskeyDiagnosticReporter,
): PasskeyLoginControl | null {
    const action = readAction(root, report);
    const status = readStatus(root, config, false, report);
    if (action === null || status === null) return null;
    if (ownedElements(root, passkeyDeviceNameDomAttr).length !== 0) {
        report(diagnostic(root, "invalid-device-name-relationship", "Passkey login must not contain a registration device-name role"));
        return null;
    }
    return { root, action, config, status };
}

function readRegistrationControl(
    root: HTMLElement,
    config: Extract<PasskeyFlowConfig, { tag: "registration" }>,
    report: PasskeyDiagnosticReporter,
): PasskeyRegistrationControl | null {
    const action = readAction(root, report);
    const status = readStatus(root, config, true, report);
    const deviceNames = ownedElements<Element>(root, passkeyDeviceNameDomAttr);
    if (deviceNames.length !== 1 || !(deviceNames[0] instanceof HTMLInputElement) || !roleIsTrue(deviceNames[0], passkeyDeviceNameDomAttr)) {
        report(diagnostic(root, "invalid-device-name-relationship", "Passkey registration requires one local generated device-name input"));
        return null;
    }
    if (action === null || status === null) return null;
    return { root, action, config, deviceName: deviceNames[0], status };
}

function readPromptControl(
    root: HTMLElement,
    config: PasskeyPromptFlowConfig,
    report: PasskeyDiagnosticReporter,
): PasskeyPromptControl | null {
    const dismissals = ownedElements<Element>(root, passkeyDismissalDomAttr);
    if (dismissals.length !== 1 || !(dismissals[0] instanceof HTMLButtonElement) || !roleIsTrue(dismissals[0], passkeyDismissalDomAttr)) {
        report(diagnostic(root, "invalid-dismissal-relationship", "Passkey setup prompt requires one local generated dismissal control"));
        return null;
    }
    if (!roleIsTrue(dismissals[0], dialogCloseDomAttr)) {
        report(diagnostic(dismissals[0], "invalid-overlay-dismissal-role", "Passkey prompt dismissal must use the generated dialog-close role"));
        return null;
    }
    return { root, config, dismissal: dismissals[0] };
}

function initializePasskeyRoot(
    root: HTMLElement,
    report: PasskeyDiagnosticReporter = defaultDiagnosticReporter,
): void {
    if (initializedPasskeyFlows.has(root)) return;
    initializedPasskeyFlows.add(root);

    const config = parseFlowForRoot(root, report);
    if (config === null || !validateFlowRole(root, config, report)) return;

    switch (config.tag) {
        case "login": {
            const control = readLoginControl(root, config, report);
            if (control === null) return;
            control.action.addEventListener("click", () => {
                void runPasskeyLogin(control);
            });
            return;
        }
        case "registration": {
            const control = readRegistrationControl(root, config, report);
            if (control === null) return;
            control.action.addEventListener("click", () => {
                void runPasskeyRegistration(control);
            });
            return;
        }
        case "setup-prompt": {
            const control = readPromptControl(root, config, report);
            if (control === null) return;
            initializePasskeySetupPrompt(control);
            return;
        }
        default:
            assertNever(config, "Unexpected generated passkey flow");
    }
}

function initializePasskeySetupPrompt(control: PasskeyPromptControl): void {
    control.root.addEventListener(dialogDismissedEvent, () => {
        if (automaticPromptDismissals.has(control.root)) {
            automaticPromptDismissals.delete(control.root);
            return;
        }
        dismissPasskeyPrompt(control.config.promptUserKey);
    }, { once: true });

    if (!passkeysAreAvailable()
        || isPasskeyPromptDismissed(control.config.promptUserKey)
        || promptModeAlreadyConfigured(control.config)) {
        automaticPromptDismissals.add(control.root);
        control.dismissal.click();
    }
}

function promptModeAlreadyConfigured(config: PasskeyPromptFlowConfig): boolean {
    switch (config.setupPromptMode) {
        case passkeyFirstPasskeyMode:
            return false;
        case passkeyAdditionalDeviceMode:
            return hasPasskeySeen(config.promptUserKey);
        default:
            return assertNever(config.setupPromptMode, "Unexpected generated passkey setup prompt mode");
    }
}

async function runPasskeyLogin(control: PasskeyLoginControl): Promise<void> {
    await withPasskeyButton(control, async () => {
        setPasskeyStatus(control.status, "info", control.config.waitingMessage);
        const beginResponse = await postJson<JsonObject>(control.config.beginUrl, control.config.failureMessage);
        const credential = await window.navigator.credentials.get({
            publicKey: authenticationOptionsToNative(beginResponse),
        });
        if (!(credential instanceof PublicKeyCredential)) throw new PasskeyStatusError(control.config.cancelledMessage);

        const finishResponse = await postJson<PasskeyFinishResponse>(
            control.config.finishUrl,
            control.config.failureMessage,
            serializeAuthenticationCredential(credential),
        );

        markPasskeySeen(finishResponse.userId);
        setPasskeyStatus(control.status, "success", control.config.successMessage);
        redirectAfterPasskeySuccess(control.config, finishResponse);
    });
}

async function runPasskeyRegistration(control: PasskeyRegistrationControl): Promise<void> {
    await withPasskeyButton(control, async () => {
        setPasskeyStatus(control.status, "info", control.config.waitingMessage);
        const beginResponse = await postJson<JsonObject>(control.config.beginUrl, control.config.failureMessage);
        const credential = await window.navigator.credentials.create({
            publicKey: registrationOptionsToNative(beginResponse),
        });
        if (!(credential instanceof PublicKeyCredential)) throw new PasskeyStatusError(control.config.cancelledMessage);

        const finishResponse = await postJson<PasskeyFinishResponse>(
            control.config.finishUrl,
            control.config.failureMessage,
            registrationPayload(control, credential),
        );

        markPasskeySeen(finishResponse.userId);
        if (finishResponse.recoveryCode) {
            setRecoveryCodeStatus(control.status, finishResponse.recoveryCode);
        } else {
            setPasskeyStatus(control.status, "success", control.config.successMessage);
            redirectAfterPasskeySuccess(control.config, finishResponse);
        }
    });
}

async function withPasskeyButton(
    control: PasskeyLoginControl | PasskeyRegistrationControl,
    callback: () => Promise<void>,
): Promise<void> {
    if (!passkeysAreAvailable()) {
        setPasskeyStatus(control.status, "danger", control.config.unsupportedMessage);
        return;
    }

    const originalHtml = control.action.innerHTML;
    control.action.disabled = true;
    const spinner = document.createElement("span");
    spinner.className = "spinner-border spinner-border-sm me-2";
    spinner.setAttribute("aria-hidden", "true");
    control.action.replaceChildren(spinner, document.createTextNode(control.config.pendingLabel));

    try {
        await callback();
    } catch (error) {
        setPasskeyStatus(
            control.status,
            "danger",
            passkeyStatusMessageForError(control.config, error),
        );
    } finally {
        control.action.disabled = false;
        control.action.innerHTML = originalHtml;
    }
}

export function passkeyStatusMessageForError(
    config: PasskeyStatusFlowConfig,
    error: unknown,
): string {
    if (error instanceof PasskeyStatusError) return error.statusMessage;
    if (isPasskeyCancellation(error)) return config.cancelledMessage;
    return config.failureMessage;
}

function isPasskeyCancellation(error: unknown): boolean {
    return typeof DOMException !== "undefined"
        && error instanceof DOMException
        && (error.name === "AbortError" || error.name === "NotAllowedError");
}

async function postJson<T extends JsonObject>(
    url: string,
    failureMessage: string,
    payload?: unknown,
): Promise<T> {
    const hasPayload = payload !== undefined;
    const response = await window.fetch(url, {
        method: "POST",
        credentials: "same-origin",
        headers: hasPayload
            ? {
                Accept: "application/json",
                "Content-Type": "application/json",
            }
            : {
                Accept: "application/json",
            },
        body: hasPayload ? JSON.stringify(payload) : undefined,
    });

    const json = await response.json().catch(() => ({})) as JsonObject;
    if (!response.ok) {
        if (typeof json.redirectTo === "string") {
            window.location.assign(json.redirectTo);
        }
        throw new PasskeyStatusError(failureMessage);
    }
    return json as T;
}

function setPasskeyStatus(status: PasskeyStatusControl, tone: PasskeyTone, message: string): void {
    status.message.hidden = false;
    status.message.textContent = message;
    if (status.recovery !== null) status.recovery.hidden = true;
    setPasskeyStatusTone(status.region, tone);
}

function setRecoveryCodeStatus(status: PasskeyStatusControl, recoveryCode: string): void {
    if (status.recovery === null || status.recoveryCode === null) return;
    status.message.hidden = true;
    status.recoveryCode.textContent = recoveryCode;
    status.recovery.hidden = false;
    setPasskeyStatusTone(status.region, "warning");
}

function setPasskeyStatusTone(region: HTMLElement, tone: PasskeyTone): void {
    region.classList.remove("d-none", "alert-info", "alert-success", "alert-danger", "alert-warning");
    region.classList.add(`alert-${tone}`);
}

function redirectAfterPasskeySuccess(
    config: PasskeyStatusFlowConfig,
    response: PasskeyFinishResponse,
): void {
    const redirectTo = response.redirectTo || config.successRedirect;
    if (redirectTo === undefined || redirectTo === "") return;
    window.location.assign(redirectTo);
}

function localStorageKey(userId: string, key: PasskeyStorageKey): string {
    return localStorageKeyForPasskey(userId, key);
}

function markPasskeySeen(userId: string | undefined): void {
    if (userId === undefined || userId === "") return;
    try {
        window.localStorage.setItem(localStorageKey(userId, "passkeySeen"), "1");
    } catch (_error) {
        // Local storage is a UX hint only; auth must not depend on it.
    }
}

function hasPasskeySeen(userId: string): boolean {
    try {
        return window.localStorage.getItem(localStorageKey(userId, "passkeySeen")) === "1";
    } catch (_error) {
        return false;
    }
}

function dismissPasskeyPrompt(userId: string): void {
    const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;
    try {
        window.localStorage.setItem(
            localStorageKey(userId, "passkeyPromptDismissedUntil"),
            String(Date.now() + thirtyDaysMs),
        );
    } catch (_error) {
        // Dismissal is best-effort browser-local state.
    }
}

function isPasskeyPromptDismissed(userId: string): boolean {
    try {
        const dismissedUntil = Number(window.localStorage.getItem(localStorageKey(userId, "passkeyPromptDismissedUntil")) || "0");
        return dismissedUntil > Date.now();
    } catch (_error) {
        return false;
    }
}

function registrationPayload(
    control: PasskeyRegistrationControl,
    credential: PublicKeyCredential,
): RegistrationCredentialPayload {
    const payload = serializeRegistrationCredential(credential);
    if (control.deviceName.value.trim()) {
        payload.name = control.deviceName.value.trim();
    }
    return payload;
}

function serializeRegistrationCredential(credential: PublicKeyCredential): RegistrationCredentialPayload {
    const response = credential.response;
    if (!(response instanceof AuthenticatorAttestationResponse)) {
        throw new Error("Invalid registration credential response.");
    }
    return {
        rawId: arrayBufferToBase64Url(credential.rawId),
        response: {
            clientDataJSON: arrayBufferToBase64Url(response.clientDataJSON),
            attestationObject: arrayBufferToBase64Url(response.attestationObject),
            transports: typeof response.getTransports === "function"
                ? response.getTransports()
                : [],
        },
        clientExtensionResults: credential.getClientExtensionResults(),
    };
}

function serializeAuthenticationCredential(credential: PublicKeyCredential): AuthenticationCredentialPayload {
    const response = credential.response;
    if (!(response instanceof AuthenticatorAssertionResponse)) {
        throw new Error("Invalid authentication credential response.");
    }
    return {
        rawId: arrayBufferToBase64Url(credential.rawId),
        response: {
            clientDataJSON: arrayBufferToBase64Url(response.clientDataJSON),
            authenticatorData: arrayBufferToBase64Url(response.authenticatorData),
            signature: arrayBufferToBase64Url(response.signature),
            userHandle: response.userHandle
                ? arrayBufferToBase64Url(response.userHandle)
                : null,
        },
        clientExtensionResults: credential.getClientExtensionResults(),
    };
}

function registrationOptionsToNative(options: JsonObject): PublicKeyCredentialCreationOptions {
    if (typeof options.challenge !== "string" || options.user === undefined || typeof options.user.id !== "string") {
        throw new Error("Invalid registration options.");
    }

    return {
        ...options,
        challenge: base64UrlToArrayBuffer(options.challenge),
        user: {
            ...options.user,
            id: base64UrlToArrayBuffer(options.user.id),
        },
        excludeCredentials: (options.excludeCredentials || []).map((descriptor: JsonObject) => ({
            ...descriptor,
            id: base64UrlToArrayBuffer(descriptor.id),
        })),
    } as PublicKeyCredentialCreationOptions;
}

function authenticationOptionsToNative(options: JsonObject): PublicKeyCredentialRequestOptions {
    if (typeof options.challenge !== "string") {
        throw new Error("Invalid authentication options.");
    }
    return {
        ...options,
        challenge: base64UrlToArrayBuffer(options.challenge),
        allowCredentials: (options.allowCredentials || []).map((descriptor: JsonObject) => ({
            ...descriptor,
            id: base64UrlToArrayBuffer(descriptor.id),
        })),
    } as PublicKeyCredentialRequestOptions;
}

function passkeysAreAvailable(): boolean {
    return typeof window.PublicKeyCredential === "function" && window.navigator.credentials !== undefined;
}

(function enablePasskeys() {
    if (typeof window === "undefined") return;

    function initPasskeys(event: Event): void {
        const target = detailTarget(event, "target");
        const root = isDomRoot(target) ? target : document;
        rootsWithRole(root, passkeyLoginDomAttr).forEach((element) => initializePasskeyRoot(element));
        rootsWithRole(root, passkeyRegistrationDomAttr).forEach((element) => initializePasskeyRoot(element));
        rootsWithRole(root, passkeySetupPromptDomAttr).forEach((element) => initializePasskeyRoot(element));
    }

    onAppPageReady(initPasskeys);
})();
