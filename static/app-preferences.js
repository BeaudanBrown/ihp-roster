"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  function isRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function hasExactKeys(value, keys) {
    return Object.keys(value).every((key) => keys.includes(key));
  }
  var pageReadyEvent = "bepis:page-ready";
  function isOrderedRangeCrossingPolicy(value) {
    return typeof value === "string" && ["clamp-other-endpoint"].includes(value);
  }
  function isOrderedRangeConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["minimumValue", "maximumValue", "stepValue", "defaultStartValue", "defaultEndValue", "valueLabels", "crossingPolicy"]) && (typeof value["minimumValue"] === "number" && Number.isInteger(value["minimumValue"])) && (typeof value["maximumValue"] === "number" && Number.isInteger(value["maximumValue"])) && (typeof value["stepValue"] === "number" && Number.isInteger(value["stepValue"])) && (typeof value["defaultStartValue"] === "number" && Number.isInteger(value["defaultStartValue"])) && (typeof value["defaultEndValue"] === "number" && Number.isInteger(value["defaultEndValue"])) && (Array.isArray(value["valueLabels"]) && value["valueLabels"].every((item) => typeof item === "string")) && isOrderedRangeCrossingPolicy(value["crossingPolicy"]);
  }
  function parseOrderedRangeConfig(value) {
    if (isOrderedRangeConfig(value)) return value;
    throw new Error("Invalid OrderedRangeConfig");
  }
  function isOrderedRangeState(value) {
    return isRecord(value) && hasExactKeys(value, ["startValue", "endValue", "available"]) && (typeof value["startValue"] === "number" && Number.isInteger(value["startValue"])) && (typeof value["endValue"] === "number" && Number.isInteger(value["endValue"])) && typeof value["available"] === "boolean";
  }
  function parseOrderedRangeState(value) {
    if (isOrderedRangeState(value)) return value;
    throw new Error("Invalid OrderedRangeState");
  }
  var orderedRangeClampOtherEndpoint = "clamp-other-endpoint";
  var orderedRangeStartPositionProperty = "--ordered-range-start-position";
  var orderedRangeEndPositionProperty = "--ordered-range-end-position";
  var orderedRangeRootDomAttr = "data-bepis-ordered-range-root";
  var orderedRangeConfigDomAttr = "data-bepis-ordered-range-config";
  var orderedRangeStateDomAttr = "data-bepis-ordered-range-state";
  var orderedRangeStartDomAttr = "data-bepis-ordered-range-start";
  var orderedRangeEndDomAttr = "data-bepis-ordered-range-end";
  var orderedRangeAvailabilityDomAttr = "data-bepis-ordered-range-availability";

  // frontend/ts/ordered-range/configuration.ts
  var crossingPolicyHandlers = {
    [orderedRangeClampOtherEndpoint]: (state, changedEndpoint) => {
      if (state.startValue <= state.endValue) return state;
      if (changedEndpoint === "start") {
        return { ...state, endValue: state.startValue };
      }
      return { ...state, startValue: state.endValue };
    }
  };
  function parseOrderedRangeConfiguration(raw) {
    return validateOrderedRangeConfiguration(parseOrderedRangeConfig(JSON.parse(raw)));
  }
  function parseOrderedRangeStateConfiguration(rawConfig, raw) {
    const config = validateOrderedRangeConfiguration(rawConfig);
    return validateOrderedRangeState(config, parseOrderedRangeState(JSON.parse(raw)));
  }
  function orderedRangeStateForInput(rawConfig, rawState, changedEndpoint, value) {
    const config = validateOrderedRangeConfiguration(rawConfig);
    const state = validateOrderedRangeState(config, rawState);
    if (!isAllowedValue(config, value)) {
      throw new Error(`OrderedRange value ${value} is outside the configured inventory`);
    }
    const changedState = changedEndpoint === "start" ? { ...state, startValue: value } : { ...state, endValue: value };
    return crossingPolicyHandlers[config.crossingPolicy](changedState, changedEndpoint);
  }
  function orderedRangeLabelForValue(rawConfig, value) {
    const config = validateOrderedRangeConfiguration(rawConfig);
    if (!isAllowedValue(config, value)) {
      throw new Error(`OrderedRange value ${value} is outside the configured inventory`);
    }
    const index = (value - config.minimumValue) / config.stepValue;
    const label = config.valueLabels[index];
    if (label === void 0) {
      throw new Error(`OrderedRange value ${value} has no configured label`);
    }
    return label;
  }
  function orderedRangePositionPercent(rawConfig, value) {
    const config = validateOrderedRangeConfiguration(rawConfig);
    if (!isAllowedValue(config, value)) {
      throw new Error(`OrderedRange value ${value} is outside the configured inventory`);
    }
    return (value - config.minimumValue) / (config.maximumValue - config.minimumValue) * 100;
  }
  function validateOrderedRangeConfiguration(config) {
    if (config.minimumValue >= config.maximumValue) {
      throw new Error("OrderedRangeConfig minimum must be less than maximum");
    }
    if (config.stepValue <= 0) {
      throw new Error("OrderedRangeConfig step must be positive");
    }
    const span = config.maximumValue - config.minimumValue;
    if (span % config.stepValue !== 0) {
      throw new Error("OrderedRangeConfig step must evenly divide the allowed range");
    }
    const expectedLabelCount = span / config.stepValue + 1;
    if (config.valueLabels.length !== expectedLabelCount) {
      throw new Error("OrderedRangeConfig labels must cover every allowed value");
    }
    if (config.valueLabels.some((label) => label.trim().length === 0)) {
      throw new Error("OrderedRangeConfig labels must not be empty");
    }
    if (!isAllowedValue(config, config.defaultStartValue)) {
      throw new Error("OrderedRangeConfig default start is outside the allowed range");
    }
    if (!isAllowedValue(config, config.defaultEndValue)) {
      throw new Error("OrderedRangeConfig default end is outside the allowed range");
    }
    if (config.defaultStartValue > config.defaultEndValue) {
      throw new Error("OrderedRangeConfig default start must not exceed default end");
    }
    return config;
  }
  function validateOrderedRangeState(config, state) {
    if (!isAllowedValue(config, state.startValue)) {
      throw new Error("OrderedRangeState start is outside the allowed range");
    }
    if (!isAllowedValue(config, state.endValue)) {
      throw new Error("OrderedRangeState end is outside the allowed range");
    }
    if (state.startValue > state.endValue) {
      throw new Error("OrderedRangeState start must not exceed end");
    }
    return state;
  }
  function isAllowedValue(config, value) {
    return Number.isInteger(value) && value >= config.minimumValue && value <= config.maximumValue && (value - config.minimumValue) % config.stepValue === 0;
  }

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

  // frontend/ts/app-preferences.ts
  var initializedControls = /* @__PURE__ */ new WeakMap();
  function defaultDiagnosticReporter(diagnostic2) {
    console.error?.("Invalid generated ordered-range configuration", diagnostic2);
  }
  function diagnostic(root, code, message) {
    return { code, rootId: root.id, message };
  }
  function exactlyOneWithin(root, selector, isExpected) {
    const matches = Array.from(root.querySelectorAll(selector));
    return matches.length === 1 && isExpected(matches[0]) ? matches[0] : null;
  }
  function outputForInput(root, input) {
    if (input.id.length === 0) return null;
    const outputs = Array.from(root.querySelectorAll("output[for]")).filter((output) => output instanceof HTMLOutputElement && output.getAttribute("for") === input.id);
    return outputs.length === 1 ? outputs[0] : null;
  }
  function readOrderedRangeControl(root, report) {
    let config;
    const rawConfig = root.getAttribute(orderedRangeConfigDomAttr);
    try {
      if (rawConfig === null) throw new Error(`Missing ${orderedRangeConfigDomAttr}`);
      config = parseOrderedRangeConfiguration(rawConfig);
    } catch (error) {
      report(diagnostic(root, "invalid-config", error instanceof Error ? error.message : String(error)));
      return null;
    }
    let state;
    const rawState = root.getAttribute(orderedRangeStateDomAttr);
    try {
      if (rawState === null) throw new Error(`Missing ${orderedRangeStateDomAttr}`);
      state = parseOrderedRangeStateConfiguration(config, rawState);
    } catch (error) {
      report(diagnostic(root, "invalid-state", error instanceof Error ? error.message : String(error)));
      return null;
    }
    const isRangeInput = (element) => element instanceof HTMLInputElement && element.type === "range" && element.name.length > 0 && element.id.length > 0;
    const startInput = exactlyOneWithin(root, `[${orderedRangeStartDomAttr}]`, isRangeInput);
    if (startInput === null) {
      report(diagnostic(root, "invalid-start", "Ordered range must contain exactly one named start range input"));
      return null;
    }
    const endInput = exactlyOneWithin(root, `[${orderedRangeEndDomAttr}]`, isRangeInput);
    if (endInput === null || endInput === startInput) {
      report(diagnostic(root, "invalid-end", "Ordered range must contain exactly one distinct named end range input"));
      return null;
    }
    const availabilityRole = exactlyOneWithin(
      root,
      `[${orderedRangeAvailabilityDomAttr}]`,
      (element) => element instanceof HTMLElement
    );
    const availabilityInput = availabilityRole === null ? null : exactlyOneWithin(
      availabilityRole,
      'input[type="checkbox"]',
      (element) => element instanceof HTMLInputElement
    );
    if (availabilityInput === null) {
      report(diagnostic(root, "invalid-availability", "Ordered range availability role must contain exactly one native checkbox"));
      return null;
    }
    const startOutput = outputForInput(root, startInput);
    const endOutput = outputForInput(root, endInput);
    if (startOutput === null || endOutput === null || startOutput === endOutput) {
      report(diagnostic(root, "invalid-output", "Ordered range endpoints must each have one native output relationship"));
      return null;
    }
    const expectedMinimum = String(config.minimumValue);
    const expectedMaximum = String(config.maximumValue);
    const expectedStep = String(config.stepValue);
    const renderedStateMatches = startInput.min === expectedMinimum && startInput.max === expectedMaximum && startInput.step === expectedStep && endInput.min === expectedMinimum && endInput.max === expectedMaximum && endInput.step === expectedStep && startInput.value === String(state.startValue) && endInput.value === String(state.endValue) && availabilityInput.checked === state.available && startInput.disabled === !state.available && endInput.disabled === !state.available && startOutput.textContent?.trim() === orderedRangeLabelForValue(config, state.startValue) && endOutput.textContent?.trim() === orderedRangeLabelForValue(config, state.endValue);
    if (!renderedStateMatches) {
      report(diagnostic(root, "rendered-state-mismatch", "Rendered ordered range disagrees with its exact configuration or state"));
      return null;
    }
    return {
      root,
      startInput,
      endInput,
      availabilityInput,
      startOutput,
      endOutput,
      config,
      state,
      report
    };
  }
  function synchronizeOrderedRange(control) {
    const {
      root,
      startInput,
      endInput,
      availabilityInput,
      startOutput,
      endOutput,
      config,
      state
    } = control;
    startInput.value = String(state.startValue);
    endInput.value = String(state.endValue);
    availabilityInput.checked = state.available;
    startInput.disabled = !state.available;
    endInput.disabled = !state.available;
    startOutput.textContent = orderedRangeLabelForValue(config, state.startValue);
    endOutput.textContent = orderedRangeLabelForValue(config, state.endValue);
    root.style.setProperty(
      orderedRangeStartPositionProperty,
      `${orderedRangePositionPercent(config, state.startValue)}%`
    );
    root.style.setProperty(
      orderedRangeEndPositionProperty,
      `${orderedRangePositionPercent(config, state.endValue)}%`
    );
  }
  function updateEndpoint(control, endpoint, input) {
    const value = Number(input.value);
    try {
      control.state = orderedRangeStateForInput(control.config, control.state, endpoint, value);
      synchronizeOrderedRange(control);
    } catch (error) {
      control.report(diagnostic(
        control.root,
        "invalid-input-value",
        error instanceof Error ? error.message : String(error)
      ));
    }
  }
  function initializeOrderedRange(root, report) {
    const existing = initializedControls.get(root);
    if (existing !== void 0) return existing;
    const control = readOrderedRangeControl(root, report);
    if (control === null) return null;
    control.availabilityInput.addEventListener("change", () => {
      control.state = { ...control.state, available: control.availabilityInput.checked };
      synchronizeOrderedRange(control);
    });
    control.startInput.addEventListener("input", () => {
      updateEndpoint(control, "start", control.startInput);
    });
    control.endInput.addEventListener("input", () => {
      updateEndpoint(control, "end", control.endInput);
    });
    initializedControls.set(root, control);
    synchronizeOrderedRange(control);
    return control;
  }
  function orderedRangeRootsWithin(target) {
    const queryRoot = rootFromTarget(target);
    const roots = Array.from(queryRoot.querySelectorAll(`[${orderedRangeRootDomAttr}]`)).filter((element) => element instanceof HTMLElement);
    if (queryRoot instanceof HTMLElement && queryRoot.hasAttribute(orderedRangeRootDomAttr)) {
      roots.unshift(queryRoot);
    }
    return roots;
  }
  function initializeOrderedRanges(target, report = defaultDiagnosticReporter) {
    for (const root of orderedRangeRootsWithin(target)) {
      initializeOrderedRange(root, report);
    }
  }
  function enableOrderedRanges() {
    if (typeof window === "undefined") return;
    onAppPageReady((event) => {
      initializeOrderedRanges(detailTarget(event, "target"));
    });
    onHtmxLoad((event) => {
      initializeOrderedRanges(detailTarget(event, "elt"));
    });
    if (document.readyState !== "loading") {
      initializeOrderedRanges(document.body);
    }
  }
  enableOrderedRanges();
})();
