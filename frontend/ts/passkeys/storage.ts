export type PasskeyStorageKey = "passkeySeen" | "passkeyPromptDismissedUntil";

export function localStorageKeyForPasskey(userId: string, key: PasskeyStorageKey): string {
    return `ihpRoster.${key}.${userId}`;
}
