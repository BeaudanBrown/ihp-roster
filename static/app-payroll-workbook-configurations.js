"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  var pageReadyEvent = "bepis:page-ready";
  var adminExportsPayrollWorkbookEditorRootDomAttr = "data-bepis-admin-exports-payroll-workbook-editor-root";
  var adminExportsPayrollWorkbookFamilyListDomAttr = "data-bepis-admin-exports-payroll-workbook-family-list";
  var adminExportsPayrollWorkbookFamilyValueDomAttr = "data-bepis-admin-exports-payroll-workbook-family-value";
  var adminExportsPayrollWorkbookFamilyRowDomAttr = "data-bepis-admin-exports-payroll-workbook-family-row";
  var adminExportsPayrollWorkbookFamilyMoveUpDomAttr = "data-bepis-admin-exports-payroll-workbook-family-move-up";
  var adminExportsPayrollWorkbookFamilyMoveDownDomAttr = "data-bepis-admin-exports-payroll-workbook-family-move-down";
  var adminExportsPayrollWorkbookFamilyRemoveDomAttr = "data-bepis-admin-exports-payroll-workbook-family-remove";
  var adminExportsPayrollWorkbookFamilyPickerDomAttr = "data-bepis-admin-exports-payroll-workbook-family-picker";
  var adminExportsPayrollWorkbookFamilyAddDomAttr = "data-bepis-admin-exports-payroll-workbook-family-add";
  var adminExportsPayrollWorkbookFamilyEmptyDomAttr = "data-bepis-admin-exports-payroll-workbook-family-empty";

  // frontend/ts/shared/dom.ts
  function isElement(value) {
    return typeof Element !== "undefined" && value instanceof Element;
  }
  function isDocument(value) {
    return typeof Document !== "undefined" && value instanceof Document;
  }
  function isDocumentFragment(value) {
    return typeof DocumentFragment !== "undefined" && value instanceof DocumentFragment;
  }
  function isDomRoot(value) {
    return isElement(value) || isDocument(value) || isDocumentFragment(value);
  }
  function rootFromTarget(target, fallback = document) {
    return isDomRoot(target) ? target : fallback;
  }

  // frontend/ts/shared/lifecycle.ts
  function eventDetailRecord(event) {
    if (typeof CustomEvent === "undefined" || !(event instanceof CustomEvent)) return null;
    if (event.detail === null || typeof event.detail !== "object") return null;
    return event.detail;
  }
  function detailTarget(event, key) {
    return eventDetailRecord(event)?.[key];
  }
  function onAppPageReady(handler) {
    if (typeof document === "undefined") return;
    document.addEventListener(pageReadyEvent, handler);
  }
  function onHtmxLoad(handler) {
    if (typeof document === "undefined") return;
    document.addEventListener("htmx:load", handler);
  }

  // frontend/ts/app-payroll-workbook-configurations.ts
  var controls = /* @__PURE__ */ new WeakMap();
  function roleSelector(attribute) {
    return `[${attribute}]`;
  }
  function readFamily(row) {
    const value = row.getAttribute(adminExportsPayrollWorkbookFamilyRowDomAttr);
    return value === null || value === "" ? null : value;
  }
  function familyRows(control) {
    return Array.from(control.list.querySelectorAll(roleSelector(adminExportsPayrollWorkbookFamilyRowDomAttr)));
  }
  function selectedFamilies(control) {
    return familyRows(control).flatMap((row) => {
      const family = readFamily(row);
      return family === null ? [] : [family];
    });
  }
  function synchronizeEditor(control) {
    const rows = familyRows(control);
    const selected = new Set(selectedFamilies(control));
    control.value.value = JSON.stringify(Array.from(selected));
    control.empty.hidden = rows.length !== 0;
    for (const [index, row] of rows.entries()) {
      const moveUp = row.querySelector(roleSelector(adminExportsPayrollWorkbookFamilyMoveUpDomAttr));
      const moveDown = row.querySelector(roleSelector(adminExportsPayrollWorkbookFamilyMoveDownDomAttr));
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
  function actionButton(attribute, label, content, classes) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = classes;
    button.setAttribute(attribute, "true");
    button.setAttribute("aria-label", label);
    button.textContent = content;
    return button;
  }
  function createFamilyRow(family, label) {
    const row = document.createElement("div");
    row.className = "d-flex align-items-center gap-2 border rounded p-2";
    row.draggable = true;
    row.setAttribute(adminExportsPayrollWorkbookFamilyRowDomAttr, family);
    const handle = document.createElement("span");
    handle.className = "text-body-secondary";
    handle.setAttribute("aria-hidden", "true");
    handle.textContent = "\u22EE\u22EE";
    const familyLabel = document.createElement("span");
    familyLabel.className = "flex-grow-1 fw-semibold";
    familyLabel.textContent = label;
    row.append(
      handle,
      familyLabel,
      actionButton(adminExportsPayrollWorkbookFamilyMoveUpDomAttr, `Move ${label} up`, "\u2191", "btn btn-outline-secondary btn-sm"),
      actionButton(adminExportsPayrollWorkbookFamilyMoveDownDomAttr, `Move ${label} down`, "\u2193", "btn btn-outline-secondary btn-sm"),
      actionButton(adminExportsPayrollWorkbookFamilyRemoveDomAttr, `Remove ${label}`, "Remove", "btn btn-outline-danger btn-sm")
    );
    return row;
  }
  function closestRow(target) {
    return target instanceof Element ? target.closest(roleSelector(adminExportsPayrollWorkbookFamilyRowDomAttr)) : null;
  }
  function initializeEditor(root) {
    if (controls.has(root)) return;
    const list = root.querySelector(roleSelector(adminExportsPayrollWorkbookFamilyListDomAttr));
    const value = root.querySelector(roleSelector(adminExportsPayrollWorkbookFamilyValueDomAttr));
    const picker = root.querySelector(roleSelector(adminExportsPayrollWorkbookFamilyPickerDomAttr));
    const add = root.querySelector(roleSelector(adminExportsPayrollWorkbookFamilyAddDomAttr));
    const empty = root.querySelector(roleSelector(adminExportsPayrollWorkbookFamilyEmptyDomAttr));
    if (list === null || value === null || picker === null || add === null || empty === null) return;
    const control = { root, list, value, picker, add, empty, dragged: null };
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
  function initializePayrollWorkbookConfigurationEditors(root) {
    if (root instanceof HTMLElement && root.hasAttribute(adminExportsPayrollWorkbookEditorRootDomAttr)) initializeEditor(root);
    for (const editor of root.querySelectorAll(roleSelector(adminExportsPayrollWorkbookEditorRootDomAttr))) {
      initializeEditor(editor);
    }
  }
  function enablePayrollWorkbookConfigurationEditors() {
    if (typeof window === "undefined") return;
    onAppPageReady((event) => initializePayrollWorkbookConfigurationEditors(rootFromTarget(detailTarget(event, "target"))));
    onHtmxLoad((event) => initializePayrollWorkbookConfigurationEditors(rootFromTarget(detailTarget(event, "elt"))));
    if (document.readyState !== "loading") initializePayrollWorkbookConfigurationEditors(document.body);
  }
  enablePayrollWorkbookConfigurationEditors();
})();
