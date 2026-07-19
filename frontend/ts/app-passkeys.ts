import { dialogCloseDomAttr } from "./generated/contracts";
import { isDomRoot } from "./shared/dom";
import { detailTarget, onAppPageReady } from "./shared/lifecycle";
import { arrayBufferToBase64Url, base64UrlToArrayBuffer } from "./passkeys/base64url";
import { localStorageKeyForPasskey, type PasskeyStorageKey } from "./passkeys/storage";

export { arrayBufferToBase64Url, base64UrlToArrayBuffer, localStorageKeyForPasskey };

type PasskeyContainer = HTMLElement;
type PasskeyButton = HTMLButtonElement;
type JsonObject = Record<string, any>;
type PasskeyTone = "info" | "success" | "danger";

type PasskeyFinishResponse = {
    userId?: string;
    redirectTo?: string;
    recoveryCode?: string;
    message?: string;
    error?: string;
};

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

(function enablePasskeys() {
    if (typeof window === "undefined") return;

    function initPasskeyAuth(event: Event): void {
        const target = detailTarget(event, "target");
        const root = isDomRoot(target) ? target : document;

        root.querySelectorAll<HTMLElement>(".js-passkey-login").forEach(function (container) {
            if (container.dataset.passkeyInitialized === "true") return;
            container.dataset.passkeyInitialized = "true";

            const button = container.querySelector<HTMLButtonElement>(".js-passkey-login-button");
            if (button === null) return;

            button.addEventListener("click", function () {
                void runPasskeyLogin(container, button);
            });
        });

        root.querySelectorAll<HTMLElement>(".js-passkey-register").forEach(function (container) {
            if (container.dataset.passkeyInitialized === "true") return;
            container.dataset.passkeyInitialized = "true";

            const button = container.querySelector<HTMLButtonElement>(".js-passkey-register-button");
            if (button === null) return;

            button.addEventListener("click", function () {
                void runPasskeyRegistration(container, button);
            });
        });

        root.querySelectorAll<HTMLElement>(".js-passkey-setup-prompt").forEach(function (container) {
            if (container.dataset.passkeyInitialized === "true") return;
            container.dataset.passkeyInitialized = "true";
            initPasskeySetupPrompt(container);
        });
    }

    async function runPasskeyLogin(container: PasskeyContainer, button: PasskeyButton): Promise<void> {
        await withPasskeyButton(container, button, async function () {
            setPasskeyStatus(container, "info", "Waiting for your passkey...");
            const beginResponse = await postJson<JsonObject>(container.dataset.beginUrl);
            const credential = await window.navigator.credentials.get({
                publicKey: authenticationOptionsToNative(beginResponse),
            });
            if (!(credential instanceof PublicKeyCredential)) throw new Error("No passkey was selected.");

            const finishResponse = await postJson<PasskeyFinishResponse>(
                container.dataset.finishUrl,
                serializeAuthenticationCredential(credential)
            );

            markPasskeySeen(finishResponse.userId);
            setPasskeyStatus(container, "success", "Signed in.");
            redirectAfterPasskeySuccess(container, finishResponse);
        });
    }

    async function runPasskeyRegistration(container: PasskeyContainer, button: PasskeyButton): Promise<void> {
        await withPasskeyButton(container, button, async function () {
            setPasskeyStatus(container, "info", "Waiting for your passkey...");
            const beginResponse = await postJson<JsonObject>(container.dataset.beginUrl);
            const credential = await window.navigator.credentials.create({
                publicKey: registrationOptionsToNative(beginResponse),
            });
            if (!(credential instanceof PublicKeyCredential)) throw new Error("Passkey registration was cancelled.");

            const finishResponse = await postJson<PasskeyFinishResponse>(
                container.dataset.finishUrl,
                registrationPayload(container, credential)
            );

            markPasskeySeen(finishResponse.userId);
            if (finishResponse.recoveryCode) {
                setRecoveryCodeStatus(container, finishResponse.recoveryCode, container.dataset.successRedirect);
            } else {
                setPasskeyStatus(container, "success", finishResponse.message || "Passkey added.");
                redirectAfterPasskeySuccess(container, finishResponse);
            }
        });
    }

    function initPasskeySetupPrompt(container: PasskeyContainer): void {
        const userId = container.dataset.userId;
        const mode = container.dataset.mode;

        if (!passkeysAreAvailable() || userId === undefined || userId === "") {
            container.remove();
            document.body.classList.remove("modal-open");
            return;
        }

        if (isPasskeyPromptDismissed(userId)) {
            container.remove();
            document.body.classList.remove("modal-open");
            return;
        }

        if (mode === "additional-device" && hasPasskeySeen(userId)) {
            container.remove();
            document.body.classList.remove("modal-open");
            return;
        }

        container.classList.remove("d-none");
        document.body.classList.add("modal-open");

        const dismissButton = container.querySelector(`[${dialogCloseDomAttr}]`);
        if (dismissButton !== null) {
            dismissButton.addEventListener("click", function (event) {
                event.preventDefault();
                dismissPasskeyPrompt(userId);
                container.remove();
                document.body.classList.remove("modal-open");
            });
        }
    }

    async function withPasskeyButton(container: PasskeyContainer, button: PasskeyButton, callback: () => Promise<void>): Promise<void> {
        if (!passkeysAreAvailable()) {
            setPasskeyStatus(container, "danger", "Passkeys are not supported in this browser.");
            return;
        }

        const originalHtml = button.innerHTML;
        button.disabled = true;
        button.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Please wait';

        try {
            await callback();
        } catch (error) {
            setPasskeyStatus(container, "danger", error instanceof Error ? error.message : "Passkey request failed.");
        } finally {
            button.disabled = false;
            button.innerHTML = originalHtml;
        }
    }

    async function postJson<T extends JsonObject>(url: string | undefined, payload?: unknown): Promise<T> {
        const hasPayload = payload !== undefined;
        const response = await window.fetch(url ?? "", {
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

        const json = await response.json().catch(function () {
            return {};
        }) as JsonObject;
        if (!response.ok) {
            if (typeof json.redirectTo === "string") {
                window.location.assign(json.redirectTo);
            }
            throw new Error(typeof json.error === "string" ? json.error : "Passkey request failed.");
        }
        return json as T;
    }

    function setPasskeyStatus(container: PasskeyContainer, tone: PasskeyTone, message: string): void {
        const element = passkeyStatusElement(container);
        if (element === null) return;

        element.className = `alert alert-${tone} mt-3`;
        element.textContent = message;
    }

    function setRecoveryCodeStatus(container: PasskeyContainer, recoveryCode: string, successRedirect: string | undefined): void {
        const element = passkeyStatusElement(container);
        if (element === null) return;

        element.className = "alert alert-warning mt-3";
        element.textContent = "";

        const title = document.createElement("strong");
        title.textContent = "Save this recovery code now.";
        const body = document.createElement("p");
        body.className = "mb-2";
        body.textContent = "This code is shown once and can be used if you lose access to your passkey.";
        const code = document.createElement("code");
        code.className = "d-block fs-5 my-2 user-select-all";
        code.textContent = recoveryCode;

        element.append(title, body, code);
        if (successRedirect !== undefined && successRedirect !== "") {
            const link = document.createElement("a");
            link.className = "btn btn-sm btn-primary mt-2";
            link.href = successRedirect;
            link.textContent = "I have saved it";
            element.append(link);
        }
    }

    function passkeyStatusElement(container: PasskeyContainer): HTMLElement | null {
        const targetId = container.dataset.statusId;
        if (targetId === undefined || targetId === "") return null;
        const element = document.getElementById(targetId);
        return element instanceof HTMLElement ? element : null;
    }

    function redirectAfterPasskeySuccess(container: PasskeyContainer, response: PasskeyFinishResponse): void {
        const redirectTo = response.redirectTo || container.dataset.successRedirect;
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
                String(Date.now() + thirtyDaysMs)
            );
        } catch (_error) {
            // Ignore; dismissal is best-effort browser-local state.
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

    function registrationPayload(container: PasskeyContainer, credential: PublicKeyCredential): RegistrationCredentialPayload {
        const payload = serializeRegistrationCredential(credential);
        const nameInput = container.querySelector<HTMLInputElement>(".js-passkey-name");
        if (nameInput !== null && nameInput.value.trim()) {
            payload.name = nameInput.value.trim();
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
            excludeCredentials: (options.excludeCredentials || []).map(function (descriptor: JsonObject) {
                return {
                    ...descriptor,
                    id: base64UrlToArrayBuffer(descriptor.id),
                };
            }),
        } as PublicKeyCredentialCreationOptions;
    }

    function authenticationOptionsToNative(options: JsonObject): PublicKeyCredentialRequestOptions {
        if (typeof options.challenge !== "string") {
            throw new Error("Invalid authentication options.");
        }
        return {
            ...options,
            challenge: base64UrlToArrayBuffer(options.challenge),
            allowCredentials: (options.allowCredentials || []).map(function (descriptor: JsonObject) {
                return {
                    ...descriptor,
                    id: base64UrlToArrayBuffer(descriptor.id),
                };
            }),
        } as PublicKeyCredentialRequestOptions;
    }

    function passkeysAreAvailable(): boolean {
        return typeof window.PublicKeyCredential === "function" && window.navigator.credentials !== undefined;
    }

    onAppPageReady(initPasskeyAuth);
})();
