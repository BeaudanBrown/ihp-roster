import { rootFromTarget } from "./shared/dom";
import { detailTarget, onAppPageReady, onHtmxLoad } from "./shared/lifecycle";

export function formatHour(hour: string | number): string {
    const parsed = typeof hour === "number" ? hour : Number.parseInt(hour, 10);
    if (Number.isNaN(parsed)) return "";
    if (parsed === 0) return "12 AM";
    if (parsed < 12) return `${parsed} AM`;
    if (parsed === 12) return "12 PM";
    return `${parsed - 12} PM`;
}

function syncWindow(container: HTMLElement): void {
    const startInput = container.querySelector<HTMLInputElement>("[data-shift-preference-start]");
    const endInput = container.querySelector<HTMLInputElement>("[data-shift-preference-end]");
    const startLabel = container.querySelector<HTMLElement>("[data-shift-preference-start-label]");
    const endLabel = container.querySelector<HTMLElement>("[data-shift-preference-end-label]");
    if (startInput === null || endInput === null || startLabel === null || endLabel === null) return;

    let startHour = Number.parseInt(startInput.value, 10);
    let endHour = Number.parseInt(endInput.value, 10);
    if (Number.isNaN(startHour) || Number.isNaN(endHour)) return;

    if (startHour > endHour) {
        const activeElement = document.activeElement;
        if (activeElement === startInput) {
            endHour = startHour;
            endInput.value = String(endHour);
        } else {
            startHour = endHour;
            startInput.value = String(startHour);
        }
    }

    const minHour = Number.parseInt(container.dataset.minHour ?? (startInput.min || "5"), 10);
    const maxHour = Number.parseInt(container.dataset.maxHour ?? (startInput.max || "23"), 10);
    const span = Math.max(1, maxHour - minHour);
    const startPercent = ((startHour - minHour) / span) * 100;
    const endPercent = ((endHour - minHour) / span) * 100;

    container.style.setProperty("--preference-start", `${startPercent}%`);
    container.style.setProperty("--preference-end", `${endPercent}%`);
    startLabel.textContent = formatHour(startHour);
    endLabel.textContent = formatHour(endHour);
}

function syncAvailability(container: HTMLElement): void {
    const availableInput = container.querySelector<HTMLInputElement>('[data-shift-preference-available], [data-app-toggle-button-input="true"]');
    const startInput = container.querySelector<HTMLInputElement>("[data-shift-preference-start]");
    const endInput = container.querySelector<HTMLInputElement>("[data-shift-preference-end]");
    if (availableInput === null || startInput === null || endInput === null) return;

    const isAvailable = availableInput.checked;
    container.classList.toggle("is-unavailable", !isAvailable);
    const availabilityButton = availableInput.closest(".shift-preference-availability-button");
    if (availabilityButton !== null) {
        availabilityButton.classList.toggle("btn-success", isAvailable);
        availabilityButton.classList.toggle("btn-outline-success", !isAvailable);
    }
    startInput.disabled = !isAvailable;
    endInput.disabled = !isAvailable;
}

function initShiftPreferenceWindows(target: unknown): void {
    const root = rootFromTarget(target);
    root.querySelectorAll<HTMLElement>("[data-shift-preference-window]").forEach((container) => {
        if (container.dataset.shiftPreferenceWindowReady === "true") return;
        container.dataset.shiftPreferenceWindowReady = "true";

        const availableInput = container.querySelector<HTMLInputElement>('[data-shift-preference-available], [data-app-toggle-button-input="true"]');
        const startInput = container.querySelector<HTMLInputElement>("[data-shift-preference-start]");
        const endInput = container.querySelector<HTMLInputElement>("[data-shift-preference-end]");
        if (availableInput !== null) {
            availableInput.addEventListener("change", () => {
                syncAvailability(container);
            });
        }
        [startInput, endInput].forEach((input) => {
            if (input === null) return;
            input.addEventListener("input", () => {
                syncWindow(container);
            });
        });

        syncWindow(container);
        syncAvailability(container);
    });
}

function initPreferenceControls(target: unknown): void {
    initShiftPreferenceWindows(target);
}

function enableShiftPreferenceWindows(): void {
    if (typeof window === "undefined") return;

    onAppPageReady((event) => {
        initPreferenceControls(detailTarget(event, "target"));
    });
    onHtmxLoad((event) => {
        initPreferenceControls(detailTarget(event, "elt"));
    });

    if (document.readyState !== "loading") {
        initPreferenceControls(document.body);
    }
}

enableShiftPreferenceWindows();
