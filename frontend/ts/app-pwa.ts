import {
    isPwaInstallState,
    pwaInstallButtonDomAttr,
    pwaInstalledStatusDomAttr,
    pwaInstallPageDomAttr,
    pwaInstallResultDomAttr,
    pwaInstallResultStateDomAttr,
    type PwaInstallState,
} from "./generated/contracts";

export function parsePwaInstallState(value: unknown): PwaInstallState {
    if (isPwaInstallState(value)) return value;
    throw new Error("Invalid PwaInstallState");
}

type InstallChoice = {
    outcome: "accepted" | "dismissed";
    platform?: string;
};

type BeforeInstallPromptEvent = Event & {
    prompt: () => Promise<void>;
    userChoice: Promise<InstallChoice>;
};

type AppleNavigator = Navigator & {
    standalone?: boolean;
};

let deferredInstallPrompt: BeforeInstallPromptEvent | null = null;
let installationCompleted = false;

function roleSelector(attribute: string): string {
    return `[${attribute}]`;
}

function isBeforeInstallPromptEvent(event: Event): event is BeforeInstallPromptEvent {
    const candidate = event as Partial<BeforeInstallPromptEvent>;
    return typeof candidate.prompt === "function"
        && typeof candidate.userChoice?.then === "function";
}

function isStandalone(): boolean {
    return window.matchMedia("(display-mode: standalone)").matches
        || (navigator as AppleNavigator).standalone === true
        || installationCompleted;
}

function installPage(): HTMLElement | null {
    return document.querySelector<HTMLElement>(roleSelector(pwaInstallPageDomAttr));
}

function renderInstallState(): void {
    const page = installPage();
    if (!page) return;

    const installed = isStandalone();
    const installedStatus = page.querySelector<HTMLElement>(roleSelector(pwaInstalledStatusDomAttr));
    const installButton = page.querySelector<HTMLButtonElement>(roleSelector(pwaInstallButtonDomAttr));

    if (installedStatus) installedStatus.hidden = !installed;
    if (installButton) installButton.hidden = installed || deferredInstallPrompt === null;
}

function installResultElements(result: HTMLElement): Map<PwaInstallState, HTMLElement> | null {
    const elements = Array.from(
        result.querySelectorAll<HTMLElement>(roleSelector(pwaInstallResultStateDomAttr)),
    );
    const byState = new Map<PwaInstallState, HTMLElement>();

    for (const element of elements) {
        let state: PwaInstallState;
        try {
            state = parsePwaInstallState(element.getAttribute(pwaInstallResultStateDomAttr));
        } catch (error) {
            console.error?.("Invalid generated PWA install result state", error);
            return null;
        }
        if (byState.has(state)) {
            console.error?.("Invalid generated PWA install result state", `Duplicate state: ${state}`);
            return null;
        }
        byState.set(state, element);
    }

    return byState;
}

function renderInstallResult(page: HTMLElement, state: PwaInstallState): void {
    const result = page.querySelector<HTMLElement>(roleSelector(pwaInstallResultDomAttr));
    if (!result) return;

    const elements = installResultElements(result);
    const selected = elements?.get(state);
    if (!elements || !selected) {
        console.error?.("Invalid generated PWA install result state", `Missing state: ${state}`);
        return;
    }

    for (const element of elements.values()) {
        element.hidden = element !== selected;
    }
}

async function promptForInstallation(page: HTMLElement): Promise<void> {
    const installPrompt = deferredInstallPrompt;
    if (!installPrompt || isStandalone()) return;

    deferredInstallPrompt = null;
    renderInstallState();

    try {
        await installPrompt.prompt();
        const choice = await installPrompt.userChoice;
        renderInstallResult(page, parsePwaInstallState(choice.outcome));
    } catch {
        renderInstallResult(page, parsePwaInstallState("failed"));
    }
}

(function enablePwaInstallation() {
    if (typeof window === "undefined") return;

    window.addEventListener("beforeinstallprompt", (event) => {
        if (!isBeforeInstallPromptEvent(event)) return;

        event.preventDefault();
        deferredInstallPrompt = event;
        renderInstallState();
    });

    window.addEventListener("appinstalled", () => {
        deferredInstallPrompt = null;
        installationCompleted = true;
        renderInstallState();
    });

    document.addEventListener("click", (event) => {
        const target = event.target;
        if (!(target instanceof Element)) return;

        const button = target.closest<HTMLElement>(roleSelector(pwaInstallButtonDomAttr));
        const page = button?.closest<HTMLElement>(roleSelector(pwaInstallPageDomAttr));
        if (!button || !page) return;

        void promptForInstallation(page);
    });

    document.addEventListener("DOMContentLoaded", renderInstallState, { once: true });
    if (document.readyState !== "loading") renderInstallState();
})();
