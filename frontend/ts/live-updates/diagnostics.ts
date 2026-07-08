import type { LiveUpdateDebugDetail, LiveUpdatePerfSpan } from "./runtime-types";

export function createLiveUpdateDiagnostics(targetWindow: Window, targetDocument: Document) {
    let nextPerfToken = 0;

    function supportsPerformanceTimeline(): boolean {
        return Boolean(targetWindow.performance && typeof targetWindow.performance.mark === 'function' && typeof targetWindow.performance.measure === 'function');
    }

    function perfToken(prefix: string): string {
        nextPerfToken += 1;
        return `${prefix}-${Date.now()}-${nextPerfToken}`;
    }

    function beginPerfSpan(name: string, detail?: LiveUpdateDebugDetail): LiveUpdatePerfSpan | null {
        if (!supportsPerformanceTimeline()) return null;

        const token = perfToken(name);
        const startMark = `${token}:start`;
        targetWindow.performance.mark(startMark, detail ? { detail } : undefined);
        return {
            token,
            name,
            startMark,
            detail: detail || null,
        };
    }

    function endPerfSpan(span: LiveUpdatePerfSpan | null, extraDetail?: LiveUpdateDebugDetail): number | null {
        if (!span || !supportsPerformanceTimeline()) return null;

        const endMark = `${span.token}:end`;
        const detail = extraDetail ? { ...span.detail, ...extraDetail } : span.detail;
        targetWindow.performance.mark(endMark, detail ? { detail } : undefined);

        let duration = null;
        try {
            targetWindow.performance.measure(span.name, {
                start: span.startMark,
                end: endMark,
                detail: detail || undefined,
            });
            const entries = targetWindow.performance.getEntriesByName(span.name, 'measure');
            const entry = entries[entries.length - 1];
            duration = entry ? entry.duration : null;
        } catch (_error) {
            duration = null;
        }

        targetWindow.performance.clearMarks(span.startMark);
        targetWindow.performance.clearMarks(endMark);

        targetDocument.dispatchEvent(new CustomEvent('app:live-update-performance', {
            detail: {
                name: span.name,
                duration,
                ...detail,
            },
        }));

        return duration;
    }

    function emitDebugEvent(name: string, detail?: LiveUpdateDebugDetail): void {
        targetDocument.dispatchEvent(new CustomEvent('app:live-update-debug', {
            detail: {
                name,
                ...(detail || {}),
            },
        }));
    }

    return {
        beginPerfSpan,
        endPerfSpan,
        emitDebugEvent,
    };
}
