import type { FrontendSurfaceFragmentProtection, FrontendSurfaceMountedFragmentConfig, LiveUpdateMessage, SurfaceScope } from "../generated/contracts";
import type { FrontendSurfaceMountedInstance } from "./frontend-surface";

export type LiveUpdateDebugDetail = Record<string, unknown>;

export type LiveUpdatePerfSpan = {
    token: string;
    name: string;
    startMark: string;
    detail: LiveUpdateDebugDetail | null;
};

export type LiveUpdatePreservedField = {
    rowId?: string | null;
    fieldKey?: string | null;
    fieldKeyAttr?: string | null;
    name?: string | null;
    value?: string;
};

export type LiveUpdateFragmentWithState = FrontendSurfaceMountedFragmentConfig & {
    preserveField?: LiveUpdatePreservedField;
};

export type SurfaceSubscription = {
    surface: string | null;
    scope: SurfaceScope;
    scopeKey: string;
    path: string;
    resyncFragments: LiveUpdateFragmentWithState[];
    decorateRequestsWithin: string[];
    ownerEl?: HTMLElement;
    ownerEls?: HTMLElement[];
    resync: (subscription: SurfaceSubscription) => void;
};

export type InFlightFragmentState = {
    next: LiveUpdateFragmentWithState | null;
};

export type FragmentProtectionAdapter = {
    matches: (fragment: LiveUpdateFragmentWithState, target: HTMLElement) => boolean;
    hasActiveInput: (target: HTMLElement) => boolean;
    captureState: (target: HTMLElement, fragment: LiveUpdateFragmentWithState) => LiveUpdateFragmentWithState;
    restoreState: (target: HTMLElement, fragment: LiveUpdateFragmentWithState) => void;
};

export type FocusedFieldProtectionPolicy = Extract<FrontendSurfaceFragmentProtection, { kind: "focused-field" }>;
export type LiveUpdateSubscribedMessage = Extract<LiveUpdateMessage, { type: "subscribed" }>;
export type LiveUpdateInvalidateMessage = Extract<LiveUpdateMessage, { type: "invalidate" }>;

export type HtmxConfigRequestEvent = Event & {
    detail?: {
        elt?: unknown;
        headers?: Record<string, string>;
    };
};

export type ActiveSurfaceInstances = Map<string, FrontendSurfaceMountedInstance>;
