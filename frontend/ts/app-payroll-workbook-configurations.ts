import {
    adminExportsPayrollWorkbookEditorRootDomAttr,
    adminExportsPayrollWorkbookFamilyAddDomAttr,
    adminExportsPayrollWorkbookFamilyEmptyDomAttr,
    adminExportsPayrollWorkbookFamilyListDomAttr,
    adminExportsPayrollWorkbookFamilyMoveDownDomAttr,
    adminExportsPayrollWorkbookFamilyMoveUpDomAttr,
    adminExportsPayrollWorkbookFamilyPickerDomAttr,
    adminExportsPayrollWorkbookFamilyRemoveDomAttr,
    adminExportsPayrollWorkbookFamilyRowDomAttr,
    adminExportsPayrollWorkbookFamilyValueDomAttr,
} from "./generated/contracts";
import { rootFromTarget } from "./shared/dom";
import { detailTarget, onAppPageReady, onHtmxLoad } from "./shared/lifecycle";

type EditorControl = {
    root: HTMLElement;
    list: HTMLElement;
    value: HTMLInputElement;
    picker: HTMLSelectElement;
    add: HTMLButtonElement;
    empty: HTMLElement;
    dragged: HTMLElement | null;
};

const controls = new WeakMap<HTMLElement, EditorControl>();

function roleSelector(attribute: string): string {
    return `[${attribute}]`;
}

function readFamily(row: Element): string | null {
    const value = row.getAttribute(adminExportsPayrollWorkbookFamilyRowDomAttr);
    return value === null || value === "" ? null : value;
}

function familyRows(control: EditorControl): HTMLElement[] {
    return Array.from(control.list.querySelectorAll<HTMLElement>(roleSelector(adminExportsPayrollWorkbookFamilyRowDomAttr)));
}

function selectedFamilies(control: EditorControl): string[] {
    return familyRows(control).flatMap((row) => {
        const family = readFamily(row);
        return family === null ? [] : [family];
    });
}

function synchronizeEditor(control: EditorControl): void {
    const rows = familyRows(control);
    const selected = new Set(selectedFamilies(control));
    control.value.value = JSON.stringify(Array.from(selected));
    control.empty.hidden = rows.length !== 0;

    for (const [index, row] of rows.entries()) {
        const moveUp = row.querySelector<HTMLButtonElement>(roleSelector(adminExportsPayrollWorkbookFamilyMoveUpDomAttr));
        const moveDown = row.querySelector<HTMLButtonElement>(roleSelector(adminExportsPayrollWorkbookFamilyMoveDownDomAttr));
        if (moveUp !== null) moveUp.disabled = index === 0;
        if (moveDown !== null) moveDown.disabled = index === rows.length - 1;
    }

    for (const option of Array.from(control.picker.options)) {
        if (option.value === "") continue;
        const unavailable = selected.has(option.value);
        option.hidden = unavailable;
        option.disabled = unavailable;
    }
    if (selected.has(control.picker.value)) {
        control.picker.value = "";
    }
    control.add.disabled = control.picker.value === "";
}

function actionButton(attribute: string, label: string, content: string, classes: string): HTMLButtonElement {
    const button = document.createElement("button");
    button.type = "button";
    button.className = classes;
    button.setAttribute(attribute, "true");
    button.setAttribute("aria-label", label);
    button.textContent = content;
    return button;
}

function createFamilyRow(family: string, label: string): HTMLElement {
    const row = document.createElement("div");
    row.className = "d-flex align-items-center gap-2 border rounded p-2";
    row.draggable = true;
    row.setAttribute(adminExportsPayrollWorkbookFamilyRowDomAttr, family);

    const handle = document.createElement("span");
    handle.className = "text-body-secondary";
    handle.setAttribute("aria-hidden", "true");
    handle.textContent = "⋮⋮";

    const familyLabel = document.createElement("span");
    familyLabel.className = "flex-grow-1 fw-semibold";
    familyLabel.textContent = label;

    row.append(
        handle,
        familyLabel,
        actionButton(adminExportsPayrollWorkbookFamilyMoveUpDomAttr, `Move ${label} up`, "↑", "btn btn-outline-secondary btn-sm"),
        actionButton(adminExportsPayrollWorkbookFamilyMoveDownDomAttr, `Move ${label} down`, "↓", "btn btn-outline-secondary btn-sm"),
        actionButton(adminExportsPayrollWorkbookFamilyRemoveDomAttr, `Remove ${label}`, "Remove", "btn btn-outline-danger btn-sm"),
    );
    return row;
}

