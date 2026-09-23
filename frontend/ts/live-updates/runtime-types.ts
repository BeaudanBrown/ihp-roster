import type { FrontendSurfaceFragmentProtection, FrontendSurfaceMountedFragmentConfig, SurfaceScope } from "../generated/contracts";

export type LiveUpdateDebugDetail = Record<string, unknown>;

export type LiveUpdatePerfSpan = {
    token: string;
    name: string;
    startMark: string;
    detail: LiveUpdateDebugDetail | null;
};

export type LiveUpdatePreservedField = {
    rowId: string | null;
    fieldKey: string | null;
    fieldKeyAttr: string;
    name: string | null;
    value: string;
};

export type LiveUpdateRequestOrigin = "actor" | "passive" | "resync";

export type LiveUpdateFragmentWithState = FrontendSurfaceMountedFragmentConfig & {
    ownerEl: HTMLElement;
    preserveField?: LiveUpdatePreservedField;
    requestOrigin?: LiveUpdateRequestOrigin;
    requestVersion?: number;
};

export type SurfaceSubscription = {
    scope: SurfaceScope;
    scopeKey: string;
    path: string;
    resyncFragments: LiveUpdateFragmentWithState[];
    renderedDependencyWatermark: number;
    ownerEls: HTMLElement[];
};

export type FragmentProtectionAdapter = {
    hasActiveInput: (target: HTMLElement) => boolean;
    captureState: (target: HTMLElement, fragment: LiveUpdateFragmentWithState) => LiveUpdateFragmentWithState;
    restoreState: (target: HTMLElement, fragment: LiveUpdateFragmentWithState) => void;
};

export type FocusedFieldProtectionPolicy = Extract<FrontendSurfaceFragmentProtection, { kind: "focused-field" }>;
