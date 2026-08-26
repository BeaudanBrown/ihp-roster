import {
    initializePasskeyRoot,
    parsePasskeyFlowConfiguration,
    passkeyStatusMessageForError,
} from "../app-passkeys";
import {
    authenticationOptionsToNative,
    registrationOptionsToNative,
    safePasskeyRedirectPath,
} from "../passkeys/wire";
import {
    dialogCloseDomAttr,
    dialogMountDomAttr,
    encodePasskeyAuthenticationRequest,
    encodePasskeyRegistrationRequest,
    parsePasskeyAuthenticationOptions,
    parsePasskeyErrorResponse,
    parsePasskeyFinishResponse,
    parsePasskeyRegistrationOptions,
    passkeyActionButtonDomAttr,
    passkeyAdditionalDeviceMode,
    passkeyFirstPasskeyMode,
    passkeyFlowConfigDomAttr,
    passkeyLoginDomAttr,
    passkeyStatusDomAttr,
    type PasskeyAuthenticationOptions,
    type PasskeyRegistrationOptions,
} from "../generated/contracts";
import { assertDeepEqual, assertEqual, assertThrows, test } from "./harness";

const loginFlow = {
    tag: "login",
    beginUrl: "/BeginPasskeyAuthentication",
    finishUrl: "/FinishPasskeyAuthentication",
    successRedirect: "/RosterWeeks",
    statusKey: "status",
    waitingMessage: "Waiting for your passkey...",
    successMessage: "Signed in.",
    unsupportedMessage: "Passkeys are not supported in this browser.",
    failureMessage: "Passkey request failed.",
    pendingLabel: "Please wait",
    cancelledMessage: "No passkey was selected.",
    autoStart: false,
    closeOverlayOnSuccess: false,
} as const;

const registrationOptions = {
    rp: { id: "example.test", name: "Bepis" },
    user: { id: "BAU", displayName: "Person", name: "person@example.test" },
    challenge: "AQID",
    pubKeyCredParams: [{ type: "public-key", alg: -7 }],
    timeout: 60_000,
    excludeCredentials: [{ type: "public-key", id: "Bgc" }],
    authenticatorSelection: {
        residentKey: "required",
        requireResidentKey: true,
        userVerification: "preferred",
    },
    attestation: "none",
} as const satisfies PasskeyRegistrationOptions;

const authenticationOptions = {
    challenge: "AQID",
    timeout: 60_000,
    rpId: "example.test",
    allowCredentials: [{ type: "public-key", id: "Bgc" }],
    userVerification: "preferred",
} as const satisfies PasskeyAuthenticationOptions;

test("passkey adapter parses only the generated exact flow configuration", () => {
    assertDeepEqual(
        parsePasskeyFlowConfiguration(JSON.stringify(loginFlow)),
        loginFlow,
    );
    assertThrows(
        () => parsePasskeyFlowConfiguration(JSON.stringify({ ...loginFlow, extra: true })),
        "Invalid PasskeyFlowConfig",
    );
    assertThrows(
        () => parsePasskeyFlowConfiguration(JSON.stringify({ ...loginFlow, beginUrl: " " })),
        "begin URL must not be empty",
    );
    assertThrows(
        () => parsePasskeyFlowConfiguration(JSON.stringify({ ...loginFlow, successRedirect: null })),
        "Invalid PasskeyFlowConfig",
    );
});

