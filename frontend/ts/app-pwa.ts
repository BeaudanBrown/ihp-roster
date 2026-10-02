import {
    isPwaInstallState, isPwaInstallGuide, isPwaInstallDevice,
    pwaInstallButtonDomAttr, pwaInstalledStatusDomAttr, pwaInstallPageDomAttr,
    pwaInstallResultDomAttr, pwaInstallResultStateDomAttr, pwaInstallLinkDomAttr,
    pwaInstallHomeDomAttr, pwaInstallManualDomAttr, pwaInstallChooserDomAttr,
    pwaInstallGuidePanelDomAttr,
    type PwaInstallState, type PwaInstallGuide, type PwaInstallDevice, type PwaInstallBrowser,
} from "./generated/contracts";

export function parsePwaInstallState(value: unknown): PwaInstallState {
    if (isPwaInstallState(value)) return value;
    throw new Error("Invalid PwaInstallState");
}

type Device = PwaInstallDevice;
type Browser = PwaInstallBrowser;

// Conservative heuristics only: viewport size says nothing about the device.
export function detectInstallEnvironment(userAgent: string, platform: string, maxTouchPoints: number): { device: Device; browser: Browser } {
    const device: Device = /iPhone|iPad|iPod/.test(userAgent) || (/Mac/.test(platform) && maxTouchPoints > 1)
        ? "ios" : /Android/.test(userAgent) ? "android" : /Windows/.test(userAgent) ? "windows"
            : /Macintosh|Mac OS X/.test(userAgent) ? "mac" : /Linux/.test(userAgent) ? "linux" : "general";
    const embedded = /; wv\)|\bwv\b|FBAN|FBAV|Instagram|Line\//.test(userAgent);
    const browser: Browser = embedded ? "general" : /Edg(?:e|A|iOS)?\//.test(userAgent) ? "edge"
        : /Firefox\/|FxiOS\//.test(userAgent) ? "firefox"
            : /Chrome\/|CriOS\//.test(userAgent) && !/OPR\/|SamsungBrowser\//.test(userAgent) ? "chrome"
                : /Version\/.*Safari\//.test(userAgent) ? "safari" : "general";
    return { device, browser };
}

export function selectedInstallGuides(device: Device, browser: Browser): PwaInstallGuide[] {
    if (device === "ios" || device === "android") return [device];
    if (device === "general") return ["general"];
    const supported = browser === "chrome" || browser === "edge"
        || (device === "mac" && browser === "safari") || (device === "windows" && browser === "firefox");
    return supported ? [device, browser] : [device, "chrome", "edge", ...(device === "mac" ? ["safari" as const] : []), "general"];
}

type BeforeInstallPromptEvent = Event & {
    prompt: () => Promise<void>;
    userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
};
let deferredInstallPrompt: BeforeInstallPromptEvent | null = null;
let installationCompleted = false;
let prompting = false;
const initializedPages = new WeakSet<HTMLElement>();
const selector = (attribute: string): string => `[${attribute}]`;
const installPage = (): HTMLElement | null => document.querySelector(selector(pwaInstallPageDomAttr));
const standalone = (): boolean => window.matchMedia("(display-mode: standalone)").matches
    || (navigator as Navigator & { standalone?: boolean }).standalone === true;

function renderGuides(page: HTMLElement, device: Device, browser: Browser): void {
    const panels = Array.from(page.querySelectorAll<HTMLElement>(selector(pwaInstallGuidePanelDomAttr)));
    // Validate the entire boundary before changing visibility.
    if (panels.some(panel => !isPwaInstallGuide(panel.getAttribute(pwaInstallGuidePanelDomAttr)))) {
        console.error("Invalid generated PWA guide panel");
        return;
    }
    const selected = selectedInstallGuides(device, browser);
    for (const panel of panels) panel.hidden = !selected.includes(panel.getAttribute(pwaInstallGuidePanelDomAttr) as PwaInstallGuide);
}

function renderInstallResult(page: HTMLElement, state: PwaInstallState | null): void {
    const result = page.querySelector<HTMLElement>(selector(pwaInstallResultDomAttr));
    if (!result) return;
    const elements = Array.from(result.querySelectorAll<HTMLElement>(selector(pwaInstallResultStateDomAttr)));
    const states = elements.map(element => element.getAttribute(pwaInstallResultStateDomAttr));
    if (states.some(value => !isPwaInstallState(value)) || new Set(states).size !== states.length
        || (state !== null && !states.includes(state))) {
        console.error("Invalid generated PWA install result state");
        return;
    }
    for (const element of elements) element.hidden = element.getAttribute(pwaInstallResultStateDomAttr) !== state;
}

