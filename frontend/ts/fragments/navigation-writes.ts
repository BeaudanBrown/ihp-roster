import { navigationWriteBarrierDomAttr } from "../generated/contracts";

// A declared navigation barrier only holds HTMX's own continuation. It does not
// send requests, schedule mutations, or replace HTMX target-scoped read sync.
export function enableNavigationWriteBarrier(root: Document = document): () => void {
    type Detail = {
        xhr?: XMLHttpRequest;
        target?: HTMLElement;
        elt?: HTMLElement;
        verb?: string;
        requestConfig?: { verb?: string };
        issueRequest?: (skipConfirmation: boolean) => void;
    };
    const writes = new Map<XMLHttpRequest, () => void>();
    const reads = new Map<XMLHttpRequest, () => void>();
    const waiting = new Map<HTMLElement, { source: HTMLElement; resume: () => void }>();
    let stopped = false;
    const detail = (event: Event): Detail => (event as CustomEvent<Detail>).detail ?? {};
    const isRead = (verb: string | undefined) => verb?.toLowerCase() === "get" || verb?.toLowerCase() === "head";
    const guarded = (target?: HTMLElement) => target?.getAttribute(navigationWriteBarrierDomAttr) === "true";
    function drain(): void {
        queueMicrotask(() => {
            if (stopped || writes.size) return;
            for (const [target, request] of waiting) {
                waiting.delete(target);
                if (target.isConnected && request.source.isConnected) request.resume();
            }
        });
    }
    const onConfirm = (event: Event) => {
        const request = detail(event);
        if (event.defaultPrevented) return;
        if (isRead(request.verb)) {
            if (!guarded(request.target) || !writes.size || !request.target || !request.elt || !request.issueRequest) return;
            event.preventDefault();
            const issueRequest = request.issueRequest;
            waiting.set(request.target, { source: request.elt, resume: () => issueRequest(false) });
        } else if (request.verb) {
            // A write must not sit behind a navigation that will detach its form.
            // Only reads are abortable; already-started mutations always finish.
            for (const xhr of reads.keys()) xhr.abort();
        }
    };
    const onSend = (event: Event) => {
        const request = detail(event);
        const xhr = request.xhr;
        if (!xhr || !request.requestConfig?.verb) return;
        const read = isRead(request.requestConfig.verb);
        if (read && !guarded(request.target)) return;
        const active = read ? reads : writes;
        if (active.has(xhr)) return;
        const finish = () => {
            xhr.removeEventListener("loadend", finish);
            active.delete(xhr);
            if (!read) drain();
        };
        active.set(xhr, finish);
        xhr.addEventListener("loadend", finish, { once: true });
    };
    root.addEventListener("htmx:confirm", onConfirm);
    root.addEventListener("htmx:beforeSend", onSend);
    return () => {
        stopped = true;
        waiting.clear();
        for (const dispose of [...reads.values(), ...writes.values()]) dispose();
        root.removeEventListener("htmx:confirm", onConfirm);
        root.removeEventListener("htmx:beforeSend", onSend);
    };
}
