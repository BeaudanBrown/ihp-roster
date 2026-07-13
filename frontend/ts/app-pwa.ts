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
    return document.querySelector<HTMLElement>("[data-pwa-install-page]");
}

function renderInstallState(): void {
    const page = installPage();
    if (!page) return;

    const installed = isStandalone();
    const installedStatus = page.querySelector<HTMLElement>("[data-pwa-installed-status]");
    const installButton = page.querySelector<HTMLButtonElement>("[data-pwa-install-button]");

    if (installedStatus) installedStatus.hidden = !installed;
    if (installButton) installButton.hidden = installed || deferredInstallPrompt === null;
}

async function promptForInstallation(page: HTMLElement): Promise<void> {
    const installPrompt = deferredInstallPrompt;
    if (!installPrompt || isStandalone()) return;

    deferredInstallPrompt = null;
    renderInstallState();

    const result = page.querySelector<HTMLElement>("[data-pwa-install-result]");

    try {
        await installPrompt.prompt();
        const choice = await installPrompt.userChoice;
        if (result) {
            result.textContent = choice.outcome === "accepted"
                ? "Installation accepted. Bepis will appear on your device when installation completes."
                : "Installation was not completed. You can use the browser menu to try again.";
        }
    } catch {
        if (result) {
            result.textContent = "Installation could not start. Use the browser menu to install Bepis.";
        }
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

        const button = target.closest<HTMLElement>("[data-pwa-install-button]");
        const page = button?.closest<HTMLElement>("[data-pwa-install-page]");
        if (!button || !page) return;

        void promptForInstallation(page);
    });

    document.addEventListener("DOMContentLoaded", renderInstallState, { once: true });
    if (document.readyState !== "loading") renderInstallState();
})();
