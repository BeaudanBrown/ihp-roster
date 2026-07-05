import { fragmentDomAttr } from "../generated/contracts";
import { closestHTMLElement, isHTMLElement } from "../shared/dom";

export const uiRegionFragmentSelector = `[${fragmentDomAttr}="true"]`;

export function closestUiRegionFragment(value: unknown): HTMLElement | null {
    if (isHTMLElement(value)) {
        if (value.matches(uiRegionFragmentSelector)) return value;
        return closestHTMLElement(value, uiRegionFragmentSelector);
    }

    return closestHTMLElement(value, uiRegionFragmentSelector);
}
