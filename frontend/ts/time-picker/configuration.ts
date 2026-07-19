import {
    parseTimePickerConfig,
    parseTimePickerOption,
    type TimePickerConfig,
    type TimePickerOption,
} from "../generated/contracts";

export function parseTimePickerConfiguration(raw: string): TimePickerConfig {
    return validateTimePickerConfiguration(parseTimePickerConfig(JSON.parse(raw)));
}

export function parseTimePickerOptionConfiguration(raw: string): TimePickerOption {
    return validateTimePickerOption(parseTimePickerOption(JSON.parse(raw)));
}

export function timePickerOptionsForConfiguration(
    rawConfig: TimePickerConfig,
    rawOptions: ReadonlyArray<TimePickerOption>,
): TimePickerOption[] {
    const config = validateTimePickerConfiguration(rawConfig);
    const optionsByValue = new Map<string, TimePickerOption>();

    for (const rawOption of rawOptions) {
        const option = validateTimePickerOption(rawOption);
        if (optionsByValue.has(option.value)) {
            throw new Error(`TimePickerOption value ${option.value} must be unique`);
        }
        optionsByValue.set(option.value, option);
    }

    const startMinute = minuteOfDayFromTimeValue(config.rangeStart);
    const rawEndMinute = minuteOfDayFromTimeValue(config.rangeEnd);
    if (startMinute === null || rawEndMinute === null) {
        throw new Error("TimePickerConfig range values must use HH:MM");
    }
    const endMinute = rawEndMinute < startMinute ? rawEndMinute + 24 * 60 : rawEndMinute;
    const selected: TimePickerOption[] = [];

    for (let minute = startMinute; minute <= endMinute; minute += config.stepMinutes) {
        const value = timeValueFromMinuteOfDay(minute);
        const option = optionsByValue.get(value);
        if (option === undefined) {
            throw new Error(`TimePickerConfig missing rendered option ${value}`);
        }
        selected.push(option);
    }

    return selected;
}

function validateTimePickerConfiguration(config: TimePickerConfig): TimePickerConfig {
    if (minuteOfDayFromTimeValue(config.rangeStart) === null || minuteOfDayFromTimeValue(config.rangeEnd) === null) {
        throw new Error("TimePickerConfig range values must use HH:MM");
    }
    if (config.stepMinutes <= 0 || config.stepMinutes > 24 * 60) {
        throw new Error("TimePickerConfig stepMinutes must be between 1 and 1440");
    }
    if (config.emptyLabel.trim().length === 0) {
        throw new Error("TimePickerConfig emptyLabel must not be empty");
    }
    return config;
}

function validateTimePickerOption(option: TimePickerOption): TimePickerOption {
    if (minuteOfDayFromTimeValue(option.value) === null) {
        throw new Error("TimePickerOption value must use HH:MM");
    }
    if (option.label.trim().length === 0) {
        throw new Error("TimePickerOption label must not be empty");
    }
    return option;
}

function minuteOfDayFromTimeValue(value: string): number | null {
    if (!/^\d{2}:\d{2}$/.test(value)) return null;
    const [rawHour, rawMinute] = value.split(":");
    const hour = Number(rawHour);
    const minute = Number(rawMinute);
    if (!Number.isInteger(hour) || !Number.isInteger(minute)) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
}

function timeValueFromMinuteOfDay(totalMinutes: number): string {
    const minuteOfDay = totalMinutes % (24 * 60);
    const hour = Math.floor(minuteOfDay / 60);
    const minute = minuteOfDay % 60;
    return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}
