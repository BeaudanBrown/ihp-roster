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
        value: typeof value === "string"
            ? value.replace(/\r\n?/g, "\n")
            : JSON.stringify({ name: value.name, size: value.size, type: value.type, lastModified: value.lastModified }),
        index,
    }));
    entries.sort((left, right) => left.name.localeCompare(right.name) || left.index - right.index);
    return JSON.stringify(entries.map(({ name, value }) => [name, value]));
}
