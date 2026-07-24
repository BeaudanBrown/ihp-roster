"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  function isRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function hasExactKeys(value, keys, requiredKeys = keys) {
    const valueKeys = Object.keys(value);
    return valueKeys.every((key) => keys.includes(key)) && requiredKeys.every((key) => Object.prototype.hasOwnProperty.call(value, key));
  }
  var pageReadyEvent = "bepis:page-ready";
  function isTimePickerConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["rangeStart", "rangeEnd", "stepMinutes", "emptyLabel"], ["rangeStart", "rangeEnd", "stepMinutes", "emptyLabel"]) && typeof value["rangeStart"] === "string" && typeof value["rangeEnd"] === "string" && (typeof value["stepMinutes"] === "number" && Number.isInteger(value["stepMinutes"])) && typeof value["emptyLabel"] === "string";
  }
  function parseTimePickerConfig(value) {
    if (isTimePickerConfig(value)) return value;
    throw new Error("Invalid TimePickerConfig");
  }
  function isTimePickerOption(value) {
    return isRecord(value) && hasExactKeys(value, ["value", "label"], ["value", "label"]) && typeof value["value"] === "string" && typeof value["label"] === "string";
  }
  function parseTimePickerOption(value) {
    if (isTimePickerOption(value)) return value;
    throw new Error("Invalid TimePickerOption");
  }
  var timePickerModalDomId = "time-picker-modal";
  var timePickerFieldDomAttr = "data-bepis-time-picker-field";
  var timePickerConfigDomAttr = "data-bepis-time-picker-config";
  var timePickerTriggerDomAttr = "data-bepis-time-picker-trigger";
  var timePickerValueDomAttr = "data-bepis-time-picker-value";
  var timePickerLabelDomAttr = "data-bepis-time-picker-label";
  var timePickerStepDownDomAttr = "data-bepis-time-picker-step-down";
  var timePickerStepUpDomAttr = "data-bepis-time-picker-step-up";
  var timePickerOptionsDomAttr = "data-bepis-time-picker-options";
  var timePickerOptionDomAttr = "data-bepis-time-picker-option";
  var timePickerClearDomAttr = "data-bepis-time-picker-clear";

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
  function isHTMLElement(value) {
    return typeof HTMLElement !== "undefined" && value instanceof HTMLElement;
  }
  function rootFromTarget(target, fallback = document) {
    return isDomRoot(target) ? target : fallback;
  }
  function closestHTMLElement(target, selector) {
    if (!isElement(target)) return null;
    const element = target.closest(selector);
    return isHTMLElement(element) ? element : null;
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

  // frontend/ts/time-picker/configuration.ts
  function parseTimePickerConfiguration(raw) {
    return validateTimePickerConfiguration(parseTimePickerConfig(JSON.parse(raw)));
  }
  function parseTimePickerOptionConfiguration(raw) {
    return validateTimePickerOption(parseTimePickerOption(JSON.parse(raw)));
  }
  function timePickerOptionsForConfiguration(rawConfig, rawOptions) {
    const config = validateTimePickerConfiguration(rawConfig);
    const optionsByValue = /* @__PURE__ */ new Map();
    for (const rawOption of rawOptions) {
      const option = validateTimePickerOption(rawOption);
      if (optionsByValue.has(option.value)) {
        throw new Error(`TimePickerOption value ${option.value} must be unique`);
      }
      optionsByValue.set(option.value, option);
    }
    const startMinute = minuteOfDayFromTimeValue(config.rangeStart);
    const rawEndMinute = minuteOfDayFromTimeValue(config.rangeEnd);
    if (startMinute === null || rawEndMinute === null) {
      throw new Error("TimePickerConfig range values must use HH:MM");
    }
    const endMinute = rawEndMinute < startMinute ? rawEndMinute + 24 * 60 : rawEndMinute;
    const selected = [];
    for (let minute = startMinute; minute <= endMinute; minute += config.stepMinutes) {
      const value = timeValueFromMinuteOfDay(minute);
      const option = optionsByValue.get(value);
      if (option === void 0) {
        throw new Error(`TimePickerConfig missing rendered option ${value}`);
      }
      selected.push(option);
    }
    return selected;
  }
  function validateTimePickerConfiguration(config) {
    if (minuteOfDayFromTimeValue(config.rangeStart) === null || minuteOfDayFromTimeValue(config.rangeEnd) === null) {
      throw new Error("TimePickerConfig range values must use HH:MM");
    }
    if (config.stepMinutes <= 0 || config.stepMinutes > 24 * 60) {
      throw new Error("TimePickerConfig stepMinutes must be between 1 and 1440");
    }
    if (config.emptyLabel.trim().length === 0) {
      throw new Error("TimePickerConfig emptyLabel must not be empty");
    }
    return config;
  }
  function validateTimePickerOption(option) {
    if (minuteOfDayFromTimeValue(option.value) === null) {
      throw new Error("TimePickerOption value must use HH:MM");
    }
    if (option.label.trim().length === 0) {
      throw new Error("TimePickerOption label must not be empty");
    }
    return option;
  }
  function minuteOfDayFromTimeValue(value) {
    if (!/^\d{2}:\d{2}$/.test(value)) return null;
    const [rawHour, rawMinute] = value.split(":");
    const hour = Number(rawHour);
    const minute = Number(rawMinute);
    if (!Number.isInteger(hour) || !Number.isInteger(minute)) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }
  function timeValueFromMinuteOfDay(totalMinutes) {
    const minuteOfDay = totalMinutes % (24 * 60);
    const hour = Math.floor(minuteOfDay / 60);
    const minute = minuteOfDay % 60;
    return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
  }

  // frontend/ts/app-time-picker.ts
  var modalControls = /* @__PURE__ */ new WeakMap();
  var fieldControls = /* @__PURE__ */ new WeakMap();
  var activeField = null;
  function defaultDiagnosticReporter(diagnostic) {
    console.error?.("Invalid generated time picker configuration", diagnostic);
  }
  function reportError(report, code, fieldName, error) {
    report({
      code,
      fieldName,
      message: error instanceof Error ? error.message : String(error)
    });
  }
  function getModalElement() {
    const modal = document.getElementById(timePickerModalDomId);
    return isHTMLElement(modal) ? modal : null;
  }
  function getBootstrapModal(modal) {
    if (modal === null || window.bootstrap?.Modal === void 0) return null;
    return window.bootstrap.Modal.getOrCreateInstance(modal);
  }
  function roleElements(root, attribute) {
    return Array.from(root.querySelectorAll(`[${attribute}]`));
  }
  function singleRoleElement(root, attribute) {
    const elements = roleElements(root, attribute);
    return elements.length === 1 ? elements[0] : null;
  }
  function readModalControl(report) {
    const modal = getModalElement();
    if (modal === null) {
      reportError(report, "invalid-modal", null, new Error(`Missing #${timePickerModalDomId}`));
      return null;
    }
    const existing = modalControls.get(modal);
    if (existing !== void 0) return existing;
    const grid = singleRoleElement(modal, timePickerOptionsDomAttr);
    const clear = singleRoleElement(modal, timePickerClearDomAttr);
    if (!(grid instanceof HTMLElement) || !(clear instanceof HTMLButtonElement)) {
      reportError(report, "invalid-modal", null, new Error("Time picker modal must contain one generated options grid and clear button"));
      return null;
    }
    const renderedOptions = [];
    const optionByElement = /* @__PURE__ */ new Map();
    try {
      for (const element of roleElements(grid, timePickerOptionDomAttr)) {
        if (!(element instanceof HTMLButtonElement)) {
          throw new Error("Time picker option role must belong to a button");
        }
        const rawConfig = element.getAttribute(timePickerOptionDomAttr);
        if (rawConfig === null) throw new Error(`Missing ${timePickerOptionDomAttr}`);
        const config = parseTimePickerOptionConfiguration(rawConfig);
        if (element.textContent?.trim() !== config.label) {
          throw new Error(`Time picker option ${config.value} label disagrees with rendered copy`);
        }
        const rendered = { element, config };
        renderedOptions.push(rendered);
        optionByElement.set(element, rendered);
      }
      if (renderedOptions.length === 0) {
        throw new Error("Time picker modal must render at least one generated option");
      }
      const optionValues = new Set(renderedOptions.map((option) => option.config.value));
      if (optionValues.size !== renderedOptions.length) {
        throw new Error("Time picker modal option values must be unique");
      }
    } catch (error) {
      reportError(report, "invalid-option", null, error);
      return null;
    }
    const control = { modal, grid, clear, options: renderedOptions, optionByElement };
    modalControls.set(modal, control);
    return control;
  }
  function getOptionalButton(field, attribute) {
    const elements = roleElements(field, attribute);
    if (elements.length === 0) return null;
    if (elements.length === 1 && elements[0] instanceof HTMLButtonElement) return elements[0];
    return void 0;
  }
  function readFieldControl(field, modal, report) {
    const existing = fieldControls.get(field);
    if (existing !== void 0) return existing;
    const rawConfig = field.getAttribute(timePickerConfigDomAttr);
    let config;
    try {
      if (rawConfig === null) throw new Error(`Missing ${timePickerConfigDomAttr}`);
      config = parseTimePickerConfiguration(rawConfig);
    } catch (error) {
      reportError(report, "invalid-field-config", null, error);
      return null;
    }
    const input = singleRoleElement(field, timePickerValueDomAttr);
    const trigger = singleRoleElement(field, timePickerTriggerDomAttr);
    const label = singleRoleElement(field, timePickerLabelDomAttr);
    const stepDown = getOptionalButton(field, timePickerStepDownDomAttr);
    const stepUp = getOptionalButton(field, timePickerStepUpDomAttr);
    const fieldName = input instanceof HTMLInputElement && input.name.length > 0 ? input.name : null;
    if (!(input instanceof HTMLInputElement) || input.type !== "hidden" || input.name.length === 0 || !(trigger instanceof HTMLButtonElement) || !(label instanceof HTMLElement) || !trigger.contains(label) || stepDown === void 0 || stepUp === void 0 || stepDown === null !== (stepUp === null)) {
      reportError(
        report,
        "invalid-field-structure",
        fieldName,
        new Error("Time picker field must contain one named hidden value, trigger/label pair, and either both or neither step buttons")
      );
      return null;
    }
    let selectedConfigs;
    try {
      selectedConfigs = timePickerOptionsForConfiguration(config, modal.options.map((option) => option.config));
    } catch (error) {
      reportError(report, "invalid-field-config", fieldName, error);
      return null;
    }
    const allOptionsByValue = new Map(modal.options.map((option) => [option.config.value, option]));
    const selectedOptions = [];
    for (const option of selectedConfigs) {
      const renderedOption = allOptionsByValue.get(option.value);
      if (renderedOption === void 0) {
        reportError(report, "invalid-field-config", fieldName, new Error("Time picker field resolved an option outside the rendered inventory"));
        return null;
      }
      selectedOptions.push(renderedOption);
    }
    if (input.value !== "" && !allOptionsByValue.has(input.value)) {
      reportError(report, "invalid-field-value", fieldName, new Error(`Time picker value ${input.value} has no Haskell-rendered option`));
      return null;
    }
    const control = {
      field,
      input,
      trigger,
      label,
      stepDown,
      stepUp,
      config,
      options: selectedOptions,
      allOptionsByValue
    };
    fieldControls.set(field, control);
    return control;
  }
  function labelForValue(control, value) {
    if (value === "") return control.config.emptyLabel;
    return control.allOptionsByValue.get(value)?.config.label ?? null;
  }
  function synchronizeField(control) {
    const currentValue = control.input.value;
    const label = labelForValue(control, currentValue);
    if (label !== null) {
      control.label.textContent = label;
      control.label.classList.toggle("app-muted", currentValue === "");
    }
    const selectedIndex = control.options.findIndex((option) => option.config.value === currentValue);
    const hasSelection = selectedIndex >= 0;
    control.trigger.disabled = control.input.disabled;
    if (control.stepDown !== null) {
      control.stepDown.disabled = control.input.disabled || !hasSelection || selectedIndex === 0;
    }
    if (control.stepUp !== null) {
      control.stepUp.disabled = control.input.disabled || !hasSelection || selectedIndex === control.options.length - 1;
    }
  }
  function applyTimeValue(control, value, label) {
    if (control.input.disabled) return;
    const previousValue = control.input.value;
    control.label.textContent = label;
    control.label.classList.toggle("app-muted", value === "");
    if (previousValue === value) return;
    control.input.value = value;
    control.input.dispatchEvent(new Event("input", { bubbles: true }));
    if (window.htmx?.trigger !== void 0) {
      window.htmx.trigger(control.input, "change");
    } else {
      control.input.dispatchEvent(new Event("change", { bubbles: true }));
    }
  }
  function renderFieldOptions(modal, field) {
    modal.grid.replaceChildren(...field.options.map((option) => option.element));
  }
  function restoreModalOptions(modal) {
    modal.grid.replaceChildren(...modal.options.map((option) => option.element));
  }
  function highlightSelectedOption(modal, value) {
    for (const option of modal.options) {
      const selected = value !== "" && option.config.value === value;
      option.element.classList.toggle("active", selected);
      option.element.classList.toggle("btn-primary", selected);
      option.element.classList.toggle("btn-outline-secondary", !selected);
    }
  }
  function forceHideModal(modal) {
    modal.modal.classList.remove("show");
    modal.modal.style.display = "none";
    modal.modal.setAttribute("aria-hidden", "true");
    modal.modal.removeAttribute("aria-modal");
    document.body.classList.remove("modal-open");
    document.body.style.removeProperty("padding-right");
    document.querySelectorAll(".modal-backdrop").forEach((backdrop) => backdrop.remove());
    restoreModalOptions(modal);
    activeField = null;
  }
  function hideTimePickerModal(modal) {
    const bootstrapModal = getBootstrapModal(modal.modal);
    if (bootstrapModal !== null) bootstrapModal.hide();
    window.setTimeout(() => {
      if (modal.modal.classList.contains("show")) forceHideModal(modal);
    }, 150);
  }
  function stepFieldValue(control, direction) {
    if (control.input.disabled) return;
    const selectedIndex = control.options.findIndex((option) => option.config.value === control.input.value);
    const nextOption = control.options[selectedIndex + direction];
    if (selectedIndex < 0 || nextOption === void 0) {
      synchronizeField(control);
      return;
    }
    applyTimeValue(control, nextOption.config.value, nextOption.config.label);
    synchronizeField(control);
  }
  function fieldFromTarget(target, modal, report) {
    const field = closestHTMLElement(target, `[${timePickerFieldDomAttr}]`);
    return field === null ? null : readFieldControl(field, modal, report);
  }
  function timePickerFieldsWithin(target) {
    const root = rootFromTarget(target);
    const fields = Array.from(root.querySelectorAll(`[${timePickerFieldDomAttr}]`)).filter(isHTMLElement);
    if (root instanceof HTMLElement && root.hasAttribute(timePickerFieldDomAttr)) fields.unshift(root);
    return fields;
  }
  function initializeTimePickerFields(target, report = defaultDiagnosticReporter) {
    const fields = timePickerFieldsWithin(target);
    if (fields.length === 0) return;
    const modal = readModalControl(report);
    if (modal === null) return;
    for (const field of fields) {
      const control = readFieldControl(field, modal, report);
      if (control !== null) synchronizeField(control);
    }
  }
  function enableQuarterHourTimePicker() {
    if (typeof window === "undefined") return;
    document.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") return;
      const modalElement = getModalElement();
      if (modalElement === null || !modalElement.classList.contains("show")) return;
      const modal = readModalControl(defaultDiagnosticReporter);
      if (modal === null) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      hideTimePickerModal(modal);
    }, true);
    document.addEventListener("click", (event) => {
      const trigger = closestHTMLElement(event.target, `[${timePickerTriggerDomAttr}]`);
      if (!(trigger instanceof HTMLButtonElement) || trigger.disabled) return;
      const modal = readModalControl(defaultDiagnosticReporter);
      if (modal === null) return;
      const field = fieldFromTarget(trigger, modal, defaultDiagnosticReporter);
      const bootstrapModal = getBootstrapModal(modal.modal);
      if (field === null || field.input.disabled || bootstrapModal === null) return;
      activeField = field;
      renderFieldOptions(modal, field);
      highlightSelectedOption(modal, field.input.value);
      bootstrapModal.show();
    });
    document.addEventListener("click", (event) => {
      const stepDown = closestHTMLElement(event.target, `[${timePickerStepDownDomAttr}]`);
      if (!(stepDown instanceof HTMLButtonElement) || stepDown.disabled) return;
      const modal = readModalControl(defaultDiagnosticReporter);
      if (modal === null) return;
      const field = fieldFromTarget(stepDown, modal, defaultDiagnosticReporter);
      if (field !== null) stepFieldValue(field, -1);
    });
    document.addEventListener("click", (event) => {
      const stepUp = closestHTMLElement(event.target, `[${timePickerStepUpDomAttr}]`);
      if (!(stepUp instanceof HTMLButtonElement) || stepUp.disabled) return;
      const modal = readModalControl(defaultDiagnosticReporter);
      if (modal === null) return;
      const field = fieldFromTarget(stepUp, modal, defaultDiagnosticReporter);
      if (field !== null) stepFieldValue(field, 1);
    });
    document.addEventListener("click", (event) => {
      const optionElement = closestHTMLElement(event.target, `[${timePickerOptionDomAttr}]`);
      if (!(optionElement instanceof HTMLButtonElement) || activeField === null) return;
      const modal = readModalControl(defaultDiagnosticReporter);
      if (modal === null) return;
      const renderedOption = modal.optionByElement.get(optionElement);
      if (renderedOption === void 0 || !modal.grid.contains(optionElement)) return;
      try {
        const rawConfig = optionElement.getAttribute(timePickerOptionDomAttr);
        if (rawConfig === null) throw new Error(`Missing ${timePickerOptionDomAttr}`);
        const currentConfig = parseTimePickerOptionConfiguration(rawConfig);
        if (currentConfig.value !== renderedOption.config.value || currentConfig.label !== renderedOption.config.label) {
          throw new Error("Time picker option payload changed after initialization");
        }
      } catch (error) {
        reportError(defaultDiagnosticReporter, "invalid-option", activeField.input.name, error);
        return;
      }
      applyTimeValue(activeField, renderedOption.config.value, renderedOption.config.label);
      highlightSelectedOption(modal, renderedOption.config.value);
      synchronizeField(activeField);
      hideTimePickerModal(modal);
    });
    document.addEventListener("click", (event) => {
      const clear = closestHTMLElement(event.target, `[${timePickerClearDomAttr}]`);
      if (!(clear instanceof HTMLButtonElement) || activeField === null) return;
      const modal = readModalControl(defaultDiagnosticReporter);
      if (modal === null || clear !== modal.clear) return;
      applyTimeValue(activeField, "", activeField.config.emptyLabel);
      highlightSelectedOption(modal, "");
      synchronizeField(activeField);
      hideTimePickerModal(modal);
    });
    document.addEventListener("hidden.bs.modal", (event) => {
      if (!(event.target instanceof HTMLElement) || event.target.id !== timePickerModalDomId) return;
      const modal = modalControls.get(event.target);
      if (modal !== void 0) restoreModalOptions(modal);
      activeField = null;
    });
    onAppPageReady((event) => {
      initializeTimePickerFields(detailTarget(event, "target"));
    });
    onHtmxLoad((event) => {
      initializeTimePickerFields(detailTarget(event, "elt"));
    });
    if (document.readyState !== "loading") {
      initializeTimePickerFields(document.body);
    }
  }
  enableQuarterHourTimePicker();
})();
