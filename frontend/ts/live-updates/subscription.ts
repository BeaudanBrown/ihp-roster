import { surfaceConfigDomAttr, surfaceDomAttr } from "../generated/contracts";
import type { FrontendSurfaceMountErrorReporter } from "./mount";
import { parseFrontendSurfaceSubscriptionConfig, readFrontendSurfaceMountElement } from "./mount";
import { buildSurfaceSubscription, liveUpdateFragmentMergeKey } from "./protocol";
import type { LiveUpdateFragmentWithState, SurfaceSubscription } from "./runtime-types";

export const surfaceConfigSelector = `[${surfaceConfigDomAttr}]`;

export function createSurfaceConfigErrorReporter(targetDocument: Document): FrontendSurfaceMountErrorReporter {
    return (ownerEl, error) => {
        const detail = {
            id: ownerEl.id || null,
            surface: ownerEl.getAttribute(surfaceDomAttr),
            error: error.message,
        };
        console.error?.("Invalid live-update surface config", detail);
        targetDocument.dispatchEvent(new CustomEvent("app:live-update-surface-config-failed", { detail }));
    };
}

export function readSurfaceSubscription(
    ownerEl: HTMLElement,
    requestRefresh: (fragment: LiveUpdateFragmentWithState) => void,
    reportError?: FrontendSurfaceMountErrorReporter,
): SurfaceSubscription | null {
    const config = readFrontendSurfaceMountElement(ownerEl, reportError);
    if (!config) return null;
    const parsed = parseFrontendSurfaceSubscriptionConfig(config);
    if (!parsed) return null;

    return {
        scope: parsed.scope,
        scopeKey: parsed.scopeKey,
        path: parsed.socketPath,
        resyncFragments: parsed.resyncFragments,
        renderedDependencyWatermark: parsed.renderedDependencyWatermark,
        ownerEls: [ownerEl],
        resync: (subscription) => subscription.resyncFragments.forEach(requestRefresh),
    };
}

export function collectDesiredSurfaceSubscriptions(
    targetDocument: Document,
    requestRefresh: (fragment: LiveUpdateFragmentWithState) => void,
    reportError?: FrontendSurfaceMountErrorReporter,
): Map<string, SurfaceSubscription> {
    const desired = new Map<string, SurfaceSubscription>();
    targetDocument.querySelectorAll(surfaceConfigSelector).forEach((ownerEl) => {
        if (!(ownerEl instanceof HTMLElement)) return;
        const subscription = readSurfaceSubscription(ownerEl, requestRefresh, reportError);
        if (!subscription?.scopeKey) return;
        desired.set(subscription.scopeKey, mergeSubscription(desired.get(subscription.scopeKey), subscription));
    });
    return desired;
}

export function wireSurfaceSubscription(subscription: SurfaceSubscription) {
    return buildSurfaceSubscription(
        subscription.scope,
        subscription.scopeKey,
        subscription.resyncFragments.map((fragment) => fragment.fragmentKey),
        subscription.renderedDependencyWatermark,
    );
}

export function subscriptionsEquivalent(left: SurfaceSubscription | undefined, right: SurfaceSubscription): boolean {
    return Boolean(left && subscriptionSignature(left) === subscriptionSignature(right));
}

function subscriptionSignature(subscription: SurfaceSubscription): string {
    const fragments = subscription.resyncFragments
        .map((fragment) => ({ key: liveUpdateFragmentMergeKey(fragment) || JSON.stringify(fragment.fragmentKey), fragment }))
        .sort((left, right) => left.key.localeCompare(right.key))
        .map((entry) => entry.fragment);
    return JSON.stringify({ path: subscription.path, scope: subscription.scope, resyncFragments: fragments, renderedDependencyWatermark: subscription.renderedDependencyWatermark });
}

function mergeSubscription(existing: SurfaceSubscription | undefined, next: SurfaceSubscription): SurfaceSubscription {
    if (!existing) return next;
    return {
        ...existing,
        resyncFragments: mergeFragments(existing.resyncFragments, next.resyncFragments),
        ownerEls: existing.ownerEls.concat(next.ownerEls),
        renderedDependencyWatermark: Math.min(existing.renderedDependencyWatermark, next.renderedDependencyWatermark),
    };
}

function mergeFragments(existing: LiveUpdateFragmentWithState[], next: LiveUpdateFragmentWithState[]): LiveUpdateFragmentWithState[] {
    const merged: LiveUpdateFragmentWithState[] = [];
    const seen = new Set<string>();
    existing.concat(next).forEach((fragment) => {
        const key = liveUpdateFragmentMergeKey(fragment);
        if (!key || seen.has(key)) return;
        seen.add(key);
        merged.push(fragment);
    });
    return merged;
}
