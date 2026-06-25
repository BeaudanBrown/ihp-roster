"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  var InteractionDom = {
    attributes: {
      surface: "data-bepis-surface",
      surfaceFamily: "data-bepis-surface-family",
      scopeKey: "data-bepis-scope-key",
      mountKey: "data-bepis-mount-key",
      intentForm: "data-bepis-intent-form",
      intent: "data-bepis-intent",
      intentField: "data-bepis-intent-field",
      fieldPresence: "data-bepis-field-presence",
      intentHiddenField: "data-bepis-intent-hidden-field"
    },
    values: {
      enabled: "true"
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
})();
