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
    const root = target instanceof Element || target instanceof Document ? target : document;
    root.querySelectorAll<HTMLInputElement>('[data-app-toggle-button-input="true"]').forEach((input) => {
        if (input.dataset.appToggleButtonReady === "true") return;
        input.dataset.appToggleButtonReady = "true";
        input.addEventListener("change", () => {
            syncToggleButton(input);
        });
        syncToggleButton(input);
    });
}

function detailTarget(event: Event, key: "target" | "elt"): unknown {
    return event instanceof CustomEvent && event.detail !== null && typeof event.detail === "object"
        ? (event.detail as Record<string, unknown>)[key]
        : undefined;
}

function enableAppToggleButtons(): void {
    if (typeof window === "undefined") return;

    document.addEventListener("app:page-ready", (event) => {
        initToggleButtons(detailTarget(event, "target"));
    });
    document.addEventListener("htmx:load", (event) => {
        initToggleButtons(detailTarget(event, "elt"));
    });

    if (document.readyState !== "loading") {
        initToggleButtons(document.body);
    }
}

enableAppToggleButtons();
