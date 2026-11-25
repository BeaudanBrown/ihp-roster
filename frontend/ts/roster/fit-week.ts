import { rosterPersonalFitActiveDomAttr, rosterFitViewportDomAttr, rosterColumnEditorDomAttr, rosterSidePanelShelfToggleDomAttr, surfaceConfigDomAttr, surfaceDomAttr } from "../generated/contracts";
import { disposeHorizontalScroll, initializeHorizontalScroll } from "../app-horizontal-scroll";
import { readFrontendSurfaceMountElement } from "../live-updates/mount";
import { onAppPageReady, onHtmxLoad } from "../shared/lifecycle";
import { anchoredZoom, constrain, fitScale, type Camera, type Extent } from "./fit-camera";
import { bindFitGestures } from "./fit-gestures";

const mountSelector = `[${surfaceDomAttr}][${surfaceConfigDomAttr}]`;

type Inspection = { camera: Camera; fitted: boolean };
const home = (): Inspection => ({ camera: { x: 0, y: 0, scale: 1 }, fitted: true });

function mount(view: HTMLElement, inspection: Inspection, lanesId: string) {
    const frame = view.querySelector<HTMLElement>(`[${rosterColumnEditorDomAttr}]`);
    if (!frame || frame.parentElement !== view) return null;
    const originalLanes = document.getElementById(lanesId);
    if (!originalLanes || !frame.contains(originalLanes)) return null;
    const originalScroll = originalLanes.scrollLeft;
    view.classList.add("roster-fit-viewport");
    view.tabIndex = 0;
    view.setAttribute("role", "region");
    const abort = new AbortController();
    let extent: Extent;
    function draw(next: Camera): void {
        const c = inspection.camera = constrain(next, extent);
        view.style.setProperty("--fit-height", Math.ceil(Math.min(extent.availableHeight, extent.height * c.scale)) + "px");
        view.style.setProperty("--fit-transform", "translate(" + -c.x + "px," + -c.y + "px) scale(" + c.scale + ")");
    }
    function availableHeight(): number {
        const shelf = view.closest(mountSelector)?.querySelector(`[${rosterSidePanelShelfToggleDomAttr}]`)?.getBoundingClientRect();
        const bottom = shelf && shelf.height > 0 ? Math.min(window.innerHeight, shelf.top) : window.innerHeight;
        return Math.max(1, bottom - Math.max(0, view.getBoundingClientRect().top) - 8);
    }
    function measure(): void {
        if (!frame || !view.isConnected || !view.clientWidth) return;
        const lanes = document.getElementById(lanesId);
        if (!lanes || !frame.contains(lanes)) return;
        disposeHorizontalScroll(lanes);
        // Resolve the standard responsive rails and the full scrollable lane
        // width BEFORE widening the frame (on phones lane widths are percentages).
        view.classList.remove("is-fit-measured");
        const tracks = getComputedStyle(frame).gridTemplateColumns.split(/\s+/).slice(0, -1);
        const laneWidth = lanes.scrollWidth;
        const width = tracks.reduce((sum, value) => sum + parseFloat(value), laneWidth);
        if (!Number.isFinite(width) || width <= 0) return;
        view.style.setProperty("--fit-width", width + "px");
        view.style.setProperty("--fit-tracks", [...tracks, laneWidth + "px"].join(" "));
        view.classList.add("is-fit-measured");
        lanes.scrollLeft = 0;
        extent = {
            width, height: Math.max(1, frame.offsetHeight), availableWidth: view.clientWidth,
            availableHeight: availableHeight(),
        };
        draw(inspection.fitted ? { scale: fitScale(extent), x: 0, y: 0 } : inspection.camera);
    }
    function pan(dx: number, dy: number): void {
        if (!extent) return;
        const c = inspection.camera;
        draw({ ...c, x: c.x + dx, y: c.y + dy });
    }
    bindFitGestures(view, {
        pan,
        zoom(factor, from, to) {
            if (!extent) return;
            const c = inspection.camera;
            draw(anchoredZoom(c, extent, c.scale * factor, from, to));
            inspection.fitted = inspection.camera.scale === fitScale(extent);
        },
        fit() { inspection.fitted = true; measure(); },
    }, abort.signal);
    view.addEventListener("focusin", event => {
        if (!(event.target instanceof HTMLElement) || event.target === view || !event.target.matches(":focus-visible")) return;
        const field = event.target.getBoundingClientRect();
        const bounds = view.getBoundingClientRect();
        const delta = (before: number, after: number) => before < 0 ? before : Math.max(0, after);
        pan(delta(field.left - bounds.left, field.right - bounds.right), delta(field.top - bounds.top, field.bottom - bounds.bottom));
    }, { signal: abort.signal });
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(frame);
    observer.observe(view);
    window.addEventListener("resize", measure, { signal: abort.signal });
    window.addEventListener("scroll", () => {
        if (!extent) return;
        extent.availableHeight = availableHeight();
        draw(inspection.fitted ? { scale: fitScale(extent), x: 0, y: 0 } : inspection.camera);
    }, { signal: abort.signal, passive: true });
    function stop(): void {
        abort.abort();
        observer.disconnect();
        view.classList.remove("roster-fit-viewport", "is-fit-measured");
        view.removeAttribute("tabindex");
        view.removeAttribute("role");
        for (const property of ["--fit-tracks", "--fit-width", "--fit-transform", "--fit-height"]) view.style.removeProperty(property);
        if (view.isConnected) {
            const lanes = document.getElementById(lanesId);
            if (lanes && view.contains(lanes)) {
                lanes.scrollLeft = originalScroll;
                initializeHorizontalScroll(lanes);
            }
        }
    }
    return { view, frame, inspection, measure, stop };
}

export function enableRosterFitWeek(): void {
    if (typeof document === "undefined") return;
    let active: ReturnType<typeof mount> = null;
    let owner: string | null = null;
    function reconcile(): void {
        const view = document.querySelector<HTMLElement>("[" + rosterFitViewportDomAttr + '="true"]');
        const surface = view?.closest<HTMLElement>(mountSelector);
        const enabled = surface?.querySelector("[" + rosterPersonalFitActiveDomAttr + '="true"]');
        if (!enabled || !view) {
            active?.stop();
            active = null;
            owner = null;
            return;
        }
        if (active && active.view === view && view.contains(active.frame)) { active.measure(); return; }
        const config = surface ? readFrontendSurfaceMountElement(surface) : null;
        const nextOwner = config?.scopeKey ?? null;
        const lanes = config?.fragments.find(fragment => fragment.fragmentKey.kind === "roster-slots-grid");
        const inspection = active && nextOwner === owner ? active.inspection : home();
        active?.stop();
        owner = nextOwner;
        active = view && lanes ? mount(view, inspection, lanes.targetId) : null;
    }
    onAppPageReady(reconcile);
    onHtmxLoad(reconcile);
    if (document.readyState !== "loading") reconcile();
}
