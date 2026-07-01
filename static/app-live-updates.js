"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  var AppEvents = { "interactionIntent": "bepis:interaction-intent", "interactionIntentSubmit": "bepis:intent-submit", "interactionSessionCancelRequest": "bepis:interaction-session-cancel-request", "interactionSessionEnd": "bepis:interaction-session-end", "interactionSessionStart": "bepis:interaction-session-start", "liveFragmentsRefresh": "app-live-fragments-refresh", "pageReady": "app:page-ready" };
  function __isLiveUpdateScopeExactRecord(value, requiredKeys, optionalKeys) {
    if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
    const actualKeys = Object.keys(value);
    const allowedKeys = /* @__PURE__ */ new Set([...requiredKeys, ...optionalKeys]);
    return requiredKeys.every((key) => Object.prototype.hasOwnProperty.call(value, key)) && actualKeys.every((key) => allowedKeys.has(key));
  }
  function isLiveUpdateScope(value) {
    return __isLiveUpdateScopeExactRecord(value, ["kind", "venueId", "rosterGroupId", "weekOffset"], []) && value["kind"] === "roster_week" && typeof value["venueId"] === "string" && typeof value["rosterGroupId"] === "string" && (typeof value["weekOffset"] === "number" && Number.isInteger(value["weekOffset"])) || __isLiveUpdateScopeExactRecord(value, ["kind", "venueId"], []) && value["kind"] === "admin_venue_config" && typeof value["venueId"] === "string" || __isLiveUpdateScopeExactRecord(value, ["kind", "venueId"], []) && value["kind"] === "admin_shift_types" && typeof value["venueId"] === "string" || __isLiveUpdateScopeExactRecord(value, ["kind", "venueId"], []) && value["kind"] === "admin_roster_groups" && typeof value["venueId"] === "string" || __isLiveUpdateScopeExactRecord(value, ["kind", "venueId"], []) && value["kind"] === "admin_invites" && typeof value["venueId"] === "string" || __isLiveUpdateScopeExactRecord(value, ["kind", "venueId"], []) && value["kind"] === "admin_exports" && typeof value["venueId"] === "string" || __isLiveUpdateScopeExactRecord(value, ["kind", "venueId"], []) && value["kind"] === "admin_xero" && typeof value["venueId"] === "string" || __isLiveUpdateScopeExactRecord(value, ["kind", "venueId"], []) && value["kind"] === "billing" && typeof value["venueId"] === "string" || __isLiveUpdateScopeExactRecord(value, ["kind", "venueId"], []) && value["kind"] === "leave_requests" && typeof value["venueId"] === "string" || __isLiveUpdateScopeExactRecord(value, ["kind", "venueId", "weekOffset"], []) && value["kind"] === "timesheet_week" && typeof value["venueId"] === "string" && (typeof value["weekOffset"] === "number" && Number.isInteger(value["weekOffset"])) || __isLiveUpdateScopeExactRecord(value, ["kind", "venueId", "staffId"], []) && value["kind"] === "profile" && typeof value["venueId"] === "string" && typeof value["staffId"] === "string" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "support_platform";
  }
  function isLiveFragmentKey(value) {
    return __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "roster_content" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "roster_grid_toolbar" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "roster_grid_frame" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "roster_day_columns" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "roster_day_rail" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "roster_wage_rail" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "roster_slots_grid" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "roster_staff_panel" || __isLiveUpdateScopeExactRecord(value, ["kind", "rosterDayId"], []) && value["kind"] === "roster_day_section" && typeof value["rosterDayId"] === "string" || __isLiveUpdateScopeExactRecord(value, ["kind", "rosterDayId", "rowIndex"], []) && value["kind"] === "roster_row" && typeof value["rosterDayId"] === "string" && (typeof value["rowIndex"] === "number" && Number.isInteger(value["rowIndex"])) || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "leave_requests_content" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "timesheet_toolbar" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "timesheet_day_columns" || __isLiveUpdateScopeExactRecord(value, ["kind", "dayOffset"], []) && value["kind"] === "timesheet_day_section" && (typeof value["dayOffset"] === "number" && Number.isInteger(value["dayOffset"])) || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "admin_venue_config" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "admin_invites" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "admin_exports" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "admin_shift_types" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "admin_roster_groups" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "admin_xero" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "admin_xero_staff_mappings" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "admin_xero_pay_items" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "admin_xero_timesheets" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "billing_status" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "profile_content" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "profile_leave_requests_content" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "support_award_rates_section" || __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "support_public_holidays_section";
  }
  function isLiveFragmentProtection(value) {
    return __isLiveUpdateScopeExactRecord(value, ["kind"], []) && value["kind"] === "none" || __isLiveUpdateScopeExactRecord(value, ["kind", "activeSelector", "fieldKeyAttr", "fieldNameFallback", "containerSelector"], []) && value["kind"] === "focused_field" && typeof value["activeSelector"] === "string" && typeof value["fieldKeyAttr"] === "string" && typeof value["fieldNameFallback"] === "boolean" && (value["containerSelector"] === null || typeof value["containerSelector"] === "string");
  }
  function isLiveUpdateWireFragment(value) {
    return __isLiveUpdateScopeExactRecord(value, ["fragmentKey", "targetId", "url", "deferUntilBlur", "protectionPolicy"], []) && isLiveFragmentKey(value["fragmentKey"]) && typeof value["targetId"] === "string" && typeof value["url"] === "string" && typeof value["deferUntilBlur"] === "boolean" && isLiveFragmentProtection(value["protectionPolicy"]);
  }
  function isLiveSurfaceConfig(value) {
    return __isLiveUpdateScopeExactRecord(value, ["feature", "socketPath", "scope", "scopeKey", "resyncFragments", "decorateRequestsWithin"], []) && typeof value["feature"] === "string" && typeof value["socketPath"] === "string" && isLiveUpdateScope(value["scope"]) && typeof value["scopeKey"] === "string" && (Array.isArray(value["resyncFragments"]) && value["resyncFragments"].every((item) => isLiveUpdateWireFragment(item))) && (Array.isArray(value["decorateRequestsWithin"]) && value["decorateRequestsWithin"].every((item) => typeof item === "string"));
  }
  function parseLiveSurfaceConfig(value) {
    if (isLiveSurfaceConfig(value)) return value;
    throw new Error("Invalid LiveSurfaceConfig");
  }
  function encodeLiveUpdateCommand(value) {
    return value;
  }
  function isLiveUpdateMessage(value) {
    return __isLiveUpdateScopeExactRecord(value, ["type", "scope", "scopeKey", "currentVersion", "resync"], []) && value["type"] === "subscribed" && isLiveUpdateScope(value["scope"]) && typeof value["scopeKey"] === "string" && (typeof value["currentVersion"] === "number" && Number.isInteger(value["currentVersion"])) && typeof value["resync"] === "boolean" || __isLiveUpdateScopeExactRecord(value, ["type", "scope", "scopeKey", "version", "fragments", "sourceClientId"], []) && value["type"] === "invalidate" && isLiveUpdateScope(value["scope"]) && typeof value["scopeKey"] === "string" && (typeof value["version"] === "number" && Number.isInteger(value["version"])) && (Array.isArray(value["fragments"]) && value["fragments"].every((item) => isLiveUpdateWireFragment(item))) && (value["sourceClientId"] === null || typeof value["sourceClientId"] === "string") || __isLiveUpdateScopeExactRecord(value, ["type", "message"], []) && value["type"] === "error" && typeof value["message"] === "string";
  }
  function parseLiveUpdateMessage(value) {
    if (isLiveUpdateMessage(value)) return value;
    throw new Error("Invalid LiveUpdateMessage");
  }
  function isInteractionConflictResolution(value) {
    return value === "apply" || value === "defer" || value === "cancel";
  }
  var InteractionDom = { "attributes": { "activation": "data-bepis-activation", "activationIntent": "data-bepis-activation-intent", "activationTrigger": "data-bepis-activation-trigger", "activationValueField": "data-bepis-activation-value-field", "conflictPolicies": "data-bepis-conflict-policies", "container": "data-bepis-container", "disposableLayer": "data-bepis-disposable-layer", "dropzone": "data-bepis-dropzone", "fieldPresence": "data-bepis-field-presence", "intent": "data-bepis-intent", "intentField": "data-bepis-intent-field", "intentForm": "data-bepis-intent-form", "intentHiddenField": "data-bepis-intent-hidden-field", "interactionActive": "data-bepis-interaction-active", "item": "data-bepis-item", "layer": "data-bepis-layer", "marker": "data-bepis-marker", "mountKey": "data-bepis-mount-key", "pointerSession": "data-bepis-pointer-session", "resizeHandle": "data-bepis-resize-handle", "scopeKey": "data-bepis-scope-key", "serverLayer": "data-bepis-server-layer", "sessionDisabled": "data-bepis-session-disabled", "sessionIntent": "data-bepis-session-intent", "sessionKind": "data-bepis-session-kind", "sessionReadOnly": "data-bepis-session-read-only", "sessionThreshold": "data-bepis-session-threshold", "sessionTimeoutMs": "data-bepis-session-timeout-ms", "slot": "data-bepis-slot", "surface": "data-bepis-surface", "surfaceFamily": "data-bepis-surface-family" }, "pointerFields": { "currentClientX": "currentClientX", "currentClientY": "currentClientY", "deltaX": "deltaX", "deltaY": "deltaY", "pointerId": "pointerId", "pointerType": "pointerType", "sessionKind": "sessionKind", "sourceItemKey": "sourceItemKey", "startClientX": "startClientX", "startClientY": "startClientY", "targetDropzoneKey": "targetDropzoneKey" }, "values": { "activationMarker": "activation", "containerMarker": "container", "dropzoneMarker": "dropzone", "enabled": "true", "itemMarker": "item", "resizeHandleMarker": "resize-handle", "slotMarker": "slot" } };
  function isUiRegionTransitionProfile(value) {
    return value === "none" || value === "fade" || value === "fade-slide" || value === "panel";
  }
  function isUiRegionLifecycleEvent(value) {
    return value === "bepis:region-request-start" || value === "bepis:region-before-swap" || value === "bepis:region-after-swap" || value === "bepis:region-settle" || value === "bepis:region-error";
  }
  var UiRegionDom = { "fragment": "data-bepis-fragment", "lazyFragment": "data-bepis-lazy-fragment", "lazyRetry": "data-bepis-lazy-retry", "lazySurface": "data-bepis-lazy-surface", "transition": "data-bepis-region-transition" };
  var UiRegionEvents = { "afterSwap": "bepis:region-after-swap", "beforeSwap": "bepis:region-before-swap", "error": "bepis:region-error", "requestStart": "bepis:region-request-start", "settle": "bepis:region-settle" };

  // frontend/ts/shared/dom.ts
  function isElement(value) {
    return typeof Element !== "undefined" && value instanceof Element;
  }
  function isHTMLElement(value) {
    return typeof HTMLElement !== "undefined" && value instanceof HTMLElement;
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

  // frontend/ts/fragments/dom.ts
  var uiRegionFragmentSelector = `[${UiRegionDom.fragment}="true"]`;
  function closestUiRegionFragment(value) {
    if (isHTMLElement(value)) {
      if (value.matches(uiRegionFragmentSelector)) return value;
      return closestHTMLElement(value, uiRegionFragmentSelector);
    }
    return closestHTMLElement(value, uiRegionFragmentSelector);
  }

  // frontend/ts/fragments/events.ts
  function uiRegionEventName(lifecycleEvent) {
    return lifecycleEvent;
  }
  function emitUiRegionLifecycleEvent(region, detail) {
    region.dispatchEvent(new CustomEvent(uiRegionEventName(detail.lifecycleEvent), {
      bubbles: true,
      detail
    }));
  }

  // frontend/ts/fragments/htmx-adapter.ts
  function regionLifecycleEvent(value) {
    if (isUiRegionLifecycleEvent(value)) return value;
    throw new Error(`Invalid generated UI region lifecycle event: ${value}`);
  }
  var htmxRegionEventSpecs = [
    { htmxEventName: "htmx:beforeRequest", lifecycleEvent: regionLifecycleEvent(UiRegionEvents.requestStart) },
    { htmxEventName: "htmx:beforeSwap", lifecycleEvent: regionLifecycleEvent(UiRegionEvents.beforeSwap) },
    { htmxEventName: "htmx:afterSwap", lifecycleEvent: regionLifecycleEvent(UiRegionEvents.afterSwap) },
    { htmxEventName: "htmx:afterSettle", lifecycleEvent: regionLifecycleEvent(UiRegionEvents.settle) },
    { htmxEventName: "htmx:responseError", lifecycleEvent: regionLifecycleEvent(UiRegionEvents.error), errorKind: "response-error" },
    { htmxEventName: "htmx:sendError", lifecycleEvent: regionLifecycleEvent(UiRegionEvents.error), errorKind: "send-error" },
    { htmxEventName: "htmx:timeout", lifecycleEvent: regionLifecycleEvent(UiRegionEvents.error), errorKind: "timeout" }
  ];
  function htmxRegionEventSource(event) {
    const source = detailTarget(event, "elt");
    return isHTMLElement(source) ? source : null;
  }
  function htmxRegionEventTarget(event) {
    const target = detailTarget(event, "target");
    return isHTMLElement(target) ? target : null;
  }
  function regionFromHtmxEvent(event) {
    return closestUiRegionFragment(htmxRegionEventTarget(event)) || closestUiRegionFragment(htmxRegionEventSource(event)) || closestUiRegionFragment(event.target);
  }
  function dispatchRegionLifecycleFromHtmx(event, spec) {
    const region = regionFromHtmxEvent(event);
    if (region === null) return;
    emitUiRegionLifecycleEvent(region, {
      lifecycleEvent: spec.lifecycleEvent,
      htmxEventName: spec.htmxEventName,
      region,
      source: htmxRegionEventSource(event),
      target: htmxRegionEventTarget(event),
      originalEvent: event,
      ...spec.errorKind ? { errorKind: spec.errorKind } : {}
    });
  }
  function enableHtmxUiRegionEventAdapter(root = document) {
    const listeners = htmxRegionEventSpecs.map((spec) => {
      const listener = (event) => dispatchRegionLifecycleFromHtmx(event, spec);
      root.addEventListener(spec.htmxEventName, listener);
      return { spec, listener };
    });
    return function disableHtmxUiRegionEventAdapter() {
      listeners.forEach(({ spec, listener }) => root.removeEventListener(spec.htmxEventName, listener));
    };
  }

  // frontend/ts/fragments/transitions.ts
  var transitionProfiles = ["fade", "fade-slide", "panel"];
  var transitionPhaseClasses = ["app-region-transition-before-swap", "app-region-transition-after-swap"];
  var transitionProfileClasses = transitionProfiles.map((profile) => regionTransitionProfileClass(profile));
  function regionTransitionProfile(region) {
    const rawProfile = region.getAttribute(UiRegionDom.transition);
    return isUiRegionTransitionProfile(rawProfile) ? rawProfile : "none";
  }
  function regionTransitionProfileClass(profile) {
    return `app-region-transition-${profile}`;
  }
  function prefersReducedMotion() {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") return false;
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }
  function shouldAnimateRegionTransition(profile, reducedMotion = prefersReducedMotion()) {
    return profile !== "none" && !reducedMotion;
  }
  function clearRegionTransitionClasses(region) {
    region.classList.remove("app-region-transition", ...transitionProfileClasses, ...transitionPhaseClasses);
  }
  function applyRegionTransitionPhase(region, phase, reducedMotion = prefersReducedMotion()) {
    const profile = regionTransitionProfile(region);
    clearRegionTransitionClasses(region);
    if (!shouldAnimateRegionTransition(profile, reducedMotion)) return false;
    region.classList.add(
      "app-region-transition",
      regionTransitionProfileClass(profile),
      `app-region-transition-${phase}`
    );
    return true;
  }
  function lifecycleDetail(event) {
    if (typeof CustomEvent === "undefined" || !(event instanceof CustomEvent)) return null;
    const detail = event.detail;
    if (detail === null || typeof detail !== "object") return null;
    const record = detail;
    return record.region instanceof HTMLElement ? record : null;
  }
  function enableUiRegionTransitions(root = document) {
    const onBeforeSwap = (event) => {
      const detail = lifecycleDetail(event);
      if (detail === null) return;
      applyRegionTransitionPhase(detail.region, "before-swap");
    };
    const onAfterSwap = (event) => {
      const detail = lifecycleDetail(event);
      if (detail === null) return;
      applyRegionTransitionPhase(detail.region, "after-swap");
    };
    const onDone = (event) => {
      const detail = lifecycleDetail(event);
      if (detail === null) return;
      clearRegionTransitionClasses(detail.region);
    };
    root.addEventListener(UiRegionEvents.beforeSwap, onBeforeSwap);
    root.addEventListener(UiRegionEvents.afterSwap, onAfterSwap);
    root.addEventListener(UiRegionEvents.settle, onDone);
    root.addEventListener(UiRegionEvents.error, onDone);
    return function disableUiRegionTransitions() {
      root.removeEventListener(UiRegionEvents.beforeSwap, onBeforeSwap);
      root.removeEventListener(UiRegionEvents.afterSwap, onAfterSwap);
      root.removeEventListener(UiRegionEvents.settle, onDone);
      root.removeEventListener(UiRegionEvents.error, onDone);
    };
  }

  // frontend/ts/interaction/live-conflicts.ts
  var attrs = InteractionDom.attributes;
  var defaultInteractionDeferFallbackTimeoutMs = 5e3;
  function resolveLiveFragmentInteractionConflict(fragment, target, tracker) {
    const session = tracker.findForTarget(target);
    if (!session) return null;
    const policy = matchingConflictPolicy(session, fragment, target);
    const action = policy?.resolution ?? "defer";
    const timeoutMs = policy?.timeoutMs ?? (action === "defer" ? defaultInteractionDeferFallbackTimeoutMs : null);
    return { action, session, timeoutMs };
  }
  function readInteractionConflictPolicies(mount) {
    const raw = mount.getAttribute(attrs.conflictPolicies);
    if (!raw) return [];
    try {
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];
      return parsed.filter(isWireConflictPolicy);
    } catch (_error) {
      return [];
    }
  }
  function matchingConflictPolicy(session, fragment, target) {
    const mount = target.closest(`[${attrs.surface}="true"]`);
    if (!mount) return null;
    const policies = readInteractionConflictPolicies(mount);
    return policies.find((policy) => {
      const sessionMatches = policy.session === "*" || policy.session === session.sessionKind;
      const targetMatches = policy.targetId === "*" || policy.targetId === fragment.targetId;
      return sessionMatches && targetMatches;
    }) ?? null;
  }
  function isWireConflictPolicy(value) {
    if (value === null || typeof value !== "object") return false;
    const maybe = value;
    return isOptionalString(maybe.session) && isOptionalString(maybe.targetId) && isOptionalResolution(maybe.resolution) && (maybe.timeoutMs === void 0 || maybe.timeoutMs === null || typeof maybe.timeoutMs === "number");
  }
  function isOptionalString(value) {
    return value === void 0 || typeof value === "string";
  }
  function isOptionalResolution(value) {
    return value === void 0 || isInteractionConflictResolution(value);
  }

  // frontend/ts/interaction/session-state.ts
  var interactionSessionStartEventName = AppEvents.interactionSessionStart;
  var interactionSessionEndEventName = AppEvents.interactionSessionEnd;
  var interactionSessionCancelRequestEventName = AppEvents.interactionSessionCancelRequest;
  var attrs2 = InteractionDom.attributes;
  function requestInteractionSessionCancel(detail, root) {
    const eventRoot = root ?? defaultDocument();
    if (!eventRoot) return;
    eventRoot.dispatchEvent(new CustomEvent(interactionSessionCancelRequestEventName, { detail }));
  }
  function createActiveInteractionSessionTracker(root) {
    const sessionsByMountId = /* @__PURE__ */ new Map();
    const handleStart = (event) => {
      const detail = customDetail(event);
      if (!detail || !detail.mountId || !detail.mount || !detail.sessionKind || !detail.intent) return;
      sessionsByMountId.set(detail.mountId, {
        mount: detail.mount,
        mountId: detail.mountId,
        sessionKind: detail.sessionKind,
        intent: detail.intent
      });
    };
    const handleEnd = (event) => {
      const detail = customDetail(event);
      if (!detail || !detail.mountId) return;
      sessionsByMountId.delete(detail.mountId);
    };
    root.addEventListener(interactionSessionStartEventName, handleStart);
    root.addEventListener(interactionSessionEndEventName, handleEnd);
    return {
      findForTarget(target) {
        const mount = target.closest(`[${attrs2.surface}="true"]`);
        if (!isElementLike(mount)) return null;
        return sessionsByMountId.get(mount.id) ?? null;
      },
      hasActiveSession() {
        return sessionsByMountId.size > 0;
      },
      requestCancel(session, reason) {
        requestInteractionSessionCancel({ ...session, reason });
      },
      stop() {
        root.removeEventListener(interactionSessionStartEventName, handleStart);
        root.removeEventListener(interactionSessionEndEventName, handleEnd);
        sessionsByMountId.clear();
      }
    };
  }
  function customDetail(event) {
    return event instanceof CustomEvent ? event.detail : null;
  }
  function defaultDocument() {
    return typeof document === "undefined" ? null : document;
  }
  function isElementLike(value) {
    return value !== null && typeof value === "object" && typeof value.id === "string";
  }

  // frontend/ts/live-updates/lazy-surface.ts
  var lazySurfaceSelector = `[${UiRegionDom.lazySurface}="true"]`;
  var lazySurfaceRetrySelector = `[${UiRegionDom.lazySurface}="true"][${UiRegionDom.lazyRetry}="true"]`;
  function customEventDetail(event) {
    if (typeof CustomEvent === "undefined" || !(event instanceof CustomEvent)) return null;
    const detail = event.detail;
    if (detail === null || typeof detail !== "object") return null;
    const record = detail;
    return isHTMLElement(record.region) ? record : null;
  }
  function lazySurfaceFromEvent(event) {
    const detail = customEventDetail(event);
    if (detail !== null) {
      if (detail.region.matches(lazySurfaceSelector)) return detail.region;
      return closestHTMLElement(detail.region, lazySurfaceSelector);
    }
    return closestHTMLElement(event.target, lazySurfaceSelector);
  }
  function lazyRetrySurfaceFromEvent(event) {
    const surface = lazySurfaceFromEvent(event);
    if (surface === null) return null;
    return surface.matches(lazySurfaceRetrySelector) ? surface : null;
  }
  function markLazySurfaceLoading(surface) {
    surface.classList.remove("app-lazy-surface-error");
    surface.setAttribute("aria-busy", "true");
  }
  function renderLazySurfaceError(surface, message = "We couldn't load this section.") {
    const retryUrl = surface.getAttribute("hx-get") || surface.getAttribute("data-hx-get") || "";
    surface.classList.add("app-lazy-surface-error");
    surface.setAttribute("aria-busy", "false");
    const body = document.createElement("div");
    body.className = "app-lazy-surface-error-body";
    const text = document.createElement("p");
    text.className = "app-lazy-surface-error-message";
    text.textContent = message;
    body.appendChild(text);
    const retryButton = document.createElement("button");
    retryButton.type = "button";
    retryButton.className = "btn btn-sm btn-outline-light app-lazy-surface-retry";
    retryButton.textContent = "Retry";
    retryButton.setAttribute("hx-get", retryUrl);
    retryButton.setAttribute("hx-target", `closest ${lazySurfaceSelector}`);
    retryButton.setAttribute("hx-swap", "outerHTML");
    retryButton.setAttribute("hx-push-url", "false");
    body.appendChild(retryButton);
    surface.replaceChildren(body);
    window.htmx?.process?.(surface);
  }
  function lazySurfaceErrorMessage(event) {
    const detail = customEventDetail(event);
    return detail?.errorKind === "timeout" ? "This section took too long to load." : "We couldn't load this section.";
  }
  function enableLazySurfaceErrorHandling(root = document) {
    const onRequestStart = function(event) {
      const surface = lazySurfaceFromEvent(event);
      if (surface === null) return;
      markLazySurfaceLoading(surface);
    };
    const onRegionError = function(event) {
      const surface = lazyRetrySurfaceFromEvent(event);
      if (surface === null) return;
      renderLazySurfaceError(surface, lazySurfaceErrorMessage(event));
    };
    root.addEventListener(UiRegionEvents.requestStart, onRequestStart);
    root.addEventListener(UiRegionEvents.error, onRegionError);
    return function disableLazySurfaceErrorHandling() {
      root.removeEventListener(UiRegionEvents.requestStart, onRequestStart);
      root.removeEventListener(UiRegionEvents.error, onRegionError);
    };
  }

  // frontend/ts/live-updates/protocol.ts
  function liveUpdateMessageScopeKey(message) {
    if (message && typeof message.scopeKey === "string" && message.scopeKey.length > 0) {
      return message.scopeKey;
    }
    return null;
  }
  function normalizeLiveUpdateVersion(value) {
    return Number.isInteger(value) && value >= 0 ? value : null;
  }
  function buildLiveUpdateSubscribeCommand(scope, clientId, lastSeenVersion) {
    return encodeLiveUpdateCommand({
      type: "subscribe",
      scope,
      clientId,
      lastSeenVersion
    });
  }
  function liveUpdateFragmentMergeKey(fragment) {
    if (!fragment || !fragment.targetId) return null;
    const fragmentKey = fragment.fragmentKey ? JSON.stringify(fragment.fragmentKey) : "";
    return `${fragmentKey}:${fragment.targetId}`;
  }

  // frontend/ts/live-updates/validation.ts
  function parseLiveUpdateSurfaceConfig(value) {
    try {
      return parseLiveSurfaceConfig(value);
    } catch (_error) {
      return null;
    }
  }

  // frontend/ts/shared/exhaustive.ts
  function assertNever(value, message = "Unexpected generated union variant") {
    throw new Error(`${message}: ${JSON.stringify(value)}`);
  }

  // frontend/ts/app-live-updates.ts
  enableHtmxUiRegionEventAdapter();
  enableUiRegionTransitions();
  enableLazySurfaceErrorHandling();
  (function enableLiveUpdates() {
    if (typeof window === "undefined") return;
    const actorFragmentRefreshEventName = AppEvents.liveFragmentsRefresh;
    const pendingDeferredFragments = /* @__PURE__ */ new Map();
    const pendingInteractionDeferredFragments = /* @__PURE__ */ new Map();
    const pendingInteractionTimers = /* @__PURE__ */ new Map();
    const activeInteractionSessions = createActiveInteractionSessionTracker(document);
    const inFlightFragments = /* @__PURE__ */ new Map();
    const activeSubscriptions = /* @__PURE__ */ new Map();
    const scopeVersions = /* @__PURE__ */ new Map();
    let socket = null;
    let socketPath = null;
    let reconnectTimer = null;
    let reconnectAttempt = 0;
    let activeClientId = null;
    let nextPerfToken = 0;
    function supportsPerformanceTimeline() {
      return Boolean(window.performance && typeof window.performance.mark === "function" && typeof window.performance.measure === "function");
    }
    function perfToken(prefix) {
      nextPerfToken += 1;
      return `${prefix}-${Date.now()}-${nextPerfToken}`;
    }
    function beginPerfSpan(name, detail) {
      if (!supportsPerformanceTimeline()) return null;
      const token = perfToken(name);
      const startMark = `${token}:start`;
      window.performance.mark(startMark, detail ? { detail } : void 0);
      return {
        token,
        name,
        startMark,
        detail: detail || null
      };
    }
    function endPerfSpan(span, extraDetail) {
      if (!span || !supportsPerformanceTimeline()) return null;
      const endMark = `${span.token}:end`;
      const detail = extraDetail ? { ...span.detail, ...extraDetail } : span.detail;
      window.performance.mark(endMark, detail ? { detail } : void 0);
      let duration = null;
      try {
        window.performance.measure(span.name, {
          start: span.startMark,
          end: endMark,
          detail: detail || void 0
        });
        const entries = window.performance.getEntriesByName(span.name, "measure");
        const entry = entries[entries.length - 1];
        duration = entry ? entry.duration : null;
      } catch (_error) {
        duration = null;
      }
      window.performance.clearMarks(span.startMark);
      window.performance.clearMarks(endMark);
      document.dispatchEvent(new CustomEvent("app:live-update-performance", {
        detail: {
          name: span.name,
          duration,
          ...detail
        }
      }));
      return duration;
    }
    function emitDebugEvent(name, detail) {
      document.dispatchEvent(new CustomEvent("app:live-update-debug", {
        detail: {
          name,
          ...detail || {}
        }
      }));
    }
    function findPreservedField(root, preserveField) {
      if (!(root instanceof HTMLElement) || !preserveField) return null;
      const fieldKey = preserveField.fieldKey;
      const fieldKeyAttr = preserveField.fieldKeyAttr || "data-live-field-key";
      if (fieldKey) {
        const escapedKey = window.CSS && typeof window.CSS.escape === "function" ? window.CSS.escape(fieldKey) : fieldKey;
        const keyedField = root.querySelector(`[${fieldKeyAttr}="${escapedKey}"]`);
        if (keyedField instanceof HTMLInputElement || keyedField instanceof HTMLSelectElement || keyedField instanceof HTMLTextAreaElement) {
          return keyedField;
        }
      }
      const name = preserveField.name;
      if (!name) return null;
      const escapedName = window.CSS && typeof window.CSS.escape === "function" ? window.CSS.escape(name) : name;
      const namedField = root.querySelector(`[name="${escapedName}"]`);
      if (namedField instanceof HTMLInputElement || namedField instanceof HTMLSelectElement || namedField instanceof HTMLTextAreaElement) {
        return namedField;
      }
      return null;
    }
    function makeClientId() {
      if (window.crypto && typeof window.crypto.randomUUID === "function") {
        return window.crypto.randomUUID();
      }
      return `live-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    }
    function ensureClientId() {
      if (!activeClientId) {
        activeClientId = makeClientId();
      }
      document.querySelectorAll("[data-live-update-surface]").forEach(function(ownerEl) {
        if (ownerEl instanceof HTMLElement) {
          ownerEl.dataset.liveUpdateClientId = activeClientId ?? "";
        }
      });
      return activeClientId;
    }
    function buildWebSocketUrl(path) {
      const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
      return `${protocol}//${window.location.host}${path}`;
    }
    function closeSocket() {
      if (reconnectTimer) {
        window.clearTimeout(reconnectTimer);
        reconnectTimer = null;
      }
      if (socket) {
        socket.onopen = null;
        socket.onmessage = null;
        socket.onclose = null;
        socket.onerror = null;
        socket.close();
        socket = null;
      }
      socketPath = null;
    }
    async function swapFragmentHtml(targetId, html) {
      const perfSpan = beginPerfSpan("live_updates.swap_fragment", { targetId });
      const target = document.getElementById(targetId);
      if (!target) {
        endPerfSpan(perfSpan, { outcome: "target_missing" });
        return;
      }
      const trimmed = (html || "").trim();
      if (!trimmed) {
        target.remove();
        endPerfSpan(perfSpan, { outcome: "removed_empty_html" });
        return;
      }
      const template = document.createElement("template");
      template.innerHTML = trimmed;
      let nextNode = template.content.firstElementChild;
      if (nextNode && nextNode.tagName === "TEMPLATE") {
        nextNode = nextNode.content.firstElementChild;
      }
      if (!(nextNode instanceof Element)) {
        endPerfSpan(perfSpan, { outcome: "no_element" });
        return;
      }
      target.replaceWith(nextNode);
      if (window.htmx && typeof window.htmx.process === "function") {
        window.htmx.process(document.body);
      }
      if (window.appPageLifecycle && typeof window.appPageLifecycle.dispatchPageReady === "function") {
        window.appPageLifecycle.dispatchPageReady({
          source: "live-fragment-refetch",
          target: nextNode,
          isFullPage: false
        });
      }
      endPerfSpan(perfSpan, {
        outcome: "swapped",
        nextTagName: nextNode.tagName
      });
    }
    async function refetchFragment(fragment) {
      const perfSpan = beginPerfSpan("live_updates.refetch_fragment", {
        targetId: fragment && fragment.targetId ? fragment.targetId : null,
        url: fragment && fragment.url ? fragment.url : null,
        deferUntilBlur: Boolean(fragment && fragment.deferUntilBlur)
      });
      const response = await window.fetch(fragment.url, {
        credentials: "same-origin",
        headers: {
          "HX-Request": "true"
        }
      });
      if (!response.ok) {
        endPerfSpan(perfSpan, { outcome: "http_error", status: response.status });
        throw new Error(`Fragment fetch failed with ${response.status}`);
      }
      const html = await response.text();
      await swapFragmentHtml(fragment.targetId, html);
      restoreDeferredState(fragment);
      endPerfSpan(perfSpan, {
        outcome: "ok",
        status: response.status,
        responseBytes: html.length
      });
    }
    function queueFragment(fragment) {
      const existing = inFlightFragments.get(fragment.targetId);
      if (existing) {
        inFlightFragments.set(fragment.targetId, { ...existing, next: fragment });
        emitDebugEvent("fragment_deduped", {
          targetId: fragment.targetId,
          url: fragment.url
        });
        return;
      }
      inFlightFragments.set(fragment.targetId, { next: null });
      void refetchFragment(fragment).catch(function(error) {
        reportFragmentRefreshError(fragment, error);
        return null;
      }).finally(function() {
        const state = inFlightFragments.get(fragment.targetId);
        const next = state && state.next;
        inFlightFragments.delete(fragment.targetId);
        if (next) {
          queueFragment(next);
        }
      });
    }
    function reportFragmentRefreshError(fragment, error) {
      const detail = {
        targetId: fragment && fragment.targetId ? fragment.targetId : null,
        url: fragment && fragment.url ? fragment.url : null,
        error: error instanceof Error ? error.message : String(error)
      };
      if (typeof window.console !== "undefined" && typeof window.console.error === "function") {
        window.console.error("Live fragment refresh failed", detail);
      }
      document.dispatchEvent(new CustomEvent("app:live-update-fragment-refresh-failed", {
        detail
      }));
    }
    function focusedFieldProtection(policy) {
      const activeSelector = policy && policy.activeSelector ? policy.activeSelector : "input:focus, select:focus, textarea:focus";
      const fieldKeyAttr = policy && policy.fieldKeyAttr ? policy.fieldKeyAttr : "data-live-field-key";
      const fieldNameFallback = !policy || policy.fieldNameFallback !== false;
      const containerSelector = policy && policy.containerSelector ? policy.containerSelector : null;
      function findActiveInput(target) {
        if (!(target instanceof HTMLElement)) return null;
        const activeInput = target.querySelector(activeSelector);
        if (activeInput instanceof HTMLInputElement || activeInput instanceof HTMLSelectElement || activeInput instanceof HTMLTextAreaElement) {
          return activeInput;
        }
        return null;
      }
      return {
        matches: function(fragment, target) {
          return Boolean(
            fragment && fragment.deferUntilBlur && target instanceof HTMLElement
          );
        },
        hasActiveInput: function(target) {
          return Boolean(findActiveInput(target));
        },
        captureState: function(target, fragment) {
          if (!(target instanceof HTMLElement)) return fragment;
          const activeInput = findActiveInput(target);
          if (!activeInput) return fragment;
          const name = activeInput.getAttribute("name");
          if (!fieldNameFallback && !activeInput.getAttribute(fieldKeyAttr)) return fragment;
          const containerEl = containerSelector ? activeInput.closest(containerSelector) : null;
          return {
            ...fragment,
            preserveField: {
              rowId: containerEl instanceof HTMLElement ? containerEl.id : null,
              fieldKey: activeInput.getAttribute(fieldKeyAttr) || null,
              fieldKeyAttr,
              name,
              value: activeInput.value
            }
          };
        },
        restoreState: function(target, fragment) {
          if (!fragment || !fragment.preserveField) return;
          const { rowId, value } = fragment.preserveField;
          const root = rowId ? document.getElementById(rowId) : target;
          const field = findPreservedField(root, fragment.preserveField);
          if (field) {
            field.value = value ?? "";
          }
        }
      };
    }
    function matchingFragmentProtection(fragment, _target) {
      if (!fragment) return null;
      switch (fragment.protectionPolicy.kind) {
        case "focused_field":
          return focusedFieldProtection(fragment.protectionPolicy);
        case "none":
          return null;
        default:
          return assertNever(fragment.protectionPolicy);
      }
    }
    function hasProtectedActiveInput(target, fragment) {
      const adapter = matchingFragmentProtection(fragment, target);
      return Boolean(adapter && adapter.hasActiveInput(target));
    }
    function captureDeferredState(target, fragment) {
      const adapter = matchingFragmentProtection(fragment, target);
      if (!adapter) return fragment;
      return adapter.captureState(target, fragment);
    }
    function restoreDeferredState(fragment) {
      if (!fragment || !fragment.targetId) return;
      const target = document.getElementById(fragment.targetId);
      if (!(target instanceof HTMLElement)) return;
      const adapter = matchingFragmentProtection(fragment, target);
      if (!adapter) return;
      adapter.restoreState(target, fragment);
    }
    function handleFragmentRefreshRequest(fragment) {
      if (!fragment || !fragment.targetId || !fragment.url) return;
      const target = document.getElementById(fragment.targetId);
      if (!(target instanceof HTMLElement)) return;
      const resolvedFragment = { ...fragment, url: target.dataset.liveUpdateUrl || fragment.url };
      const interactionConflict = resolveLiveFragmentInteractionConflict(resolvedFragment, target, activeInteractionSessions);
      if (interactionConflict && interactionConflict.action === "cancel") {
        activeInteractionSessions.requestCancel(interactionConflict.session, "live-fragment-conflict");
      }
      if (interactionConflict && interactionConflict.action === "defer") {
        pendingInteractionDeferredFragments.set(resolvedFragment.targetId, resolvedFragment);
        scheduleInteractionDeferredFallbackFlush(resolvedFragment.targetId, interactionConflict.timeoutMs);
        document.dispatchEvent(new CustomEvent("app:live-update-performance", {
          detail: {
            name: "live_updates.defer_fragment",
            duration: 0,
            targetId: resolvedFragment.targetId,
            reason: "interaction_session"
          }
        }));
        return;
      }
      clearInteractionDeferredFragment(resolvedFragment.targetId);
      if (resolvedFragment.deferUntilBlur && hasProtectedActiveInput(target, resolvedFragment)) {
        pendingDeferredFragments.set(resolvedFragment.targetId, captureDeferredState(target, resolvedFragment));
        document.dispatchEvent(new CustomEvent("app:live-update-performance", {
          detail: {
            name: "live_updates.defer_fragment",
            duration: 0,
            targetId: resolvedFragment.targetId,
            reason: "active_input"
          }
        }));
        return;
      }
      pendingDeferredFragments.delete(resolvedFragment.targetId);
      queueFragment(resolvedFragment);
    }
    function clearInteractionDeferredFragment(targetId) {
      const timer = pendingInteractionTimers.get(targetId);
      if (timer) window.clearTimeout(timer);
      pendingInteractionTimers.delete(targetId);
      pendingInteractionDeferredFragments.delete(targetId);
    }
    function scheduleInteractionDeferredFallbackFlush(targetId, timeoutMs) {
      const existing = pendingInteractionTimers.get(targetId);
      if (existing) window.clearTimeout(existing);
      if (timeoutMs === null || timeoutMs <= 0) return;
      pendingInteractionTimers.set(targetId, window.setTimeout(function() {
        const fragment = pendingInteractionDeferredFragments.get(targetId);
        const target = document.getElementById(targetId);
        if (fragment && target instanceof HTMLElement) {
          const conflict = resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions);
          if (conflict) activeInteractionSessions.requestCancel(conflict.session, "live-fragment-defer-fallback-timeout");
        }
        flushInteractionDeferredFragment(targetId, "interaction_fallback_timeout");
      }, timeoutMs));
    }
    function flushInteractionDeferredFragment(targetId, reason) {
      const fragment = pendingInteractionDeferredFragments.get(targetId);
      if (!fragment) return;
      clearInteractionDeferredFragment(targetId);
      emitDebugEvent("deferred_fragment_flush", {
        targetId,
        reason
      });
      queueFragment(fragment);
    }
    function flushInteractionDeferredFragmentsWithoutActiveSessions() {
      Array.from(pendingInteractionDeferredFragments.entries()).forEach(function([targetId, fragment]) {
        const target = document.getElementById(targetId);
        if (!(target instanceof HTMLElement)) {
          flushInteractionDeferredFragment(targetId, "target_missing");
          return;
        }
        const conflict = resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions);
        if (!conflict) flushInteractionDeferredFragment(targetId, "interaction_session_end");
      });
    }
    function flushDeferredFragment(targetId) {
      const fragment = pendingDeferredFragments.get(targetId);
      if (!fragment) return;
      pendingDeferredFragments.delete(targetId);
      emitDebugEvent("deferred_fragment_flush", {
        targetId,
        reason: "inactive_input"
      });
      queueFragment(fragment);
    }
    function flushDeferredFragmentsWithoutActiveInputs() {
      Array.from(pendingDeferredFragments.entries()).forEach(function([targetId]) {
        const target = document.getElementById(targetId);
        const fragment = pendingDeferredFragments.get(targetId);
        if (target instanceof HTMLElement && fragment && resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions)) return;
        if (!target || !hasProtectedActiveInput(target, fragment)) {
          flushDeferredFragment(targetId);
        }
      });
    }
    function scheduleReconnect() {
      if (reconnectTimer) return;
      reconnectAttempt += 1;
      const cappedAttempt = Math.min(reconnectAttempt, 6);
      const baseDelay = 250 * 2 ** cappedAttempt;
      const delayMs = Math.floor(Math.random() * Math.min(baseDelay, 1e4));
      emitDebugEvent("reconnect_scheduled", {
        attempt: reconnectAttempt,
        delayMs
      });
      reconnectTimer = window.setTimeout(function() {
        reconnectTimer = null;
        syncConnection();
      }, delayMs);
    }
    function sendCommand(command) {
      if (!socket || socket.readyState !== window.WebSocket.OPEN) return;
      socket.send(JSON.stringify(command));
    }
    function getScopeVersion(scopeKey) {
      const version = scopeVersions.get(scopeKey);
      return Number.isInteger(version) ? version ?? null : null;
    }
    function setScopeVersion(scopeKey, version) {
      if (!Number.isInteger(version) || version < 0) return;
      scopeVersions.set(scopeKey, version);
    }
    function clearScopeVersion(scopeKey) {
      scopeVersions.delete(scopeKey);
    }
    function normalizeVersion(value) {
      return normalizeLiveUpdateVersion(value);
    }
    function messageScopeKey(message) {
      return liveUpdateMessageScopeKey(message);
    }
    function subscribeScope(subscription) {
      const lastSeenVersion = getScopeVersion(subscription.scopeKey);
      sendCommand(buildLiveUpdateSubscribeCommand(subscription.scope, ensureClientId(), lastSeenVersion));
    }
    function unsubscribeScope(subscription) {
      sendCommand({
        type: "unsubscribe",
        scope: subscription.scope
      });
    }
    function readDeclarativeSurface(ownerEl) {
      if (!(ownerEl instanceof HTMLElement)) return null;
      const rawConfig = ownerEl.getAttribute("data-live-update-surface");
      if (!rawConfig) return null;
      let config = null;
      try {
        config = JSON.parse(rawConfig);
      } catch (error) {
        reportSurfaceConfigError(ownerEl, error);
        return null;
      }
      const parsedConfig = parseLiveUpdateSurfaceConfig(config);
      if (parsedConfig === null) {
        reportSurfaceConfigError(ownerEl, new Error("Invalid live-update surface scope"));
        return null;
      }
      return {
        feature: parsedConfig.feature,
        scope: parsedConfig.scope,
        scopeKey: parsedConfig.scopeKey,
        path: parsedConfig.socketPath,
        resyncFragments: parsedConfig.resyncFragments,
        decorateRequestsWithin: parsedConfig.decorateRequestsWithin,
        ownerEls: [ownerEl],
        resync: function(subscription) {
          subscription.resyncFragments.forEach(handleFragmentRefreshRequest);
        }
      };
    }
    function reportSurfaceConfigError(ownerEl, error) {
      const detail = {
        id: ownerEl && ownerEl.id ? ownerEl.id : null,
        feature: null,
        error: error instanceof Error ? error.message : String(error)
      };
      if (typeof window.console !== "undefined" && typeof window.console.error === "function") {
        window.console.error("Invalid live-update surface config", detail);
      }
      document.dispatchEvent(new CustomEvent("app:live-update-surface-config-failed", {
        detail
      }));
    }
    function collectDeclarativeSubscriptions() {
      const subscriptions = [];
      document.querySelectorAll("[data-live-update-surface]").forEach(function(ownerEl) {
        if (!(ownerEl instanceof HTMLElement)) return;
        const scopeInfo = readDeclarativeSurface(ownerEl);
        if (!scopeInfo || !scopeInfo.scopeKey) return;
        subscriptions.push({ ...scopeInfo, ownerEl });
      });
      return subscriptions;
    }
    function shouldDecorateDeclarativeRequest(event) {
      const sourceEl = event.detail && event.detail.elt;
      if (!(sourceEl instanceof HTMLElement)) return false;
      const ownerEl = sourceEl.closest("[data-live-update-surface]");
      if (!(ownerEl instanceof HTMLElement)) return false;
      const scopeInfo = readDeclarativeSurface(ownerEl);
      if (!scopeInfo) return false;
      if (scopeInfo.decorateRequestsWithin.length === 0) return true;
      return scopeInfo.decorateRequestsWithin.some(function(selector) {
        return Boolean(selector && sourceEl.closest(selector));
      });
    }
    function fragmentMergeKey(fragment) {
      return liveUpdateFragmentMergeKey(fragment);
    }
    function mergeFragments(existingFragments, nextFragments) {
      const merged = [];
      const seen = /* @__PURE__ */ new Set();
      existingFragments.concat(nextFragments).forEach(function(fragment) {
        const mergeKey = fragmentMergeKey(fragment);
        if (!mergeKey || seen.has(mergeKey)) {
          if (mergeKey) {
            emitDebugEvent("fragment_deduped", {
              targetId: fragment && fragment.targetId ? fragment.targetId : null,
              mergeKey
            });
          }
          return;
        }
        seen.add(mergeKey);
        merged.push(fragment);
      });
      return merged;
    }
    function mergeStringLists(existingValues, nextValues) {
      return Array.from(new Set(existingValues.concat(nextValues).filter(Boolean)));
    }
    function mergeSubscription(existing, next) {
      if (!existing) return next;
      return {
        ...existing,
        feature: existing.feature || next.feature,
        resyncFragments: mergeFragments(existing.resyncFragments, next.resyncFragments),
        decorateRequestsWithin: mergeStringLists(existing.decorateRequestsWithin, next.decorateRequestsWithin),
        ownerEls: (existing.ownerEls || []).concat(next.ownerEl ? [next.ownerEl] : next.ownerEls || [])
      };
    }
    function desiredSubscriptions() {
      const desired = /* @__PURE__ */ new Map();
      collectDeclarativeSubscriptions().forEach(function(subscription) {
        desired.set(subscription.scopeKey, mergeSubscription(desired.get(subscription.scopeKey), subscription));
      });
      return desired;
    }
    function handleSubscribedMessage(message) {
      if (!message) return;
      const scopeKey = messageScopeKey(message);
      if (!scopeKey) return;
      const subscription = activeSubscriptions.get(scopeKey);
      if (!subscription) return;
      const currentVersion = normalizeVersion(message.currentVersion);
      if (currentVersion !== null) {
        setScopeVersion(scopeKey, currentVersion);
      }
      if (message.resync && typeof subscription.resync === "function") {
        subscription.resync(subscription);
      }
    }
    function handleInvalidateMessage(message) {
      if (!message || !Array.isArray(message.fragments)) return;
      if (message.sourceClientId && message.sourceClientId === activeClientId) return;
      const perfSpan = beginPerfSpan("live_updates.handle_invalidate", {
        fragmentCount: message.fragments.length,
        scopeKind: message.scope && message.scope.kind ? message.scope.kind : null,
        version: normalizeVersion(message.version)
      });
      const scopeKey = messageScopeKey(message);
      if (!scopeKey) {
        endPerfSpan(perfSpan, { outcome: "invalid_scope" });
        return;
      }
      const subscription = activeSubscriptions.get(scopeKey);
      if (!subscription) {
        endPerfSpan(perfSpan, { outcome: "unsubscribed_scope", scopeKey });
        return;
      }
      const nextVersion = normalizeVersion(message.version);
      const previousVersion = getScopeVersion(scopeKey);
      if (nextVersion !== null) {
        if (previousVersion !== null && nextVersion > previousVersion + 1) {
          setScopeVersion(scopeKey, nextVersion);
          if (typeof subscription.resync === "function") {
            subscription.resync(subscription);
          }
          emitDebugEvent("resync_version_gap", {
            scopeKey,
            previousVersion,
            nextVersion
          });
          endPerfSpan(perfSpan, {
            outcome: "resync_gap",
            scopeKey,
            previousVersion,
            nextVersion
          });
          return;
        }
        if (previousVersion !== null && nextVersion <= previousVersion) {
          endPerfSpan(perfSpan, {
            outcome: "stale",
            scopeKey,
            previousVersion,
            nextVersion
          });
          return;
        }
        setScopeVersion(scopeKey, nextVersion);
      }
      if (message.fragments.length === 0 && typeof subscription.resync === "function") {
        subscription.resync(subscription);
        endPerfSpan(perfSpan, { outcome: "resync_empty_fragments", scopeKey });
        return;
      }
      message.fragments.forEach(handleFragmentRefreshRequest);
      endPerfSpan(perfSpan, { outcome: "queued_fragments", scopeKey });
    }
    function openSocket(path) {
      const connectPerfSpan = beginPerfSpan("live_updates.open_socket", { path });
      socket = new window.WebSocket(buildWebSocketUrl(path));
      socketPath = path;
      socket.onopen = function() {
        reconnectAttempt = 0;
        activeSubscriptions.forEach(function(subscription) {
          subscribeScope(subscription);
          emitDebugEvent("subscription_added", {
            scopeKey: subscription.scopeKey,
            fragmentCount: subscription.resyncFragments.length,
            ownerCount: (subscription.ownerEls || []).length
          });
        });
        endPerfSpan(connectPerfSpan, {
          outcome: "open",
          subscriptionCount: activeSubscriptions.size
        });
      };
      socket.onmessage = function(event) {
        let parsedMessage = null;
        try {
          parsedMessage = JSON.parse(event.data);
        } catch (_error) {
          return;
        }
        let message;
        try {
          message = parseLiveUpdateMessage(parsedMessage);
        } catch (_error) {
          return;
        }
        if (message.type === "subscribed") {
          handleSubscribedMessage(message);
          return;
        }
        if (message.type === "invalidate") {
          handleInvalidateMessage(message);
        }
      };
      socket.onclose = function() {
        endPerfSpan(connectPerfSpan, { outcome: "closed_before_open" });
        socket = null;
        if (activeSubscriptions.size > 0) {
          scheduleReconnect();
        }
      };
      socket.onerror = function() {
        endPerfSpan(connectPerfSpan, { outcome: "error" });
        if (socket) {
          socket.close();
        }
      };
    }
    function syncConnection() {
      ensureClientId();
      const desired = desiredSubscriptions();
      const firstDesired = desired.values().next().value;
      const nextPath = firstDesired?.path ?? null;
      if (desired.size === 0 || !nextPath) {
        activeSubscriptions.clear();
        closeSocket();
        return;
      }
      const removed = [];
      activeSubscriptions.forEach(function(subscription, scopeKey) {
        if (!desired.has(scopeKey)) {
          removed.push(subscription);
        }
      });
      const added = [];
      desired.forEach(function(subscription, scopeKey) {
        if (!activeSubscriptions.has(scopeKey)) {
          added.push(subscription);
        }
      });
      removed.forEach(function(subscription) {
        unsubscribeScope(subscription);
        activeSubscriptions.delete(subscription.scopeKey);
        clearScopeVersion(subscription.scopeKey);
        emitDebugEvent("subscription_removed", {
          scopeKey: subscription.scopeKey
        });
      });
      desired.forEach(function(subscription, scopeKey) {
        activeSubscriptions.set(scopeKey, subscription);
      });
      if (!socket || socket.readyState > window.WebSocket.OPEN || socketPath !== nextPath) {
        closeSocket();
        openSocket(nextPath);
        return;
      }
      if (socket.readyState === window.WebSocket.OPEN) {
        added.forEach(function(subscription) {
          subscribeScope(subscription);
          emitDebugEvent("subscription_added", {
            scopeKey: subscription.scopeKey,
            fragmentCount: subscription.resyncFragments.length,
            ownerCount: (subscription.ownerEls || []).length
          });
        });
      }
    }
    document.addEventListener("htmx:configRequest", function(event) {
      const htmxEvent = event;
      if (!shouldDecorateDeclarativeRequest(htmxEvent)) return;
      const clientId = ensureClientId();
      if (htmxEvent.detail?.headers !== void 0) {
        htmxEvent.detail.headers["X-Live-Update-Client-Id"] = clientId;
      }
    });
    function handleActorFragmentRefreshEvent(event) {
      const detail = event instanceof CustomEvent ? event.detail : null;
      const fragments = Array.isArray(detail && detail.fragments) ? detail.fragments : [];
      fragments.forEach(handleFragmentRefreshRequest);
    }
    document.addEventListener(actorFragmentRefreshEventName, handleActorFragmentRefreshEvent);
    document.addEventListener(AppEvents.interactionSessionEnd, function() {
      flushInteractionDeferredFragmentsWithoutActiveSessions();
      flushDeferredFragmentsWithoutActiveInputs();
    });
    document.addEventListener("htmx:afterSwap", function() {
      flushInteractionDeferredFragmentsWithoutActiveSessions();
    });
    document.addEventListener("htmx:responseError", function() {
      flushInteractionDeferredFragmentsWithoutActiveSessions();
    });
    document.addEventListener("focusout", function() {
      window.setTimeout(function() {
        flushDeferredFragmentsWithoutActiveInputs();
      }, 0);
    });
    document.addEventListener("input", function() {
      window.setTimeout(function() {
        flushDeferredFragmentsWithoutActiveInputs();
      }, 0);
    });
    document.addEventListener("change", function() {
      window.setTimeout(function() {
        flushDeferredFragmentsWithoutActiveInputs();
      }, 0);
    });
    document.addEventListener(AppEvents.pageReady, syncConnection);
  })();
})();
