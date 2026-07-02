import type { LiveUpdateScope, LiveUpdateWireFragment } from "../generated/contracts";

export type FrontendSurfaceMountedFragmentConfig = {
    key: {
        kind: string;
        params: unknown;
    };
    targetId: string;
    url: string;
    protection?: { kind?: string } | null;
    loadPolicy?: string | null;
};

export type FrontendSurfaceMountConfig = {
    surface: string;
    scopeKey: string;
    mountKey: string;
    mountState: unknown;
    fragments: FrontendSurfaceMountedFragmentConfig[];
};

type TimesheetWeekLiveUpdateScope = Extract<LiveUpdateScope, { kind: "timesheet_week" }>;
type RosterWeekLiveUpdateScope = Extract<LiveUpdateScope, { kind: "roster_week" }>;

export type ParsedFrontendSurfaceSubscriptionConfig = {
    feature: string;
    scope: LiveUpdateScope;
    scopeKey: string;
    socketPath: string;
    resyncFragments: LiveUpdateWireFragment[];
    decorateRequestsWithin: string[];
};

export function parseFrontendSurfaceSubscriptionConfig(value: unknown): ParsedFrontendSurfaceSubscriptionConfig | null {
    const config = parseFrontendSurfaceMountConfig(value);
    if (!config) return null;

    if (config.surface === "timesheets") {
        const scope = parseTimesheetsScope(config.scopeKey);
        if (!scope) return null;
        const resyncFragments = config.fragments.map(timesheetsFragmentToWire).filter((fragment): fragment is LiveUpdateWireFragment => fragment !== null);
        if (resyncFragments.length === 0) return null;

        return {
            feature: config.surface,
            scope,
            scopeKey: `timesheet_week:${scope.venueId}:${scope.weekOffset}`,
            socketPath: "/live-updates",
            resyncFragments,
            decorateRequestsWithin: config.fragments.map((fragment) => `#${fragment.targetId}`),
        };
    }

    if (config.surface === "roster") {
        const scope = parseRosterScope(config.scopeKey);
        if (!scope) return null;
        const resyncFragments = config.fragments.map(rosterFragmentToWire).filter((fragment): fragment is LiveUpdateWireFragment => fragment !== null);
        if (resyncFragments.length === 0) return null;

        return {
            feature: config.surface,
            scope,
            scopeKey: `roster_week:${scope.venueId}:${scope.rosterGroupId}:${scope.weekOffset}`,
            socketPath: "/live-updates",
            resyncFragments,
            decorateRequestsWithin: config.fragments.map((fragment) => `#${fragment.targetId}`),
        };
    }

    return null;
}

export function parseFrontendSurfaceMountConfig(value: unknown): FrontendSurfaceMountConfig | null {
    if (!isRecord(value)) return null;
    if (typeof value.surface !== "string") return null;
    if (typeof value.scopeKey !== "string") return null;
    if (typeof value.mountKey !== "string") return null;
    if (!Array.isArray(value.fragments)) return null;

    const fragments = value.fragments.map(parseMountedFragmentConfig);
    if (fragments.some((fragment) => fragment === null)) return null;

    return {
        surface: value.surface,
        scopeKey: value.scopeKey,
        mountKey: value.mountKey,
        mountState: value.mountState,
        fragments: fragments as FrontendSurfaceMountedFragmentConfig[],
    };
}

function parseMountedFragmentConfig(value: unknown): FrontendSurfaceMountedFragmentConfig | null {
    if (!isRecord(value)) return null;
    if (!isRecord(value.key)) return null;
    if (typeof value.key.kind !== "string") return null;
    if (typeof value.targetId !== "string") return null;
    if (typeof value.url !== "string") return null;

    return {
        key: {
            kind: value.key.kind,
            params: value.key.params,
        },
        targetId: value.targetId,
        url: value.url,
        protection: isRecord(value.protection) ? { kind: typeof value.protection.kind === "string" ? value.protection.kind : undefined } : null,
        loadPolicy: typeof value.loadPolicy === "string" ? value.loadPolicy : null,
    };
}

