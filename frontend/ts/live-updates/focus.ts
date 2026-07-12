import { assertNever } from "../shared/exhaustive";
import type {
    FocusedFieldProtectionPolicy,
    FragmentProtectionAdapter,
    LiveUpdateFragmentWithState,
    LiveUpdatePreservedField,
} from "./runtime-types";

export type FocusedFieldProtection = {
    hasProtectedActiveInput(target: HTMLElement, fragment: LiveUpdateFragmentWithState | undefined): boolean;
    captureDeferredState(target: HTMLElement, fragment: LiveUpdateFragmentWithState): LiveUpdateFragmentWithState;
    restoreDeferredState(fragment: LiveUpdateFragmentWithState): void;
};

export function createFocusedFieldProtection(targetWindow: Window, targetDocument: Document): FocusedFieldProtection {
    const css = (targetWindow as Window & { CSS?: { escape?: (value: string) => string } }).CSS;
    function findPreservedField(root: HTMLElement | null, preserveField: LiveUpdatePreservedField): HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement | null {
        if (!(root instanceof HTMLElement)) return null;

        if (preserveField.fieldKey) {
            const escapedKey = css && typeof css.escape === "function"
                ? css.escape(preserveField.fieldKey)
                : preserveField.fieldKey;
            const keyedField = root.querySelector(`[${preserveField.fieldKeyAttr}="${escapedKey}"]`);
            if (isFormField(keyedField)) return keyedField;
        }

        if (!preserveField.name) return null;
        const escapedName = css && typeof css.escape === "function"
            ? css.escape(preserveField.name)
            : preserveField.name;
        const namedField = root.querySelector(`[name="${escapedName}"]`);
        return isFormField(namedField) ? namedField : null;
    }

    function focusedFieldProtection(policy: FocusedFieldProtectionPolicy): FragmentProtectionAdapter {
        const { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector } = policy;

        function findActiveInput(target: HTMLElement): HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement | null {
            const activeInput = target.querySelector(activeSelector);
            return isFormField(activeInput) ? activeInput : null;
        }

        return {
            hasActiveInput: (target) => Boolean(findActiveInput(target)),
            captureState(target, fragment) {
                const activeInput = findActiveInput(target);
                if (!activeInput) return fragment;

                const name = activeInput.getAttribute("name");
                if (!fieldNameFallback && !activeInput.getAttribute(fieldKeyAttr)) return fragment;

                const containerEl = containerSelector ? activeInput.closest(containerSelector) : null;
                return {
                    ...fragment,
                    preserveField: {
                        rowId: containerEl instanceof HTMLElement ? containerEl.id : null,
                        fieldKey: activeInput.getAttribute(fieldKeyAttr) || null,
                        fieldKeyAttr,
                        name,
                        value: activeInput.value,
                    },
                };
            },
            restoreState(target, fragment) {
                if (!fragment.preserveField) return;
                const root = fragment.preserveField.rowId
                    ? targetDocument.getElementById(fragment.preserveField.rowId)
                    : target;
                const field = findPreservedField(root, fragment.preserveField);
                if (field) field.value = fragment.preserveField.value ?? "";
            },
        };
    }

    function matchingProtection(fragment: LiveUpdateFragmentWithState | undefined): FragmentProtectionAdapter | null {
        if (!fragment) return null;
        switch (fragment.protection.kind) {
            case "focused-field":
                return focusedFieldProtection(fragment.protection);
            case "replace":
                return null;
            default:
                return assertNever(fragment.protection);
        }
    }

    return {
        hasProtectedActiveInput(target, fragment) {
            return Boolean(matchingProtection(fragment)?.hasActiveInput(target));
        },
        captureDeferredState(target, fragment) {
            return matchingProtection(fragment)?.captureState(target, fragment) ?? fragment;
        },
        restoreDeferredState(fragment) {
            const target = targetDocument.getElementById(fragment.targetId);
            if (!(target instanceof HTMLElement)) return;
            matchingProtection(fragment)?.restoreState(target, fragment);
        },
    };
}

function isFormField(value: Element | null): value is HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement {
    return value instanceof HTMLInputElement || value instanceof HTMLSelectElement || value instanceof HTMLTextAreaElement;
}
