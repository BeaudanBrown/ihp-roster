import { surfaceConfigDomAttr } from "../generated/contracts";
import { resolveLiveFragmentInteractionConflict, type ActiveInteractionSessionTracker } from "../interaction/live-conflicts";
import type { createLiveUpdateDiagnostics } from "./diagnostics";
import { createFocusedFieldProtection } from "./focus";
import { decorateSurfaceFragmentRequest } from "./request-context";
import type { LiveUpdateFragmentWithState } from "./runtime-types";

export type LiveFragmentRefresher = {
    activateOwner(ownerEl: HTMLElement): void;
    disposeOwner(ownerEl: HTMLElement): void;
    markProtectionChanged(target: Element): void;
    request(fragment: LiveUpdateFragmentWithState): void;
    flushInteractionDeferredFragmentsWithoutActiveSessions(): void;
    flushFocusedFragmentsWithoutActiveInputs(): void;
    stop(): void;
};

type LiveUpdateDiagnostics = ReturnType<typeof createLiveUpdateDiagnostics>;

type FragmentRequestSlot = {
    controller: AbortController;
    fragment: LiveUpdateFragmentWithState;
    fetchedTarget: HTMLElement | null;
    generation: number;
    next: LiveUpdateFragmentWithState | null;
    protectionChanged: boolean;
};

type OwnerRefreshState = {
    active: boolean;
    inFlight: Map<string, FragmentRequestSlot>;
    pendingFocused: Map<string, LiveUpdateFragmentWithState>;
    pendingInteraction: Map<string, LiveUpdateFragmentWithState>;
    pendingInteractionTimers: Map<string, ReturnType<Window["setTimeout"]>>;
};

