import { InteractionDom, dragPreviewOffsetProperty, dragPreviewExtentProperty } from "../generated/contracts";
import type { IntervalDrag, IntervalProjection } from "./interval-drag";

const attrs = InteractionDom.attributes;
const enabled = InteractionDom.values.enabled;

type DropFeedbackInput = {
    mount: Element;
    currentClientX: number;
    currentClientY: number;
    intervalDrag: IntervalDrag | undefined;
};

export type DropFeedback = {
    target: Element | null;
    projection: IntervalProjection | null;
    preview: HTMLElement | null;
};

const noFeedback: DropFeedback = { target: null, projection: null, preview: null };

// Browser paint order owns precedence; the DSL-owned selector owns compatibility.
// A foreign mount blocks discovery rather than leaking through to its parent.
function hitTarget(mount: Element, x: number, y: number, selector: string): { target: Element | null; blocked: boolean } {
    const doc = mount.ownerDocument;
    const hits = doc?.elementsFromPoint?.(x, y) ?? [doc?.elementFromPoint?.(x, y)];
    for (const hit of hits) {
        if (!hit?.closest) continue;
        const owner = hit.closest(`[${attrs.surface}]`);
        if (owner && owner !== mount) return { target: null, blocked: true };
        const target = hit.closest(selector);
        if (target?.closest(`[${attrs.surface}]`) === mount) return { target, blocked: false };
    }
    return { target: null, blocked: false };
}

export function resolveDropFeedback(session: DropFeedbackInput, selector: string): DropFeedback {
    const hit = hitTarget(session.mount, session.currentClientX, session.currentClientY, selector);
    if (hit.blocked) return noFeedback;
    // Interval sources refine the pointed-to axis using their preserved grab
    // offset and server-supplied positions. Discrete sources use the hit itself.
    const projection = session.intervalDrag?.project(session.currentClientX, session.currentClientY, hit.target) ?? null;
    const target = session.intervalDrag ? projection?.target ?? null : hit.target;
    const preview = targetPreviewWithinMount(target, session.mount);
    // A preview without target defaults is explicitly source-interval-only.
    // Do not fall through to another target or infer availability from its text.
    if (preview && !projection && preview.getAttribute(attrs.dragTargetPreviewDefault) !== enabled) return noFeedback;
    return { target, projection, preview };
}

export function targetPreviewWithinMount(target: Element | null, mount: Element): HTMLElement | null {
    return Array.from(target?.querySelectorAll<HTMLElement>(`[${attrs.dragTargetPreview}="${enabled}"]`) ?? [])
        .find(preview => preview.closest(`[${attrs.surface}]`) === mount
            && preview.closest(`[${attrs.dropzoneRef}]`) === target) ?? null;
}

// Destination state is independent of floating source feedback. Target defaults
// and source projections use exactly the same opt-in element and CSS renderer.
export function createDestinationFeedback(className: string | undefined) {
    let preview: HTMLElement | null = null;
    let restore: (() => void) | null = null;
    const cleanup = () => {
        restore?.();
        restore = null;
        preview = null;
    };
    return {
        update(feedback: DropFeedback) {
            if (feedback.preview !== preview) {
                cleanup();
                preview = feedback.preview;
                if (preview) {
                    const element = preview;
                    const text = element.textContent;
                    const style = element.getAttribute("style");
                    const classes = element.getAttribute("class");
                    if (className) element.classList.add(...className.split(/\s+/).filter(Boolean));
                    restore = () => {
                        element.textContent = text;
                        if (style === null) element.removeAttribute("style");
                        else element.setAttribute("style", style);
                        if (classes === null) element.removeAttribute("class");
                        else element.setAttribute("class", classes);
                    };
                }
            }
            if (preview && feedback.projection) {
                preview.style.setProperty(dragPreviewOffsetProperty, `${feedback.projection.previewOffsetPercent}%`);
                preview.style.setProperty(dragPreviewExtentProperty, `${feedback.projection.previewExtentPercent}%`);
                preview.textContent = feedback.projection.label;
            }
        },
        cleanup,
    };
}
