export type Point = { x: number; y: number };
export type Camera = Point & { scale: number };
export type Extent = { width: number; height: number; availableWidth: number; availableHeight: number };

export function fitScale(e: Extent): number {
    return Math.min(1, e.availableWidth / e.width, e.availableHeight / e.height);
}

export function constrain(camera: Camera, e: Extent): Camera {
    const scale = Math.min(4, Math.max(fitScale(e), camera.scale));
    return {
        scale,
        x: Math.min(Math.max(0, e.width * scale - e.availableWidth), Math.max(0, camera.x)),
        y: Math.min(Math.max(0, e.height * scale - e.availableHeight), Math.max(0, camera.y)),
    };
}

// Keep the content point under the old gesture anchor under the new anchor.
export function anchoredZoom(camera: Camera, e: Extent, requested: number, from: Point, to: Point): Camera {
    const { scale } = constrain({ ...camera, scale: requested }, e);
    const ratio = scale / camera.scale;
    return constrain({ scale, x: (camera.x + from.x) * ratio - to.x, y: (camera.y + from.y) * ratio - to.y }, e);
}