function closestRow(target: EventTarget | null): HTMLElement | null {
    return target instanceof Element
        ? target.closest<HTMLElement>(roleSelector(adminExportsPayrollWorkbookFamilyRowDomAttr))
        : null;
}

function initializeEditor(root: HTMLElement): void {
    if (controls.has(root)) return;
    const list = root.querySelector<HTMLElement>(roleSelector(adminExportsPayrollWorkbookFamilyListDomAttr));
    const value = root.querySelector<HTMLInputElement>(roleSelector(adminExportsPayrollWorkbookFamilyValueDomAttr));
    const picker = root.querySelector<HTMLSelectElement>(roleSelector(adminExportsPayrollWorkbookFamilyPickerDomAttr));
    const add = root.querySelector<HTMLButtonElement>(roleSelector(adminExportsPayrollWorkbookFamilyAddDomAttr));
    const empty = root.querySelector<HTMLElement>(roleSelector(adminExportsPayrollWorkbookFamilyEmptyDomAttr));
    if (list === null || value === null || picker === null || add === null || empty === null) return;

    const control: EditorControl = { root, list, value, picker, add, empty, dragged: null };
    controls.set(root, control);

    picker.addEventListener("change", () => synchronizeEditor(control));
    add.addEventListener("click", () => {
        if (picker.value === "") return;
        const option = picker.selectedOptions.item(0);
        if (option === null) return;
        list.append(createFamilyRow(picker.value, option.textContent ?? picker.value));
        picker.value = "";
        synchronizeEditor(control);
    });

    list.addEventListener("click", (event) => {
        const row = closestRow(event.target);
        if (row === null) return;
        const target = event.target;
        if (!(target instanceof Element)) return;
        if (target.closest(roleSelector(adminExportsPayrollWorkbookFamilyRemoveDomAttr)) !== null) row.remove();
        else if (target.closest(roleSelector(adminExportsPayrollWorkbookFamilyMoveUpDomAttr)) !== null && row.previousElementSibling !== null) {
            list.insertBefore(row, row.previousElementSibling);
        } else if (target.closest(roleSelector(adminExportsPayrollWorkbookFamilyMoveDownDomAttr)) !== null && row.nextElementSibling !== null) {
            list.insertBefore(row.nextElementSibling, row);
        }
        synchronizeEditor(control);
    });

    list.addEventListener("dragstart", (event) => {
        const row = closestRow(event.target);
        if (row === null) return;
        control.dragged = row;
        if (event.dataTransfer !== null) event.dataTransfer.effectAllowed = "move";
    });
    list.addEventListener("dragover", (event) => {
        const targetRow = closestRow(event.target);
        const dragged = control.dragged;
        if (targetRow === null || dragged === null || targetRow === dragged) return;
        event.preventDefault();
        const targetBounds = targetRow.getBoundingClientRect();
        const insertAfter = event.clientY > targetBounds.top + targetBounds.height / 2;
        list.insertBefore(dragged, insertAfter ? targetRow.nextElementSibling : targetRow);
    });
    list.addEventListener("drop", (event) => {
        event.preventDefault();
        synchronizeEditor(control);
    });
    list.addEventListener("dragend", () => {
        control.dragged = null;
        synchronizeEditor(control);
    });

    synchronizeEditor(control);
}

export function initializePayrollWorkbookConfigurationEditors(root: ParentNode): void {
    if (root instanceof HTMLElement && root.hasAttribute(adminExportsPayrollWorkbookEditorRootDomAttr)) initializeEditor(root);
    for (const editor of root.querySelectorAll<HTMLElement>(roleSelector(adminExportsPayrollWorkbookEditorRootDomAttr))) {
        initializeEditor(editor);
    }
}

function enablePayrollWorkbookConfigurationEditors(): void {
    if (typeof window === "undefined") return;
    onAppPageReady((event) => initializePayrollWorkbookConfigurationEditors(rootFromTarget(detailTarget(event, "target"))));
    onHtmxLoad((event) => initializePayrollWorkbookConfigurationEditors(rootFromTarget(detailTarget(event, "elt"))));
    if (document.readyState !== "loading") initializePayrollWorkbookConfigurationEditors(document.body);
}

enablePayrollWorkbookConfigurationEditors();
