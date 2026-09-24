import type { DialogDismissalGuardConfig } from "../generated/contracts";

export interface UnsavedChangeTracker {
    isGuarded(currentSnapshot: string): boolean;
    baselineSnapshot: string;
}

export function createUnsavedChangeTracker(baselineSnapshot: string, guardImmediately: boolean): UnsavedChangeTracker {
    return {
        baselineSnapshot,
        isGuarded: (currentSnapshot) => guardImmediately || currentSnapshot !== baselineSnapshot,
    };
}

export function normalizedFormSnapshot(form: HTMLFormElement): string {
    const entries = Array.from(new FormData(form).entries()).map(([name, value], index) => ({
        name,
        value: normalizeEntryValue(value),
        index,
    }));
    entries.sort((left, right) => left.name.localeCompare(right.name) || left.index - right.index);
    return JSON.stringify(entries.map(({ name, value }) => [name, value]));
}

function normalizeEntryValue(value: FormDataEntryValue): string {
    if (typeof value === "string") return value.replace(/\r\n?/g, "\n");
    return JSON.stringify({ name: value.name, size: value.size, type: value.type, lastModified: value.lastModified });
}

export function validateDismissalGuardConfig(config: DialogDismissalGuardConfig): DialogDismissalGuardConfig {
    if (config.formId.trim().length === 0) throw new Error("DialogDismissalGuardConfig formId must not be empty");
    if (config.confirmationTitle.trim().length === 0) throw new Error("DialogDismissalGuardConfig confirmationTitle must not be empty");
    if (config.keepEditingLabel.trim().length === 0) throw new Error("DialogDismissalGuardConfig keepEditingLabel must not be empty");
    if (config.discardLabel.trim().length === 0) throw new Error("DialogDismissalGuardConfig discardLabel must not be empty");
    return config;
}
