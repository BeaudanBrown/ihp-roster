import { InteractionDom, isInteractionConflictResolution, type InteractionConflictResolution } from "../generated/contracts";
import type { LiveUpdateMountedFragment } from "../live-updates/frontend-surface";
import type { InteractionSessionSnapshot } from "./session-state";

export type ActiveInteractionSessionTracker = {
    findForTarget(target: Element): InteractionSessionSnapshot | null;
    requestCancel(session: InteractionSessionSnapshot, reason: string): void;
};

export type LiveFragmentInteractionConflict = {
    action: InteractionConflictResolution;
    session: InteractionSessionSnapshot;
    timeoutMs: number | null;
};

type WireConflictPolicy = {
    session?: string | "*";
    targetId?: string | "*";
    resolution?: InteractionConflictResolution;
    timeoutMs?: number | null;
};

const attrs = InteractionDom.attributes;
// Deferral is session-bound: passive fragments should flush as soon as the
// interaction session ends. This timeout is only a fallback watchdog for stuck
// or lost session-end events, not the ordinary delay mechanism.
const defaultInteractionDeferFallbackTimeoutMs = 5000;

export function resolveLiveFragmentInteractionConflict(
    fragment: Pick<LiveUpdateMountedFragment, "targetId">,
    target: Element,
    tracker: ActiveInteractionSessionTracker
): LiveFragmentInteractionConflict | null {
    const session = tracker.findForTarget(target);
    if (!session) return null;

    const policy = matchingConflictPolicy(session, fragment, target);
    const action = policy?.resolution ?? "defer";
    const timeoutMs = policy?.timeoutMs ?? (action === "defer" ? defaultInteractionDeferFallbackTimeoutMs : null);

    return { action, session, timeoutMs };
}

export function readInteractionConflictPolicies(mount: Element): WireConflictPolicy[] {
    const raw = mount.getAttribute(attrs.conflictPolicies);
    if (!raw) return [];

    try {
        const parsed = JSON.parse(raw);
        if (!Array.isArray(parsed)) return [];
        return parsed.filter(isWireConflictPolicy);
    } catch (_error) {
        return [];
    }
}

function matchingConflictPolicy(session: InteractionSessionSnapshot, fragment: Pick<LiveUpdateMountedFragment, "targetId">, target: Element): WireConflictPolicy | null {
    const mount = target.closest(`[${attrs.surface}]`);
    if (!mount) return null;

    const policies = readInteractionConflictPolicies(mount);
    return policies.find((policy) => {
        const sessionMatches = policy.session === "*" || policy.session === session.sessionKind;
        const targetMatches = policy.targetId === "*" || policy.targetId === fragment.targetId;
        return sessionMatches && targetMatches;
    }) ?? null;
}

function isWireConflictPolicy(value: unknown): value is WireConflictPolicy {
    if (value === null || typeof value !== "object") return false;
    const maybe = value as WireConflictPolicy;
    return isOptionalString(maybe.session)
        && isOptionalString(maybe.targetId)
        && isOptionalResolution(maybe.resolution)
        && (maybe.timeoutMs === undefined || maybe.timeoutMs === null || typeof maybe.timeoutMs === "number");
}

function isOptionalString(value: unknown): boolean {
    return value === undefined || typeof value === "string";
}

function isOptionalResolution(value: unknown): value is InteractionConflictResolution | undefined {
    return value === undefined || isInteractionConflictResolution(value);
}
