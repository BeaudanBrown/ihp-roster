import { fragmentDomAttr, surfaceDomAttr } from "../generated/contracts";
import { readFrontendSurfaceMountElement } from "../live-updates/mount";
import { closestHTMLElement, isHTMLElement } from "../shared/dom";

export const uiRegionFragmentSelector = `[${fragmentDomAttr}="true"]`;

export function closestUiRegionFragment(value: unknown): HTMLElement | null {
    if (isHTMLElement(value)) {
        if (value.matches(uiRegionFragmentSelector)) return value;
        // Mounted descriptors already register ordinary fragments; do not add a second registry.
        const mount = closestHTMLElement(value, `[${surfaceDomAttr}]`);
        const config = mount && readFrontendSurfaceMountElement(mount, (_owner, error) => console.error(error));
        if (config) {
            for (let current: HTMLElement | null = value; current && mount.contains(current); current = current.parentElement) {
                if (config.fragments.some((fragment) => fragment.targetId === current?.id)) return current;
                if (current === mount) break;
            }
        }
        return closestHTMLElement(value, uiRegionFragmentSelector);
    }

    return closestHTMLElement(value, uiRegionFragmentSelector);
}
