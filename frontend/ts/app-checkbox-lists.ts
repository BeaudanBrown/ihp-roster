import {
    checkboxListRootDomAttr,
    checkboxListGroupDomAttr,
    checkboxListItemDomAttr,
    checkboxListGroupToggleDomAttr,
    checkboxListSelectAllDomAttr,
    checkboxListClearAllDomAttr,
    checkboxListCountDomAttr,
    checkboxListTotalDomAttr,
    checkboxListWeightDomAttr,
    checkboxListSubmitDomAttr,
} from './generated/contracts';

// Deferred selection changes native form state only. No URLs, requests, or
// domain identities are interpreted here; the server validates final submission.
export function updateCheckboxList(target: Element): void {
    const root = target.closest(`[${checkboxListRootDomAttr}]`);
    if (!(root instanceof HTMLFormElement)) return;
    const owns = (element: Element) => element.closest(`[${checkboxListRootDomAttr}]`) === root;
    const itemElements = Array.from(root.querySelectorAll(`[${checkboxListItemDomAttr}]`)).filter(owns);
    const items: Array<{ input: HTMLInputElement; weight: number }> = [];
    for (const element of itemElements) {
        if (!(element instanceof HTMLInputElement) || element.type !== 'checkbox') return;
        const rawWeight = element.getAttribute(checkboxListWeightDomAttr);
        if (rawWeight === null || rawWeight.trim() === '') return;
        const weight = Number(rawWeight);
        if (!Number.isFinite(weight) || weight < 0) return;
        items.push({ input: element, weight });
    }
    const groupElements = Array.from(root.querySelectorAll(`[${checkboxListGroupToggleDomAttr}]`)).filter(owns);
    const groups: Array<{ input: HTMLInputElement; items: typeof items }> = [];
    for (const element of groupElements) {
        if (!(element instanceof HTMLInputElement) || element.type !== 'checkbox') return;
        const group = element.closest(`[${checkboxListGroupDomAttr}]`);
        if (group === null || !owns(group)) return;
        groups.push({ input: element, items: items.filter(item => item.input.closest(`[${checkboxListGroupDomAttr}]`) === group) });
    }
    const counts = Array.from(root.querySelectorAll(`[${checkboxListCountDomAttr}]`)).filter(owns);
    const totals = Array.from(root.querySelectorAll(`[${checkboxListTotalDomAttr}]`)).filter(owns);
    if (!counts.every(element => element instanceof HTMLOutputElement)
        || !totals.every(element => element instanceof HTMLOutputElement)) return;

    const selectAll = target.hasAttribute(checkboxListSelectAllDomAttr);
    const clearAll = target.hasAttribute(checkboxListClearAllDomAttr);
    const selectedGroup = groups.find(group => group.input === target);
    if (selectAll || clearAll) {
        for (const item of items) item.input.checked = selectAll;
    } else if (selectedGroup !== undefined) {
        for (const item of selectedGroup.items) item.input.checked = selectedGroup.input.checked;
    } else if (!items.some(item => item.input === target)) return;

    for (const group of groups) {
        group.input.checked = group.items.length > 0 && group.items.every(item => item.input.checked);
        group.input.indeterminate = false;
    }
    const selected = items.filter(item => item.input.checked);
    for (const count of counts) count.value = String(selected.length);
    const total = Math.round(selected.reduce((sum, item) => sum + item.weight, 0) * 100) / 100;
    for (const output of totals) output.value = String(total);
    // form.elements includes the footer's externally associated submit control.
    for (const element of Array.from(root.elements)) {
        if (element instanceof HTMLButtonElement && element.hasAttribute(checkboxListSubmitDomAttr)) {
            element.disabled = selected.length === 0;
        }
    }
}

if (typeof document !== 'undefined') {
    document.addEventListener('change', event => {
        if (!(event.target instanceof HTMLInputElement)) return;
        if (event.target.hasAttribute(checkboxListItemDomAttr) || event.target.hasAttribute(checkboxListGroupToggleDomAttr)) {
            updateCheckboxList(event.target);
        }
    });
    document.addEventListener('click', event => {
        if (!(event.target instanceof Element)) return;
        const control = event.target.closest(`[${checkboxListSelectAllDomAttr}], [${checkboxListClearAllDomAttr}]`);
        if (control !== null) updateCheckboxList(control);
    });
}
