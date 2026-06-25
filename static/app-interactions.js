"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  var InteractionDom = {
    attributes: {
      surface: "data-bepis-surface",
      surfaceFamily: "data-bepis-surface-family",
      scopeKey: "data-bepis-scope-key",
      mountKey: "data-bepis-mount-key",
      marker: "data-bepis-marker",
      activation: "data-bepis-activation",
      activationIntent: "data-bepis-activation-intent",
      activationTrigger: "data-bepis-activation-trigger",
      activationValueField: "data-bepis-activation-value-field",
      pointerSession: "data-bepis-pointer-session",
      sessionKind: "data-bepis-session-kind",
      sessionIntent: "data-bepis-session-intent",
      sessionDisabled: "data-bepis-session-disabled",
      sessionReadOnly: "data-bepis-session-read-only",
      sessionThreshold: "data-bepis-session-threshold",
      sessionTimeoutMs: "data-bepis-session-timeout-ms",
      disposableLayer: "data-bepis-disposable-layer",
      intentForm: "data-bepis-intent-form",
      intent: "data-bepis-intent",
      intentField: "data-bepis-intent-field",
      fieldPresence: "data-bepis-field-presence",
      intentHiddenField: "data-bepis-intent-hidden-field"
    },
    values: {
      enabled: "true",
      activationMarker: "activation"
    }
  };

  // frontend/ts/interaction/form-bridge.ts
  var attrs = InteractionDom.attributes;
  var values = InteractionDom.values;
  function submitCommittedInteractionIntent(intent, logger = console) {
    if (intent.phase !== "commit") return { ok: false, reason: "intent phase is not commit" };
    const mount = resolveInteractionMount(intent);
    if (!mount) return fail(logger, `No interaction mount found for intent ${intent.intent}`);
    const form = findIntentForm(mount, intent.intent);
    if (!form) return fail(logger, `No interaction form found for intent ${intent.intent}`);
    const validation = validateIntentFields(form, intent.fields);
    if (!validation.ok) return fail(logger, validation.reason);
    const trigger = formTriggerName(form);
    if (!trigger) return fail(logger, `Intent form ${intent.intent} has no hx-trigger`);
    for (const field of validation.fields) {
      if (hasOwn(intent.fields, field.name)) {
        field.input.value = intent.fields[field.name] ?? "";
        field.input.setAttribute("value", field.input.value);
      }
    }
    form.dispatchEvent(new CustomEvent(trigger, { bubbles: true, cancelable: true, detail: { intent } }));
    return { ok: true, form, trigger };
  }
  function resolveInteractionMount(intent) {
    if (isElementLike(intent.mount) && isInteractionMount(intent.mount)) return intent.mount;
    if (isElementLike(intent.marker)) return closestInteractionMount(intent.marker);
    const sourceTarget = intent.sourceEvent?.target;
    if (isElementLike(sourceTarget)) return closestInteractionMount(sourceTarget);
    return null;
  }
  function isInteractionMount(element) {
    return element.getAttribute(attrs.surface) === values.enabled;
  }
  function closestInteractionMount(element) {
    const selector = attrEqualsSelector(attrs.surface, values.enabled);
    const closest = element.closest?.(selector) ?? null;
    return isElementLike(closest) ? closest : null;
  }
  function findIntentForm(mount, intentName) {
    for (const form of queryAll(mount, attrSelector(attrs.intentForm))) {
      if (form.getAttribute(attrs.intent) === intentName || form.getAttribute(attrs.intentForm) === intentName) {
        return form;
      }
    }
    return null;
  }
  function validateIntentFields(form, emittedFields) {
    const fields = readFieldContracts(form);
    const fieldsByName = new Map(fields.map((field) => [field.name, field]));
    for (const [name, value] of Object.entries(emittedFields)) {
      if (!fieldsByName.has(name)) return { ok: false, reason: `Unknown intent field ${name}` };
      if (typeof value !== "string") return { ok: false, reason: `Intent field ${name} is not a string` };
    }
    for (const field of fields) {
      if (field.presence === "required" && !hasOwn(emittedFields, field.name)) {
        return { ok: false, reason: `Missing required intent field ${field.name}` };
      }
    }
    return { ok: true, fields };
  }
  function readFieldContracts(form) {
    return queryAll(form, attrSelector(attrs.intentField)).flatMap((element) => {
      if (!isFieldInput(element)) return [];
      const name = element.getAttribute(attrs.intentField);
      const presence = element.getAttribute(attrs.fieldPresence);
      if (!name || !isInteractionFieldPresence(presence)) return [];
      return [{ name, presence, input: element }];
    });
  }
  function isInteractionFieldPresence(value) {
    return value === "required" || value === "optional";
  }
  function isFieldInput(element) {
    return "value" in element && typeof element.value === "string";
  }
  function formTriggerName(form) {
    const trigger = form.getAttribute("hx-trigger")?.trim();
    if (!trigger) return null;
    return trigger.split(/[\s,]+/, 1)[0] || null;
  }
  function queryAll(root, selector) {
    return Array.from(root.querySelectorAll(selector)).filter(isElementLike);
  }
  function isElementLike(value) {
    if (value === null || typeof value !== "object") return false;
    const maybe = value;
    return typeof maybe.getAttribute === "function" && typeof maybe.setAttribute === "function" && typeof maybe.querySelectorAll === "function" && typeof maybe.dispatchEvent === "function";
  }
  function attrSelector(attribute) {
    return `[${attribute}]`;
  }
  function attrEqualsSelector(attribute, value) {
    return `[${attribute}="${value}"]`;
  }
  function hasOwn(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
  }
  function fail(logger, reason) {
    logger.warn(`[bepis interaction] ${reason}`);
    return { ok: false, reason };
  }

  // frontend/ts/interaction/intent-bus.ts
  var interactionIntentEventName = "bepis:interaction-intent";
  function normalizeFields(fields) {
    if (!fields) return {};
    const normalized = {};
    for (const [name, value] of Object.entries(fields)) {
      normalized[name] = value;
    }
    return normalized;
  }
  function normalizeInteractionIntent(payload) {
    return {
      phase: payload.phase,
      intent: payload.intent,
      fields: normalizeFields(payload.fields),
      mount: payload.mount ?? null,
      marker: payload.marker ?? null,
      sourceEvent: payload.sourceEvent ?? null
    };
  }
  var InteractionIntentBus = class {
    constructor(target = new EventTarget()) {
      this.target = target;
    }
    observe(listener) {
      this.target.addEventListener(interactionIntentEventName, listener);
      return () => this.target.removeEventListener(interactionIntentEventName, listener);
    }
    emit(payload) {
      const intent = normalizeInteractionIntent(payload);
      const event = new CustomEvent(interactionIntentEventName, {
        bubbles: false,
        cancelable: true,
        detail: intent
      });
      const accepted = this.target.dispatchEvent(event);
      return { intent, event, canceled: !accepted || event.defaultPrevented };
    }
  };

  // frontend/ts/interaction/runtime.ts
  function createInteractionRuntime(options = {}) {
    const bus = options.bus ?? new InteractionIntentBus();
    const logger = options.logger ?? console;
    return {
      bus,
      emit(payload) {
        const emitted = bus.emit(payload);
        if (emitted.canceled || emitted.intent.phase !== "commit") return { canceled: emitted.canceled };
        const submitted = submitCommittedInteractionIntent(emitted.intent, logger);
        return { canceled: !submitted.ok, submitted };
      },
      stop() {
      }
    };
  }
  var defaultInteractionRuntime = createInteractionRuntime();

  // frontend/ts/interaction/activation.ts
  var attrs2 = InteractionDom.attributes;
  var values2 = InteractionDom.values;
  var activationSelector = `[${attrs2.marker}="${values2.activationMarker}"]`;
  function enableGenericInteractionActivations(options = {}) {
    if (typeof document === "undefined") return () => void 0;
    const root = options.root ?? document;
    const runtime = options.runtime ?? defaultInteractionRuntime;
    const clickHandler = (event) => handleActivationEvent(event, "click", runtime);
    const changeHandler = (event) => handleActivationEvent(event, "change", runtime);
    const keydownHandler = (event) => handleKeyboardActivationEvent(event, runtime);
    root.addEventListener("click", clickHandler);
    root.addEventListener("change", changeHandler);
    root.addEventListener("keydown", keydownHandler);
    return () => {
      root.removeEventListener("click", clickHandler);
      root.removeEventListener("change", changeHandler);
      root.removeEventListener("keydown", keydownHandler);
    };
  }
  function readActivationIntentPayload(event, expectedTrigger) {
    const marker = closestActivationMarker(event.target);
    if (!marker) return null;
    const trigger = marker.getAttribute(attrs2.activationTrigger);
    if (!trigger || expectedTrigger && trigger !== expectedTrigger) return null;
    const intent = marker.getAttribute(attrs2.activationIntent);
    if (!intent) return null;
    const fields = readActivationFields(marker, event);
    if (fields === null) return null;
    return {
      phase: "commit",
      intent,
      fields,
      marker,
      sourceEvent: event
    };
  }
  function handleActivationEvent(event, expectedTrigger, runtime) {
    const payload = readActivationIntentPayload(event, expectedTrigger);
    if (!payload) return;
    const result = runtime.emit(payload);
    if (result.canceled && event.cancelable) event.preventDefault();
  }
  function handleKeyboardActivationEvent(event, runtime) {
    if (!isKeyboardEvent(event)) return;
    const trigger = keyboardTriggerForEvent(event);
    if (!trigger) return;
    handleActivationEvent(event, trigger, runtime);
  }
  function keyboardTriggerForEvent(event) {
    if (event.key === "Enter") return "keydown-enter";
    if (event.key === " " || event.key === "Spacebar") return "keydown-space";
    return null;
  }
  function closestActivationMarker(target) {
    if (!isElementLike2(target)) return null;
    const marker = target.closest(activationSelector);
    return isElementLike2(marker) ? marker : null;
  }
  function readActivationFields(marker, event) {
    const valueField = marker.getAttribute(attrs2.activationValueField);
    if (!valueField) return {};
    const valueElement = valueSourceElement(marker, event);
    if (!valueElement) return null;
    return { [valueField]: valueElement.value };
  }
  function valueSourceElement(marker, event) {
    if (isValueElement(event.target)) return event.target;
    if (isValueElement(marker)) return marker;
    const nested = marker.querySelector("input,select,textarea");
    return isValueElement(nested) ? nested : null;
  }
  function isKeyboardEvent(event) {
    return typeof KeyboardEvent !== "undefined" && event instanceof KeyboardEvent;
  }
  function isValueElement(value) {
    return isElementLike2(value) && typeof value.value === "string";
  }
  function isElementLike2(value) {
    if (value === null || typeof value !== "object") return false;
    const maybe = value;
    return typeof maybe.getAttribute === "function" && typeof maybe.closest === "function" && typeof maybe.querySelector === "function";
  }

  // frontend/ts/interaction/pointer-session.ts
  var attrs3 = InteractionDom.attributes;
  var values3 = InteractionDom.values;
  var sessionSelector = `[${attrs3.pointerSession}="${values3.enabled}"]`;
  var disposableLayerSelector = `[${attrs3.disposableLayer}]`;
  var defaultThresholdPx = 4;
  function enableGenericPointerSessions(options = {}) {
    if (typeof document === "undefined") return () => void 0;
    const controller = createPointerSessionController(options);
    const root = options.root ?? document;
    root.addEventListener("pointerdown", controller.handlePointerDown);
    root.addEventListener("pointermove", controller.handlePointerMove);
    root.addEventListener("pointerup", controller.handlePointerUp);
    root.addEventListener("pointercancel", controller.handlePointerCancel);
    root.addEventListener("keydown", controller.handleKeyDown);
    root.addEventListener("htmx:beforeSwap", controller.handleExternalCleanup);
    root.addEventListener("htmx:beforeCleanupElement", controller.handleExternalCleanup);
    return () => {
      root.removeEventListener("pointerdown", controller.handlePointerDown);
      root.removeEventListener("pointermove", controller.handlePointerMove);
      root.removeEventListener("pointerup", controller.handlePointerUp);
      root.removeEventListener("pointercancel", controller.handlePointerCancel);
      root.removeEventListener("keydown", controller.handleKeyDown);
      root.removeEventListener("htmx:beforeSwap", controller.handleExternalCleanup);
      root.removeEventListener("htmx:beforeCleanupElement", controller.handleExternalCleanup);
      controller.stop();
    };
  }
  function createPointerSessionController(options = {}) {
    const runtime = options.runtime ?? defaultInteractionRuntime;
    const fallbackThresholdPx = options.thresholdPx ?? defaultThresholdPx;
    let activeSession = null;
    let timeoutHandle = null;
    const clearTimeoutHandle = () => {
      if (timeoutHandle !== null) clearTimeout(timeoutHandle);
      timeoutHandle = null;
    };
    const scheduleTimeout = (session) => {
      clearTimeoutHandle();
      const timeoutMs = numberAttribute(session.marker, attrs3.sessionTimeoutMs);
      if (timeoutMs === null || timeoutMs <= 0) return;
      timeoutHandle = setTimeout(() => {
        if (activeSession === session) cancelSession(session, null);
      }, timeoutMs);
    };
    const cleanupSession = (session) => {
      clearTimeoutHandle();
      clearDisposableLayers(session.mount);
      releasePointerCapture(session.marker, session.pointerId);
      if (activeSession === session) activeSession = null;
    };
    const cancelSession = (session, sourceEvent) => {
      runtime.emit({
        phase: "cancel",
        intent: session.intent,
        fields: pointerSessionFields(session),
        mount: session.mount,
        marker: session.marker,
        sourceEvent
      });
      cleanupSession(session);
    };
    const finishSession = (session, sourceEvent) => {
      const result = runtime.emit({
        phase: "commit",
        intent: session.intent,
        fields: pointerSessionFields(session),
        mount: session.mount,
        marker: session.marker,
        sourceEvent
      });
      if (result.canceled && sourceEvent.cancelable) sourceEvent.preventDefault();
      cleanupSession(session);
    };
    const updateSession = (session, event) => {
      session.currentClientX = numberValue(event.clientX);
      session.currentClientY = numberValue(event.clientY);
      if (!session.activated && movementDistance(session) < session.thresholdPx) return;
      session.activated = true;
      runtime.emit({
        phase: "preview",
        intent: session.intent,
        fields: pointerSessionFields(session),
        mount: session.mount,
        marker: session.marker,
        sourceEvent: event
      });
    };
    return {
      handlePointerDown(event) {
        const start = readPointerSessionStart(event, fallbackThresholdPx);
        if (!start) return;
        if (activeSession) cancelSession(activeSession, event);
        clearDisposableLayers(start.mount);
        activeSession = start;
        capturePointer(start.marker, start.pointerId);
        const result = runtime.emit({
          phase: "start",
          intent: start.intent,
          fields: pointerSessionFields(start),
          mount: start.mount,
          marker: start.marker,
          sourceEvent: event
        });
        if (result.canceled) {
          if (event.cancelable) event.preventDefault();
          cleanupSession(start);
          return;
        }
        scheduleTimeout(start);
      },
      handlePointerMove(event) {
        if (!activeSession || !isMatchingPointerEvent(event, activeSession)) return;
        updateSession(activeSession, event);
      },
      handlePointerUp(event) {
        if (!activeSession || !isMatchingPointerEvent(event, activeSession)) return;
        updateSession(activeSession, event);
        if (activeSession.activated) finishSession(activeSession, event);
        else cancelSession(activeSession, event);
      },
      handlePointerCancel(event) {
        if (!activeSession || !isMatchingPointerEvent(event, activeSession)) return;
        cancelSession(activeSession, event);
      },
      handleKeyDown(event) {
        if (!activeSession || !isEscapeKeyboardEvent(event)) return;
        if (event.cancelable) event.preventDefault();
        cancelSession(activeSession, event);
      },
      handleExternalCleanup(event) {
        if (!activeSession) return;
        cancelSession(activeSession, event);
      },
      currentSession() {
        return activeSession;
      },
      stop() {
        if (activeSession) cancelSession(activeSession, null);
        clearTimeoutHandle();
      }
    };
  }
  function readPointerSessionStart(event, fallbackThresholdPx = defaultThresholdPx) {
    const pointerEvent = event;
    const marker = closestPointerSessionMarker(event.target);
    if (!marker) return null;
    if (isDisabled(marker)) return null;
    const mount = closestInteractionMount2(marker);
    if (!mount) return null;
    const intent = marker.getAttribute(attrs3.sessionIntent);
    const sessionKind = marker.getAttribute(attrs3.sessionKind);
    if (!intent || !sessionKind) return null;
    const startClientX = numberValue(pointerEvent.clientX);
    const startClientY = numberValue(pointerEvent.clientY);
    const thresholdPx = numberAttribute(marker, attrs3.sessionThreshold) ?? fallbackThresholdPx;
    return {
      mount,
      marker,
      intent,
      sessionKind,
      pointerId: numberValue(pointerEvent.pointerId),
      pointerType: pointerEvent.pointerType ?? "unknown",
      startClientX,
      startClientY,
      currentClientX: startClientX,
      currentClientY: startClientY,
      thresholdPx: Math.max(0, thresholdPx),
      activated: thresholdPx <= 0
    };
  }
  function pointerSessionFields(session) {
    const deltaX = session.currentClientX - session.startClientX;
    const deltaY = session.currentClientY - session.startClientY;
    return {
      sessionKind: session.sessionKind,
      pointerId: String(session.pointerId),
      pointerType: session.pointerType,
      startClientX: String(session.startClientX),
      startClientY: String(session.startClientY),
      currentClientX: String(session.currentClientX),
      currentClientY: String(session.currentClientY),
      deltaX: String(deltaX),
      deltaY: String(deltaY)
    };
  }
  function movementDistance(session) {
    const deltaX = session.currentClientX - session.startClientX;
    const deltaY = session.currentClientY - session.startClientY;
    return Math.hypot(deltaX, deltaY);
  }
  function closestPointerSessionMarker(target) {
    if (!isElementLike3(target)) return null;
    const marker = target.closest(sessionSelector);
    return isElementLike3(marker) ? marker : null;
  }
  function closestInteractionMount2(marker) {
    const mount = marker.closest(`[${attrs3.surface}="${values3.enabled}"]`);
    return isElementLike3(mount) ? mount : null;
  }
  function clearDisposableLayers(mount) {
    for (const layer of mount.querySelectorAll(disposableLayerSelector)) clearElement(layer);
  }
  function clearElement(element) {
    const mutable = element;
    if (typeof mutable.replaceChildren === "function") {
      mutable.replaceChildren();
      return;
    }
    if (typeof mutable.innerHTML === "string") mutable.innerHTML = "";
  }
  function isDisabled(marker) {
    return marker.getAttribute(attrs3.sessionDisabled) === values3.enabled || marker.getAttribute(attrs3.sessionReadOnly) === values3.enabled;
  }
  function isMatchingPointerEvent(event, session) {
    return numberValue(event.pointerId) === session.pointerId;
  }
  function isEscapeKeyboardEvent(event) {
    return event.type === "keydown" && event.key === "Escape";
  }
  function capturePointer(marker, pointerId) {
    try {
      marker.setPointerCapture?.(pointerId);
    } catch {
    }
  }
  function releasePointerCapture(marker, pointerId) {
    try {
      marker.releasePointerCapture?.(pointerId);
    } catch {
    }
  }
  function numberAttribute(element, attribute) {
    const value = element.getAttribute(attribute);
    if (value === null || value.trim() === "") return null;
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  function numberValue(value) {
    return typeof value === "number" && Number.isFinite(value) ? value : 0;
  }
  function isElementLike3(value) {
    if (value === null || typeof value !== "object") return false;
    const maybe = value;
    return typeof maybe.getAttribute === "function" && typeof maybe.closest === "function" && typeof maybe.querySelectorAll === "function";
  }

  // frontend/ts/app-interactions.ts
  enableGenericInteractionActivations();
  enableGenericPointerSessions();
})();
