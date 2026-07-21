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
  var surfaceDomAttr = "data-bepis-surface";
  function isRosterStaffPanelSortRow(value) {
    return isRecord(value) && hasExactKeys(value, ["staffRowKey", "staffName", "staffRole", "assignedShifts", "idealShifts"], ["staffRowKey", "staffName", "staffRole", "assignedShifts", "idealShifts"]) && typeof value["staffRowKey"] === "string" && typeof value["staffName"] === "string" && typeof value["staffRole"] === "string" && (typeof value["assignedShifts"] === "number" && Number.isInteger(value["assignedShifts"])) && (typeof value["idealShifts"] === "number" && Number.isInteger(value["idealShifts"]));
  }
  function parseRosterStaffPanelSortRow(value) {
    if (isRosterStaffPanelSortRow(value)) return value;
    throw new Error("Invalid RosterStaffPanelSortRow");
  }
  var rosterContentDomToken = "roster-content";
  var rosterStaffPanelSortRootDomAttr = "data-bepis-roster-staff-panel-sort-root";
  var rosterStaffPanelSortRowDomAttr = "data-bepis-roster-staff-panel-sort-row";
  var rosterStaffPanelSortControlDomAttr = "data-bepis-roster-staff-panel-sort-control";
  var rosterStaffPanelTabDomAttr = "data-bepis-roster-staff-panel-tab";
  var rosterFullscreenRootDomAttr = "data-bepis-roster-fullscreen-root";
  var rosterFullscreenToggleDomAttr = "data-bepis-roster-fullscreen-toggle";
  var rosterFullscreenLabelDomAttr = "data-bepis-roster-fullscreen-label";
  var rosterColumnEditorDomAttr = "data-bepis-roster-column-editor";
  var rosterColumnEditStartDomAttr = "data-bepis-roster-column-edit-start";
  var rosterColumnEditDoneDomAttr = "data-bepis-roster-column-edit-done";
  var rosterStaffHighlightSourceDomAttr = "data-bepis-roster-staff-highlight-source";
  var rosterStaffHighlightMemberDomAttr = "data-bepis-roster-staff-highlight-member";
  var rosterStaffHighlightPinDomAttr = "data-bepis-roster-staff-highlight-pin";
  var rosterShiftGroupHighlightSourceDomAttr = "data-bepis-roster-shift-group-highlight-source";
  var rosterShiftGroupHighlightMemberDomAttr = "data-bepis-roster-shift-group-highlight-member";
  var rosterFullscreenDomAttr = "data-bepis-roster-fullscreen";
  var rosterColumnEditingDomAttr = "data-bepis-roster-column-editing";
  var rosterStaffHighlightOrderDomAttr = "data-bepis-roster-staff-highlight-order";
  var rosterDayTimelineShiftGroupHighlightSourceDomAttr = "data-bepis-roster-day-timeline-shift-group-highlight-source";
  var rosterDayTimelineShiftGroupHighlightMemberDomAttr = "data-bepis-roster-day-timeline-shift-group-highlight-member";
  var rosterFullscreenStates = { "collapsed": "collapsed", "expanded": "expanded" };
  function isRosterFullscreenState(value) {
    return typeof value === "string" && ["collapsed", "expanded"].includes(value);
  }
  var rosterColumnEditingStates = { "inactive": "inactive", "active": "active" };
  function isRosterColumnEditingState(value) {
    return typeof value === "string" && ["inactive", "active"].includes(value);
  }
  function isRosterStaffPanelSortKey(value) {
    return typeof value === "string" && ["name", "role", "shifts"].includes(value);
  }
  function isRosterStaffPanelTabsKey(value) {
    return typeof value === "string" && ["staff", "settings"].includes(value);
  }
  var FrontendSurfaceLinkedHighlightRegistry = { "timesheets": [], "roster": [{ "name": "staff-shifts-highlight", "sourceRoleAttribute": rosterStaffHighlightSourceDomAttr, "memberRoleAttribute": rosterStaffHighlightMemberDomAttr, "pinRoleAttribute": rosterStaffHighlightPinDomAttr, "orderStateAttribute": rosterStaffHighlightOrderDomAttr, "activations": ["hover", "focus", "keyboard", "pin"], "effects": ["matching-source", "matching-member", "ordered-member-bounds"] }, { "name": "shift-group-highlight", "sourceRoleAttribute": rosterShiftGroupHighlightSourceDomAttr, "memberRoleAttribute": rosterShiftGroupHighlightMemberDomAttr, "pinRoleAttribute": null, "orderStateAttribute": null, "activations": ["hover", "focus", "keyboard"], "effects": ["matching-member"] }], "roster-day-timeline": [{ "name": "shift-group-highlight", "sourceRoleAttribute": rosterDayTimelineShiftGroupHighlightSourceDomAttr, "memberRoleAttribute": rosterDayTimelineShiftGroupHighlightMemberDomAttr, "pinRoleAttribute": null, "orderStateAttribute": null, "activations": ["hover", "focus", "keyboard"], "effects": ["matching-member"] }], "leave-requests": [], "billing": [], "support": [], "profile": [], "staff": [], "admin-page": [], "admin-xero-page": [], "admin-venue-config": [], "admin-invites": [], "admin-exports": [], "admin-shift-types": [], "admin-roster-groups": [], "admin-xero": [] };
  var FrontendSurfaceCompleteSetSortRegistry = { "timesheets": [], "roster": [{ "name": "roster-staff-panel-sort", "rootRoleAttribute": rosterStaffPanelSortRootDomAttr, "rowRoleAttribute": rosterStaffPanelSortRowDomAttr, "controlRoleAttribute": rosterStaffPanelSortControlDomAttr, "parseRow": parseRosterStaffPanelSortRow, "isKey": isRosterStaffPanelSortKey, "keys": [{ "key": "name", "comparators": [{ "field": "staffName", "valueType": "text", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffRowKey }] }, { "key": "role", "comparators": [{ "field": "staffRole", "valueType": "text", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).staffRole }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffRowKey }] }, { "key": "shifts", "comparators": [{ "field": "assignedShifts", "valueType": "integer", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).assignedShifts }, { "field": "idealShifts", "valueType": "integer", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).idealShifts }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffRowKey }] }], "defaultKey": "name", "defaultDirection": "ascending" }], "roster-day-timeline": [], "leave-requests": [], "billing": [], "support": [], "profile": [], "staff": [], "admin-page": [], "admin-xero-page": [], "admin-venue-config": [], "admin-invites": [], "admin-exports": [], "admin-shift-types": [], "admin-roster-groups": [], "admin-xero": [] };
  var FrontendSurfaceTabSetRegistry = { "timesheets": [], "roster": [{ "name": "roster-staff-panel-tabs", "tabRoleAttribute": rosterStaffPanelTabDomAttr, "keys": ["staff", "settings"], "defaultKey": "staff", "isKey": isRosterStaffPanelTabsKey }], "roster-day-timeline": [], "leave-requests": [], "billing": [], "support": [], "profile": [], "staff": [], "admin-page": [], "admin-xero-page": [], "admin-venue-config": [], "admin-invites": [], "admin-exports": [], "admin-shift-types": [], "admin-roster-groups": [], "admin-xero": [] };
  var FrontendSurfaceFragmentRegistry = { "timesheets": ["timesheet-toolbar", "timesheet-day-columns", "timesheet-day-section"], "roster": ["roster-content", "roster-grid-toolbar", "roster-grid-frame", "roster-day-columns", "roster-day-rail", "roster-wage-rail", "roster-slots-grid", "roster-staff-panel", "roster-staff-self-service-leave-form", "roster-day-section", "roster-row"], "roster-day-timeline": ["roster-day-timeline-content"], "leave-requests": ["leave-section-count", "leave-section-list"], "billing": ["billing-status"], "support": ["support-award-rates", "support-public-holidays"], "profile": ["profile-details-section", "profile-preferences-section", "profile-security-section", "profile-leave-section", "profile-rsa-section"], "staff": ["staff-details-section", "staff-preferences-section", "staff-leave-section"], "admin-page": [], "admin-xero-page": [], "admin-venue-config": ["admin-venue-settings"], "admin-invites": ["admin-invites"], "admin-exports": ["admin-exports"], "admin-shift-types": ["admin-shift-types"], "admin-roster-groups": ["admin-roster-groups"], "admin-xero": ["admin-xero-shell"] };
  function isFrontendSurfaceName(value) {
    return typeof value === "string" && Object.prototype.hasOwnProperty.call(FrontendSurfaceFragmentRegistry, value);
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
  function detailRoot(event, key, fallback = document) {
    return rootFromTarget(detailTarget(event, key), fallback);
  }
  function onAppPageReady(handler) {
    if (typeof document === "undefined") return;
    document.addEventListener(pageReadyEvent, handler);
  }

  // frontend/ts/roster/column-edit.ts
  var editorSelector = `[${rosterColumnEditorDomAttr}]`;
  var startSelector = `[${rosterColumnEditStartDomAttr}]`;
  var doneSelector = `[${rosterColumnEditDoneDomAttr}]`;
  var finishDelayMs = 350;
  function defaultDiagnosticReporter(diagnostic5) {
    console.error?.("Invalid generated roster column-edit boundary", diagnostic5);
  }
  function defaultScheduler() {
    return {
      setTimeout: (handler, delayMs) => window.setTimeout(handler, delayMs),
      clearTimeout: (timerId) => window.clearTimeout(timerId)
    };
  }
  function diagnostic(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function closestEditor(target) {
    return target.closest(editorSelector);
  }
  function ownedControls(editor, selector) {
    return Array.from(editor.querySelectorAll(selector)).filter((control) => closestEditor(control) === editor);
  }
  function stateFor(editor, report) {
    if (editor.getAttribute(rosterColumnEditorDomAttr) !== "true") {
      report(diagnostic(editor, "invalid-editor-role", "Roster column editor role must equal true"));
      return null;
    }
    const state = editor.getAttribute(rosterColumnEditingDomAttr);
    if (!isRosterColumnEditingState(state)) {
      report(diagnostic(editor, "invalid-state", "Roster column-editing state is not declared by the Surface contract"));
      return null;
    }
    return state;
  }
  function createRosterColumnEditController(report = defaultDiagnosticReporter, scheduler = defaultScheduler()) {
    const pendingFinishTimers = /* @__PURE__ */ new Map();
    function clearPendingFinish(editor) {
      const timerId = pendingFinishTimers.get(editor);
      if (timerId === void 0) return;
      scheduler.clearTimeout(timerId);
      pendingFinishTimers.delete(editor);
    }
    function reconcile(editor) {
      const state = stateFor(editor, report);
      if (!state) return false;
      const active = state === rosterColumnEditingStates.active;
      const starts = ownedControls(editor, startSelector);
      const doneControls = ownedControls(editor, doneSelector);
      const invalidStarts = starts.filter((start2) => start2.getAttribute(rosterColumnEditStartDomAttr) !== "true");
      const invalidDoneControls = doneControls.filter((done) => done.getAttribute(rosterColumnEditDoneDomAttr) !== "true");
      invalidStarts.forEach((start2) => {
        report(diagnostic(start2, "invalid-control-role", "Roster column-edit start role must equal true"));
      });
      invalidDoneControls.forEach((done) => {
        report(diagnostic(done, "invalid-control-role", "Roster column-edit done role must equal true"));
      });
      if (invalidStarts.length > 0 || invalidDoneControls.length > 0) return false;
      starts.forEach((start2) => start2.setAttribute("aria-pressed", active ? "true" : "false"));
      return true;
    }
    function setState(editor, state) {
      if (!stateFor(editor, report)) return false;
      clearPendingFinish(editor);
      editor.setAttribute(rosterColumnEditingDomAttr, state);
      return reconcile(editor);
    }
    function start(target) {
      const startControl = target.closest(startSelector);
      if (!startControl || startControl.getAttribute(rosterColumnEditStartDomAttr) !== "true") return false;
      const editor = closestEditor(startControl);
      if (!editor) return false;
      return setState(editor, rosterColumnEditingStates.active);
    }
    function finish(target, activeElement) {
      const doneControl = target.closest(doneSelector);
      if (!doneControl || doneControl.getAttribute(rosterColumnEditDoneDomAttr) !== "true") return false;
      const editor = closestEditor(doneControl);
      if (!editor || !stateFor(editor, report)) return false;
      clearPendingFinish(editor);
      if (activeElement && editor.contains(activeElement)) {
        const blur = activeElement.blur;
        if (typeof blur === "function") blur.call(activeElement);
        const timerId = scheduler.setTimeout(() => {
          pendingFinishTimers.delete(editor);
          editor.setAttribute(rosterColumnEditingDomAttr, rosterColumnEditingStates.inactive);
          reconcile(editor);
        }, finishDelayMs);
        pendingFinishTimers.set(editor, timerId);
        return true;
      }
      return setState(editor, rosterColumnEditingStates.inactive);
    }
    function dispose(root) {
      for (const [editor, timerId] of pendingFinishTimers) {
        if (editor === root || root.contains(editor)) {
          scheduler.clearTimeout(timerId);
          pendingFinishTimers.delete(editor);
        }
      }
    }
    return { reconcile, start, finish, dispose };
  }
  function editorRootsWithin(root) {
    const editors = Array.from(root.querySelectorAll(editorSelector));
    if (root instanceof Element) {
      if (root.matches(editorSelector)) editors.unshift(root);
      const owner = closestEditor(root);
      if (owner && !editors.includes(owner)) editors.unshift(owner);
    }
    return editors;
  }
  function enableRosterColumnEditMode() {
    if (typeof window === "undefined") return;
    const controller = createRosterColumnEditController();
    const reconcileWithin = (root) => editorRootsWithin(root).forEach(controller.reconcile);
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const handled = controller.start(event.target) || controller.finish(event.target, document.activeElement instanceof Element ? document.activeElement : null);
      if (handled) event.preventDefault();
    });
    onAppPageReady((event) => reconcileWithin(detailRoot(event, "target")));
    document.addEventListener("htmx:afterSwap", (event) => reconcileWithin(detailRoot(event, "target")));
    document.addEventListener("htmx:beforeCleanupElement", (event) => {
      const cleanupRoot = detailTarget(event, "elt");
      if (cleanupRoot instanceof Element) controller.dispose(cleanupRoot);
    });
    if (document.readyState !== "loading") reconcileWithin(document);
  }

  // frontend/ts/roster/fullscreen.ts
  function rosterFullscreenLabels(expanded) {
    return {
      pressed: expanded ? "true" : "false",
      label: expanded ? "Exit expanded roster" : "Expand roster",
      iconAdd: expanded ? "bi-fullscreen-exit" : "bi-fullscreen",
      iconRemove: expanded ? "bi-fullscreen" : "bi-fullscreen-exit"
    };
  }

  // frontend/ts/roster/fullscreen-runtime.ts
  var rootSelector = `[${rosterFullscreenRootDomAttr}]`;
  var toggleSelector = `[${rosterFullscreenToggleDomAttr}]`;
  var labelSelector = `[${rosterFullscreenLabelDomAttr}]`;
  function defaultDiagnosticReporter2(diagnostic5) {
    console.error?.("Invalid generated roster fullscreen boundary", diagnostic5);
  }
  function diagnostic2(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function closestRoot(target) {
    return target.closest(rootSelector);
  }
  function ownedToggles(root) {
    return Array.from(root.querySelectorAll(toggleSelector)).filter((toggle) => closestRoot(toggle) === root);
  }
  function stateFor2(root, report) {
    if (root.getAttribute(rosterFullscreenRootDomAttr) !== "true") {
      report(diagnostic2(root, "invalid-root-role", "Roster fullscreen root role must equal true"));
      return null;
    }
    const state = root.getAttribute(rosterFullscreenDomAttr);
    if (!isRosterFullscreenState(state)) {
      report(diagnostic2(root, "invalid-state", "Roster fullscreen state is not declared by the Surface contract"));
      return null;
    }
    return state;
  }
  function validateToggle(toggle, report) {
    if (toggle.getAttribute(rosterFullscreenToggleDomAttr) !== "true") {
      report(diagnostic2(toggle, "invalid-toggle-role", "Roster fullscreen toggle role must equal true"));
      return null;
    }
    const labels = Array.from(toggle.querySelectorAll(labelSelector)).filter((label) => label.closest(toggleSelector) === toggle);
    if (labels.length !== 1 || labels[0]?.getAttribute(rosterFullscreenLabelDomAttr) !== "true") {
      report(diagnostic2(toggle, "invalid-label-role", "Roster fullscreen toggle must own one label role equal to true"));
      return null;
    }
    return { toggle, label: labels[0] };
  }
  function updateToggle(validated, state) {
    const expanded = state === rosterFullscreenStates.expanded;
    const labels = rosterFullscreenLabels(expanded);
    validated.toggle.setAttribute("aria-pressed", labels.pressed);
    validated.toggle.setAttribute("aria-label", labels.label);
    validated.toggle.setAttribute("title", labels.label);
    validated.label.textContent = labels.label;
    const icon = validated.toggle.querySelector(".bi");
    if (icon) {
      icon.classList.toggle(labels.iconRemove, false);
      icon.classList.toggle(labels.iconAdd, true);
    }
  }
  function createRosterFullscreenController(report = defaultDiagnosticReporter2) {
    function validatedToggles(root) {
      const toggles = ownedToggles(root);
      const validated = toggles.map((toggle2) => validateToggle(toggle2, report));
      return validated.some((toggle2) => toggle2 === null) ? null : validated;
    }
    function reconcile(root) {
      const state = stateFor2(root, report);
      const toggles = validatedToggles(root);
      if (!state || !toggles) return false;
      toggles.forEach((toggle2) => updateToggle(toggle2, state));
      return true;
    }
    function setState(root, state, focusToggle) {
      if (!stateFor2(root, report)) return false;
      const toggles = validatedToggles(root);
      if (!toggles) return false;
      root.setAttribute(rosterFullscreenDomAttr, state);
      toggles.forEach((toggle2) => updateToggle(toggle2, state));
      if (state === rosterFullscreenStates.expanded && focusToggle) {
        const focus = focusToggle.focus;
        if (typeof focus === "function") focus.call(focusToggle, { preventScroll: true });
      }
      return true;
    }
    function toggle(target) {
      const toggleElement = target.closest(toggleSelector);
      if (!toggleElement || !validateToggle(toggleElement, report)) return false;
      const root = closestRoot(toggleElement);
      if (!root) return false;
      const state = stateFor2(root, report);
      if (!state) return false;
      const nextState = state === rosterFullscreenStates.expanded ? rosterFullscreenStates.collapsed : rosterFullscreenStates.expanded;
      return setState(root, nextState, toggleElement);
    }
    function collapse(root) {
      return setState(root, rosterFullscreenStates.collapsed, null);
    }
    return { reconcile, toggle, collapse };
  }
  function fullscreenRootsWithin(root) {
    const roots = Array.from(root.querySelectorAll(rootSelector));
    if (root instanceof Element) {
      if (root.matches(rootSelector)) roots.unshift(root);
      const owner = closestRoot(root);
      if (owner && !roots.includes(owner)) roots.unshift(owner);
    }
    return roots;
  }
  function enableRosterFullscreenToggle() {
    if (typeof window === "undefined") return;
    const controller = createRosterFullscreenController();
    const reconcileWithin = (root) => fullscreenRootsWithin(root).forEach(controller.reconcile);
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      controller.toggle(event.target);
    });
    document.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") return;
      const focusedRoot = document.activeElement instanceof Element ? closestRoot(document.activeElement) : null;
      const expandedRoot = focusedRoot?.getAttribute(rosterFullscreenDomAttr) === rosterFullscreenStates.expanded ? focusedRoot : document.querySelector(`${rootSelector}[${rosterFullscreenDomAttr}="${rosterFullscreenStates.expanded}"]`);
      if (expandedRoot) controller.collapse(expandedRoot);
    });
    onAppPageReady((event) => reconcileWithin(detailRoot(event, "target")));
    document.addEventListener("htmx:afterSwap", (event) => reconcileWithin(detailRoot(event, "target")));
    if (document.readyState !== "loading") reconcileWithin(document);
  }

  // frontend/ts/shared/exhaustive.ts
  function assertNever(value, message = "Unexpected generated union variant") {
    throw new Error(`${message}: ${JSON.stringify(value)}`);
  }

  // frontend/ts/linked-highlight/runtime.ts
  var sourceHighlightClass = "is-linked-highlight-source";
  var memberHighlightClass = "is-linked-highlight-member";
  var firstMemberHighlightClass = "is-linked-highlight-member-first";
  var lastMemberHighlightClass = "is-linked-highlight-member-last";
  var effectClasses = [
    sourceHighlightClass,
    memberHighlightClass,
    firstMemberHighlightClass,
    lastMemberHighlightClass
  ];
  function createLinkedHighlightController() {
    const statesByMount = /* @__PURE__ */ new WeakMap();
    function stateFor3(mount, definition) {
      let mountStates = statesByMount.get(mount);
      if (!mountStates) {
        mountStates = /* @__PURE__ */ new Map();
        statesByMount.set(mount, mountStates);
      }
      let state = mountStates.get(definition.name);
      if (!state) {
        state = { hoverKey: null, focusKey: null, pinnedKey: null };
        mountStates.set(definition.name, state);
      }
      return state;
    }
    function pointerEntered(target, relatedTarget) {
      const context = sourceContext(target);
      if (!context || !context.definition.activations.includes("hover")) return;
      if (relatedSourceMatches(context, relatedTarget)) return;
      stateFor3(context.mount, context.definition).hoverKey = context.membershipKey;
      refreshMount(context.mount);
    }
    function pointerLeft(target, relatedTarget) {
      const context = sourceContext(target);
      if (!context || !context.definition.activations.includes("hover")) return;
      if (relatedSourceMatches(context, relatedTarget)) return;
      const state = stateFor3(context.mount, context.definition);
      if (state.hoverKey === context.membershipKey) state.hoverKey = null;
      refreshMount(context.mount);
    }
    function focusEntered(target) {
      const context = sourceContext(target);
      if (!context || !context.definition.activations.includes("focus")) return;
      stateFor3(context.mount, context.definition).focusKey = context.membershipKey;
      refreshMount(context.mount);
    }
    function focusLeft(target, relatedTarget) {
      const context = sourceContext(target);
      if (!context || !context.definition.activations.includes("focus")) return;
      if (relatedSourceMatches(context, relatedTarget)) return;
      const state = stateFor3(context.mount, context.definition);
      if (state.focusKey === context.membershipKey) state.focusKey = null;
      refreshMount(context.mount);
    }
    function togglePin(target) {
      const context = pinContext(target);
      if (!context || !context.definition.activations.includes("pin")) return false;
      const state = stateFor3(context.mount, context.definition);
      if (state.pinnedKey === context.membershipKey) {
        state.pinnedKey = null;
        state.hoverKey = null;
        state.focusKey = null;
      } else {
        state.pinnedKey = context.membershipKey;
      }
      refreshMount(context.mount);
      return true;
    }
    function activateKeyboard(target, key) {
      const context = sourceContext(target);
      if (!context || context.source !== target) return false;
      if (!context.definition.activations.includes("keyboard")) return false;
      if (key !== "Enter" && key !== " ") return false;
      context.source.click?.();
      return true;
    }
    function reconcile(root) {
      const queryRoot = root;
      const mounts = Array.from(queryRoot.querySelectorAll(`[${surfaceDomAttr}]`)).filter(isElementLike);
      if (isElementLike(root) && root.getAttribute(surfaceDomAttr) !== null) mounts.unshift(root);
      for (const mount of mounts) {
        for (const definition of definitionsForMount(mount)) {
          const state = stateFor3(mount, definition);
          if (state.pinnedKey && !sourceExists(mount, definition, state.pinnedKey)) state.pinnedKey = null;
          if (state.hoverKey && !sourceExists(mount, definition, state.hoverKey)) state.hoverKey = null;
          if (state.focusKey && !sourceExists(mount, definition, state.focusKey)) state.focusKey = null;
        }
        refreshMount(mount);
      }
    }
    function refreshMount(mount) {
      const definitions = definitionsForMount(mount);
      clearEffectClasses(mount);
      for (const definition of definitions) {
        const state = stateFor3(mount, definition);
        const activeKey = state.pinnedKey ?? state.focusKey ?? state.hoverKey;
        if (activeKey) applyEffects(mount, definition, activeKey);
        syncPinControls(mount, definition, state.pinnedKey);
      }
    }
    return {
      pointerEntered,
      pointerLeft,
      focusEntered,
      focusLeft,
      togglePin,
      activateKeyboard,
      reconcile
    };
  }
  function sourceContext(target) {
    if (!isElementLike(target)) return null;
    const mount = closestSurfaceMount(target);
    if (!mount) return null;
    for (const definition of definitionsForMount(mount)) {
      const source = closestOwnedRole(target, mount, definition.sourceRoleAttribute);
      const membershipKey = source?.getAttribute(definition.sourceRoleAttribute) ?? "";
      if (source && membershipKey !== "") return { mount, definition, source, membershipKey };
    }
    return null;
  }
  function pinContext(target) {
    if (!isElementLike(target)) return null;
    const mount = closestSurfaceMount(target);
    if (!mount) return null;
    for (const definition of definitionsForMount(mount)) {
      if (!definition.pinRoleAttribute) continue;
      const pin = closestOwnedRole(target, mount, definition.pinRoleAttribute);
      const membershipKey = pin?.getAttribute(definition.pinRoleAttribute) ?? "";
      if (pin && membershipKey !== "") return { mount, definition, pin, membershipKey };
    }
    return null;
  }
  function relatedSourceMatches(context, relatedTarget) {
    if (!relatedTarget || !isElementLike(relatedTarget)) return false;
    const relatedSource = closestOwnedRole(relatedTarget, context.mount, context.definition.sourceRoleAttribute);
    return relatedSource?.getAttribute(context.definition.sourceRoleAttribute) === context.membershipKey;
  }
  function closestOwnedRole(target, mount, attribute) {
    const candidate = target.closest(`[${attribute}]`);
    if (!isElementLike(candidate)) return null;
    return closestSurfaceMount(candidate) === mount ? candidate : null;
  }
  function closestSurfaceMount(target) {
    const mount = target.closest(`[${surfaceDomAttr}]`);
    return isElementLike(mount) ? mount : null;
  }
  function definitionsForMount(mount) {
    const surface = mount.getAttribute(surfaceDomAttr);
    return isFrontendSurfaceName(surface) ? FrontendSurfaceLinkedHighlightRegistry[surface] : [];
  }
  function sourceExists(mount, definition, membershipKey) {
    return elementsForKey(mount, definition.sourceRoleAttribute, membershipKey).length > 0;
  }
  function clearEffectClasses(mount) {
    const highlightedElements = /* @__PURE__ */ new Set();
    for (const className of effectClasses) {
      Array.from(mount.querySelectorAll(`.${className}`)).filter(isElementLike).filter((element) => closestSurfaceMount(element) === mount).forEach((element) => highlightedElements.add(element));
    }
    highlightedElements.forEach((element) => element.classList.remove(...effectClasses));
  }
  function applyEffects(mount, definition, membershipKey) {
    const sources = elementsForKey(mount, definition.sourceRoleAttribute, membershipKey);
    const members = elementsForKey(mount, definition.memberRoleAttribute, membershipKey);
    for (const effect of definition.effects) {
      applyEffect(effect, definition, sources, members);
    }
  }
  function applyEffect(effect, definition, sources, members) {
    switch (effect) {
      case "matching-source":
        sources.forEach((source) => source.classList.add(sourceHighlightClass));
        return;
      case "matching-member":
        members.forEach((member) => member.classList.add(memberHighlightClass));
        return;
      case "ordered-member-bounds":
        markOrderedMemberBounds(definition, members);
        return;
      default:
        assertNever(effect);
    }
  }
  function markOrderedMemberBounds(definition, members) {
    if (!definition.orderStateAttribute) return;
    const membersByOrderKey = /* @__PURE__ */ new Map();
    for (const member of members) {
      const orderKey = member.getAttribute(definition.orderStateAttribute);
      if (!orderKey) continue;
      const orderedMembers = membersByOrderKey.get(orderKey) ?? [];
      orderedMembers.push(member);
      membersByOrderKey.set(orderKey, orderedMembers);
    }
    for (const orderedMembers of membersByOrderKey.values()) {
      orderedMembers[0]?.classList.add(firstMemberHighlightClass);
      orderedMembers[orderedMembers.length - 1]?.classList.add(lastMemberHighlightClass);
    }
  }
  function syncPinControls(mount, definition, pinnedKey) {
    if (!definition.pinRoleAttribute) return;
    for (const pin of ownedRoleElements(mount, definition.pinRoleAttribute)) {
      pin.setAttribute("aria-pressed", pin.getAttribute(definition.pinRoleAttribute) === pinnedKey ? "true" : "false");
    }
  }
  function elementsForKey(mount, attribute, membershipKey) {
    return ownedRoleElements(mount, attribute).filter((element) => element.getAttribute(attribute) === membershipKey);
  }
  function ownedRoleElements(mount, attribute) {
    return Array.from(mount.querySelectorAll(`[${attribute}]`)).filter(isElementLike).filter((element) => closestSurfaceMount(element) === mount);
  }
  function isElementLike(value) {
    if (value === null || typeof value !== "object") return false;
    const candidate = value;
    return Boolean(candidate.classList) && typeof candidate.getAttribute === "function" && typeof candidate.setAttribute === "function" && typeof candidate.closest === "function" && typeof candidate.querySelectorAll === "function";
  }
  var browserRuntimeEnabled = false;
  function enableFrontendSurfaceLinkedHighlight() {
    if (browserRuntimeEnabled || typeof document === "undefined") return;
    browserRuntimeEnabled = true;
    const controller = createLinkedHighlightController();
    document.addEventListener("mouseover", (event) => {
      controller.pointerEntered(event.target, relatedElement(event));
    });
    document.addEventListener("mouseout", (event) => {
      controller.pointerLeft(event.target, relatedElement(event));
    });
    document.addEventListener("focusin", (event) => {
      controller.focusEntered(event.target);
    });
    document.addEventListener("focusout", (event) => {
      controller.focusLeft(event.target, relatedElement(event));
    });
    document.addEventListener("click", (event) => {
      if (!controller.togglePin(event.target)) return;
      event.preventDefault();
      event.stopPropagation();
    }, true);
    document.addEventListener("keydown", (event) => {
      if (!controller.activateKeyboard(event.target, event.key)) return;
      event.preventDefault();
    });
    onAppPageReady(() => controller.reconcile(document));
    controller.reconcile(document);
  }
  function relatedElement(event) {
    return isElementLike(event.relatedTarget) ? event.relatedTarget : null;
  }

  // frontend/ts/roster/image-export.ts
  var exportConfigs = {
    jpg: { mimeType: "image/jpeg", extension: "jpg", quality: 0.92 }
  };
  var exportPixelRatio = 2;
  var exportMinWidth = 920;
  var exportMaxWidth = 1240;
  function waitForNextPaint() {
    return new Promise((resolve) => {
      window.requestAnimationFrame(() => {
        window.requestAnimationFrame(() => resolve());
      });
    });
  }
  function sanitizeFilenamePart(value) {
    return (value || "").trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").replace(/-{2,}/g, "-");
  }
  function textOrEmpty(value) {
    return (value || "").trim();
  }
  function replaceCellContents(cellEl, value) {
    const displayValue = textOrEmpty(value);
    cellEl.replaceChildren();
    cellEl.dataset.rosterExportText = displayValue;
    const valueEl = document.createElement("div");
    valueEl.className = "slot-cell-export-value";
    if (!displayValue) {
      valueEl.classList.add("app-muted");
      valueEl.innerHTML = "&nbsp;";
    } else {
      valueEl.textContent = displayValue;
    }
    cellEl.appendChild(valueEl);
    cellEl.removeAttribute("title");
    cellEl.removeAttribute("data-conflict-message");
  }
  function normalizeDayLabelCell(cellEl) {
    cellEl.querySelectorAll("form, button, input, select, textarea").forEach((element) => {
      element.remove();
    });
    cellEl.querySelectorAll(".roster-day-actions, .roster-day-actions-placeholder").forEach((element) => {
      element.remove();
    });
    const lines = Array.from(cellEl.querySelectorAll(".roster-day-date, .roster-day-closed-label")).map((element) => textOrEmpty(element.textContent)).filter(Boolean);
    cellEl.dataset.rosterExportText = lines.join("\n");
  }
  function normalizeExportTable(tableEl) {
    if (!(tableEl instanceof HTMLElement)) {
      throw new Error("Could not clone the current roster grid.");
    }
    tableEl.classList.add("roster-export-grid");
    const theadEl = tableEl.querySelector("thead");
    if (theadEl) {
      theadEl.remove();
    }
    tableEl.querySelectorAll(".day-row").forEach((rowEl) => {
      if (!(rowEl instanceof HTMLElement)) return;
      Array.from(rowEl.querySelectorAll('[role="gridcell"], td')).forEach((cellEl, cellIndex) => {
        if (!(cellEl instanceof HTMLElement)) return;
        if (cellIndex === 0 && cellEl.classList.contains("day-label")) {
          normalizeDayLabelCell(cellEl);
          return;
        }
        if (cellEl.classList.contains("slot-empty-cell") || cellEl.classList.contains("slot-closed-cell")) {
          replaceCellContents(cellEl, "");
          return;
        }
        if (cellEl.classList.contains("slot-time-cell")) {
          const staticValue = cellEl.querySelector(".slot-cell-static");
          replaceCellContents(cellEl, textOrEmpty(staticValue && staticValue.textContent));
          return;
        }
        if (cellEl.classList.contains("slot-staff-cell")) {
          const staticValue = cellEl.querySelector(".slot-cell-static");
          replaceCellContents(cellEl, textOrEmpty(staticValue && staticValue.textContent));
          return;
        }
        if (cellEl.classList.contains("slot-shift-type-cell")) {
          const staticValue = cellEl.querySelector(".slot-cell-static");
          replaceCellContents(cellEl, textOrEmpty(staticValue && staticValue.textContent));
          return;
        }
        replaceCellContents(cellEl, cellEl.textContent || "");
      });
    });
    return tableEl;
  }
  function escapeXml(value) {
    return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }
  function parsePixelValue(value, fallbackValue) {
    const parsed = Number.parseFloat(value || "");
    return Number.isFinite(parsed) ? parsed : fallbackValue;
  }
  function isTransparentColor(colorValue) {
    if (!colorValue) return true;
    const normalizedValue = colorValue.trim().toLowerCase();
    return normalizedValue === "transparent" || normalizedValue === "rgba(0, 0, 0, 0)";
  }
  function buildCellTextSvg(cellEl, x, y, width, height) {
    const lines = (cellEl.dataset.rosterExportText || cellEl.textContent || "").split("\n").map((line) => line.trim()).filter(Boolean);
    if (lines.length === 0) return "";
    const computedStyle = window.getComputedStyle(cellEl);
    const fontSize = parsePixelValue(computedStyle.fontSize, 12);
    const fontWeight = computedStyle.fontWeight || "400";
    const fontFamily = escapeXml(computedStyle.fontFamily || "sans-serif");
    const textColor = computedStyle.color || "#ffffff";
    const textAlign = computedStyle.textAlign || "center";
    const lineHeight = Math.max(fontSize * 1.15, 12);
    const blockHeight = lineHeight * lines.length;
    const startY = y + (height - blockHeight) / 2 + lineHeight * 0.78;
    let textAnchor = "middle";
    let textX = x + width / 2;
    if (textAlign === "left" || textAlign === "start") {
      textAnchor = "start";
      textX = x + 8;
    } else if (textAlign === "right" || textAlign === "end") {
      textAnchor = "end";
      textX = x + width - 8;
    }
    const tspans = lines.map((line, index) => `<tspan x="${textX}" y="${startY + index * lineHeight}">${escapeXml(line)}</tspan>`).join("");
    return `<text font-family="${fontFamily}" font-size="${fontSize}" font-weight="${fontWeight}" fill="${escapeXml(textColor)}" text-anchor="${textAnchor}">${tspans}</text>`;
  }
  function buildTableSvgMarkup(surfaceEl, tableEl) {
    const surfaceRect = surfaceEl.getBoundingClientRect();
    const tableRect = tableEl.getBoundingClientRect();
    const width = Math.ceil(surfaceRect.width);
    const height = Math.ceil(surfaceRect.height);
    const tableLeft = tableRect.left - surfaceRect.left;
    const parts = [
      `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`,
      "<defs>",
      '<linearGradient id="rosterExportBg" x1="0%" y1="0%" x2="0%" y2="100%">',
      '<stop offset="0%" stop-color="#1a2331" />',
      '<stop offset="100%" stop-color="#0f1622" />',
      "</linearGradient>",
      "</defs>",
      `<rect x="0" y="0" width="${width}" height="${height}" fill="url(#rosterExportBg)" />`
    ];
    tableEl.querySelectorAll(".day-row, tbody tr").forEach((rowEl) => {
      if (!(rowEl instanceof HTMLElement)) return;
      const rowRect = rowEl.getBoundingClientRect();
      const rowStyle = window.getComputedStyle(rowEl);
      const rowFill = rowStyle.backgroundColor;
      if (!isTransparentColor(rowFill)) {
        const rowY = rowRect.top - surfaceRect.top;
        parts.push(
          `<rect x="${tableLeft}" y="${rowY}" width="${tableRect.width}" height="${rowRect.height}" fill="${escapeXml(rowFill)}" />`
        );
      }
    });
    tableEl.querySelectorAll('[role="gridcell"], tbody td').forEach((cellEl) => {
      if (!(cellEl instanceof HTMLElement)) return;
      const cellRect = cellEl.getBoundingClientRect();
      const cellStyle = window.getComputedStyle(cellEl);
      const x = cellRect.left - surfaceRect.left;
      const y = cellRect.top - surfaceRect.top;
      const fill = isTransparentColor(cellStyle.backgroundColor) ? "none" : escapeXml(cellStyle.backgroundColor);
      const stroke = escapeXml(cellStyle.borderTopColor || "#3a4658");
      const strokeWidth = Math.max(1, parsePixelValue(cellStyle.borderTopWidth, 1));
      parts.push(
        `<rect x="${x}" y="${y}" width="${cellRect.width}" height="${cellRect.height}" fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}" shape-rendering="crispEdges" />`
      );
      parts.push(buildCellTextSvg(cellEl, x, y, cellRect.width, cellRect.height));
    });
    parts.push("</svg>");
    return { width, height, svgMarkup: parts.join("") };
  }
  async function exportSurfaceToBlob(surfaceEl, tableEl, formatConfig) {
    const renderSpec = buildTableSvgMarkup(surfaceEl, tableEl);
    const svgBlob = new Blob([renderSpec.svgMarkup], { type: "image/svg+xml;charset=utf-8" });
    const svgUrl = URL.createObjectURL(svgBlob);
    try {
      const imageEl = await new Promise((resolve, reject) => {
        const image = new window.Image();
        image.decoding = "async";
        image.onload = () => {
          resolve(image);
        };
        image.onerror = () => {
          reject(new Error("Failed to render roster export image."));
        };
        image.src = svgUrl;
      });
      const canvasEl = document.createElement("canvas");
      canvasEl.width = renderSpec.width * exportPixelRatio;
      canvasEl.height = renderSpec.height * exportPixelRatio;
      const context = canvasEl.getContext("2d");
      if (!context) {
        throw new Error("Failed to initialize roster export canvas.");
      }
      context.scale(exportPixelRatio, exportPixelRatio);
      context.drawImage(imageEl, 0, 0, renderSpec.width, renderSpec.height);
      return await new Promise((resolve, reject) => {
        canvasEl.toBlob((blob) => {
          if (blob) {
            resolve(blob);
            return;
          }
          reject(new Error("Failed to encode roster export image."));
        }, formatConfig.mimeType, formatConfig.quality);
      });
    } finally {
      URL.revokeObjectURL(svgUrl);
    }
  }
  async function buildRosterExportBlob(formatConfig) {
    const rosterTable = document.querySelector(`#${rosterContentDomToken} .roster-grid`);
    if (!(rosterTable instanceof HTMLElement)) {
      throw new Error("Could not find the current roster grid.");
    }
    const exportTable = normalizeExportTable(rosterTable.cloneNode(true));
    const stageEl = document.createElement("div");
    stageEl.className = "roster-export-stage";
    const surfaceEl = document.createElement("div");
    surfaceEl.className = "roster-export-surface";
    const measuredWidth = Math.ceil(rosterTable.getBoundingClientRect().width);
    const exportWidth = Math.max(exportMinWidth, Math.min(exportMaxWidth, measuredWidth));
    surfaceEl.style.width = `${exportWidth}px`;
    surfaceEl.appendChild(exportTable);
    stageEl.appendChild(surfaceEl);
    document.body.appendChild(stageEl);
    try {
      if (document.fonts && typeof document.fonts.ready === "object") {
        await document.fonts.ready;
      }
      await waitForNextPaint();
      return await exportSurfaceToBlob(surfaceEl, exportTable, formatConfig);
    } finally {
      stageEl.remove();
    }
  }
  function exportFilename(formatConfig) {
    const groupSelect = document.getElementById("roster-group-switch");
    const groupLabel = groupSelect instanceof HTMLSelectElement && groupSelect.selectedOptions[0] ? groupSelect.selectedOptions[0].textContent : "group";
    const weekLabelEl = document.querySelector(".roster-week-overview-trigger span:last-child");
    const weekLabel = weekLabelEl ? weekLabelEl.textContent : "week";
    const parts = ["roster", sanitizeFilenamePart(groupLabel || ""), sanitizeFilenamePart(weekLabel || "")].filter(Boolean);
    return `${parts.join("-")}.${formatConfig.extension}`;
  }
  function triggerBlobDownload(blob, filename) {
    const downloadUrl = URL.createObjectURL(blob);
    const linkEl = document.createElement("a");
    linkEl.href = downloadUrl;
    linkEl.download = filename;
    document.body.appendChild(linkEl);
    linkEl.click();
    linkEl.remove();
    window.setTimeout(() => {
      URL.revokeObjectURL(downloadUrl);
    }, 1e3);
  }
  async function handleRosterExport(buttonEl) {
    const formatKey = buttonEl.dataset.rosterExportFormat || "jpg";
    const formatConfig = exportConfigs[formatKey];
    if (!formatConfig) return;
    const originalLabel = buttonEl.textContent;
    buttonEl.dataset.rosterExportStatus = "working";
    document.body.dataset.rosterExportLastStatus = "working";
    buttonEl.disabled = true;
    buttonEl.textContent = "Preparing...";
    try {
      const blob = await buildRosterExportBlob(formatConfig);
      triggerBlobDownload(blob, exportFilename(formatConfig));
      buttonEl.dataset.rosterExportStatus = "success";
      document.body.dataset.rosterExportLastStatus = "success";
      buttonEl.textContent = "Downloaded";
      window.setTimeout(() => {
        buttonEl.textContent = originalLabel;
      }, 1200);
    } catch (error) {
      console.error(error);
      buttonEl.dataset.rosterExportStatus = "error";
      document.body.dataset.rosterExportLastStatus = "error";
      buttonEl.textContent = "Export failed";
      window.setTimeout(() => {
        buttonEl.textContent = originalLabel;
      }, 1600);
      window.alert("Roster export failed. Please try again.");
    } finally {
      window.setTimeout(() => {
        buttonEl.disabled = false;
      }, 200);
    }
  }
  function enableRosterImageExport() {
    if (typeof window === "undefined") return;
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const buttonEl = event.target.closest("[data-roster-export-format]");
      if (!(buttonEl instanceof HTMLButtonElement)) return;
      event.preventDefault();
      void handleRosterExport(buttonEl);
    });
  }

  // frontend/ts/roster/overview.ts
  function rosterOverviewSummaryFromDayDataset(dataset) {
    const hasDetails = dataset.weekOverviewDetails === "true";
    const isClosed = dataset.weekOverviewClosed === "true";
    return {
      hasDetails,
      isClosed,
      label: dataset.weekOverviewLabel || "",
      leave: hasDetails ? dataset.weekOverviewLeave || "0" : "\u2014",
      assigned: hasDetails ? dataset.weekOverviewAssigned || "0" : "\u2014",
      hours: hasDetails ? dataset.weekOverviewHours || "0h" : "\u2014",
      summary: dataset.weekOverviewSummary || "",
      weekLabel: `In ${dataset.weekOverviewWeekLabel || ""}`,
      url: dataset.weekOverviewUrl || ""
    };
  }

  // frontend/ts/shared/surface-mount.ts
  function surfaceMountsWithin(root) {
    const queryRoot = root;
    const mounts = Array.from(queryRoot.querySelectorAll(`[${surfaceDomAttr}]`)).filter(isSurfaceElementLike);
    if (isSurfaceElementLike(root)) {
      const ownerMount = closestSurfaceMount2(root);
      if (ownerMount && !mounts.includes(ownerMount)) mounts.unshift(ownerMount);
    }
    return mounts;
  }
  function surfaceDefinitionsForMount(mount, registry) {
    const surface = mount.getAttribute(surfaceDomAttr);
    return isFrontendSurfaceName(surface) ? registry[surface] : [];
  }
  function ownedSurfaceRoleElements(owner, mount, attribute) {
    return Array.from(owner.querySelectorAll(`[${attribute}]`)).filter(isSurfaceElementLike).filter((element) => closestSurfaceMount2(element) === mount);
  }
  function closestOwnedSurfaceRole(target, mount, attribute) {
    const candidate = target.closest(`[${attribute}]`);
    return isSurfaceElementLike(candidate) && closestSurfaceMount2(candidate) === mount ? candidate : null;
  }
  function closestSurfaceRole(target, attribute) {
    const candidate = target.closest(`[${attribute}]`);
    return isSurfaceElementLike(candidate) ? candidate : null;
  }
  function closestSurfaceMount2(target) {
    const mount = target.closest(`[${surfaceDomAttr}]`);
    return isSurfaceElementLike(mount) ? mount : null;
  }
  function isSurfaceElementLike(value) {
    if (value === null || typeof value !== "object") return false;
    const candidate = value;
    return typeof candidate.appendChild === "function" && typeof candidate.getAttribute === "function" && typeof candidate.setAttribute === "function" && typeof candidate.closest === "function" && typeof candidate.querySelectorAll === "function";
  }
  function surfaceRootFromPageReadyEvent(event) {
    const target = event.detail?.target;
    return target instanceof Element || target instanceof Document ? target : document;
  }

  // frontend/ts/complete-set-sort/runtime.ts
  function defaultDiagnosticReporter3(diagnostic5) {
    console.error?.("Invalid generated complete-set sort boundary", diagnostic5);
  }
  function diagnostic3(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function createCompleteSetSortController(report = defaultDiagnosticReporter3) {
    const statesByRoot = /* @__PURE__ */ new WeakMap();
    function stateFor3(root, definition) {
      let rootStates = statesByRoot.get(root);
      if (!rootStates) {
        rootStates = /* @__PURE__ */ new Map();
        statesByRoot.set(root, rootStates);
      }
      let state = rootStates.get(definition.name);
      if (!state) {
        state = { key: definition.defaultKey, direction: definition.defaultDirection };
        rootStates.set(definition.name, state);
      }
      return state;
    }
    function reconcile(root) {
      for (const mount of surfaceMountsWithin(root)) {
        for (const definition of definitionsForMount2(mount)) {
          for (const sortRoot of ownedSurfaceRoleElements(mount, mount, definition.rootRoleAttribute)) {
            if (sortRoot.getAttribute(definition.rootRoleAttribute) !== "true") {
              report(diagnostic3(sortRoot, "invalid-root-role", "Complete-set sort root role must equal true"));
              continue;
            }
            const state = stateFor3(sortRoot, definition);
            applySort({ mount, root: sortRoot, definition }, state);
          }
        }
      }
    }
    function activate(target) {
      if (!isSurfaceElementLike(target)) return false;
      const mount = closestSurfaceMount2(target);
      if (!mount) return false;
      for (const definition of definitionsForMount2(mount)) {
        const control = closestOwnedSurfaceRole(target, mount, definition.controlRoleAttribute);
        if (!control) continue;
        const sortRoot = closestSurfaceRole(control, definition.rootRoleAttribute);
        if (!sortRoot || closestSurfaceMount2(sortRoot) !== mount) continue;
        const rawKey = control.getAttribute(definition.controlRoleAttribute);
        const key = rawKey !== null && definition.isKey(rawKey) ? definition.keys.find((candidate) => candidate.key === rawKey) : void 0;
        if (!key) {
          report(diagnostic3(control, "invalid-control-key", "Complete-set sort control has an undeclared key"));
          return false;
        }
        const current = stateFor3(sortRoot, definition);
        const next = {
          key: key.key,
          direction: current.key === key.key ? oppositeDirection(current.direction) : definition.defaultDirection
        };
        if (!applySort({ mount, root: sortRoot, definition }, next)) return false;
        const rootStates = statesByRoot.get(sortRoot);
        rootStates?.set(definition.name, next);
        return true;
      }
      return false;
    }
    function applySort(context, state) {
      const key = context.definition.keys.find((candidate) => candidate.key === state.key);
      if (!key) {
        report(diagnostic3(context.root, "missing-default-key", "Complete-set sort definition has no matching active key"));
        return false;
      }
      const rows = [];
      for (const row of ownedSurfaceRoleElements(context.root, context.mount, context.definition.rowRoleAttribute)) {
        const raw = row.getAttribute(context.definition.rowRoleAttribute);
        try {
          if (raw === null) throw new Error(`Missing ${context.definition.rowRoleAttribute}`);
          rows.push({ element: row, value: context.definition.parseRow(JSON.parse(raw)) });
        } catch (error) {
          report(diagnostic3(
            row,
            "invalid-row-payload",
            error instanceof Error ? error.message : String(error)
          ));
          return false;
        }
      }
      const rowParent = rows[0]?.element.parentElement ?? null;
      if (rows.some((row) => row.element.parentElement !== rowParent) || rows.length > 0 && rowParent === null) {
        report(diagnostic3(context.root, "invalid-row-parent", "Complete-set sort rows must share one local parent"));
        return false;
      }
      try {
        rows.sort((left, right) => compareRows(left.value, right.value, key.comparators, state.direction));
      } catch (error) {
        report(diagnostic3(
          context.root,
          "invalid-comparator-value",
          error instanceof Error ? error.message : String(error)
        ));
        return false;
      }
      if (rowParent) rows.forEach((row) => rowParent.appendChild(row.element));
      syncControlStates(context, state);
      return true;
    }
    return { activate, reconcile };
  }
  function compareRows(left, right, comparators, selectedDirection) {
    for (const comparator of comparators) {
      const result = compareValues(
        comparator.read(left),
        comparator.read(right),
        comparator.valueType,
        comparator.field
      );
      if (result === 0) continue;
      return comparator.direction === "selected" ? result * directionMultiplier(selectedDirection) : result;
    }
    return 0;
  }
  function compareValues(left, right, valueType, field) {
    switch (valueType) {
      case "text":
        if (typeof left !== "string" || typeof right !== "string") {
          throw new Error(`Complete-set sort text comparator ${field} received a non-text value`);
        }
        return left.localeCompare(right, void 0, { sensitivity: "base" });
      case "integer":
        if (!Number.isInteger(left) || !Number.isInteger(right)) {
          throw new Error(`Complete-set sort integer comparator ${field} received a non-integer value`);
        }
        return left - right;
      case "opaque":
        if (typeof left !== "string" || typeof right !== "string") {
          throw new Error(`Complete-set sort opaque comparator ${field} received a non-text value`);
        }
        return left === right ? 0 : left < right ? -1 : 1;
      default:
        return assertNever(valueType);
    }
  }
  function directionMultiplier(direction) {
    switch (direction) {
      case "ascending":
        return 1;
      case "descending":
        return -1;
      default:
        return assertNever(direction);
    }
  }
  function oppositeDirection(direction) {
    switch (direction) {
      case "ascending":
        return "descending";
      case "descending":
        return "ascending";
      default:
        return assertNever(direction);
    }
  }
  function syncControlStates(context, state) {
    for (const control of ownedSurfaceRoleElements(context.root, context.mount, context.definition.controlRoleAttribute)) {
      const rawKey = control.getAttribute(context.definition.controlRoleAttribute);
      const isActive = context.definition.isKey(rawKey) && rawKey === state.key;
      const ariaSort = isActive ? state.direction : "none";
      control.setAttribute("aria-sort", ariaSort);
      const header = control.closest("th");
      if (isSurfaceElementLike(header) && closestSurfaceRole(header, context.definition.rootRoleAttribute) === context.root) {
        header.setAttribute("aria-sort", ariaSort);
      }
    }
  }
  function definitionsForMount2(mount) {
    return surfaceDefinitionsForMount(mount, FrontendSurfaceCompleteSetSortRegistry);
  }
  var browserRuntimeEnabled2 = false;
  function enableFrontendSurfaceCompleteSetSort() {
    if (browserRuntimeEnabled2 || typeof document === "undefined") return;
    browserRuntimeEnabled2 = true;
    const controller = createCompleteSetSortController();
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      controller.activate(event.target);
    });
    onAppPageReady((event) => controller.reconcile(surfaceRootFromPageReadyEvent(event)));
    controller.reconcile(document);
  }

  // frontend/ts/surface-tab-set/runtime.ts
  function defaultShowTab(element) {
    if (!(element instanceof HTMLElement)) return;
    window.bootstrap?.Tab?.getOrCreateInstance(element).show();
  }
  function defaultDiagnosticReporter4(diagnostic5) {
    console.error?.("Invalid generated Surface tab-set boundary", diagnostic5);
  }
  function diagnostic4(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function createSurfaceTabSetController(showTab = defaultShowTab, report = defaultDiagnosticReporter4) {
    const activeKeysByMount = /* @__PURE__ */ new WeakMap();
    function rememberedKey(mount, definition) {
      return activeKeysByMount.get(mount)?.get(definition.name) ?? definition.defaultKey;
    }
    function setRememberedKey(mount, definition, key) {
      let activeKeys = activeKeysByMount.get(mount);
      if (!activeKeys) {
        activeKeys = /* @__PURE__ */ new Map();
        activeKeysByMount.set(mount, activeKeys);
      }
      activeKeys.set(definition.name, key);
    }
    function remember(target) {
      if (!isSurfaceElementLike(target)) return false;
      const mount = closestSurfaceMount2(target);
      if (!mount) return false;
      for (const definition of definitionsForMount3(mount)) {
        const tab = closestOwnedSurfaceRole(target, mount, definition.tabRoleAttribute);
        if (!tab) continue;
        const key = tab.getAttribute(definition.tabRoleAttribute);
        if (key === null || !definition.isKey(key)) {
          report(diagnostic4(tab, "invalid-tab-key", "Surface tab has an undeclared key"));
          return false;
        }
        setRememberedKey(mount, definition, key);
        return true;
      }
      return false;
    }
    function reconcile(root) {
      for (const mount of surfaceMountsWithin(root)) {
        for (const definition of definitionsForMount3(mount)) {
          const tabs = ownedSurfaceRoleElements(mount, mount, definition.tabRoleAttribute);
          const tabsByKey = /* @__PURE__ */ new Map();
          let valid = true;
          for (const tab of tabs) {
            const key = tab.getAttribute(definition.tabRoleAttribute);
            if (key === null || !definition.isKey(key)) {
              report(diagnostic4(tab, "invalid-tab-key", "Surface tab has an undeclared key"));
              valid = false;
              continue;
            }
            const matchingTabs = tabsByKey.get(key) ?? [];
            matchingTabs.push(tab);
            tabsByKey.set(key, matchingTabs);
          }
          for (const [key, matchingTabs] of tabsByKey) {
            if (matchingTabs.length <= 1) continue;
            report(diagnostic4(mount, "duplicate-tab-key", `Surface tab set renders key ${key} more than once`));
            valid = false;
          }
          if (!valid) continue;
          const remembered = rememberedKey(mount, definition);
          const desiredKey = tabsByKey.has(remembered) ? remembered : definition.defaultKey;
          if (desiredKey !== remembered) {
            report(diagnostic4(mount, "missing-tab-key", `Surface tab set is missing rendered key ${remembered}; restoring ${desiredKey}`));
            setRememberedKey(mount, definition, desiredKey);
          }
          const desiredTabs = tabsByKey.get(desiredKey) ?? [];
          if (desiredTabs.length === 0) {
            report(diagnostic4(mount, "missing-tab-key", `Surface tab set is missing rendered default key ${definition.defaultKey}`));
            continue;
          }
          const desiredTab = desiredTabs[0];
          if (desiredTab?.getAttribute("aria-selected") === "true") continue;
          showTab(desiredTab);
        }
      }
    }
    return { remember, reconcile };
  }
  function definitionsForMount3(mount) {
    return surfaceDefinitionsForMount(mount, FrontendSurfaceTabSetRegistry);
  }
  var browserRuntimeEnabled3 = false;
  function enableFrontendSurfaceTabSets() {
    if (browserRuntimeEnabled3 || typeof document === "undefined") return;
    browserRuntimeEnabled3 = true;
    const controller = createSurfaceTabSetController();
    document.addEventListener("shown.bs.tab", (event) => {
      if (!(event.target instanceof Element)) return;
      controller.remember(event.target);
    });
    onAppPageReady((event) => controller.reconcile(surfaceRootFromPageReadyEvent(event)));
    document.addEventListener("htmx:afterSettle", () => controller.reconcile(document));
    controller.reconcile(document);
  }

  // frontend/ts/roster/week-overview.ts
  function updateOverviewSelection(panelEl, dayButton) {
    if (!(panelEl instanceof HTMLElement) || !(dayButton instanceof HTMLElement)) return;
    panelEl.querySelectorAll('[data-week-overview-day="true"]').forEach((button) => {
      if (button instanceof HTMLElement) {
        button.classList.toggle("is-selected", button === dayButton);
        button.setAttribute("aria-pressed", button === dayButton ? "true" : "false");
      }
    });
    const selectedLabel = panelEl.querySelector('[data-week-overview-selected-label="true"]');
    const leaveValue = panelEl.querySelector('[data-week-overview-leave-value="true"]');
    const assignedValue = panelEl.querySelector('[data-week-overview-assigned-value="true"]');
    const hoursValue = panelEl.querySelector('[data-week-overview-hours-value="true"]');
    const summaryText = panelEl.querySelector('[data-week-overview-summary-text="true"]');
    const weekLabel = panelEl.querySelector('[data-week-overview-week-label="true"]');
    const goLink = panelEl.querySelector('[data-week-overview-go-link="true"]');
    const detailsPanel = panelEl.querySelector('[data-week-overview-details-panel="true"]');
    const summary = rosterOverviewSummaryFromDayDataset(dayButton.dataset);
    if (selectedLabel) selectedLabel.textContent = summary.label;
    if (leaveValue) leaveValue.textContent = summary.leave;
    if (assignedValue) assignedValue.textContent = summary.assigned;
    if (hoursValue) hoursValue.textContent = summary.hours;
    if (summaryText) summaryText.textContent = summary.summary;
    if (weekLabel) weekLabel.textContent = summary.weekLabel;
    if (goLink instanceof HTMLAnchorElement && summary.url) {
      goLink.href = summary.url;
    }
    if (detailsPanel instanceof HTMLElement) {
      detailsPanel.classList.toggle("is-unloaded", !summary.hasDetails);
      detailsPanel.classList.toggle("is-closed", summary.isClosed);
    }
  }
  function selectToday(panelEl) {
    if (!(panelEl instanceof HTMLElement)) return;
    const today = panelEl.dataset.weekOverviewCurrentDate;
    if (!today) return;
    const button = panelEl.querySelector(`[data-week-overview-day="true"][data-week-overview-date="${CSS.escape(today)}"]`);
    if (button instanceof HTMLElement) {
      updateOverviewSelection(panelEl, button);
    }
  }
  function enableRosterWeekOverview() {
    if (typeof window === "undefined") return;
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const dayButton = event.target.closest('[data-week-overview-day="true"]');
      if (dayButton instanceof HTMLElement) {
        const panelEl = dayButton.closest('[data-week-overview-panel="true"]');
        updateOverviewSelection(panelEl, dayButton);
        return;
      }
      const todayButton = event.target.closest('[data-week-overview-today="true"]');
      if (todayButton instanceof HTMLElement) {
        const panelEl = todayButton.closest('[data-week-overview-panel="true"]');
        selectToday(panelEl);
      }
    });
    document.addEventListener("shown.bs.dropdown", (event) => {
      const trigger = event.target;
      if (!(trigger instanceof HTMLElement)) return;
      const panelEl = trigger.parentElement?.querySelector('[data-week-overview-panel="true"]');
      if (!(panelEl instanceof HTMLElement)) return;
      const selectedButton = panelEl.querySelector('[data-week-overview-day="true"].is-selected');
      if (selectedButton instanceof HTMLElement) {
        updateOverviewSelection(panelEl, selectedButton);
      }
    });
  }

  // frontend/ts/app-roster.ts
  enableRosterWeekOverview();
  enableRosterFullscreenToggle();
  enableRosterColumnEditMode();
  enableRosterImageExport();
  enableFrontendSurfaceCompleteSetSort();
  enableFrontendSurfaceTabSets();
  enableFrontendSurfaceLinkedHighlight();
})();
