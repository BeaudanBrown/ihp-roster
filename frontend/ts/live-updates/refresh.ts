import { resolveLiveFragmentInteractionConflict, type ActiveInteractionSessionTracker } from "../interaction/live-conflicts";
import type { createLiveUpdateDiagnostics } from "./diagnostics";
import { createFocusedFieldProtection } from "./focus";
import { decorateSurfaceFragmentRequest } from "./request-context";
import type { InFlightFragmentState, LiveUpdateFragmentWithState } from "./runtime-types";

export type LiveFragmentRefresher = {
    request(fragment: LiveUpdateFragmentWithState): void;
    flushInteractionDeferredFragmentsWithoutActiveSessions(): void;
    flushFocusedFragmentsWithoutActiveInputs(): void;
    stop(): void;
};

type LiveUpdateDiagnostics = ReturnType<typeof createLiveUpdateDiagnostics>;

export function createLiveFragmentRefresher(options: {
    targetWindow: Window & typeof globalThis;
    targetDocument: Document;
    diagnostics: LiveUpdateDiagnostics;
    activeInteractionSessions: ActiveInteractionSessionTracker;
}): LiveFragmentRefresher {
    const { targetWindow, targetDocument, diagnostics, activeInteractionSessions } = options;
    const { beginPerfSpan, endPerfSpan, emitDebugEvent } = diagnostics;
    const focus = createFocusedFieldProtection(targetWindow, targetDocument);
    const pendingFocusedFragments = new Map<string, LiveUpdateFragmentWithState>();
    const pendingInteractionFragments = new Map<string, LiveUpdateFragmentWithState>();
    const pendingInteractionTimers = new Map<string, ReturnType<typeof targetWindow.setTimeout>>();
    const inFlightFragments = new Map<string, InFlightFragmentState>();

    async function swapFragmentHtml(targetId: string, html: string): Promise<void> {
        const perfSpan = beginPerfSpan("live_updates.swap_fragment", { targetId });
        const target = targetDocument.getElementById(targetId);
        if (!target) {
            endPerfSpan(perfSpan, { outcome: "target_missing" });
            return;
        }

        const trimmed = (html || "").trim();
        if (!trimmed) {
            target.remove();
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

        target.replaceWith(nextNode);
        targetWindow.htmx?.process?.(targetDocument.body);
        targetWindow.appPageLifecycle?.dispatchPageReady?.({
            source: "live-fragment-refetch",
            target: nextNode,
            isFullPage: false,
        });
        endPerfSpan(perfSpan, { outcome: "swapped", nextTagName: nextNode.tagName });
    }

    async function refetchFragment(fragment: LiveUpdateFragmentWithState): Promise<void> {
        const perfSpan = beginPerfSpan("live_updates.refetch_fragment", {
            targetId: fragment.targetId,
            url: fragment.url,
            focusProtected: fragment.protection.kind === "focused-field",
        });
        const target = targetDocument.getElementById(fragment.targetId);
        const requestUrl = target instanceof HTMLElement
            ? decorateSurfaceFragmentRequest(fragment.url, fragment, target)
            : fragment.url;
        const response = await targetWindow.fetch(requestUrl, {
            credentials: "same-origin",
            headers: { "HX-Request": "true" },
        });
        if (!response.ok) {
            endPerfSpan(perfSpan, { outcome: "http_error", status: response.status });
            throw new Error(`Fragment fetch failed with ${response.status}`);
        }

        const html = await response.text();
        await swapFragmentHtml(fragment.targetId, html);
        focus.restoreDeferredState(fragment);
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
        const existing = inFlightFragments.get(fragment.targetId);
        if (existing) {
            inFlightFragments.set(fragment.targetId, { ...existing, next: fragment });
            emitDebugEvent("fragment_deduped", { targetId: fragment.targetId, url: fragment.url });
            return;
        }

        inFlightFragments.set(fragment.targetId, { next: null });
        void refetchFragment(fragment)
            .catch((error) => reportFragmentRefreshError(fragment, error))
            .finally(() => {
                const next = inFlightFragments.get(fragment.targetId)?.next;
                inFlightFragments.delete(fragment.targetId);
                if (next) queueFragment(next);
            });
    }

    function clearInteractionDeferredFragment(targetId: string): void {
        const timer = pendingInteractionTimers.get(targetId);
        if (timer) targetWindow.clearTimeout(timer);
        pendingInteractionTimers.delete(targetId);
        pendingInteractionFragments.delete(targetId);
    }

    function flushInteractionDeferredFragment(targetId: string, reason: string): void {
        const fragment = pendingInteractionFragments.get(targetId);
        if (!fragment) return;
        clearInteractionDeferredFragment(targetId);
        emitDebugEvent("deferred_fragment_flush", { targetId, reason });
        queueFragment(fragment);
    }

    function scheduleInteractionFallback(targetId: string, timeoutMs: number | null): void {
        const existing = pendingInteractionTimers.get(targetId);
        if (existing) targetWindow.clearTimeout(existing);
        if (timeoutMs === null || timeoutMs <= 0) return;

        pendingInteractionTimers.set(targetId, targetWindow.setTimeout(() => {
            const fragment = pendingInteractionFragments.get(targetId);
            const target = targetDocument.getElementById(targetId);
            if (fragment && target instanceof HTMLElement) {
                const conflict = resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions);
                if (conflict) activeInteractionSessions.requestCancel(conflict.session, "live-fragment-defer-fallback-timeout");
            }
            flushInteractionDeferredFragment(targetId, "interaction_fallback_timeout");
        }, timeoutMs));
    }

    function request(fragment: LiveUpdateFragmentWithState): void {
        if (!fragment.targetId || !fragment.url) return;
        const target = targetDocument.getElementById(fragment.targetId);
        if (!(target instanceof HTMLElement)) return;

        const conflict = resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions);
        if (conflict?.action === "cancel") activeInteractionSessions.requestCancel(conflict.session, "live-fragment-conflict");
        if (conflict?.action === "defer") {
            pendingInteractionFragments.set(fragment.targetId, fragment);
            scheduleInteractionFallback(fragment.targetId, conflict.timeoutMs);
            targetDocument.dispatchEvent(new CustomEvent("app:live-update-performance", {
                detail: { name: "live_updates.defer_fragment", duration: 0, targetId: fragment.targetId, reason: "interaction_session" },
            }));
            return;
        }

        clearInteractionDeferredFragment(fragment.targetId);
        if (fragment.protection.kind === "focused-field" && focus.hasProtectedActiveInput(target, fragment)) {
            pendingFocusedFragments.set(fragment.targetId, focus.captureDeferredState(target, fragment));
            targetDocument.dispatchEvent(new CustomEvent("app:live-update-performance", {
                detail: { name: "live_updates.defer_fragment", duration: 0, targetId: fragment.targetId, reason: "active_input" },
            }));
            return;
        }

        pendingFocusedFragments.delete(fragment.targetId);
        queueFragment(fragment);
    }

    function flushInteractionDeferredFragmentsWithoutActiveSessions(): void {
        Array.from(pendingInteractionFragments.entries()).forEach(([targetId, fragment]) => {
            const target = targetDocument.getElementById(targetId);
            if (!(target instanceof HTMLElement)) {
                flushInteractionDeferredFragment(targetId, "target_missing");
                return;
            }
            if (!resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions)) {
                flushInteractionDeferredFragment(targetId, "interaction_session_end");
            }
        });
    }

    function flushFocusedFragment(targetId: string): void {
        const fragment = pendingFocusedFragments.get(targetId);
        if (!fragment) return;
        pendingFocusedFragments.delete(targetId);
        emitDebugEvent("deferred_fragment_flush", { targetId, reason: "inactive_input" });
        queueFragment(fragment);
    }

    function flushFocusedFragmentsWithoutActiveInputs(): void {
        Array.from(pendingFocusedFragments.entries()).forEach(([targetId, fragment]) => {
            const target = targetDocument.getElementById(targetId);
            if (target instanceof HTMLElement && resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions)) return;
            if (!(target instanceof HTMLElement) || !focus.hasProtectedActiveInput(target, fragment)) flushFocusedFragment(targetId);
        });
    }

    function stop(): void {
        pendingInteractionTimers.forEach((timer) => targetWindow.clearTimeout(timer));
        pendingInteractionTimers.clear();
        pendingInteractionFragments.clear();
        pendingFocusedFragments.clear();
        inFlightFragments.clear();
    }

    return { request, flushInteractionDeferredFragmentsWithoutActiveSessions, flushFocusedFragmentsWithoutActiveInputs, stop };
}
