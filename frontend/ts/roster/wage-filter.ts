import {
    encodeRosterWageFilterRequest,
    liveFragmentsRefreshEvent,
    parseRosterWageFilterConfig,
    rosterStaffHighlightPinDomAttr,
    rosterWageFilterConfigDomAttr,
    surfaceConfigDomAttr,
    surfaceDomAttr,
    type FrontendSurfaceMountedFragmentConfig,
} from "../generated/contracts";
import type { LinkedHighlightPinChange } from "../linked-highlight/runtime";
import { readFrontendSurfaceMountElement } from "../live-updates/mount";
import { registerSurfaceFragmentRequestDecorator } from "../live-updates/request-context";

export type RosterWageFilterController = {
    pinChanged: (change: LinkedHighlightPinChange) => void;
    decorateRequest: (event: Event) => void;
    decorateFragmentUrl: (url: string, fragment: FrontendSurfaceMountedFragmentConfig, target: HTMLElement) => string;
};

type HtmxConfigRequestEvent = Event & {
    detail?: {
        elt?: unknown;
        parameters?: Record<string, unknown>;
        path?: string;
    };
};

export function createRosterWageFilterController(targetDocument: Document): RosterWageFilterController {
    const pinnedKeysByMount = new WeakMap<HTMLElement, string | null>();

    function pinChanged(change: LinkedHighlightPinChange): void {
        if (change.pinRoleAttribute !== rosterStaffHighlightPinDomAttr) return;
        if (!(change.mount instanceof HTMLElement)) return;
        const ownerMount = owningRosterMount(change.mount);
        if (!ownerMount) return;
        pinnedKeysByMount.set(ownerMount, change.pinnedKey);
        const config = readWageFilterConfig(ownerMount);
        if (!config?.wageFilterEnabled) return;

        const mountConfig = readFrontendSurfaceMountElement(ownerMount);
        if (!mountConfig || mountConfig.surface !== "roster" || !mountConfig.subscription) return;
        const targetIds = new Set(config.wageFilterRefreshTargetIds);
        const fragments = mountConfig.fragments
            .filter((fragment) => targetIds.has(fragment.targetId))
            .map((fragment) => fragment.fragmentKey);
        if (fragments.length === 0) return;

        targetDocument.dispatchEvent(new CustomEvent(liveFragmentsRefreshEvent, {
            detail: {
                scope: mountConfig.subscription.scope,
                scopeKey: mountConfig.scopeKey,
                fragments,
            },
        }));
    }

    function decorateRequest(event: Event): void {
        const htmxEvent = event as HtmxConfigRequestEvent;
        const source = htmxEvent.detail?.elt;
        if (!(source instanceof Element)) return;
        const ownerMount = source.closest<HTMLElement>(`[${surfaceDomAttr}=\"roster\"][${surfaceConfigDomAttr}]`);
        if (!ownerMount) return;
        const config = readWageFilterConfig(ownerMount);
        const mountConfig = readFrontendSurfaceMountElement(ownerMount);
        if (!config?.wageFilterEnabled || !mountConfig || !htmxEvent.detail?.path) return;
        if (!requestTargetsWageFragment(source, ownerMount, config.wageFilterRequestTargetIds)) return;
        const requestPath = new URL(htmxEvent.detail.path, targetDocument.defaultView?.location.origin ?? "http://localhost").pathname;
        const isMountedFragmentRequest = mountConfig.fragments.some((fragment) =>
            config.wageFilterRequestTargetIds.includes(fragment.targetId)
            && new URL(fragment.url, targetDocument.defaultView?.location.origin ?? "http://localhost").pathname === requestPath
        );
        if (!isMountedFragmentRequest) return;

        const pinnedStaffKey = pinnedKeysByMount.get(ownerMount) ?? null;
        if (!pinnedStaffKey || !htmxEvent.detail) return;
        const encodedRequest = encodeRosterWageFilterRequest({ pinnedStaffKey });
        if (htmxEvent.detail.parameters) {
            Object.assign(htmxEvent.detail.parameters, encodedRequest);
        } else {
            htmxEvent.detail.parameters = { ...encodedRequest };
        }
    }

    function decorateFragmentUrl(url: string, _fragment: FrontendSurfaceMountedFragmentConfig, target: HTMLElement): string {
        const ownerMount = target.closest<HTMLElement>(`[${surfaceDomAttr}=\"roster\"][${surfaceConfigDomAttr}]`);
        if (!ownerMount) return url;
        const config = readWageFilterConfig(ownerMount);
        if (!config?.wageFilterEnabled || !config.wageFilterRequestTargetIds.includes(target.id)) return url;
        const pinnedStaffKey = pinnedKeysByMount.get(ownerMount) ?? null;
        if (!pinnedStaffKey) return url;

        const request = encodeRosterWageFilterRequest({ pinnedStaffKey });
        const parsed = new URL(url, targetDocument.defaultView?.location.origin ?? "http://localhost");
        Object.entries(request).forEach(([name, value]) => {
            if (value !== undefined) parsed.searchParams.set(name, value);
        });
        return url.startsWith("/") ? `${parsed.pathname}${parsed.search}${parsed.hash}` : parsed.toString();
    }

    return { pinChanged, decorateRequest, decorateFragmentUrl };
}

export function enableRosterWageFilter(): RosterWageFilterController {
    const controller = createRosterWageFilterController(document);
    document.addEventListener("htmx:configRequest", controller.decorateRequest);
    registerSurfaceFragmentRequestDecorator(controller.decorateFragmentUrl);
    return controller;
}

function owningRosterMount(interactionMount: HTMLElement): HTMLElement | null {
    return interactionMount.closest<HTMLElement>(`[${surfaceDomAttr}=\"roster\"][${surfaceConfigDomAttr}]`);
}

function readWageFilterConfig(mount: HTMLElement) {
    const element = mount.querySelector<HTMLElement>(`[${rosterWageFilterConfigDomAttr}]`);
    if (!element) return null;
    const raw = element.getAttribute(rosterWageFilterConfigDomAttr);
    if (!raw) return null;
    try {
        return parseRosterWageFilterConfig(JSON.parse(raw));
    } catch {
        return null;
    }
}

function requestTargetsWageFragment(source: Element, mount: HTMLElement, targetIds: ReadonlyArray<string>): boolean {
    for (const targetId of targetIds) {
        const target = mount.querySelector<HTMLElement>(`#${targetId}`);
        if (target && (target === source || target.contains(source))) return true;
    }
    return false;
}
