export function parsePositiveIntegerForHorizontalScroll(value: string | null | undefined): number | null {
    const parsed = Number.parseInt(value || "", 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

export function parseNonNegativeIntegerForHorizontalScroll(value: string | null | undefined, fallback: number): number {
    const parsed = Number.parseInt(value || "", 10);
    return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

export function clampHorizontalScrollLeft(scrollLeft: number, scrollWidth: number, clientWidth: number): number {
    const maxScrollLeft = Math.max(0, scrollWidth - clientWidth);
    return Math.min(Math.max(0, scrollLeft), maxScrollLeft);
}
