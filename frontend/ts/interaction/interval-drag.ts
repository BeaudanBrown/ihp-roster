import { InteractionDom, dragAxisDirectionProperty, parseDragIntervalConfig, type DragIntervalConfig } from "../generated/contracts";

const attrs = InteractionDom.attributes;

export type IntervalProjection = {
    target: Element; label: string;
    left: number; top: number; width: number; height: number;
    previewOffsetPercent: number; previewExtentPercent: number;
};

function verticalAxis(element: Element): boolean | null {
    const value = element.ownerDocument?.defaultView?.getComputedStyle(element).getPropertyValue(dragAxisDirectionProperty).trim() ?? "";
    if (value === "vertical") return true;
    if (value === "" || value === "horizontal") return false;
    return null;
}
export type IntervalDrag = { project: (x: number, y: number, hitTarget?: Element | null) => IntervalProjection | null };

export function nearestIntervalChoice(config: DragIntervalConfig, position: number): number {
    let best = 0;
    for (let index = 1; index < config.positions.length; index++) {
        if (Math.abs(config.positions[index]! - position) < Math.abs(config.positions[best]! - position)) best = index;
    }
    return best;
}

// Missing configuration retains ordinary discrete drag/drop. Malformed
// configuration refuses the gesture rather than falling back to unsafe geometry.
export function readIntervalDrag(marker: Element, mount: Element, targetSelector: string, startX: number, startY = 0): IntervalDrag | null | undefined {
    const raw = marker.getAttribute(attrs.dragIntervalConfig);
    if (raw === null) return undefined;
    let config: DragIntervalConfig;
    try {
        config = parseDragIntervalConfig(JSON.parse(raw));
        if (!Number.isSafeInteger(config.rangeSize) || config.rangeSize <= 0
            || !Number.isSafeInteger(config.extent) || config.extent <= 0 || config.extent > config.rangeSize
            || config.positions.length !== config.labels.length
            || config.positions.some((position, index) => !Number.isSafeInteger(position) || position < 0
                || position + config.extent > config.rangeSize
                || (index > 0 && position <= config.positions[index - 1]!))) throw new Error();
    } catch {
        console.warn("Invalid interval drag configuration");
        return null;
    }
    if (config.positions.length === 0) return null;
    const vertical = verticalAxis(marker);
    if (vertical === null) return null;
    const sourceRect = marker.getBoundingClientRect();
    const grabX = startX - sourceRect.left;
    const grabY = startY - sourceRect.top;
    const grabOffset = vertical ? grabY : grabX;
    const axes = Array.from(mount.querySelectorAll(`[${attrs.dragAxis}]`))
        .filter((axis) => axis.getAttribute(attrs.dragAxis) === "true" && axis.closest(`[${attrs.surface}]`) === mount)
        .map((axis) => {
            const targets = new Map<number, Element>();
            for (const target of axis.querySelectorAll(targetSelector)) {
                if (target.closest(`[${attrs.surface}]`) !== mount || target.closest(`[${attrs.dragAxis}]`) !== axis) continue;
                const rawPosition = target.getAttribute(attrs.dragPosition);
                if (rawPosition === null || rawPosition.trim() === "") continue;
                const position = Number(rawPosition);
                if (Number.isSafeInteger(position)) targets.set(position, target);
            }
            return { axis, targets };
        });
    return {
        project(x, y, hitTarget) {
            if (verticalAxis(marker) !== vertical) return null;
            for (const { axis, targets } of axes) {
                if (hitTarget && hitTarget.closest(`[${attrs.dragAxis}]`) !== axis) continue;
                if (verticalAxis(axis) !== vertical) continue;
                const rect = axis.getBoundingClientRect();
                const length = vertical ? rect.height : rect.width;
                const crossPosition = vertical ? x : y;
                const crossStart = vertical ? rect.left : rect.top;
                const crossLength = vertical ? rect.width : rect.height;
                if (length <= 0 || crossPosition < crossStart || crossPosition > crossStart + crossLength) continue;
                const start = vertical ? rect.top : rect.left;
                const proposed = ((vertical ? y : x) - grabOffset - start) * config.rangeSize / length;
                const index = nearestIntervalChoice(config, proposed);
                const position = config.positions[index]!;
                const target = targets.get(position);
                if (!target || target.isConnected === false) return null;
                const snapped = start + position * length / config.rangeSize;
                const extent = config.extent * length / config.rangeSize;
                const targetRect = target.getBoundingClientRect();
                const targetLength = vertical ? targetRect.height : targetRect.width;
                if (targetLength <= 0) return null;
                return {
                    target, label: config.labels[index]!,
                    left: vertical ? x - grabX : snapped,
                    top: vertical ? snapped : y - grabY,
                    previewOffsetPercent: (snapped - (vertical ? targetRect.top : targetRect.left)) * 100 / targetLength,
                    previewExtentPercent: extent * 100 / targetLength,
                    width: vertical ? sourceRect.width : extent,
                    height: vertical ? extent : sourceRect.height,
                };
            }
            return null;
        },
    };
}
