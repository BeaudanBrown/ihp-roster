// Shared browser mechanics only: feature adapters supply their active layer and
// isolation boundary. The highest layer owns interaction; every owner keeps the
// document locked until it releases, including when a picker covers a dialog.
export interface PageOverlayLayer {
    element: HTMLElement;
    boundary: HTMLElement;
    priority: number;
    companions?: readonly HTMLElement[];
}

const layers = new Map<object, PageOverlayLayer>();
const previousInert = new Map<HTMLElement, boolean>();
let scrollPosition: { left: number; top: number } | null = null;
let observer: MutationObserver | null = null;

function reconcilePageOverlays(): void {
    if (document.body === null) return;
    for (const [owner, layer] of layers) {
        if (!layer.element.isConnected || !layer.boundary.isConnected) layers.delete(owner);
    }
    const active = [...layers.values()].sort((a, b) => b.priority - a.priority)[0];
    const blocked = new Set<HTMLElement>();
    if (active !== undefined) {
        const allowed = [active.element, ...(active.companions ?? [])].filter((element) => element.isConnected);
        const visit = (parent: HTMLElement): void => {
            for (const child of parent.children) {
                if (!(child instanceof HTMLElement) || allowed.includes(child)) continue;
                if (allowed.some((element) => child.contains(element))) visit(child);
                else blocked.add(child);
            }
        };
        visit(active.boundary);
    }

    for (const [element, wasInert] of previousInert) {
        if (!blocked.has(element)) {
            element.inert = wasInert;
            previousInert.delete(element);
        }
    }
    for (const element of blocked) {
        if (!previousInert.has(element)) previousInert.set(element, element.inert);
        element.inert = true;
    }

    if (active !== undefined && scrollPosition === null) {
        scrollPosition = { left: window.scrollX, top: window.scrollY };
        // Classes, rather than inline styles, survive Bootstrap's independent
        // body overflow cleanup and leave pre-existing inline styles untouched.
        document.documentElement.classList.add("app-page-scroll-locked");
        observer = new MutationObserver(reconcilePageOverlays);
        observer.observe(document.body, { childList: true, subtree: true });
    } else if (active === undefined && scrollPosition !== null) {
        const position = scrollPosition;
        scrollPosition = null;
        observer?.disconnect();
        observer = null;
        document.documentElement.classList.remove("app-page-scroll-locked");
        window.scrollTo({ ...position, behavior: "instant" });
    }
}

export function setPageOverlay(owner: object, layer: PageOverlayLayer | null): void {
    if (layer === null) layers.delete(owner);
    else layers.set(owner, layer);
    reconcilePageOverlays();
}

if (typeof window !== "undefined") {
    window.addEventListener("pagehide", () => {
        layers.clear();
        reconcilePageOverlays();
    });
}
