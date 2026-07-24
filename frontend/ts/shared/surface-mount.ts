import {
    isFrontendSurfaceName,
    surfaceDomAttr,
    type FrontendSurfaceName,
} from "../generated/contracts";

export type SurfaceElementLike = {
    id?: string;
    parentElement: SurfaceElementLike | null;
    appendChild: (child: any) => unknown;
    getAttribute: (name: string) => string | null;
    setAttribute: (name: string, value: string) => void;
    closest: (selector: string) => unknown;
    querySelectorAll: (selector: string) => Iterable<unknown>;
};

type SurfaceQueryRootLike = {
    querySelectorAll: (selector: string) => Iterable<unknown>;
};

export function surfaceMountsWithin(root: Document | Element): SurfaceElementLike[] {
    const queryRoot = root as unknown as SurfaceQueryRootLike;
    const mounts = Array.from(queryRoot.querySelectorAll(`[${surfaceDomAttr}]`)).filter(isSurfaceElementLike);
    if (isSurfaceElementLike(root)) {
        const ownerMount = closestSurfaceMount(root);
        if (ownerMount && !mounts.includes(ownerMount)) mounts.unshift(ownerMount);
    }
    return mounts;
}

export function surfaceDefinitionsForMount<definition>(
    mount: SurfaceElementLike,
    registry: Record<FrontendSurfaceName, ReadonlyArray<definition>>,
): ReadonlyArray<definition> {
    const surface = mount.getAttribute(surfaceDomAttr);
    return isFrontendSurfaceName(surface) ? registry[surface] : [];
}

export function ownedSurfaceRoleElements(
    owner: SurfaceElementLike,
    mount: SurfaceElementLike,
    attribute: string,
): SurfaceElementLike[] {
    return Array.from(owner.querySelectorAll(`[${attribute}]`))
        .filter(isSurfaceElementLike)
        .filter((element) => closestSurfaceMount(element) === mount);
}

export function closestOwnedSurfaceRole(
    target: SurfaceElementLike,
    mount: SurfaceElementLike,
    attribute: string,
): SurfaceElementLike | null {
    const candidate = target.closest(`[${attribute}]`);
    return isSurfaceElementLike(candidate) && closestSurfaceMount(candidate) === mount ? candidate : null;
}

export function closestSurfaceRole(target: SurfaceElementLike, attribute: string): SurfaceElementLike | null {
    const candidate = target.closest(`[${attribute}]`);
    return isSurfaceElementLike(candidate) ? candidate : null;
}

export function closestSurfaceMount(target: SurfaceElementLike): SurfaceElementLike | null {
    const mount = target.closest(`[${surfaceDomAttr}]`);
    return isSurfaceElementLike(mount) ? mount : null;
}

export function isSurfaceElementLike(value: unknown): value is SurfaceElementLike {
    if (value === null || typeof value !== "object") return false;
    const candidate = value as Partial<SurfaceElementLike>;
    return typeof candidate.appendChild === "function"
        && typeof candidate.getAttribute === "function"
        && typeof candidate.setAttribute === "function"
        && typeof candidate.closest === "function"
        && typeof candidate.querySelectorAll === "function";
}

type PageReadyEvent = Event & { detail?: { target?: unknown } };

export function surfaceRootFromPageReadyEvent(event: Event): Document | Element {
    const target = (event as PageReadyEvent).detail?.target;
    return target instanceof Element || target instanceof Document ? target : document;
}