function renderInstallState(): void {
    const inApp = standalone();
    for (const link of document.querySelectorAll<HTMLElement>(selector(pwaInstallLinkDomAttr))) {
        link.hidden = inApp || installationCompleted;
    }
    const page = installPage();
    if (!page) return;
    if (inApp) {
        const home = page.querySelector<HTMLAnchorElement>(selector(pwaInstallHomeDomAttr));
        if (home instanceof HTMLAnchorElement && home.origin === window.location.origin) window.location.replace(home.href);
        return;
    }
    if (!initializedPages.has(page)) {
        const environment = detectInstallEnvironment(navigator.userAgent, navigator.platform, navigator.maxTouchPoints);
        renderGuides(page, environment.device, environment.browser);
        const chooser = page.querySelector<HTMLSelectElement>(`select${selector(pwaInstallChooserDomAttr)}`);
        if (chooser) chooser.value = environment.device;
        const details = page.querySelector<HTMLDetailsElement>(`details${selector(pwaInstallChooserDomAttr)}`);
        if (details) {
            details.hidden = false;
            details.open = environment.device === "general";
        }
        initializedPages.add(page);
    }
    const status = page.querySelector<HTMLElement>(selector(pwaInstalledStatusDomAttr));
    const button = page.querySelector<HTMLButtonElement>(selector(pwaInstallButtonDomAttr));
    const manual = page.querySelector<HTMLDetailsElement>(selector(pwaInstallManualDomAttr));
    if (status) status.hidden = !installationCompleted;
    if (button) button.hidden = installationCompleted || prompting || deferredInstallPrompt === null;
    if (manual) manual.open = deferredInstallPrompt === null;
    if (installationCompleted) renderInstallResult(page, null);
}

async function promptForInstallation(link?: HTMLAnchorElement): Promise<void> {
    const prompt = deferredInstallPrompt;
    if (!prompt || standalone() || installationCompleted || prompting) return;
    deferredInstallPrompt = null;
    prompting = true;
    // Call synchronously, while the initiating click still owns user activation.
    let outcome: PwaInstallState;
    try {
        const started = prompt.prompt();
        renderInstallState();
        await started;
        outcome = parsePwaInstallState((await prompt.userChoice).outcome);
    } catch {
        outcome = "failed";
    } finally {
        prompting = false;
    }
    renderInstallState();
    if (installationCompleted || standalone()) return;
    if (link && outcome !== "accepted") window.location.assign(link.href);
    else {
        const page = installPage();
        if (page) renderInstallResult(page, outcome);
    }
}

(function enablePwaInstallation() {
    if (typeof window === "undefined") return;
    window.addEventListener("beforeinstallprompt", event => {
        const candidate = event as Partial<BeforeInstallPromptEvent>;
        if (typeof candidate.prompt !== "function" || typeof candidate.userChoice?.then !== "function") return;
        event.preventDefault();
        if (standalone() || installationCompleted || prompting) return;
        deferredInstallPrompt = event as BeforeInstallPromptEvent;
        const page = installPage();
        if (page) renderInstallResult(page, null);
        renderInstallState();
    });
    window.addEventListener("appinstalled", () => {
        deferredInstallPrompt = null;
        installationCompleted = true;
        renderInstallState();
    });
    // Capture before navigation adapters, without changing modified/new-tab clicks.
    document.addEventListener("click", event => {
        if (!(event.target instanceof Element) || event.defaultPrevented || event.button !== 0
            || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
        const link = event.target.closest<HTMLAnchorElement>(`a${selector(pwaInstallLinkDomAttr)}`);
        if (link && (!link.target || link.target === "_self") && !link.hasAttribute("download")
            && link.origin === window.location.origin && (deferredInstallPrompt || prompting) && !installationCompleted && !standalone()) {
            event.preventDefault();
            event.stopImmediatePropagation();
            if (!prompting) void promptForInstallation(link);
            return;
        }
        const button = event.target.closest<HTMLButtonElement>(`button${selector(pwaInstallButtonDomAttr)}`);
        if (button?.closest(selector(pwaInstallPageDomAttr))) void promptForInstallation();
    }, true);
    document.addEventListener("change", event => {
        if (!(event.target instanceof HTMLSelectElement) || !event.target.hasAttribute(pwaInstallChooserDomAttr)) return;
        const value = event.target.value;
        const page = event.target.closest<HTMLElement>(selector(pwaInstallPageDomAttr));
        if (!page || !isPwaInstallDevice(value)) {
            console.error("Invalid generated PWA device choice");
            return;
        }
        // Manual corrections may concern a different device, so show browser alternatives.
        renderGuides(page, value, "general");
    });
    window.matchMedia("(display-mode: standalone)").addEventListener("change", renderInstallState);
    document.addEventListener("DOMContentLoaded", renderInstallState, { once: true });
    document.addEventListener("ihp:load", renderInstallState);
    if (document.readyState !== "loading") renderInstallState();
})();
