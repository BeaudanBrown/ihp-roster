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
    if (!(section instanceof HTMLDetailsElement)) return;
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

if (typeof document !== 'undefined') {
    document.addEventListener('change', event => {
        if (event.target instanceof HTMLInputElement && event.target.hasAttribute(filterSelectionItemDomAttr)) {
            updateFilterSelection(event.target);
        }
    });
    document.addEventListener('click', event => {
        if (!(event.target instanceof Element)) return;
        const clear = event.target.closest(`[${filterSelectionClearDomAttr}]`);
        if (clear !== null) updateFilterSelection(clear);
        const summary = event.target.closest('summary');
        const section = summary?.parentElement;
        if (section instanceof HTMLDetailsElement && section.hasAttribute(filterSelectionSectionDomAttr) && section.open) {
            // Native collapse can move a formerly sticky header above the scrollport.
            requestAnimationFrame(() => {
                if (summary?.isConnected && !section.open) summary.scrollIntoView({ block: 'nearest' });
            });
        }
    });
}
