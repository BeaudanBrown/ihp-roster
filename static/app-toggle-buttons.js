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
  function isTogglePresentationState(value) {
    return typeof value === "string" && ["checked", "unchecked"].includes(value);
  }
  function isToggleSubmissionPolicy(value) {
    return typeof value === "string" && ["deferred", "immediate"].includes(value);
  }
  function isToggleTarget(value) {
    return isRecord(value) && hasExactKeys(value, ["tag", "value"], ["tag", "value"]) && value["tag"] === "value" && typeof value["value"] === "string" || isRecord(value) && hasExactKeys(value, ["tag"], ["tag"]) && value["tag"] === "omitted";
  }
  function isToggleConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["presentationState", "checkedTarget", "uncheckedTarget", "transportKey", "submissionPolicy", "breakRegionKey"], ["presentationState", "checkedTarget", "uncheckedTarget", "transportKey", "submissionPolicy", "breakRegionKey"]) && isTogglePresentationState(value["presentationState"]) && isToggleTarget(value["checkedTarget"]) && isToggleTarget(value["uncheckedTarget"]) && typeof value["transportKey"] === "string" && isToggleSubmissionPolicy(value["submissionPolicy"]) && (value["breakRegionKey"] === null || typeof value["breakRegionKey"] === "string");
  }
  function parseToggleConfig(value) {
    if (isToggleConfig(value)) return value;
    throw new Error("Invalid ToggleConfig");
  }
  var toggleRootDomAttr = "data-bepis-toggle-root";
  var toggleInputDomAttr = "data-bepis-toggle-input";
  var toggleLabelStateDomAttr = "data-bepis-toggle-label-state";
  var toggleTransportDomAttr = "data-bepis-toggle-transport";
  var toggleBreakRegionDomAttr = "data-bepis-toggle-break-region";
  var toggleConfigDomAttr = "data-bepis-toggle-config";

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

  // frontend/ts/shared/exhaustive.ts
  function assertNever(value, message = "Unexpected generated union variant") {
    throw new Error(`${message}: ${JSON.stringify(value)}`);
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

  // frontend/ts/app-toggle-buttons.ts
  var initializedControls = /* @__PURE__ */ new WeakMap();
  var checkedClass = "is-toggle-checked";
  function targetsEqual(left, right) {
    if (left.tag !== right.tag) return false;
    if (left.tag === "omitted" || right.tag === "omitted") return true;
    return left.value === right.value;
  }
  function parseToggleConfiguration(raw) {
    const config = parseToggleConfig(JSON.parse(raw));
    if (config.transportKey.length === 0) {
      throw new Error("Toggle transportKey must not be empty");
    }
    if (config.breakRegionKey !== null && config.breakRegionKey.length === 0) {
      throw new Error("Toggle breakRegionKey must be null or non-empty");
    }
    if (targetsEqual(config.checkedTarget, config.uncheckedTarget)) {
      throw new Error("Toggle checkedTarget and uncheckedTarget must differ");
    }
    return config;
  }
  function toggleTargetForChecked(config, checked) {
    return checked ? config.checkedTarget : config.uncheckedTarget;
  }
  function toggleTransportState(target) {
    switch (target.tag) {
      case "value":
        return { value: target.value, disabled: false };
      case "omitted":
        return { value: "", disabled: true };
      default:
        return assertNever(target);
    }
  }
  function presentationStateForChecked(checked) {
    return checked ? "checked" : "unchecked";
  }
  function defaultDiagnosticReporter(diagnostic2) {
    console.error?.("Invalid generated toggle configuration", diagnostic2);
  }
  function diagnostic(input, code, message) {
    return { code, inputId: input.id, message };
  }
  function elementsWithRelationship(root, attribute, key) {
    return Array.from(root.querySelectorAll(`[${attribute}]`)).filter((element) => element.getAttribute(attribute) === key);
  }
  function readToggleControl(input, report) {
    const rawConfig = input.getAttribute(toggleConfigDomAttr);
    let config;
    try {
      if (rawConfig === null) throw new Error(`Missing ${toggleConfigDomAttr}`);
      config = parseToggleConfiguration(rawConfig);
    } catch (error) {
      report(diagnostic(input, "invalid-config", error instanceof Error ? error.message : String(error)));
      return null;
    }
    if (input.getAttribute(toggleInputDomAttr) !== config.transportKey) {
      report(diagnostic(input, "invalid-input-key", "Toggle input relationship does not match transportKey"));
      return null;
    }
    const root = input.closest(`[${toggleRootDomAttr}]`);
    if (!(root instanceof HTMLElement)) {
      report(diagnostic(input, "missing-root", "Toggle input has no generated root"));
      return null;
    }
    if (root.getAttribute(toggleRootDomAttr) !== config.transportKey) {
      report(diagnostic(input, "invalid-root-key", "Toggle root relationship does not match transportKey"));
      return null;
    }
    const form = input.form;
    if (!(form instanceof HTMLFormElement)) {
      report(diagnostic(input, "missing-form", "Toggle input must belong to a form"));
      return null;
    }
    const transports = elementsWithRelationship(form, toggleTransportDomAttr, config.transportKey);
    if (transports.length !== 1 || !(transports[0] instanceof HTMLInputElement) || transports[0].type !== "hidden" || transports[0].name.length === 0) {
      report(diagnostic(input, "invalid-transport", "Toggle must resolve exactly one named hidden transport within input.form"));
      return null;
    }
    const transport = transports[0];
    const expectedPresentation = presentationStateForChecked(input.checked);
    if (config.presentationState !== expectedPresentation) {
      report(diagnostic(input, "invalid-presentation-state", "Rendered checkbox state disagrees with ToggleConfig presentationState"));
      return null;
    }
    const expectedTransport = toggleTransportState(toggleTargetForChecked(config, input.checked));
    if (transport.value !== expectedTransport.value || transport.disabled !== expectedTransport.disabled) {
      report(diagnostic(input, "invalid-transport", "Rendered transport state disagrees with ToggleConfig"));
      return null;
    }
    const labels = [];
    const seenStates = /* @__PURE__ */ new Set();
    for (const label of root.querySelectorAll(`[${toggleLabelStateDomAttr}]`)) {
      const state = label.getAttribute(toggleLabelStateDomAttr);
      if (!(label instanceof HTMLElement) || !isTogglePresentationState(state) || seenStates.has(state)) {
        report(diagnostic(input, "invalid-label-state", "Toggle labels must use unique generated presentation states"));
        return null;
      }
      seenStates.add(state);
      labels.push({ element: label, state });
    }
    if (labels.length !== 0 && labels.length !== 2) {
      report(diagnostic(input, "invalid-label-state", "State-labelled toggles must render checked and unchecked labels"));
      return null;
    }
    let breakRegion = null;
    if (config.breakRegionKey !== null) {
      const regions = elementsWithRelationship(form, toggleBreakRegionDomAttr, config.breakRegionKey);
      if (regions.length !== 1 || !(regions[0] instanceof HTMLFieldSetElement) || regions[0].id.length === 0 || input.getAttribute("aria-controls") !== regions[0].id) {
        report(diagnostic(input, "invalid-break-region", "Toggle must resolve one aria-related break fieldset within input.form"));
        return null;
      }
      breakRegion = regions[0];
    }
    return { input, root, form, transport, breakRegion, labels, config };
  }
  function synchronizeToggle(control) {
    const { input, root, transport, breakRegion, labels, config } = control;
    const checked = input.checked;
    const transportState = toggleTransportState(toggleTargetForChecked(config, checked));
    transport.value = transportState.value;
    transport.disabled = transportState.disabled;
    root.classList.toggle(checkedClass, checked);
    root.setAttribute("aria-pressed", String(checked));
    if (input.getAttribute("role") === "switch") {
      input.setAttribute("aria-checked", String(checked));
    }
    for (const label of labels) {
      label.element.hidden = label.state !== presentationStateForChecked(checked);
    }
    if (breakRegion !== null) {
      breakRegion.disabled = !checked;
      breakRegion.setAttribute("aria-disabled", String(!checked));
    }
  }
  function initializeToggle(input, report) {
    const existing = initializedControls.get(input);
    if (existing !== void 0) return existing;
    const control = readToggleControl(input, report);
    if (control === null) return null;
    initializedControls.set(input, control);
    synchronizeToggle(control);
    return control;
  }
  function toggleInputsWithin(target) {
    const root = rootFromTarget(target);
    const inputs = Array.from(root.querySelectorAll(`[${toggleInputDomAttr}]`)).filter((element) => element instanceof HTMLInputElement);
    if (root instanceof HTMLInputElement && root.hasAttribute(toggleInputDomAttr)) {
      inputs.unshift(root);
    }
    return inputs;
  }
  function initializeToggleButtons(target, report = defaultDiagnosticReporter) {
    for (const input of toggleInputsWithin(target)) {
      initializeToggle(input, report);
    }
  }
  function handleToggleChange(event) {
    if (!(event.target instanceof HTMLInputElement) || !event.target.hasAttribute(toggleInputDomAttr)) return;
    const control = initializeToggle(event.target, defaultDiagnosticReporter);
    if (control === null) return;
    synchronizeToggle(control);
    if (control.config.submissionPolicy === "immediate") {
      control.form.requestSubmit();
    }
  }
  function enableAppToggleButtons() {
    if (typeof window === "undefined") return;
    document.addEventListener("change", handleToggleChange, true);
    onAppPageReady((event) => {
      initializeToggleButtons(detailTarget(event, "target"));
    });
    onHtmxLoad((event) => {
      initializeToggleButtons(detailTarget(event, "elt"));
    });
    if (document.readyState !== "loading") {
      initializeToggleButtons(document.body);
    }
  }
  enableAppToggleButtons();
})();