test("in-place passkey overlay attempts immediately and retains an accessible retry after unsupported browser failure", async () => {
    if (typeof document === "undefined") return;

    const originalPublicKeyCredential = Object.getOwnPropertyDescriptor(window, "PublicKeyCredential");
    Object.defineProperty(window, "PublicKeyCredential", { configurable: true, value: undefined });
    const dialog = document.createElement("div");
    dialog.setAttribute(dialogMountDomAttr, "true");
    const close = document.createElement("button");
    close.setAttribute(dialogCloseDomAttr, "true");
    const root = document.createElement("div");
    root.setAttribute(passkeyLoginDomAttr, "true");
    root.setAttribute(passkeyFlowConfigDomAttr, JSON.stringify({
        ...loginFlow,
        autoStart: true,
        closeOverlayOnSuccess: true,
    }));
    const action = document.createElement("button");
    action.setAttribute(passkeyActionButtonDomAttr, "true");
    const statusRegion = document.createElement("div");
    statusRegion.setAttribute("role", "status");
    const status = document.createElement("span");
    status.setAttribute(passkeyStatusDomAttr, "status");
    statusRegion.append(status);
    root.append(action, statusRegion);
    dialog.append(close, root);
    document.body.append(dialog);

    try {
        initializePasskeyRoot(root);
        await Promise.resolve();
        assertEqual(status.textContent, loginFlow.unsupportedMessage);
        assertEqual(action.disabled, false);
    } finally {
        dialog.remove();
        if (originalPublicKeyCredential === undefined) {
            delete (window as Window & { PublicKeyCredential?: typeof PublicKeyCredential }).PublicKeyCredential;
        } else {
            Object.defineProperty(window, "PublicKeyCredential", originalPublicKeyCredential);
        }
    }
});

test("passkey begin envelopes parse exactly before conversion to browser buffers", () => {
    const parsedRegistration = parsePasskeyRegistrationOptions(registrationOptions);
    const nativeRegistration = registrationOptionsToNative(parsedRegistration);
    assertDeepEqual(bytes(nativeRegistration.challenge), [1, 2, 3]);
    assertDeepEqual(bytes(nativeRegistration.user.id), [4, 5]);
    assertDeepEqual(bytes(nativeRegistration.excludeCredentials?.[0].id), [6, 7]);
    assertEqual(nativeRegistration.pubKeyCredParams[0].type, "public-key");
    assertEqual(nativeRegistration.authenticatorSelection?.residentKey, "required");

    const parsedAuthentication = parsePasskeyAuthenticationOptions(authenticationOptions);
    const nativeAuthentication = authenticationOptionsToNative(parsedAuthentication);
    assertDeepEqual(bytes(nativeAuthentication.challenge), [1, 2, 3]);
    assertDeepEqual(bytes(nativeAuthentication.allowCredentials?.[0].id), [6, 7]);
    assertEqual(nativeAuthentication.userVerification, "preferred");

    assertThrows(
        () => parsePasskeyRegistrationOptions({ ...registrationOptions, extra: true }),
        "Invalid PasskeyRegistrationOptions",
    );
    const { excludeCredentials: _excluded, ...missingCredentials } = registrationOptions;
    assertThrows(
        () => parsePasskeyRegistrationOptions(missingCredentials),
        "Invalid PasskeyRegistrationOptions",
    );
    assertThrows(
        () => parsePasskeyRegistrationOptions({
            ...registrationOptions,
            excludeCredentials: [{ type: "public-key", id: "Bgc", transports: [] }],
        }),
        "Invalid PasskeyRegistrationOptions",
    );
    assertThrows(
        () => parsePasskeyAuthenticationOptions({ ...authenticationOptions, allowCredentials: null }),
        "Invalid PasskeyAuthenticationOptions",
    );
});

test("passkey credential encoders preserve exact nullable and nested request shapes", () => {
    assertDeepEqual(
        encodePasskeyRegistrationRequest({
            rawId: "AQ",
            response: {
                clientDataJSON: "Ag",
                attestationObject: "Aw",
                transports: ["internal", "hybrid"],
            },
            clientExtensionResults: {},
            name: "Laptop",
        }),
        {
            rawId: "AQ",
            response: {
                clientDataJSON: "Ag",
                attestationObject: "Aw",
                transports: ["internal", "hybrid"],
            },
            clientExtensionResults: {},
            name: "Laptop",
        },
    );
    assertDeepEqual(
        encodePasskeyAuthenticationRequest({
            rawId: "AQ",
            response: {
                clientDataJSON: "Ag",
                authenticatorData: "Aw",
                signature: "BA",
                userHandle: null,
            },
            clientExtensionResults: {},
        }),
        {
            rawId: "AQ",
            response: {
                clientDataJSON: "Ag",
                authenticatorData: "Aw",
                signature: "BA",
                userHandle: null,
            },
            clientExtensionResults: {},
        },
    );
});

