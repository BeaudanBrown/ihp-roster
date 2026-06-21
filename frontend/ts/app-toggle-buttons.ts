import { rootFromTarget } from "./shared/dom";
import { detailTarget, onAppPageReady, onHtmxLoad } from "./shared/lifecycle";

function syncHiddenInput(input: HTMLInputElement): void {
    const hiddenInputId = input.dataset.appToggleHiddenInputId;
    if (hiddenInputId === undefined || hiddenInputId === "") return;

    const hiddenInput = document.getElementById(hiddenInputId);
    if (!(hiddenInput instanceof HTMLInputElement)) return;

    const checkedValue = input.dataset.appToggleHiddenCheckedValue ?? "true";
    const uncheckedValue = input.dataset.appToggleHiddenUncheckedValue ?? "false";
    hiddenInput.value = input.checked ? checkedValue : uncheckedValue;
}

export function syncToggleButton(input: HTMLInputElement): void {
    const button = input.closest("[data-app-toggle-button]");
    if (button === null) return;

    button.classList.toggle("btn-success", input.checked);
    button.classList.toggle("btn-outline-success", !input.checked);
    button.setAttribute("aria-pressed", input.checked ? "true" : "false");
    if (input.getAttribute("role") === "switch") {
        input.setAttribute("aria-checked", input.checked ? "true" : "false");
    }
    syncHiddenInput(input);
}

function initToggleButtons(target: unknown): void {
    const root = rootFromTarget(target);
    root.querySelectorAll<HTMLInputElement>('[data-app-toggle-button-input="true"]').forEach((input) => {
        if (input.dataset.appToggleButtonReady === "true") return;
        input.dataset.appToggleButtonReady = "true";
        input.addEventListener("change", () => {
            syncToggleButton(input);
        });
        syncToggleButton(input);
    });
}

function enableAppToggleButtons(): void {
    if (typeof window === "undefined") return;

    onAppPageReady((event) => {
        initToggleButtons(detailTarget(event, "target"));
    });
    onHtmxLoad((event) => {
        initToggleButtons(detailTarget(event, "elt"));
    });

    if (document.readyState !== "loading") {
        initToggleButtons(document.body);
    }
}

enableAppToggleButtons();