export function createLiveFragmentRefresher(options: {
    targetWindow: Window & typeof globalThis;
    targetDocument: Document;
    diagnostics: LiveUpdateDiagnostics;
    activeInteractionSessions: ActiveInteractionSessionTracker;
}): LiveFragmentRefresher {
    const { targetWindow, targetDocument, diagnostics, activeInteractionSessions } = options;
    const { beginPerfSpan, endPerfSpan, emitDebugEvent } = diagnostics;
    const focus = createFocusedFieldProtection(targetWindow, targetDocument);
    const ownerStates = new Map<HTMLElement, OwnerRefreshState>();
    let generation = 1;
    let stopped = false;

    function activateOwner(ownerEl: HTMLElement): void {
        if (stopped) return;
        const existing = ownerStates.get(ownerEl);
        if (existing) {
            existing.active = true;
            return;
        }
        ownerStates.set(ownerEl, {
            active: true,
            inFlight: new Map(),
            pendingFocused: new Map(),
            pendingInteraction: new Map(),
            pendingInteractionTimers: new Map(),
        });
    }

    function resolveOwnedTarget(fragment: LiveUpdateFragmentWithState): HTMLElement | null {
        const target = targetDocument.getElementById(fragment.targetId);
        if (!(target instanceof HTMLElement) || !fragment.ownerEl.contains(target)) return null;
        const closestOwner = target === fragment.ownerEl
            ? fragment.ownerEl
            : target.closest(`[${surfaceConfigDomAttr}]`);
        return closestOwner === fragment.ownerEl ? target : null;
    }

    function requestIsCurrent(state: OwnerRefreshState, targetId: string, slot: FragmentRequestSlot): boolean {
        return !stopped
            && state.active
            && slot.generation === generation
            && !slot.controller.signal.aborted
            && state.inFlight.get(targetId) === slot;
    }

    function clearInteractionDeferredFragment(state: OwnerRefreshState, targetId: string): void {
        const timer = state.pendingInteractionTimers.get(targetId);
        if (timer) targetWindow.clearTimeout(timer);
        state.pendingInteractionTimers.delete(targetId);
        state.pendingInteraction.delete(targetId);
    }

    function disposeState(state: OwnerRefreshState): void {
        if (!state.active) return;
        state.active = false;
        state.pendingInteractionTimers.forEach((timer) => targetWindow.clearTimeout(timer));
        state.pendingInteractionTimers.clear();
        state.pendingInteraction.clear();
        state.pendingFocused.clear();
        state.inFlight.forEach((slot) => slot.controller.abort());
        state.inFlight.clear();
    }

    function disposeOwner(ownerEl: HTMLElement): void {
        const state = ownerStates.get(ownerEl);
        if (!state) return;
        disposeState(state);
        ownerStates.delete(ownerEl);
    }

    function markProtectionChanged(target: Element): void {
        ownerStates.forEach((state) => {
            if (!state.active) return;
            state.inFlight.forEach((slot) => {
                const refreshedTarget = resolveOwnedTarget(slot.fragment);
                if (refreshedTarget && (refreshedTarget.contains(target) || target.contains(refreshedTarget))) {
                    slot.protectionChanged = true;
                }
            });
        });
    }

    async function swapFragmentHtml(
        fragment: LiveUpdateFragmentWithState,
        state: OwnerRefreshState,
        slot: FragmentRequestSlot,
        html: string,
    ): Promise<void> {
        const perfSpan = beginPerfSpan("live_updates.swap_fragment", { targetId: fragment.targetId });
        if (!requestIsCurrent(state, fragment.targetId, slot)) {
            endPerfSpan(perfSpan, { outcome: "stale" });
            return;
        }
        const target = resolveOwnedTarget(fragment);
        if (!target) {
            endPerfSpan(perfSpan, { outcome: "target_missing" });
            return;
        }

        const trimmed = (html || "").trim();
        if (!trimmed) {
            if (requestIsCurrent(state, fragment.targetId, slot) && resolveOwnedTarget(fragment) === target) target.remove();
            endPerfSpan(perfSpan, { outcome: "removed_empty_html" });
            return;
        }

        const template = targetDocument.createElement("template");
        template.innerHTML = trimmed;
        let nextNode = template.content.firstElementChild;
        if (nextNode instanceof HTMLTemplateElement) nextNode = nextNode.content.firstElementChild;
        if (!(nextNode instanceof Element)) {
            endPerfSpan(perfSpan, { outcome: "no_element" });
            return;
        }

        if (!requestIsCurrent(state, fragment.targetId, slot) || resolveOwnedTarget(fragment) !== target) {
            endPerfSpan(perfSpan, { outcome: "stale" });
            return;
        }
        const restoreFocus = focus.captureReplacementFocus(target);
        target.replaceWith(nextNode);
        if (!requestIsCurrent(state, fragment.targetId, slot)) {
            endPerfSpan(perfSpan, { outcome: "stale_after_swap" });
            return;
        }
        targetWindow.htmx?.process?.(nextNode);
        if (!requestIsCurrent(state, fragment.targetId, slot)) {
            endPerfSpan(perfSpan, { outcome: "stale_after_process" });
            return;
        }
        targetWindow.appPageLifecycle?.dispatchPageReady?.({
            source: "live-fragment-refetch",
            target: nextNode,
            isFullPage: false,
        });
        if (requestIsCurrent(state, fragment.targetId, slot)) restoreFocus(nextNode);
        endPerfSpan(perfSpan, { outcome: "swapped", nextTagName: nextNode.tagName });
    }

    async function refetchFragment(fragment: LiveUpdateFragmentWithState, state: OwnerRefreshState, slot: FragmentRequestSlot): Promise<void> {
        const perfSpan = beginPerfSpan("live_updates.refetch_fragment", {
            targetId: fragment.targetId,
            url: fragment.url,
            focusProtected: fragment.protection.kind === "focused-field",
        });
        const target = resolveOwnedTarget(fragment);
        if (!target || !requestIsCurrent(state, fragment.targetId, slot)) {
            endPerfSpan(perfSpan, { outcome: "stale_before_fetch" });
            return;
        }
        function fenceForCurrentProtection(stage: "response" | "body", status: number): boolean {
            const currentTarget = resolveOwnedTarget(fragment);
            const latestDemand = slot.next ?? fragment;
            if (!currentTarget || currentTarget !== slot.fetchedTarget) {
                endPerfSpan(perfSpan, { outcome: `target_changed_after_${stage}`, status });
                return true;
            }
            if (deferForCurrentProtection(state, slot, latestDemand, currentTarget)) {
                endPerfSpan(perfSpan, { outcome: `deferred_after_${stage}`, status });
                return true;
            }
            if (slot.protectionChanged) {
                slot.next = latestDemand;
                endPerfSpan(perfSpan, { outcome: `protection_changed_during_${stage}`, status });
                return true;
            }
            return false;
        }

        slot.fetchedTarget = target;
        const requestUrl = decorateSurfaceFragmentRequest(fragment.url, fragment, target);
        const response = await targetWindow.fetch(requestUrl, {
            credentials: "same-origin",
            headers: { "HX-Request": "true" },
            signal: slot.controller.signal,
        });
        if (!requestIsCurrent(state, fragment.targetId, slot)) {
            endPerfSpan(perfSpan, { outcome: "stale_response", status: response.status });
            return;
        }
        if (resolveOwnedTarget(fragment) !== slot.fetchedTarget) {
            endPerfSpan(perfSpan, { outcome: "target_changed_after_response", status: response.status });
            return;
        }
        if (!response.ok) {
            endPerfSpan(perfSpan, { outcome: "http_error", status: response.status });
            throw new Error(`Fragment fetch failed with ${response.status}`);
        }
        if (fenceForCurrentProtection("response", response.status)) return;
        if (response.headers.get("HX-Refresh")?.toLowerCase() === "true") {
            endPerfSpan(perfSpan, { outcome: "calendar_revision_reload", status: response.status });
            if (requestIsCurrent(state, fragment.targetId, slot)) targetWindow.location.reload();
            return;
        }

        const html = await response.text();
        if (!requestIsCurrent(state, fragment.targetId, slot)) {
            endPerfSpan(perfSpan, { outcome: "stale_body", status: response.status });
            return;
        }
        if (fenceForCurrentProtection("body", response.status)) return;
        await swapFragmentHtml(fragment, state, slot, html);
        if (requestIsCurrent(state, fragment.targetId, slot)) {
            const currentTarget = resolveOwnedTarget(fragment);
            if (currentTarget) focus.restoreDeferredState(currentTarget, fragment);
        }
        endPerfSpan(perfSpan, { outcome: "ok", status: response.status, responseBytes: html.length });
    }

    function reportFragmentRefreshError(fragment: LiveUpdateFragmentWithState, error: unknown): void {
        const detail = {
            targetId: fragment.targetId || null,
            url: fragment.url || null,
            error: error instanceof Error ? error.message : String(error),
        };
        targetWindow.console?.error?.("Live fragment refresh failed", detail);
        targetDocument.dispatchEvent(new CustomEvent("app:live-update-fragment-refresh-failed", { detail }));
    }

    function queueFragment(fragment: LiveUpdateFragmentWithState): void {
        const state = ownerStates.get(fragment.ownerEl);
        if (!state?.active || stopped) return;
        const existing = state.inFlight.get(fragment.targetId);
        if (existing) {
            existing.next = fragment;
            emitDebugEvent("fragment_deduped", { targetId: fragment.targetId, url: fragment.url });
            return;
        }

        const slot: FragmentRequestSlot = {
            controller: new AbortController(),
            fragment,
            fetchedTarget: null,
            generation,
            next: null,
            protectionChanged: false,
        };
        state.inFlight.set(fragment.targetId, slot);
        void refetchFragment(fragment, state, slot)
            .catch((error) => {
                if (requestIsCurrent(state, fragment.targetId, slot)) reportFragmentRefreshError(fragment, error);
            })
            .finally(() => {
                if (state.inFlight.get(fragment.targetId) !== slot) return;
                state.inFlight.delete(fragment.targetId);
                const next = slot.next;
                if (next && state.active && slot.generation === generation && !stopped) queueFragment(next);
            });
    }

    function flushInteractionDeferredFragment(state: OwnerRefreshState, targetId: string, reason: string): void {
        const fragment = state.pendingInteraction.get(targetId);
        if (!fragment) return;
        clearInteractionDeferredFragment(state, targetId);
        emitDebugEvent("deferred_fragment_flush", { targetId, reason });
        queueFragment(fragment);
    }

    function scheduleInteractionFallback(state: OwnerRefreshState, fragment: LiveUpdateFragmentWithState, timeoutMs: number | null): void {
        const existing = state.pendingInteractionTimers.get(fragment.targetId);
        if (existing) targetWindow.clearTimeout(existing);
        if (timeoutMs === null || timeoutMs <= 0) return;

        state.pendingInteractionTimers.set(fragment.targetId, targetWindow.setTimeout(() => {
            if (!state.active) return;
            const pending = state.pendingInteraction.get(fragment.targetId);
            const target = resolveOwnedTarget(fragment);
            if (pending && target) {
                const conflict = resolveLiveFragmentInteractionConflict(pending, target, activeInteractionSessions);
                if (conflict) activeInteractionSessions.requestCancel(conflict.session, "live-fragment-defer-fallback-timeout");
            }
            flushInteractionDeferredFragment(state, fragment.targetId, "interaction_fallback_timeout");
        }, timeoutMs));
    }

    function deferForCurrentProtection(
        state: OwnerRefreshState,
        slot: FragmentRequestSlot | null,
        fragment: LiveUpdateFragmentWithState,
        target: HTMLElement,
    ): boolean {
        const conflict = resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions);
        if (conflict) {
            if (conflict.action === "cancel") activeInteractionSessions.requestCancel(conflict.session, "live-fragment-conflict");
            state.pendingInteraction.set(fragment.targetId, fragment);
            scheduleInteractionFallback(state, fragment, conflict.timeoutMs);
            if (slot) slot.next = null;
            targetDocument.dispatchEvent(new CustomEvent("app:live-update-performance", {
                detail: { name: "live_updates.defer_fragment", duration: 0, targetId: fragment.targetId, reason: "interaction_session" },
            }));
            return true;
        }

        clearInteractionDeferredFragment(state, fragment.targetId);
        if (fragment.protection.kind === "focused-field" && focus.hasProtectedActiveInput(target, fragment)) {
            state.pendingFocused.set(fragment.targetId, focus.captureDeferredState(target, fragment));
            if (slot) slot.next = null;
            targetDocument.dispatchEvent(new CustomEvent("app:live-update-performance", {
                detail: { name: "live_updates.defer_fragment", duration: 0, targetId: fragment.targetId, reason: "active_input" },
            }));
            return true;
        }

        state.pendingFocused.delete(fragment.targetId);
        return false;
    }

    function request(fragment: LiveUpdateFragmentWithState): void {
        if (!fragment.targetId || !fragment.url || stopped) return;
        const state = ownerStates.get(fragment.ownerEl);
        if (!state?.active) return;
        const target = resolveOwnedTarget(fragment);
        if (!target) return;

        const existing = state.inFlight.get(fragment.targetId);
        if (existing) {
            existing.next = fragment;
            emitDebugEvent("fragment_deduped", { targetId: fragment.targetId, url: fragment.url });
            if (deferForCurrentProtection(state, null, fragment, target)) return;
            return;
        }
        if (deferForCurrentProtection(state, null, fragment, target)) return;
        queueFragment(fragment);
    }

    function flushInteractionDeferredFragmentsWithoutActiveSessions(): void {
        ownerStates.forEach((state) => {
            if (!state.active) return;
            Array.from(state.pendingInteraction.entries()).forEach(([targetId, fragment]) => {
                const target = resolveOwnedTarget(fragment);
                if (!target) {
                    flushInteractionDeferredFragment(state, targetId, "target_missing");
                    return;
                }
                if (!resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions)) {
                    flushInteractionDeferredFragment(state, targetId, "interaction_session_end");
                }
            });
        });
    }

    function flushFocusedFragmentsWithoutActiveInputs(): void {
        ownerStates.forEach((state) => {
            if (!state.active) return;
            Array.from(state.pendingFocused.entries()).forEach(([targetId, fragment]) => {
                const target = resolveOwnedTarget(fragment);
                if (target && resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions)) return;
                if (!target || !focus.hasProtectedActiveInput(target, fragment)) {
                    state.pendingFocused.delete(targetId);
                    emitDebugEvent("deferred_fragment_flush", { targetId, reason: "inactive_input" });
                    queueFragment(fragment);
                }
            });
        });
    }

    function stop(): void {
        if (stopped) return;
        stopped = true;
        generation += 1;
        ownerStates.forEach(disposeState);
    }

    return {
        activateOwner,
        disposeOwner,
        markProtectionChanged,
        request,
        flushInteractionDeferredFragmentsWithoutActiveSessions,
        flushFocusedFragmentsWithoutActiveInputs,
        stop,
    };
}
