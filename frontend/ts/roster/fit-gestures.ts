import type { Point } from "./fit-camera";

type Actions = {
    pan(dx: number, dy: number): void;
    zoom(factor: number, from: Point, to: Point): void;
    fit(): void;
};

const distance = (a: Point, b: Point) => Math.hypot(a.x - b.x, a.y - b.y);
const midpoint = (a: Point, b: Point) => ({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 });

export function bindFitGestures(view: HTMLElement, actions: Actions, signal: AbortSignal): void {
    const options = { signal, capture: true };
    const points = new Map<number, Point>();
    let gesture = false;
    function local(event: MouseEvent): Point {
        const bounds = view.getBoundingClientRect();
        return { x: event.clientX - bounds.left, y: event.clientY - bounds.top };
    }
    view.addEventListener("pointerdown", event => {
        if (event.button !== 0 || !(event.target instanceof Element)) return;
        // Capture on the original element, not the viewport: native clicks must
        // retain their original target. Don't start an underlying shift drag.
        event.stopPropagation();
        event.target.setPointerCapture(event.pointerId);
        gesture = points.size > 0;
        points.set(event.pointerId, local(event));
    }, options);
    view.addEventListener("pointermove", event => {
        const last = points.get(event.pointerId);
        if (!last) return;
        const next = local(event);
        if (!gesture && distance(last, next) < 6) return;
        gesture = true;
        const other = Array.from(points).find(([id]) => id !== event.pointerId)?.[1];
        if (points.size === 2 && other) {
            const span = distance(last, other);
            if (span >= 1) actions.zoom(distance(next, other) / span, midpoint(last, other), midpoint(next, other));
        } else if (points.size === 1) actions.pan(last.x - next.x, last.y - next.y);
        points.set(event.pointerId, next);
    }, options);
    for (const eventName of ["pointerup", "pointercancel", "lostpointercapture"] as const) {
        view.addEventListener(eventName, event => points.delete(event.pointerId), options);
    }
    view.addEventListener("dragstart", event => event.preventDefault(), options);
    view.addEventListener("click", event => {
        if (!gesture || event.detail === 0) return;
        event.preventDefault();
        event.stopImmediatePropagation();
    }, options);
    view.addEventListener("wheel", event => {
        if (event.ctrlKey || event.metaKey || event.altKey) return; // browser accessibility zoom
        event.preventDefault();
        const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? view.clientHeight : 1;
        const anchor = local(event);
        actions.zoom(Math.exp(-event.deltaY * unit * 0.002), anchor, anchor);
    }, { ...options, passive: false });
    view.addEventListener("keydown", event => {
        if (event.target !== view || event.ctrlKey || event.metaKey || event.altKey) return;
        const center = { x: view.clientWidth / 2, y: view.clientHeight / 2 };
        const key = event.key;
        if (key === "+" || key === "=") actions.zoom(1.4, center, center);
        else if (key === "-") actions.zoom(1 / 1.4, center, center);
        else if (key === "0" || key === "Home") actions.fit();
        else if (key === "ArrowLeft") actions.pan(-80, 0);
        else if (key === "ArrowRight") actions.pan(80, 0);
        else if (key === "ArrowUp") actions.pan(0, -80);
        else if (key === "ArrowDown") actions.pan(0, 80);
        else return;
        event.preventDefault();
    }, options);
}
