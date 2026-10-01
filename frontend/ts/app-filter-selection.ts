import {
    filterSelectionSectionDomAttr,
    filterSelectionItemDomAttr,
    filterSelectionClearDomAttr,
    filterSelectionAllDomAttr,
    filterSelectionSelectedDomAttr,
    filterSelectionCountDomAttr,
} from './generated/contracts';

// Local, deferred native form state only. IDs, filtering and requests belong to Haskell.
export function updateFilterSelection(target: Element): void {
    const section = target.closest(`[${filterSelectionSectionDomAttr}]`);
    if (!(section instanceof HTMLElement)) return;
    const owned = (selector: string) => Array.from(section.querySelectorAll(selector))
        .filter(element => element.closest(`[${filterSelectionSectionDomAttr}]`) === section);
    const items = owned(`[${filterSelectionItemDomAttr}]`);
    if (!items.every((item): item is HTMLInputElement => item instanceof HTMLInputElement && item.type === 'checkbox')) return;
    if (target.hasAttribute(filterSelectionClearDomAttr)) {
        for (const item of items) item.checked = false;
    }
    const count = items.filter(item => item.checked).length;
    for (const element of owned(`[${filterSelectionCountDomAttr}]`)) element.textContent = String(count);
    for (const element of owned(`[${filterSelectionAllDomAttr}]`)) {
        if (element instanceof HTMLElement) element.hidden = count !== 0;
    }
    for (const element of owned(`[${filterSelectionSelectedDomAttr}]`)) {
        if (element instanceof HTMLElement) element.hidden = count === 0;
    }
}

// Clip the options themselves, preserving rounded headings without a square mask.
// Their clipping edge follows the actual sticky heading, including section push-off.
export function clipFilterSelectionOptions(section: Element): void {
    const button = section.querySelector('button[aria-controls]');
    const contentId = button?.getAttribute('aria-controls');
    if (!(button instanceof HTMLElement) || !contentId) return;
    const content = section.querySelector(`#${CSS.escape(contentId)}`);
    if (!(content instanceof HTMLElement)) return;
    const headingBottom = button.getBoundingClientRect().bottom;
    const contentBox = content.getBoundingClientRect();
    const inset = Math.min(contentBox.height, Math.max(0, headingBottom - contentBox.top));
    content.style.clipPath = inset > 0 ? `inset(${inset}px 0 0)` : '';
}

if (typeof document !== 'undefined') {
    let clipFrame: number | null = null;
    const scheduleClipping = () => {
        if (clipFrame !== null) return;
        clipFrame = requestAnimationFrame(() => {
            clipFrame = null;
            document.querySelectorAll(`[${filterSelectionSectionDomAttr}]`).forEach(clipFilterSelectionOptions);
        });
    };
    document.addEventListener('scroll', scheduleClipping, { capture: true, passive: true });
    window.addEventListener('resize', scheduleClipping, { passive: true });
    document.addEventListener('shown.bs.collapse', scheduleClipping);
    document.addEventListener('change', event => {
        if (event.target instanceof HTMLInputElement && event.target.hasAttribute(filterSelectionItemDomAttr)) {
            updateFilterSelection(event.target);
        }
    });
    document.addEventListener('click', event => {
        if (!(event.target instanceof Element)) return;
        const clear = event.target.closest(`[${filterSelectionClearDomAttr}]`);
        if (clear !== null) updateFilterSelection(clear);
    });
    document.addEventListener('hidden.bs.collapse', event => {
        if (!(event.target instanceof HTMLElement)) return;
        const section = event.target.closest(`[${filterSelectionSectionDomAttr}]`);
        if (section === null) return;
        const button = section.querySelector(`[aria-controls="${CSS.escape(event.target.id)}"]`);
        // Wait for Bootstrap's collapse to finish before restoring header visibility.
        if (button instanceof HTMLElement) button.scrollIntoView({ block: 'nearest' });
        scheduleClipping();
    });
}
