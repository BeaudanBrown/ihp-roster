export type DomRoot = Document | DocumentFragment | Element;

export function isElement(value: unknown): value is Element {
    return typeof Element !== "undefined" && value instanceof Element;
}

export function isDocument(value: unknown): value is Document {
    return typeof Document !== "undefined" && value instanceof Document;
}

export function isDocumentFragment(value: unknown): value is DocumentFragment {
    return typeof DocumentFragment !== "undefined" && value instanceof DocumentFragment;
}

export function isDomRoot(value: unknown): value is DomRoot {
    return isElement(value) || isDocument(value) || isDocumentFragment(value);
}

export function isHTMLElement(value: unknown): value is HTMLElement {
    return typeof HTMLElement !== "undefined" && value instanceof HTMLElement;
}

export function rootFromTarget(target: unknown, fallback: DomRoot = document): DomRoot {
    return isDomRoot(target) ? target : fallback;
}

export function closestHTMLElement(target: unknown, selector: string): HTMLElement | null {
    if (!isElement(target)) return null;
    const element = target.closest(selector);
    return isHTMLElement(element) ? element : null;
}

export function queryHTMLElement(root: DomRoot, selector: string): HTMLElement | null {
    const element = root.querySelector(selector);
    return isHTMLElement(element) ? element : null;
}

export function queryHTMLElements(root: DomRoot, selector: string): HTMLElement[] {
    return Array.from(root.querySelectorAll(selector)).filter(isHTMLElement);
}

export function datasetFlag(element: HTMLElement, key: string): boolean {
    return element.dataset[key] === "true";
}
