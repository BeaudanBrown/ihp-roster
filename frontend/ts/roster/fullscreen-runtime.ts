import { rosterFullscreenLabels } from "./fullscreen";

const shellSelector = "#roster-week-shell";
const toggleSelector = '[data-roster-fullscreen-toggle="true"]';
const labelSelector = '[data-roster-fullscreen-toggle-label="true"]';

function rosterShellFromToggle(toggle: HTMLElement): Element | null {
    return toggle.closest(shellSelector);
}

function isExpanded(shell: Element | null): boolean {
    return shell instanceof HTMLElement && shell.dataset.rosterFullscreen === "true";
}

function updateToggle(toggle: HTMLElement, expanded: boolean): void {
    const labels = rosterFullscreenLabels(expanded);
    toggle.setAttribute("aria-pressed", labels.pressed);
    toggle.setAttribute("aria-label", labels.label);
    toggle.setAttribute("title", labels.label);

    const label = toggle.querySelector(labelSelector);
    if (label) label.textContent = labels.label;

    const icon = toggle.querySelector(".bi");
    if (icon) {
        icon.classList.toggle(labels.iconRemove, false);
        icon.classList.toggle(labels.iconAdd, true);
    }
}

function syncShell(shell: Element): void {
    if (!(shell instanceof HTMLElement)) return;
    const expanded = isExpanded(shell);
    shell.querySelectorAll(toggleSelector).forEach((toggle) => {
        if (toggle instanceof HTMLElement) updateToggle(toggle, expanded);
    });
}

function syncAllShells(): void {
    document.querySelectorAll(shellSelector).forEach(syncShell);
}

function setRosterFullscreen(shell: Element | null, expanded: boolean, toggle: Element | null): void {
    if (!(shell instanceof HTMLElement)) return;
    shell.dataset.rosterFullscreen = expanded ? "true" : "false";
    syncShell(shell);

    if (expanded && toggle instanceof HTMLElement) {
        toggle.focus({ preventScroll: true });
    }
}

export function enableRosterFullscreenToggle(): void {
    if (typeof window === "undefined") return;

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;

        const toggle = event.target.closest(toggleSelector);
        if (!(toggle instanceof HTMLElement)) return;

        const shell = rosterShellFromToggle(toggle);
        if (!(shell instanceof HTMLElement)) return;

        setRosterFullscreen(shell, !isExpanded(shell), toggle);
    });

    document.addEventListener("keydown", (event) => {
        if (event.key !== "Escape") return;

        const shell = document.querySelector(`${shellSelector}[data-roster-fullscreen="true"]`);
        if (shell instanceof HTMLElement) {
            setRosterFullscreen(shell, false, shell.querySelector(toggleSelector));
        }
    });

    document.addEventListener("htmx:afterSwap", syncAllShells);
    document.addEventListener("DOMContentLoaded", syncAllShells);
}
