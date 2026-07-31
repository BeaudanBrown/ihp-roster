import type { TimePickerOption } from "../generated/contracts";

export type TimePickerStepDirection = -1 | 1;

export function steppedTimePickerOption(
    options: ReadonlyArray<TimePickerOption>,
    currentValue: string,
    direction: TimePickerStepDirection,
): TimePickerOption | null {
    if (options.length === 0) return null;

    const currentIndex = options.findIndex((option) => option.value === currentValue);
    if (currentIndex < 0) {
        return direction === 1 ? options[0] : options[options.length - 1];
    }

    const nextIndex = (currentIndex + direction + options.length) % options.length;
    return options[nextIndex] ?? null;
}

export function wholeHourTimePickerOption(
    options: ReadonlyArray<TimePickerOption>,
    digits: string,
): TimePickerOption | null {
    if (!/^\d{1,2}$/.test(digits)) return null;
    const hour = Number(digits);
    if (!Number.isInteger(hour) || hour < 0 || hour > 23) return null;

    const value = `${String(hour).padStart(2, "0")}:00`;
    return options.find((option) => option.value === value) ?? null;
}
