import { liveUpdateClientIdHeader } from "../generated/contracts";
import type { FrontendSurfaceMountErrorReporter } from "./mount";
import type { HtmxConfigRequestEvent, LiveUpdateFragmentWithState } from "./runtime-types";
import { shouldDecorateSurfaceRequest } from "./subscription";

export function enableLiveUpdateRequestDecoration(options: {
    targetDocument: Document;
    ensureClientId: () => string;
    requestRefresh: (fragment: LiveUpdateFragmentWithState) => void;
    reportSurfaceConfigError?: FrontendSurfaceMountErrorReporter;
}): () => void {
    const { targetDocument, ensureClientId, requestRefresh, reportSurfaceConfigError } = options;
    const handleConfigRequest = (event: Event) => {
        const htmxEvent = event as HtmxConfigRequestEvent;
        if (!shouldDecorateSurfaceRequest(htmxEvent, requestRefresh, reportSurfaceConfigError)) return;
        if (htmxEvent.detail?.headers) {
            htmxEvent.detail.headers[liveUpdateClientIdHeader] = ensureClientId();
        }
    };

    targetDocument.addEventListener("htmx:configRequest", handleConfigRequest);
    return () => targetDocument.removeEventListener("htmx:configRequest", handleConfigRequest);
}
