import type { DialogDismissalGuardConfig } from "../generated/contracts";

export { createUnsavedChangeTracker, normalizedFormSnapshot, type UnsavedChangeTracker } from "../shared/form-state";

export function validateDismissalGuardConfig(config: DialogDismissalGuardConfig): DialogDismissalGuardConfig {
    if (config.formId.trim().length === 0) throw new Error("DialogDismissalGuardConfig formId must not be empty");
    if (config.confirmationTitle.trim().length === 0) throw new Error("DialogDismissalGuardConfig confirmationTitle must not be empty");
    if (config.keepEditingLabel.trim().length === 0) throw new Error("DialogDismissalGuardConfig keepEditingLabel must not be empty");
    if (config.discardLabel.trim().length === 0) throw new Error("DialogDismissalGuardConfig discardLabel must not be empty");
    return config;
}
