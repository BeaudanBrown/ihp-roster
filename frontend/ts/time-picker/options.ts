export type TimeRange = {
    startMinute: number;
    endMinute: number;
};

export type TimeOption = {
    value: string;
    label: string;
};

export function minuteOfDayFromTimeValue(value: string): number | null {
    if (!value || !/^\d{2}:\d{2}$/.test(value)) return null;
    const parts = value.split(":");
    const hour = Number(parts[0]);
    const minute = Number(parts[1]);
    if (!Number.isInteger(hour) || !Number.isInteger(minute)) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
}

export function displayLabelFromTimeValue(value: string): string {
    const minuteOfDay = minuteOfDayFromTimeValue(value);
    if (minuteOfDay === null) return value;

    const hour24 = Math.floor(minuteOfDay / 60);
    const minute = minuteOfDay % 60;
    const meridiem = hour24 >= 12 ? "PM" : "AM";
    const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
    const minuteLabel = String(minute).padStart(2, "0");
    return `${hour12}:${minuteLabel} ${meridiem}`;
}

export function buildTimeOptionsWithStepForRange(range: TimeRange | null, stepMinutes: number): TimeOption[] {
    if (range === null) return [];

    const options: TimeOption[] = [];
    for (let minute = range.startMinute; minute <= range.endMinute; minute += stepMinutes) {
        const minuteOfDay = minute % (24 * 60);
        const hour = Math.floor(minuteOfDay / 60);
        const minutePart = minuteOfDay % 60;
        const value = `${String(hour).padStart(2, "0")}:${String(minutePart).padStart(2, "0")}`;
        options.push({ value, label: displayLabelFromTimeValue(value) });
    }
    return options;
}