test("passkey redirects remain path-only and same-origin after URL normalization", () => {
    const origin = "https://bepis.test";
    assertEqual(safePasskeyRedirectPath("/ShowRosterWindow?anchorDate=2025-01-13", origin), "/ShowRosterWindow?anchorDate=2025-01-13");
    assertEqual(safePasskeyRedirectPath("//evil.example/", origin), null);
    assertEqual(safePasskeyRedirectPath("/\\evil.example/", origin), null);
    assertEqual(safePasskeyRedirectPath("https://bepis.test/RosterWeeks", origin), null);
    assertEqual(safePasskeyRedirectPath("RosterWeeks", origin), null);
    assertEqual(safePasskeyRedirectPath("", origin), null);
});

test("passkey finish and error envelopes reject compatibility shapes", () => {
    const userId = "11111111-1111-1111-1111-111111111111";
    assertDeepEqual(
        parsePasskeyFinishResponse({ tag: "registered", userId, recoveryCode: null }),
        { tag: "registered", userId, recoveryCode: null },
    );
    assertDeepEqual(
        parsePasskeyFinishResponse({ tag: "authenticated", userId, redirectTo: "/RosterWeeks" }),
        { tag: "authenticated", userId, redirectTo: "/RosterWeeks" },
    );
    assertThrows(
        () => parsePasskeyFinishResponse({ userId, redirectTo: "/RosterWeeks" }),
        "Invalid PasskeyFinishResponse",
    );
    assertThrows(
        () => parsePasskeyFinishResponse({ tag: "registered", userId }),
        "Invalid PasskeyFinishResponse",
    );
    assertThrows(
        () => parsePasskeyFinishResponse({ tag: "registered", userId, recoveryCode: null, message: "legacy" }),
        "Invalid PasskeyFinishResponse",
    );

    assertDeepEqual(
        parsePasskeyErrorResponse({ tag: "redirect", error: "Verify first.", redirectTo: "/PasskeyStepUp" }),
        { tag: "redirect", error: "Verify first.", redirectTo: "/PasskeyStepUp" },
    );
    assertThrows(
        () => parsePasskeyErrorResponse({ error: "legacy", redirectTo: "/PasskeyStepUp" }),
        "Invalid PasskeyErrorResponse",
    );
    assertThrows(
        () => parsePasskeyErrorResponse({ tag: "failure", error: "Failed", redirectTo: "/elsewhere" }),
        "Invalid PasskeyErrorResponse",
    );
});

test("passkey status copy never exposes native exception text", () => {
    assertEqual(
        passkeyStatusMessageForError(loginFlow, new Error("browser-native detail")),
        loginFlow.failureMessage,
    );
    assertEqual(
        passkeyStatusMessageForError(
            loginFlow,
            new DOMException("browser-native cancellation detail", "NotAllowedError"),
        ),
        loginFlow.cancelledMessage,
    );
});

test("passkey prompt configuration accepts only generated closed modes", () => {
    for (const setupPromptMode of [passkeyFirstPasskeyMode, passkeyAdditionalDeviceMode]) {
        assertDeepEqual(
            parsePasskeyFlowConfiguration(JSON.stringify({
                tag: "setup-prompt",
                promptUserKey: "user-1",
                setupPromptMode,
            })),
            { tag: "setup-prompt", promptUserKey: "user-1", setupPromptMode },
        );
    }
    assertThrows(
        () => parsePasskeyFlowConfiguration(JSON.stringify({
            tag: "setup-prompt",
            promptUserKey: "user-1",
            setupPromptMode: "sometimes",
        })),
        "Invalid PasskeyFlowConfig",
    );
});

function bytes(value: BufferSource | undefined): number[] {
    if (value === undefined) return [];
    const view = value instanceof ArrayBuffer
        ? new Uint8Array(value)
        : new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
    return Array.from(view);
}
