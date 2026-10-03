import { InteractionDom, parseDragIntervalConfig, type DragIntervalConfig } from "../generated/contracts";

const attrs = InteractionDom.attributes;

export type IntervalProjection = { target: Element; label: string; left: number; width: number };
export type IntervalDrag = { project: (x: number, y: number) => IntervalProjection | null };

export function nearestIntervalChoice(config: DragIntervalConfig, position: number): number {
    let best = 0;
    for (let index = 1; index < config.positions.length; index++) {
        if (Math.abs(config.positions[index]! - position) < Math.abs(config.positions[best]! - position)) best = index;
    }
    return best;
}

// Missing configuration retains ordinary discrete drag/drop. Malformed
// configuration refuses the gesture rather than falling back to unsafe geometry.
export function readIntervalDrag(marker: Element, mount: Element, targetSelector: string, startX: number): IntervalDrag | null | undefined {
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
    const grabOffset = startX - marker.getBoundingClientRect().left;
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
        project(x, y) {
            for (const { axis, targets } of axes) {
                const rect = axis.getBoundingClientRect();
                if (rect.width <= 0 || y < rect.top || y > rect.top + rect.height) continue;
                const proposed = (x - grabOffset - rect.left) * config.rangeSize / rect.width;
                const index = nearestIntervalChoice(config, proposed);
                const position = config.positions[index]!;
                const target = targets.get(position);
                if (!target || target.isConnected === false) return null;
                return { target, label: config.labels[index]!, left: rect.left + position * rect.width / config.rangeSize, width: config.extent * rect.width / config.rangeSize };
            }
            return null;
        },
    };
}
