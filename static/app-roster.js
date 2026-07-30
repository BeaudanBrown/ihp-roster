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
  function isRosterImageExportConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["imageExportFilename", "imageExportMimeType", "imageExportQualityPercent", "imageExportPixelRatio", "imageExportMinimumWidth", "imageExportMaximumWidth", "imageExportIdleLabel", "imageExportPreparingLabel", "imageExportDownloadedLabel", "imageExportFailedLabel", "imageExportFailureMessage", "imageExportMissingProjectionMessage", "imageExportCloneFailureMessage", "imageExportRenderFailureMessage", "imageExportCanvasFailureMessage", "imageExportEncodingFailureMessage"], ["imageExportFilename", "imageExportMimeType", "imageExportQualityPercent", "imageExportPixelRatio", "imageExportMinimumWidth", "imageExportMaximumWidth", "imageExportIdleLabel", "imageExportPreparingLabel", "imageExportDownloadedLabel", "imageExportFailedLabel", "imageExportFailureMessage", "imageExportMissingProjectionMessage", "imageExportCloneFailureMessage", "imageExportRenderFailureMessage", "imageExportCanvasFailureMessage", "imageExportEncodingFailureMessage"]) && typeof value["imageExportFilename"] === "string" && typeof value["imageExportMimeType"] === "string" && (typeof value["imageExportQualityPercent"] === "number" && Number.isInteger(value["imageExportQualityPercent"])) && (typeof value["imageExportPixelRatio"] === "number" && Number.isInteger(value["imageExportPixelRatio"])) && (typeof value["imageExportMinimumWidth"] === "number" && Number.isInteger(value["imageExportMinimumWidth"])) && (typeof value["imageExportMaximumWidth"] === "number" && Number.isInteger(value["imageExportMaximumWidth"])) && typeof value["imageExportIdleLabel"] === "string" && typeof value["imageExportPreparingLabel"] === "string" && typeof value["imageExportDownloadedLabel"] === "string" && typeof value["imageExportFailedLabel"] === "string" && typeof value["imageExportFailureMessage"] === "string" && typeof value["imageExportMissingProjectionMessage"] === "string" && typeof value["imageExportCloneFailureMessage"] === "string" && typeof value["imageExportRenderFailureMessage"] === "string" && typeof value["imageExportCanvasFailureMessage"] === "string" && typeof value["imageExportEncodingFailureMessage"] === "string";
  }
  function parseRosterImageExportConfig(value) {
    if (isRosterImageExportConfig(value)) return value;
    throw new Error("Invalid RosterImageExportConfig");
  }
  function isRosterImageExportCell(value) {
    return isRecord(value) && hasExactKeys(value, ["imageExportText"], ["imageExportText"]) && typeof value["imageExportText"] === "string";
  }
  function parseRosterImageExportCell(value) {
    if (isRosterImageExportCell(value)) return value;
    throw new Error("Invalid RosterImageExportCell");
  }
  function isRosterWeekOverviewPanelConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["weekOverviewCurrentDate"], ["weekOverviewCurrentDate"]) && typeof value["weekOverviewCurrentDate"] === "string";
  }
  function parseRosterWeekOverviewPanelConfig(value) {
    if (isRosterWeekOverviewPanelConfig(value)) return value;
    throw new Error("Invalid RosterWeekOverviewPanelConfig");
  }
  function isRosterWeekOverviewDayConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["weekOverviewDate", "weekOverviewSelectedLabel", "weekOverviewLeaveDisplay", "weekOverviewAssignedDisplay", "weekOverviewHoursDisplay", "weekOverviewSummaryText", "weekOverviewWeekLabel", "weekOverviewNavigationUrl", "weekOverviewAvailability", "weekOverviewClosure"], ["weekOverviewDate", "weekOverviewSelectedLabel", "weekOverviewLeaveDisplay", "weekOverviewAssignedDisplay", "weekOverviewHoursDisplay", "weekOverviewSummaryText", "weekOverviewWeekLabel", "weekOverviewNavigationUrl", "weekOverviewAvailability", "weekOverviewClosure"]) && typeof value["weekOverviewDate"] === "string" && typeof value["weekOverviewSelectedLabel"] === "string" && typeof value["weekOverviewLeaveDisplay"] === "string" && typeof value["weekOverviewAssignedDisplay"] === "string" && typeof value["weekOverviewHoursDisplay"] === "string" && typeof value["weekOverviewSummaryText"] === "string" && typeof value["weekOverviewWeekLabel"] === "string" && typeof value["weekOverviewNavigationUrl"] === "string" && typeof value["weekOverviewAvailability"] === "string" && typeof value["weekOverviewClosure"] === "string";
  }
  function parseRosterWeekOverviewDayConfig(value) {
    if (isRosterWeekOverviewDayConfig(value)) return value;
    throw new Error("Invalid RosterWeekOverviewDayConfig");
  }
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
  var rosterImageExportTriggerDomAttr = "data-bepis-roster-image-export-trigger";
  var rosterImageExportConfigDomAttr = "data-bepis-roster-image-export-config";
  var rosterImageExportProjectionDomAttr = "data-bepis-roster-image-export-projection";
  var rosterImageExportRowDomAttr = "data-bepis-roster-image-export-row";
  var rosterImageExportCellDomAttr = "data-bepis-roster-image-export-cell";
  var rosterWeekOverviewPanelDomAttr = "data-bepis-roster-week-overview-panel";
  var rosterWeekOverviewDayDomAttr = "data-bepis-roster-week-overview-day";
  var rosterWeekOverviewTodayDomAttr = "data-bepis-roster-week-overview-today";
  var rosterWeekOverviewDetailsDomAttr = "data-bepis-roster-week-overview-details";
  var rosterWeekOverviewSelectedLabelDomAttr = "data-bepis-roster-week-overview-selected-label";
  var rosterWeekOverviewLeaveValueDomAttr = "data-bepis-roster-week-overview-leave-value";
  var rosterWeekOverviewAssignedValueDomAttr = "data-bepis-roster-week-overview-assigned-value";
  var rosterWeekOverviewHoursValueDomAttr = "data-bepis-roster-week-overview-hours-value";
  var rosterWeekOverviewSummaryDomAttr = "data-bepis-roster-week-overview-summary";
  var rosterWeekOverviewWeekLabelDomAttr = "data-bepis-roster-week-overview-week-label";
  var rosterWeekOverviewGoLinkDomAttr = "data-bepis-roster-week-overview-go-link";
  var rosterStaffHighlightSourceDomAttr = "data-bepis-roster-staff-highlight-source";
  var rosterStaffHighlightMemberDomAttr = "data-bepis-roster-staff-highlight-member";
  var rosterStaffHighlightPinDomAttr = "data-bepis-roster-staff-highlight-pin";
  var rosterShiftGroupHighlightSourceDomAttr = "data-bepis-roster-shift-group-highlight-source";
  var rosterShiftGroupHighlightMemberDomAttr = "data-bepis-roster-shift-group-highlight-member";
  var rosterFullscreenDomAttr = "data-bepis-roster-fullscreen";
  var rosterColumnEditingDomAttr = "data-bepis-roster-column-editing";
  var rosterImageExportFormatDomAttr = "data-bepis-roster-image-export-format";
  var rosterWeekOverviewAvailabilityDomAttr = "data-bepis-roster-week-overview-availability";
  var rosterWeekOverviewClosureDomAttr = "data-bepis-roster-week-overview-closure";
  var rosterWeekOverviewCalendarDayDomAttr = "data-bepis-roster-week-overview-calendar-day";
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
  var rosterImageExportFormatStates = { "jpg": "jpg" };
  function isRosterImageExportFormatState(value) {
    return typeof value === "string" && ["jpg"].includes(value);
  }
  var rosterWeekOverviewAvailabilityStates = { "loaded": "loaded", "unloaded": "unloaded" };
  function isRosterWeekOverviewAvailabilityState(value) {
    return typeof value === "string" && ["loaded", "unloaded"].includes(value);
  }
  var rosterWeekOverviewClosureStates = { "open": "open", "closed": "closed" };
  function isRosterWeekOverviewClosureState(value) {
    return typeof value === "string" && ["open", "closed"].includes(value);
  }
  var rosterWeekOverviewCalendarDayStates = { "today": "today", "other-day": "other-day" };
  function isRosterWeekOverviewCalendarDayState(value) {
    return typeof value === "string" && ["today", "other-day"].includes(value);
  }
  function isRosterStaffPanelSortKey(value) {
    return typeof value === "string" && ["name", "role", "shifts"].includes(value);
  }
  function isRosterStaffPanelTabsKey(value) {
    return typeof value === "string" && ["staff", "settings"].includes(value);
  }
  var FrontendSurfaceLinkedHighlightRegistry = { "timesheets": [], "roster": [{ "name": "staff-shifts-highlight", "sourceRoleAttribute": rosterStaffHighlightSourceDomAttr, "memberRoleAttribute": rosterStaffHighlightMemberDomAttr, "pinRoleAttribute": rosterStaffHighlightPinDomAttr, "orderStateAttribute": rosterStaffHighlightOrderDomAttr, "activations": ["hover", "focus", "keyboard", "pin"], "effects": ["matching-source", "matching-member", "ordered-member-bounds"] }, { "name": "shift-group-highlight", "sourceRoleAttribute": rosterShiftGroupHighlightSourceDomAttr, "memberRoleAttribute": rosterShiftGroupHighlightMemberDomAttr, "pinRoleAttribute": null, "orderStateAttribute": null, "activations": ["hover", "focus", "keyboard"], "effects": ["matching-member"] }], "roster-day-timeline": [{ "name": "shift-group-highlight", "sourceRoleAttribute": rosterDayTimelineShiftGroupHighlightSourceDomAttr, "memberRoleAttribute": rosterDayTimelineShiftGroupHighlightMemberDomAttr, "pinRoleAttribute": null, "orderStateAttribute": null, "activations": ["hover", "focus", "keyboard"], "effects": ["matching-member"] }], "leave-requests": [], "self-service-leave": [], "billing": [], "support": [], "profile": [], "staff": [], "admin-page": [], "admin-xero-page": [], "admin-venue-config": [], "admin-invites": [], "admin-exports": [], "admin-shift-types": [], "admin-roster-groups": [], "admin-xero": [] };
  var FrontendSurfaceCompleteSetSortRegistry = { "timesheets": [], "roster": [{ "name": "roster-staff-panel-sort", "rootRoleAttribute": rosterStaffPanelSortRootDomAttr, "rowRoleAttribute": rosterStaffPanelSortRowDomAttr, "controlRoleAttribute": rosterStaffPanelSortControlDomAttr, "parseRow": parseRosterStaffPanelSortRow, "isKey": isRosterStaffPanelSortKey, "keys": [{ "key": "name", "comparators": [{ "field": "staffName", "valueType": "text", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffRowKey }] }, { "key": "role", "comparators": [{ "field": "staffRole", "valueType": "text", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).staffRole }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffRowKey }] }, { "key": "shifts", "comparators": [{ "field": "assignedShifts", "valueType": "integer", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).assignedShifts }, { "field": "idealShifts", "valueType": "integer", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).idealShifts }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffRowKey }] }], "defaultKey": "name", "defaultDirection": "ascending" }], "roster-day-timeline": [], "leave-requests": [], "self-service-leave": [], "billing": [], "support": [], "profile": [], "staff": [], "admin-page": [], "admin-xero-page": [], "admin-venue-config": [], "admin-invites": [], "admin-exports": [], "admin-shift-types": [], "admin-roster-groups": [], "admin-xero": [] };
  var FrontendSurfaceTabSetRegistry = { "timesheets": [], "roster": [{ "name": "roster-staff-panel-tabs", "tabRoleAttribute": rosterStaffPanelTabDomAttr, "keys": ["staff", "settings"], "defaultKey": "staff", "isKey": isRosterStaffPanelTabsKey }], "roster-day-timeline": [], "leave-requests": [], "self-service-leave": [], "billing": [], "support": [], "profile": [], "staff": [], "admin-page": [], "admin-xero-page": [], "admin-venue-config": [], "admin-invites": [], "admin-exports": [], "admin-shift-types": [], "admin-roster-groups": [], "admin-xero": [] };
  var FrontendSurfaceFragmentRegistry = { "timesheets": ["timesheet-toolbar", "timesheet-day-columns", "timesheet-day-section"], "roster": ["roster-content", "roster-grid-toolbar", "roster-grid-frame", "roster-day-columns", "roster-day-rail", "roster-wage-rail", "roster-slots-grid", "roster-staff-panel", "roster-day-section", "roster-row"], "roster-day-timeline": ["roster-day-timeline-content"], "leave-requests": ["leave-section-count", "leave-section-list"], "self-service-leave": ["self-service-leave-form", "self-service-leave-history"], "billing": ["billing-status"], "support": ["support-award-rates", "support-public-holidays"], "profile": ["profile-details-section", "profile-preferences-section", "profile-security-section", "profile-leave-section", "profile-rsa-section"], "staff": ["staff-details-section", "staff-preferences-section", "staff-leave-section"], "admin-page": [], "admin-xero-page": [], "admin-venue-config": ["admin-venue-settings"], "admin-invites": ["admin-invites"], "admin-exports": ["admin-exports"], "admin-shift-types": ["admin-shift-types"], "admin-roster-groups": ["admin-roster-groups"], "admin-xero": ["admin-xero-shell"] };
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

  // frontend/ts/shared/lifecycle.ts
  function eventDetailRecord(event) {
    if (typeof CustomEvent === "undefined" || !(event instanceof CustomEvent)) return null;
    if (event.detail === null || typeof event.detail !== "object") return null;
    return event.detail;
  }
  function detailTarget(event, key) {
    return eventDetailRecord(event)?.[key];
  }
  function isConnectedRoot(root) {
    return root instanceof Document || root.isConnected;
  }
  function detailRoot(event, key, fallback = document) {
    const detailCandidate = detailTarget(event, key);
    if (isDomRoot(detailCandidate) && isConnectedRoot(detailCandidate)) return detailCandidate;
    if (isDomRoot(event.target) && isConnectedRoot(event.target)) return event.target;
    return fallback;
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
  function defaultDiagnosticReporter(diagnostic7) {
    console.error?.("Invalid generated roster column-edit boundary", diagnostic7);
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
  function defaultDiagnosticReporter2(diagnostic7) {
    console.error?.("Invalid generated roster fullscreen boundary", diagnostic7);
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

  // frontend/ts/roster/image-export-configuration.ts
  function requireNonEmpty(value, field) {
    if (value.trim().length === 0) {
      throw new Error(`RosterImageExportConfig ${field} must not be empty`);
    }
  }
  function parseRosterImageExportConfiguration(raw) {
    const config = parseRosterImageExportConfig(JSON.parse(raw));
    [
      [config.imageExportFilename, "filename"],
      [config.imageExportMimeType, "MIME type"],
      [config.imageExportIdleLabel, "idle label"],
      [config.imageExportPreparingLabel, "preparing label"],
      [config.imageExportDownloadedLabel, "downloaded label"],
      [config.imageExportFailedLabel, "failed label"],
      [config.imageExportFailureMessage, "failure message"],
      [config.imageExportMissingProjectionMessage, "missing projection message"],
      [config.imageExportCloneFailureMessage, "clone failure message"],
      [config.imageExportRenderFailureMessage, "render failure message"],
      [config.imageExportCanvasFailureMessage, "canvas failure message"],
      [config.imageExportEncodingFailureMessage, "encoding failure message"]
    ].forEach(([value, field]) => requireNonEmpty(value ?? "", field ?? "field"));
    if (config.imageExportQualityPercent < 0 || config.imageExportQualityPercent > 100) {
      throw new Error("RosterImageExportConfig quality percent must be between 0 and 100");
    }
    if (config.imageExportPixelRatio <= 0) {
      throw new Error("RosterImageExportConfig pixel ratio must be positive");
    }
    if (config.imageExportMinimumWidth <= 0 || config.imageExportMaximumWidth < config.imageExportMinimumWidth) {
      throw new Error("RosterImageExportConfig width range is invalid");
    }
    return config;
  }
  function parseRosterImageExportCellConfiguration(raw) {
    return parseRosterImageExportCell(JSON.parse(raw));
  }

  // frontend/ts/roster/image-export.ts
  var triggerSelector = `[${rosterImageExportTriggerDomAttr}]`;
  var projectionSelector = `[${rosterImageExportProjectionDomAttr}]`;
  var rowSelector = `[${rosterImageExportRowDomAttr}]`;
  var cellSelector = `[${rosterImageExportCellDomAttr}]`;
  var surfaceSelector = `[${surfaceDomAttr}]`;
  function defaultDiagnosticReporter3(diagnostic7) {
    console.error?.("Invalid generated roster image-export boundary", diagnostic7);
  }
  function diagnostic3(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function ownedElements(surface, selector) {
    return Array.from(surface.querySelectorAll(selector)).filter((element) => element.closest(surfaceSelector) === surface);
  }
  function readImageExport(button, report) {
    if (button.getAttribute(rosterImageExportTriggerDomAttr) !== "true") {
      report(diagnostic3(button, "invalid-trigger-role", "Roster image-export trigger role must equal true"));
      return null;
    }
    const format = button.getAttribute(rosterImageExportFormatDomAttr);
    if (!isRosterImageExportFormatState(format) || format !== rosterImageExportFormatStates.jpg) {
      report(diagnostic3(button, "invalid-format", "Roster image-export format is not declared by the Surface contract"));
      return null;
    }
    let config;
    try {
      const rawConfig = button.getAttribute(rosterImageExportConfigDomAttr);
      if (rawConfig === null) throw new Error(`Missing ${rosterImageExportConfigDomAttr}`);
      config = parseRosterImageExportConfiguration(rawConfig);
    } catch (error) {
      report(diagnostic3(
        button,
        "invalid-config",
        error instanceof Error ? error.message : String(error)
      ));
      return null;
    }
    const surface = button.closest(surfaceSelector);
    if (surface === null) {
      report(diagnostic3(button, "missing-surface", "Roster image-export trigger has no generated Surface owner"));
      return null;
    }
    const projections = ownedElements(surface, projectionSelector);
    if (projections.length !== 1) {
      report(diagnostic3(
        surface,
        "invalid-projection-count",
        "Roster image-export Surface must contain exactly one generated projection"
      ));
      return null;
    }
    const projection = projections[0];
    if (projection.getAttribute(rosterImageExportProjectionDomAttr) !== "true") {
      report(diagnostic3(projection, "invalid-projection-role", "Roster image-export projection role must equal true"));
      return null;
    }
    return { config, projection };
  }
  function waitForNextPaint() {
    return new Promise((resolve) => {
      window.requestAnimationFrame(() => {
        window.requestAnimationFrame(() => resolve());
      });
    });
  }
  function replaceCellContents(cell, displayValue) {
    const value = displayValue.trim();
    const valueElement = document.createElement("div");
    valueElement.className = "slot-cell-export-value";
    if (value.length === 0) {
      valueElement.classList.add("app-muted");
      valueElement.textContent = "\xA0";
    } else {
      valueElement.textContent = value;
    }
    cell.replaceChildren(valueElement);
    cell.removeAttribute("title");
  }
  function normalizeExportProjection(source, config, report) {
    const cloned = source.cloneNode(true);
    if (!(cloned instanceof HTMLElement)) {
      throw new Error(config.imageExportCloneFailureMessage);
    }
    cloned.classList.add("roster-export-grid");
    for (const row of cloned.querySelectorAll(rowSelector)) {
      if (row.getAttribute(rosterImageExportRowDomAttr) !== "true") {
        report(diagnostic3(row, "invalid-row-role", "Roster image-export row role must equal true"));
        throw new Error(config.imageExportCloneFailureMessage);
      }
    }
    for (const cell of cloned.querySelectorAll(cellSelector)) {
      try {
        const rawCell = cell.getAttribute(rosterImageExportCellDomAttr);
        if (rawCell === null) throw new Error(`Missing ${rosterImageExportCellDomAttr}`);
        const cellConfig = parseRosterImageExportCellConfiguration(rawCell);
        replaceCellContents(cell, cellConfig.imageExportText);
      } catch (error) {
        report(diagnostic3(
          cell,
          "invalid-cell-config",
          error instanceof Error ? error.message : String(error)
        ));
        throw new Error(config.imageExportCloneFailureMessage);
      }
    }
    return cloned;
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
  function buildCellTextSvg(cell, x, y, width, height) {
    const lines = (cell.textContent || "").split("\n").map((line) => line.trim()).filter(Boolean);
    if (lines.length === 0) return "";
    const computedStyle = window.getComputedStyle(cell);
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
  function buildProjectionSvgMarkup(surface, projection) {
    const surfaceRect = surface.getBoundingClientRect();
    const projectionRect = projection.getBoundingClientRect();
    const width = Math.ceil(surfaceRect.width);
    const height = Math.ceil(surfaceRect.height);
    const projectionLeft = projectionRect.left - surfaceRect.left;
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
    projection.querySelectorAll(rowSelector).forEach((row) => {
      const rowRect = row.getBoundingClientRect();
      const rowStyle = window.getComputedStyle(row);
      const rowFill = rowStyle.backgroundColor;
      if (!isTransparentColor(rowFill)) {
        const rowY = rowRect.top - surfaceRect.top;
        parts.push(
          `<rect x="${projectionLeft}" y="${rowY}" width="${projectionRect.width}" height="${rowRect.height}" fill="${escapeXml(rowFill)}" />`
        );
      }
    });
    projection.querySelectorAll(cellSelector).forEach((cell) => {
      const cellRect = cell.getBoundingClientRect();
      const cellStyle = window.getComputedStyle(cell);
      const x = cellRect.left - surfaceRect.left;
      const y = cellRect.top - surfaceRect.top;
      const fill = isTransparentColor(cellStyle.backgroundColor) ? "none" : escapeXml(cellStyle.backgroundColor);
      const stroke = escapeXml(cellStyle.borderTopColor || "#3a4658");
      const strokeWidth = Math.max(1, parsePixelValue(cellStyle.borderTopWidth, 1));
      parts.push(
        `<rect x="${x}" y="${y}" width="${cellRect.width}" height="${cellRect.height}" fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}" shape-rendering="crispEdges" />`
      );
      parts.push(buildCellTextSvg(cell, x, y, cellRect.width, cellRect.height));
    });
    parts.push("</svg>");
    return { width, height, svgMarkup: parts.join("") };
  }
  async function exportSurfaceToBlob(surface, projection, config) {
    const renderSpec = buildProjectionSvgMarkup(surface, projection);
    const svgBlob = new Blob([renderSpec.svgMarkup], { type: "image/svg+xml;charset=utf-8" });
    const svgUrl = URL.createObjectURL(svgBlob);
    try {
      const image = await new Promise((resolve, reject) => {
        const imageElement = new window.Image();
        imageElement.decoding = "async";
        imageElement.onload = () => resolve(imageElement);
        imageElement.onerror = () => reject(new Error(config.imageExportRenderFailureMessage));
        imageElement.src = svgUrl;
      });
      const canvas = document.createElement("canvas");
      canvas.width = renderSpec.width * config.imageExportPixelRatio;
      canvas.height = renderSpec.height * config.imageExportPixelRatio;
      const context = canvas.getContext("2d");
      if (!context) throw new Error(config.imageExportCanvasFailureMessage);
      context.scale(config.imageExportPixelRatio, config.imageExportPixelRatio);
      context.drawImage(image, 0, 0, renderSpec.width, renderSpec.height);
      return await new Promise((resolve, reject) => {
        canvas.toBlob((blob) => {
          if (blob) resolve(blob);
          else reject(new Error(config.imageExportEncodingFailureMessage));
        }, config.imageExportMimeType, config.imageExportQualityPercent / 100);
      });
    } finally {
      URL.revokeObjectURL(svgUrl);
    }
  }
  async function buildRosterExportBlob(source, config, report) {
    if (!source.isConnected) throw new Error(config.imageExportMissingProjectionMessage);
    const projection = normalizeExportProjection(source, config, report);
    const stage = document.createElement("div");
    stage.className = "roster-export-stage";
    const surface = document.createElement("div");
    surface.className = "roster-export-surface";
    const measuredWidth = Math.ceil(source.getBoundingClientRect().width);
    const exportWidth = Math.max(
      config.imageExportMinimumWidth,
      Math.min(config.imageExportMaximumWidth, measuredWidth)
    );
    surface.style.width = `${exportWidth}px`;
    surface.appendChild(projection);
    stage.appendChild(surface);
    document.body.appendChild(stage);
    try {
      if (document.fonts && typeof document.fonts.ready === "object") {
        await document.fonts.ready;
      }
      await waitForNextPaint();
      return await exportSurfaceToBlob(surface, projection, config);
    } finally {
      stage.remove();
    }
  }
  function triggerBlobDownload(blob, filename) {
    const downloadUrl = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = downloadUrl;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(downloadUrl), 1e3);
  }
  async function handleRosterExport(button, validated, report) {
    const { config, projection } = validated;
    button.disabled = true;
    button.textContent = config.imageExportPreparingLabel;
    try {
      const blob = await buildRosterExportBlob(projection, config, report);
      triggerBlobDownload(blob, config.imageExportFilename);
      button.textContent = config.imageExportDownloadedLabel;
      window.setTimeout(() => {
        button.textContent = config.imageExportIdleLabel;
      }, 1200);
    } catch (error) {
      report(diagnostic3(
        button,
        "export-failed",
        error instanceof Error ? error.message : String(error)
      ));
      button.textContent = config.imageExportFailedLabel;
      window.setTimeout(() => {
        button.textContent = config.imageExportIdleLabel;
      }, 1600);
      window.alert(config.imageExportFailureMessage);
    } finally {
      window.setTimeout(() => {
        button.disabled = false;
      }, 200);
    }
  }
  function enableRosterImageExport(report = defaultDiagnosticReporter3) {
    if (typeof window === "undefined") return;
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const button = event.target.closest(triggerSelector);
      if (!(button instanceof HTMLButtonElement)) return;
      event.preventDefault();
      const validated = readImageExport(button, report);
      if (validated !== null) void handleRosterExport(button, validated, report);
    });
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
  function defaultDiagnosticReporter4(diagnostic7) {
    console.error?.("Invalid generated complete-set sort boundary", diagnostic7);
  }
  function diagnostic4(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function createCompleteSetSortController(report = defaultDiagnosticReporter4) {
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
              report(diagnostic4(sortRoot, "invalid-root-role", "Complete-set sort root role must equal true"));
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
          report(diagnostic4(control, "invalid-control-key", "Complete-set sort control has an undeclared key"));
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
        report(diagnostic4(context.root, "missing-default-key", "Complete-set sort definition has no matching active key"));
        return false;
      }
      const rows = [];
      for (const row of ownedSurfaceRoleElements(context.root, context.mount, context.definition.rowRoleAttribute)) {
        const raw = row.getAttribute(context.definition.rowRoleAttribute);
        try {
          if (raw === null) throw new Error(`Missing ${context.definition.rowRoleAttribute}`);
          rows.push({ element: row, value: context.definition.parseRow(JSON.parse(raw)) });
        } catch (error) {
          report(diagnostic4(
            row,
            "invalid-row-payload",
            error instanceof Error ? error.message : String(error)
          ));
          return false;
        }
      }
      const rowParent = rows[0]?.element.parentElement ?? null;
      if (rows.some((row) => row.element.parentElement !== rowParent) || rows.length > 0 && rowParent === null) {
        report(diagnostic4(context.root, "invalid-row-parent", "Complete-set sort rows must share one local parent"));
        return false;
      }
      try {
        rows.sort((left, right) => compareRows(left.value, right.value, key.comparators, state.direction));
      } catch (error) {
        report(diagnostic4(
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
  function tabPresentationMatchesSelection(element) {
    if (typeof HTMLElement === "undefined" || !(element instanceof HTMLElement)) {
      return element.getAttribute("aria-selected") === "true";
    }
    const paneSelector = element.getAttribute("data-bs-target");
    if (paneSelector === null || !paneSelector.startsWith("#")) return false;
    const pane = document.querySelector(paneSelector);
    return element.classList.contains("active") && pane?.classList.contains("active") === true && pane.classList.contains("show");
  }
  function defaultShowTab(element) {
    if (!(element instanceof HTMLElement)) return;
    if (element.getAttribute("aria-selected") === "true" && !tabPresentationMatchesSelection(element)) {
      element.classList.remove("active");
      element.setAttribute("aria-selected", "false");
    }
    window.bootstrap?.Tab?.getOrCreateInstance(element).show();
  }
  function defaultDiagnosticReporter5(diagnostic7) {
    console.error?.("Invalid generated Surface tab-set boundary", diagnostic7);
  }
  function diagnostic5(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function createSurfaceTabSetController(showTab = defaultShowTab, report = defaultDiagnosticReporter5) {
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
          report(diagnostic5(tab, "invalid-tab-key", "Surface tab has an undeclared key"));
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
          if (tabs.length === 0) continue;
          const tabsByKey = /* @__PURE__ */ new Map();
          let valid = true;
          for (const tab of tabs) {
            const key = tab.getAttribute(definition.tabRoleAttribute);
            if (key === null || !definition.isKey(key)) {
              report(diagnostic5(tab, "invalid-tab-key", "Surface tab has an undeclared key"));
              valid = false;
              continue;
            }
            const matchingTabs = tabsByKey.get(key) ?? [];
            matchingTabs.push(tab);
            tabsByKey.set(key, matchingTabs);
          }
          for (const [key, matchingTabs] of tabsByKey) {
            if (matchingTabs.length <= 1) continue;
            report(diagnostic5(mount, "duplicate-tab-key", `Surface tab set renders key ${key} more than once`));
            valid = false;
          }
          if (!valid) continue;
          const remembered = rememberedKey(mount, definition);
          const desiredKey = tabsByKey.has(remembered) ? remembered : definition.defaultKey;
          if (desiredKey !== remembered) {
            report(diagnostic5(mount, "missing-tab-key", `Surface tab set is missing rendered key ${remembered}; restoring ${desiredKey}`));
            setRememberedKey(mount, definition, desiredKey);
          }
          const desiredTabs = tabsByKey.get(desiredKey) ?? [];
          if (desiredTabs.length === 0) {
            report(diagnostic5(mount, "missing-tab-key", `Surface tab set is missing rendered default key ${definition.defaultKey}`));
            continue;
          }
          const desiredTab = desiredTabs[0];
          if (desiredTab && tabPresentationMatchesSelection(desiredTab)) continue;
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

  // frontend/ts/roster/week-overview-configuration.ts
  function parseRosterWeekOverviewPanelConfiguration(raw) {
    return parseRosterWeekOverviewPanelConfig(JSON.parse(raw));
  }
  function parseRosterWeekOverviewDayConfiguration(raw) {
    const config = parseRosterWeekOverviewDayConfig(JSON.parse(raw));
    if (!isRosterWeekOverviewAvailabilityState(config.weekOverviewAvailability) || config.weekOverviewAvailability !== rosterWeekOverviewAvailabilityStates.loaded && config.weekOverviewAvailability !== rosterWeekOverviewAvailabilityStates.unloaded) {
      throw new Error("RosterWeekOverviewDayConfig availability state is not declared");
    }
    if (!isRosterWeekOverviewClosureState(config.weekOverviewClosure) || config.weekOverviewClosure !== rosterWeekOverviewClosureStates.open && config.weekOverviewClosure !== rosterWeekOverviewClosureStates.closed) {
      throw new Error("RosterWeekOverviewDayConfig closure state is not declared");
    }
    return config;
  }

  // frontend/ts/roster/week-overview.ts
  var panelSelector = `[${rosterWeekOverviewPanelDomAttr}]`;
  var daySelector = `[${rosterWeekOverviewDayDomAttr}]`;
  var todaySelector = `[${rosterWeekOverviewTodayDomAttr}]`;
  function roleSelector(attribute) {
    return `[${attribute}]`;
  }
  function defaultDiagnosticReporter6(diagnostic7) {
    console.error?.("Invalid generated roster week-overview boundary", diagnostic7);
  }
  function diagnostic6(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function ownedElements2(panel, attribute) {
    return Array.from(panel.querySelectorAll(roleSelector(attribute))).filter((element) => element.closest(panelSelector) === panel);
  }
  function readPanel(panel, report) {
    try {
      const raw = panel.getAttribute(rosterWeekOverviewPanelDomAttr);
      if (raw === null) throw new Error(`Missing ${rosterWeekOverviewPanelDomAttr}`);
      return parseRosterWeekOverviewPanelConfiguration(raw);
    } catch (error) {
      report(diagnostic6(
        panel,
        "invalid-panel-config",
        error instanceof Error ? error.message : String(error)
      ));
      return null;
    }
  }
  function readDay(day, report) {
    try {
      const raw = day.getAttribute(rosterWeekOverviewDayDomAttr);
      if (raw === null) throw new Error(`Missing ${rosterWeekOverviewDayDomAttr}`);
      const config = parseRosterWeekOverviewDayConfiguration(raw);
      const calendarDay = day.getAttribute(rosterWeekOverviewCalendarDayDomAttr);
      const calendarDayIsDeclared = isRosterWeekOverviewCalendarDayState(calendarDay) && (calendarDay === rosterWeekOverviewCalendarDayStates.today || calendarDay === rosterWeekOverviewCalendarDayStates["other-day"]);
      if (day.getAttribute(rosterWeekOverviewAvailabilityDomAttr) !== config.weekOverviewAvailability || day.getAttribute(rosterWeekOverviewClosureDomAttr) !== config.weekOverviewClosure || !calendarDayIsDeclared) {
        report(diagnostic6(day, "invalid-day-state", "Week-overview day states must agree with its exact payload"));
        return null;
      }
      return config;
    } catch (error) {
      report(diagnostic6(
        day,
        "invalid-day-config",
        error instanceof Error ? error.message : String(error)
      ));
      return null;
    }
  }
  function readSingleSlot(panel, attribute, report) {
    const slots = ownedElements2(panel, attribute);
    if (slots.length !== 1) {
      report(diagnostic6(panel, "invalid-slot-count", `Week-overview panel requires exactly one ${attribute} slot`));
      return null;
    }
    const slot = slots[0];
    if (slot.getAttribute(attribute) !== "true") {
      report(diagnostic6(slot, "invalid-slot-role", `Week-overview slot ${attribute} must equal true`));
      return null;
    }
    return slot;
  }
  function readOptionalSlot(panel, attribute, report) {
    const slots = ownedElements2(panel, attribute);
    if (slots.length > 1) {
      report(diagnostic6(panel, "invalid-slot-count", `Week-overview panel permits at most one ${attribute} slot`));
      return false;
    }
    const slot = slots[0] ?? null;
    if (slot !== null && slot.getAttribute(attribute) !== "true") {
      report(diagnostic6(slot, "invalid-slot-role", `Week-overview slot ${attribute} must equal true`));
      return false;
    }
    return slot;
  }
  function readSlots(panel, report) {
    const selectedLabel = readSingleSlot(panel, rosterWeekOverviewSelectedLabelDomAttr, report);
    const leaveValue = readOptionalSlot(panel, rosterWeekOverviewLeaveValueDomAttr, report);
    const assignedValue = readSingleSlot(panel, rosterWeekOverviewAssignedValueDomAttr, report);
    const hoursValue = readSingleSlot(panel, rosterWeekOverviewHoursValueDomAttr, report);
    const summary = readSingleSlot(panel, rosterWeekOverviewSummaryDomAttr, report);
    const weekLabel = readSingleSlot(panel, rosterWeekOverviewWeekLabelDomAttr, report);
    const goLinkElement = readSingleSlot(panel, rosterWeekOverviewGoLinkDomAttr, report);
    const details = readSingleSlot(panel, rosterWeekOverviewDetailsDomAttr, report);
    if (selectedLabel === null || leaveValue === false || assignedValue === null || hoursValue === null || summary === null || weekLabel === null || goLinkElement === null || details === null) return null;
    if (goLinkElement.tagName !== "A") {
      report(diagnostic6(goLinkElement, "invalid-go-link", "Week-overview go-link slot must be an anchor"));
      return null;
    }
    if (!isRosterWeekOverviewAvailabilityState(details.getAttribute(rosterWeekOverviewAvailabilityDomAttr)) || !isRosterWeekOverviewClosureState(details.getAttribute(rosterWeekOverviewClosureDomAttr))) {
      report(diagnostic6(details, "invalid-details-state", "Week-overview details states must be generated values"));
      return null;
    }
    return {
      selectedLabel,
      leaveValue,
      assignedValue,
      hoursValue,
      summary,
      weekLabel,
      goLink: goLinkElement,
      details
    };
  }
  function updateRosterWeekOverviewSelection(panel, selectedDay, report = defaultDiagnosticReporter6) {
    if (selectedDay.closest(panelSelector) !== panel) {
      report(diagnostic6(selectedDay, "day-outside-panel", "Week-overview day is not owned by this panel"));
      return false;
    }
    if (readPanel(panel, report) === null) return false;
    const selectedConfig = readDay(selectedDay, report);
    if (selectedConfig === null) return false;
    const slots = readSlots(panel, report);
    if (slots === null) return false;
    const validDays = /* @__PURE__ */ new Map();
    for (const day of ownedElements2(panel, rosterWeekOverviewDayDomAttr)) {
      const config = day === selectedDay ? selectedConfig : readDay(day, report);
      if (config !== null) validDays.set(day, config);
    }
    validDays.forEach((_config, day) => {
      day.setAttribute("aria-pressed", day === selectedDay ? "true" : "false");
    });
    slots.selectedLabel.textContent = selectedConfig.weekOverviewSelectedLabel;
    if (slots.leaveValue !== null) slots.leaveValue.textContent = selectedConfig.weekOverviewLeaveDisplay;
    slots.assignedValue.textContent = selectedConfig.weekOverviewAssignedDisplay;
    slots.hoursValue.textContent = selectedConfig.weekOverviewHoursDisplay;
    slots.summary.textContent = selectedConfig.weekOverviewSummaryText;
    slots.weekLabel.textContent = selectedConfig.weekOverviewWeekLabel;
    slots.goLink.href = selectedConfig.weekOverviewNavigationUrl;
    slots.details.setAttribute(rosterWeekOverviewAvailabilityDomAttr, selectedConfig.weekOverviewAvailability);
    slots.details.setAttribute(rosterWeekOverviewClosureDomAttr, selectedConfig.weekOverviewClosure);
    return true;
  }
  function selectToday(panel, report) {
    const panelConfig = readPanel(panel, report);
    if (panelConfig === null) return false;
    for (const day of ownedElements2(panel, rosterWeekOverviewDayDomAttr)) {
      const config = readDay(day, report);
      if (config?.weekOverviewDate === panelConfig.weekOverviewCurrentDate) {
        return updateRosterWeekOverviewSelection(panel, day, report);
      }
    }
    report(diagnostic6(panel, "missing-today-day", "Week-overview panel has no valid day for its Haskell-provided current date"));
    return false;
  }
  function panelForControl(control) {
    const panel = control.closest(panelSelector);
    return panel instanceof HTMLElement ? panel : null;
  }
  function enableRosterWeekOverview(report = defaultDiagnosticReporter6) {
    if (typeof window === "undefined") return;
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const day = event.target.closest(daySelector);
      if (day instanceof HTMLElement) {
        const panel = panelForControl(day);
        if (panel !== null) updateRosterWeekOverviewSelection(panel, day, report);
        return;
      }
      const today = event.target.closest(todaySelector);
      if (today instanceof HTMLElement) {
        if (today.getAttribute(rosterWeekOverviewTodayDomAttr) !== "true") {
          report(diagnostic6(today, "invalid-today-role", "Week-overview today role must equal true"));
          return;
        }
        const panel = panelForControl(today);
        if (panel !== null) selectToday(panel, report);
      }
    });
    document.addEventListener("shown.bs.dropdown", (event) => {
      const trigger = event.target;
      if (!(trigger instanceof HTMLElement) || trigger.parentElement === null) return;
      const panels = Array.from(trigger.parentElement.querySelectorAll(panelSelector));
      const panel = panels.find((candidate) => candidate.closest(panelSelector) === candidate);
      if (panel === void 0) return;
      const selectedDay = ownedElements2(panel, rosterWeekOverviewDayDomAttr).find((day) => day.getAttribute("aria-pressed") === "true");
      if (selectedDay !== void 0) updateRosterWeekOverviewSelection(panel, selectedDay, report);
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