function parseTimesheetsScope(scopeKey: string): TimesheetWeekLiveUpdateScope | null {
    const match = /^timesheets:([^:]+):(-?\d+)$/.exec(scopeKey);
    if (!match) return null;
    const weekOffset = Number(match[2]);
    if (!Number.isInteger(weekOffset)) return null;
    return { kind: "timesheet_week", venueId: match[1], weekOffset };
}

function timesheetsFragmentToWire(fragment: FrontendSurfaceMountedFragmentConfig): LiveUpdateWireFragment | null {
    const base = liveFragmentBase(fragment);

    if (fragment.key.kind === "timesheet-toolbar") {
        return { ...base, fragmentKey: { kind: "timesheet_toolbar" } };
    }

    if (fragment.key.kind === "timesheet-day-columns") {
        return { ...base, fragmentKey: { kind: "timesheet_day_columns" } };
    }

    if (fragment.key.kind === "timesheet-day-section") {
        const params = fragment.key.params;
        if (!isRecord(params) || typeof params.dayOffset !== "number" || !Number.isInteger(params.dayOffset)) return null;
        return { ...base, fragmentKey: { kind: "timesheet_day_section", dayOffset: params.dayOffset } };
    }

    return null;
}

function parseRosterScope(scopeKey: string): RosterWeekLiveUpdateScope | null {
    const match = /^roster:([^:]+):([^:]+):(-?\d+)$/.exec(scopeKey);
    if (!match) return null;
    const weekOffset = Number(match[3]);
    if (!Number.isInteger(weekOffset)) return null;
    return { kind: "roster_week", venueId: match[1], rosterGroupId: match[2], weekOffset };
}

function rosterFragmentToWire(fragment: FrontendSurfaceMountedFragmentConfig): LiveUpdateWireFragment | null {
    const base = liveFragmentBase(fragment);

    if (fragment.key.kind === "roster-content") {
        return { ...base, fragmentKey: { kind: "roster_content" } };
    }

    if (fragment.key.kind === "roster-grid-toolbar") {
        return { ...base, fragmentKey: { kind: "roster_grid_toolbar" } };
    }

    if (fragment.key.kind === "roster-grid-frame") {
        return { ...base, fragmentKey: { kind: "roster_grid_frame" } };
    }

    if (fragment.key.kind === "roster-day-columns") {
        return { ...base, fragmentKey: { kind: "roster_day_columns" } };
    }

    if (fragment.key.kind === "roster-day-rail") {
        return { ...base, fragmentKey: { kind: "roster_day_rail" } };
    }

    if (fragment.key.kind === "roster-wage-rail") {
        return { ...base, fragmentKey: { kind: "roster_wage_rail" } };
    }

    if (fragment.key.kind === "roster-slots-grid") {
        return { ...base, fragmentKey: { kind: "roster_slots_grid" } };
    }

    if (fragment.key.kind === "roster-staff-panel") {
        return { ...base, fragmentKey: { kind: "roster_staff_panel" } };
    }

    if (fragment.key.kind === "roster-day-section") {
        const params = fragment.key.params;
        if (!isRecord(params) || typeof params.rosterDayId !== "string") return null;
        return { ...base, fragmentKey: { kind: "roster_day_section", rosterDayId: params.rosterDayId } };
    }

    if (fragment.key.kind === "roster-row") {
        const params = fragment.key.params;
        if (!isRecord(params) || typeof params.rosterDayId !== "string" || typeof params.rowIndex !== "number" || !Number.isInteger(params.rowIndex)) return null;
        return { ...base, fragmentKey: { kind: "roster_row", rosterDayId: params.rosterDayId, rowIndex: params.rowIndex } };
    }

    return null;
}

function liveFragmentBase(fragment: FrontendSurfaceMountedFragmentConfig) {
    return {
        targetId: fragment.targetId,
        url: fragment.url,
        deferUntilBlur: false,
        protectionPolicy: { kind: "none" as const },
    };
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}
