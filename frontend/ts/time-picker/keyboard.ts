import type { TimePickerOption } from "../generated/contracts";

export type TimePickerStepDirection = -1 | 1;

export function compactTimePickerValue(
    digits: string,
    stepMinutes: number,
    rangeStart: string,
    rangeEnd: string,
): string | null {
    if (!/^\d{1,4}$/.test(digits) || (stepMinutes !== 1 && stepMinutes !== 15)) return null;

    if (digits.length <= 2) {
        const hour = Number(digits);
        if (!Number.isInteger(hour) || hour < 0 || hour > 23) return null;
        const value = `${String(hour).padStart(2, "0")}:00`;
        return timeIsSelectable(value, stepMinutes, rangeStart, rangeEnd) ? value : null;
    }

    const hour = Number(digits.slice(0, 2));
    if (!Number.isInteger(hour) || hour < 0 || hour > 23) return null;
    const minuteDigits = digits.slice(2);
    const candidates = Array.from({ length: 60 / stepMinutes }, (_, index) => index * stepMinutes)
        .filter((minute) => String(minute).padStart(2, "0").startsWith(minuteDigits));
    for (const minute of candidates) {
        const value = `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
        if (timeIsSelectable(value, stepMinutes, rangeStart, rangeEnd)) return value;
    }
    return null;
}

function timeIsSelectable(value: string, stepMinutes: number, rangeStart: string, rangeEnd: string): boolean {
    const minute = parseMinute(value);
    const start = parseMinute(rangeStart);
    const rawEnd = parseMinute(rangeEnd);
    if (minute === null || start === null || rawEnd === null || minute % stepMinutes !== 0) return false;
    const end = rawEnd < start ? rawEnd + 24 * 60 : rawEnd;
    const normalized = minute < start ? minute + 24 * 60 : minute;
    return normalized >= start && normalized <= end;
}

function parseMinute(value: string): number | null {
    const match = /^(\d{2}):(\d{2})$/.exec(value);
    if (match === null) return null;
    const hour = Number(match[1]);
    const minute = Number(match[2]);
    return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 ? hour * 60 + minute : null;
}

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
