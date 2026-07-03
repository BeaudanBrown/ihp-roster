import type { LiveFragmentProtection, LiveUpdateScope, LiveUpdateWireFragment } from "../generated/contracts";

export type FrontendSurfaceMountedFragmentConfig = {
    key: {
        kind: string;
        params: unknown;
    };
    targetId: string;
    url: string;
    protection?: {
        kind?: string;
        activeSelector?: unknown;
        fieldKeyAttr?: unknown;
        fieldNameFallback?: unknown;
        containerSelector?: unknown;
    } | null;
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
type LeaveRequestsLiveUpdateScope = Extract<LiveUpdateScope, { kind: "leave_requests" }>;
type BillingLiveUpdateScope = Extract<LiveUpdateScope, { kind: "billing" }>;
type SupportPlatformLiveUpdateScope = Extract<LiveUpdateScope, { kind: "support_platform" }>;
type ProfileLiveUpdateScope = Extract<LiveUpdateScope, { kind: "profile" }>;
type AdminVenueConfigScope = Extract<LiveUpdateScope, { kind: "admin_venue_config" }>;
type AdminInvitesScope = Extract<LiveUpdateScope, { kind: "admin_invites" }>;
type AdminExportsScope = Extract<LiveUpdateScope, { kind: "admin_exports" }>;
type AdminShiftTypesScope = Extract<LiveUpdateScope, { kind: "admin_shift_types" }>;
type AdminRosterGroupsScope = Extract<LiveUpdateScope, { kind: "admin_roster_groups" }>;
type AdminXeroScope = Extract<LiveUpdateScope, { kind: "admin_xero" }>;

export type ParsedFrontendSurfaceSubscriptionConfig = {
    feature: string;
    surface: string;
    scope: LiveUpdateScope;
    scopeKey: string;
    mountKey: string;
    socketPath: string;
    resyncFragments: LiveUpdateWireFragment[];
    decorateRequestsWithin: string[];
};

export type FrontendSurfaceMountedInstance = {
    instanceId: string;
    surface: string;
    scopeKey: string;
    mountKey: string;
    ownerEl: HTMLElement;
    depth: number;
};

export type FrontendSurfaceInstanceReconciliation = {
    added: FrontendSurfaceMountedInstance[];
    removed: FrontendSurfaceMountedInstance[];
    retained: FrontendSurfaceMountedInstance[];
};

export function parseFrontendSurfaceSubscriptionConfig(value: unknown): ParsedFrontendSurfaceSubscriptionConfig | null {
    const config = parseFrontendSurfaceMountConfig(value);
    if (!config) return null;

    if (config.surface === "admin-page" || config.surface === "admin-xero-page") return null;

    if (config.surface === "timesheets") {
        const scope = parseTimesheetsScope(config.scopeKey);
        if (!scope) return null;
        const resyncFragments = config.fragments.map(timesheetsFragmentToWire).filter((fragment): fragment is LiveUpdateWireFragment => fragment !== null);
        if (resyncFragments.length === 0) return null;

        return {
            feature: config.surface,
            surface: config.surface,
            scope,
            scopeKey: `timesheet_week:${scope.venueId}:${scope.weekOffset}`,
            mountKey: config.mountKey,
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
            surface: config.surface,
            scope,
            scopeKey: `roster_week:${scope.venueId}:${scope.rosterGroupId}:${scope.weekOffset}`,
            mountKey: config.mountKey,
            socketPath: "/live-updates",
            resyncFragments,
            decorateRequestsWithin: config.fragments.map((fragment) => `#${fragment.targetId}`),
        };
    }

    if (config.surface === "leave-requests") {
        const scope = parseLeaveRequestsScope(config.scopeKey);
        if (!scope) return null;
        const resyncFragments = config.fragments.map(leaveRequestsFragmentToWire).filter((fragment): fragment is LiveUpdateWireFragment => fragment !== null);
        if (resyncFragments.length === 0) return null;

        return {
            feature: config.surface,
            surface: config.surface,
            scope,
            scopeKey: `leave_requests:${scope.venueId}`,
            mountKey: config.mountKey,
            socketPath: "/live-updates",
            resyncFragments,
            decorateRequestsWithin: config.fragments.map((fragment) => `#${fragment.targetId}`),
        };
    }

    if (config.surface === "billing") {
        const scope = parseBillingScope(config.scopeKey);
        if (!scope) return null;
        const resyncFragments = config.fragments.map(billingFragmentToWire).filter((fragment): fragment is LiveUpdateWireFragment => fragment !== null);
        if (resyncFragments.length === 0) return null;

        return {
            feature: config.surface,
            surface: config.surface,
            scope,
            scopeKey: `billing:${scope.venueId}`,
            mountKey: config.mountKey,
            socketPath: "/live-updates",
            resyncFragments,
            decorateRequestsWithin: config.fragments.map((fragment) => `#${fragment.targetId}`),
        };
    }

    if (config.surface === "support") {
        const scope = parseSupportScope(config.scopeKey);
        if (!scope) return null;
        const resyncFragments = config.fragments.map(supportFragmentToWire).filter((fragment): fragment is LiveUpdateWireFragment => fragment !== null);
        if (resyncFragments.length === 0) return null;

        return {
            feature: config.surface,
            surface: config.surface,
            scope,
            scopeKey: "support_platform",
            mountKey: config.mountKey,
            socketPath: "/live-updates",
            resyncFragments,
            decorateRequestsWithin: config.fragments.map((fragment) => `#${fragment.targetId}`),
        };
    }

    if (config.surface.startsWith("admin-")) {
        const parsed = parseAdminSurface(config);
        if (parsed) return parsed;
    }

    if (config.surface === "profile") {
        const scope = parseProfileScope(config.scopeKey);
        if (!scope) return null;
        const resyncFragments = config.fragments.map(profileFragmentToWire).filter((fragment): fragment is LiveUpdateWireFragment => fragment !== null);
        if (resyncFragments.length === 0) return null;

        return {
            feature: config.surface,
            surface: config.surface,
            scope,
            scopeKey: `profile:${scope.venueId}:${scope.staffId}`,
            mountKey: config.mountKey,
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
        protection: isRecord(value.protection)
            ? {
                kind: typeof value.protection.kind === "string" ? value.protection.kind : undefined,
                activeSelector: value.protection.activeSelector,
                fieldKeyAttr: value.protection.fieldKeyAttr,
                fieldNameFallback: value.protection.fieldNameFallback,
                containerSelector: value.protection.containerSelector,
            }
            : null,
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

function parseLeaveRequestsScope(scopeKey: string): LeaveRequestsLiveUpdateScope | null {
    const match = /^leave-requests:([^:]+)$/.exec(scopeKey);
    if (!match) return null;
    return { kind: "leave_requests", venueId: match[1] };
}

function leaveRequestsFragmentToWire(fragment: FrontendSurfaceMountedFragmentConfig): LiveUpdateWireFragment | null {
    const base = liveFragmentBase(fragment);

    if (fragment.key.kind === "leave-requests-content") {
        return { ...base, fragmentKey: { kind: "leave_requests_content" } };
    }

    return null;
}

function parseBillingScope(scopeKey: string): BillingLiveUpdateScope | null {
    const match = /^billing:([^:]+)$/.exec(scopeKey);
    if (!match) return null;
    return { kind: "billing", venueId: match[1] };
}

function billingFragmentToWire(fragment: FrontendSurfaceMountedFragmentConfig): LiveUpdateWireFragment | null {
    const base = liveFragmentBase(fragment);

    if (fragment.key.kind === "billing-status") {
        return { ...base, fragmentKey: { kind: "billing_status" } };
    }

    return null;
}

function parseSupportScope(scopeKey: string): SupportPlatformLiveUpdateScope | null {
    if (scopeKey !== "support") return null;
    return { kind: "support_platform" };
}

function supportFragmentToWire(fragment: FrontendSurfaceMountedFragmentConfig): LiveUpdateWireFragment | null {
    const base = liveFragmentBase(fragment);

    if (fragment.key.kind === "support-award-rates") {
        return { ...base, fragmentKey: { kind: "support_award_rates_section" } };
    }

    if (fragment.key.kind === "support-public-holidays") {
        return { ...base, fragmentKey: { kind: "support_public_holidays_section" } };
    }

    return null;
}

function parseAdminSurface(config: FrontendSurfaceMountConfig): ParsedFrontendSurfaceSubscriptionConfig | null {
    const scope = parseAdminScope(config.surface, config.scopeKey);
    if (!scope) return null;
    const resyncFragments = config.fragments.map(adminFragmentToWire).filter((fragment): fragment is LiveUpdateWireFragment => fragment !== null);
    if (resyncFragments.length === 0) return null;
    return {
        feature: config.surface,
        surface: config.surface,
        scope,
        scopeKey: adminWireScopeKey(scope),
        mountKey: config.mountKey,
        socketPath: "/live-updates",
        resyncFragments,
        decorateRequestsWithin: config.fragments.map((fragment) => `#${fragment.targetId}`),
    };
}

function parseAdminScope(surface: string, scopeKey: string): AdminVenueConfigScope | AdminInvitesScope | AdminExportsScope | AdminShiftTypesScope | AdminRosterGroupsScope | AdminXeroScope | null {
    const match = /^admin-[^:]+(?:-[^:]+)*:([^:]+)(?::([^:]+))?$/.exec(scopeKey);
    if (!match) return null;
    const venueId = match[1];
    if (surface === "admin-venue-config") return { kind: "admin_venue_config", venueId };
    if (surface === "admin-invites") return { kind: "admin_invites", venueId };
    if (surface === "admin-exports") return { kind: "admin_exports", venueId };
    if (surface === "admin-shift-types") return { kind: "admin_shift_types", venueId };
    if (surface === "admin-roster-groups") return { kind: "admin_roster_groups", venueId };
    if (surface === "admin-xero") return { kind: "admin_xero", venueId };
    return null;
}

function adminWireScopeKey(scope: AdminVenueConfigScope | AdminInvitesScope | AdminExportsScope | AdminShiftTypesScope | AdminRosterGroupsScope | AdminXeroScope): string {
    return `${scope.kind}:${scope.venueId}`;
}

function adminFragmentToWire(fragment: FrontendSurfaceMountedFragmentConfig): LiveUpdateWireFragment | null {
    const base = liveFragmentBase(fragment);
    if (fragment.key.kind === "admin-venue-config") return { ...base, fragmentKey: { kind: "admin_venue_config" } };
    if (fragment.key.kind === "admin-invites") return { ...base, fragmentKey: { kind: "admin_invites" } };
    if (fragment.key.kind === "admin-exports") return { ...base, fragmentKey: { kind: "admin_exports" } };
    if (fragment.key.kind === "admin-shift-types") return { ...base, fragmentKey: { kind: "admin_shift_types" } };
    if (fragment.key.kind === "admin-roster-groups") return { ...base, fragmentKey: { kind: "admin_roster_groups" } };
    if (fragment.key.kind === "admin-xero") return { ...base, fragmentKey: { kind: "admin_xero" } };
    if (fragment.key.kind === "admin-xero-staff-mappings") return { ...base, fragmentKey: { kind: "admin_xero_staff_mappings" } };
    if (fragment.key.kind === "admin-xero-pay-items") return { ...base, fragmentKey: { kind: "admin_xero_pay_items" } };
    if (fragment.key.kind === "admin-xero-timesheets") return { ...base, fragmentKey: { kind: "admin_xero_timesheets" } };
    return null;
}

function parseProfileScope(scopeKey: string): ProfileLiveUpdateScope | null {
    const match = /^profile:([^:]+):([^:]+)$/.exec(scopeKey);
    if (!match) return null;
    return { kind: "profile", venueId: match[1], staffId: match[2] };
}

function profileFragmentToWire(fragment: FrontendSurfaceMountedFragmentConfig): LiveUpdateWireFragment | null {
    const base = liveFragmentBase(fragment);

    if (fragment.key.kind === "profile-details-section") {
        return { ...base, fragmentKey: { kind: "profile_details_section" } };
    }

    if (fragment.key.kind === "profile-preferences-section") {
        return { ...base, fragmentKey: { kind: "profile_preferences_section" } };
    }

    if (fragment.key.kind === "profile-security-section") {
        return { ...base, fragmentKey: { kind: "profile_security_section" } };
    }

    if (fragment.key.kind === "profile-leave-section") {
        return { ...base, fragmentKey: { kind: "profile_leave_section" } };
    }

    if (fragment.key.kind === "profile-rsa-section") {
        return { ...base, fragmentKey: { kind: "profile_rsa_section" } };
    }

    return null;
}

function liveFragmentBase(fragment: FrontendSurfaceMountedFragmentConfig) {
    return {
        targetId: fragment.targetId,
        url: fragment.url,
        deferUntilBlur: false,
        protectionPolicy: fragmentProtectionToWire(fragment.protection),
    };
}

function fragmentProtectionToWire(protection: FrontendSurfaceMountedFragmentConfig["protection"]): LiveFragmentProtection {
    if (protection?.kind !== "focused-field") return { kind: "none" };
    if (typeof protection.activeSelector !== "string") return { kind: "none" };
    if (typeof protection.fieldKeyAttr !== "string") return { kind: "none" };
    if (typeof protection.fieldNameFallback !== "boolean") return { kind: "none" };
    if (protection.containerSelector !== null && protection.containerSelector !== undefined && typeof protection.containerSelector !== "string") return { kind: "none" };

    return {
        kind: "focused_field",
        activeSelector: protection.activeSelector,
        fieldKeyAttr: protection.fieldKeyAttr,
        fieldNameFallback: protection.fieldNameFallback,
        containerSelector: protection.containerSelector ?? null,
    };
}

export function frontendSurfaceInstanceId(config: Pick<FrontendSurfaceMountConfig, "surface" | "scopeKey" | "mountKey">): string {
    return `${config.surface}:${config.scopeKey}:${config.mountKey}`;
}

export function scanFrontendSurfaceMountInstances(root?: ParentNode): FrontendSurfaceMountedInstance[] {
    const scanRoot = root ?? (typeof document !== "undefined" ? document : null);
    if (!scanRoot) return [];

    const instances: FrontendSurfaceMountedInstance[] = [];
    scanRoot.querySelectorAll('[data-bepis-surface-config]').forEach((ownerEl) => {
        if (!(ownerEl instanceof HTMLElement)) return;
        const rawConfig = ownerEl.getAttribute('data-bepis-surface-config');
        if (!rawConfig) return;

        let parsedJson: unknown;
        try {
            parsedJson = JSON.parse(rawConfig);
        } catch (_error) {
            return;
        }

        const config = parseFrontendSurfaceMountConfig(parsedJson);
        if (!config) return;
        instances.push({
            instanceId: frontendSurfaceInstanceId(config),
            surface: config.surface,
            scopeKey: config.scopeKey,
            mountKey: config.mountKey,
            ownerEl,
            depth: surfaceMountDepth(ownerEl),
        });
    });
    return instances;
}

export function reconcileFrontendSurfaceInstances(
    activeInstances: ReadonlyMap<string, FrontendSurfaceMountedInstance>,
    currentInstances: FrontendSurfaceMountedInstance[],
): FrontendSurfaceInstanceReconciliation {
    const currentById = new Map<string, FrontendSurfaceMountedInstance>();
    currentInstances.forEach((instance) => currentById.set(instance.instanceId, instance));

    const removed: FrontendSurfaceMountedInstance[] = [];
    activeInstances.forEach((instance, instanceId) => {
        if (!currentById.has(instanceId)) removed.push(instance);
    });

    const added: FrontendSurfaceMountedInstance[] = [];
    const retained: FrontendSurfaceMountedInstance[] = [];
    currentById.forEach((instance, instanceId) => {
        if (activeInstances.has(instanceId)) retained.push(instance);
        else added.push(instance);
    });

    removed.sort((left, right) => right.depth - left.depth);
    return { added, removed, retained };
}

function surfaceMountDepth(ownerEl: HTMLElement): number {
    let depth = 0;
    let current: HTMLElement | null = ownerEl.parentElement;
    while (current) {
        if (current.hasAttribute('data-bepis-surface-config')) depth += 1;
        current = current.parentElement;
    }
    return depth;
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}
