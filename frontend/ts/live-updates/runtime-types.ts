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

export type LiveUpdateFragmentWithState = FrontendSurfaceMountedFragmentConfig & {
    preserveField?: LiveUpdatePreservedField;
};

export type SurfaceSubscription = {
    scope: SurfaceScope;
    scopeKey: string;
    path: string;
    resyncFragments: LiveUpdateFragmentWithState[];
    decorateRequestsWithin: string[];
    ownerEls: HTMLElement[];
    resync: (subscription: SurfaceSubscription) => void;
};

export type InFlightFragmentState = {
    next: LiveUpdateFragmentWithState | null;
};

export type FragmentProtectionAdapter = {
    hasActiveInput: (target: HTMLElement) => boolean;
    captureState: (target: HTMLElement, fragment: LiveUpdateFragmentWithState) => LiveUpdateFragmentWithState;
    restoreState: (target: HTMLElement, fragment: LiveUpdateFragmentWithState) => void;
};

export type FocusedFieldProtectionPolicy = Extract<FrontendSurfaceFragmentProtection, { kind: "focused-field" }>;
export type HtmxConfigRequestEvent = Event & {
    detail?: {
        elt?: unknown;
        headers?: Record<string, string>;
    };
};
