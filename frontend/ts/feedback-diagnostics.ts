import {
    feedbackDevicePixelRatioInputDomAttr,
    feedbackDisplayModeInputDomAttr,
    feedbackViewportHeightInputDomAttr,
    feedbackViewportWidthInputDomAttr,
    type FeedbackDisplayMode,
} from "./generated/contracts";

const initializedForms = new WeakSet<HTMLFormElement>();

type AppleNavigator = Navigator & { standalone?: boolean };

type FeedbackDiagnosticInputs = {
    form: HTMLFormElement;
    viewportWidth: HTMLInputElement;
    viewportHeight: HTMLInputElement;
    devicePixelRatio: HTMLInputElement;
    displayMode: HTMLInputElement;
};

function roleSelector(attribute: string): string {
    return `[${attribute}]`;
}

function hiddenInput(form: HTMLFormElement, attribute: string): HTMLInputElement | null {
    const input = form.querySelector<HTMLInputElement>(roleSelector(attribute));
    return input?.type === "hidden" ? input : null;
}

function diagnosticInputs(viewportWidth: HTMLInputElement): FeedbackDiagnosticInputs | null {
    const form = viewportWidth.closest("form");
    if (!form || viewportWidth.type !== "hidden") return null;

    const viewportHeight = hiddenInput(form, feedbackViewportHeightInputDomAttr);
    const devicePixelRatio = hiddenInput(form, feedbackDevicePixelRatioInputDomAttr);
    const displayMode = hiddenInput(form, feedbackDisplayModeInputDomAttr);
    if (!viewportWidth || !viewportHeight || !devicePixelRatio || !displayMode) return null;

    return { form, viewportWidth, viewportHeight, devicePixelRatio, displayMode };
}

function currentDisplayMode(): FeedbackDisplayMode {
    const mediaStandalone = typeof window.matchMedia === "function"
        && window.matchMedia("(display-mode: standalone)").matches;
    const appleStandalone = (navigator as AppleNavigator).standalone === true;
    return mediaStandalone || appleStandalone ? "standalone" : "browser";
}

function populateFeedbackDiagnostics(inputs: FeedbackDiagnosticInputs): void {
    inputs.viewportWidth.value = String(window.innerWidth);
    inputs.viewportHeight.value = String(window.innerHeight);
    inputs.devicePixelRatio.value = String(window.devicePixelRatio);
    inputs.displayMode.value = currentDisplayMode();
}

export function initializeFeedbackDiagnostics(root: ParentNode = document): void {
    const viewportWidths = Array.from(
        root.querySelectorAll<HTMLInputElement>(roleSelector(feedbackViewportWidthInputDomAttr)),
    );

    if (root instanceof HTMLInputElement && root.matches(roleSelector(feedbackViewportWidthInputDomAttr))) {
        viewportWidths.unshift(root);
    }

    for (const viewportWidth of viewportWidths) {
        const inputs = diagnosticInputs(viewportWidth);
        if (!inputs) continue;

        populateFeedbackDiagnostics(inputs);
        if (initializedForms.has(inputs.form)) continue;

        initializedForms.add(inputs.form);
        inputs.form.addEventListener("submit", () => populateFeedbackDiagnostics(inputs));
    }
}
