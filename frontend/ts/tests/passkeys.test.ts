import {
    parsePasskeyFlowConfiguration,
    passkeyStatusMessageForError,
} from "../app-passkeys";
import {
    passkeyAdditionalDeviceMode,
    passkeyFirstPasskeyMode,
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
} as const;

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
