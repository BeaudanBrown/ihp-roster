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
  function isFrontendSurfaceInteractionSurfaceName(value) {
    return typeof value === "string" && ["roster", "roster-day-timeline"].includes(value);
  }
  var pageReadyEvent = "bepis:page-ready";
  var interactionIntentEvent = "bepis:interaction-intent";
  var interactionSessionStartEvent = "bepis:interaction-session-start";
  var interactionSessionEndEvent = "bepis:interaction-session-end";
  var interactionSessionCancelRequestEvent = "bepis:interaction-session-cancel-request";
  function isInteractionFieldPresence(value) {
    return typeof value === "string" && ["required", "optional"].includes(value);
  }
  var surfaceDomAttr = "data-bepis-surface";
  var surfaceFamilyDomAttr = "data-bepis-surface-family";
  var sessionDisabledDomAttr = "data-bepis-session-disabled";
  var sessionReadOnlyDomAttr = "data-bepis-session-read-only";
  var sessionThresholdDomAttr = "data-bepis-session-threshold";
  var sessionTimeoutMsDomAttr = "data-bepis-session-timeout-ms";
  var interactionActiveDomAttr = "data-bepis-interaction-active";
  var disposableLayerDomAttr = "data-bepis-disposable-layer";
  var conflictPoliciesDomAttr = "data-bepis-conflict-policies";
  var intentFormDomAttr = "data-bepis-intent-form";
  var intentDomAttr = "data-bepis-intent";
  var intentFieldDomAttr = "data-bepis-intent-field";
  var fieldPresenceDomAttr = "data-bepis-field-presence";
  var sourceRefDomAttr = "data-bepis-source-ref";
  var sourceKeyDomAttr = "data-bepis-source-key";
  var dropzoneRefDomAttr = "data-bepis-dropzone-ref";
  var dropzoneKeyDomAttr = "data-bepis-dropzone-key";
  var activationRefDomAttr = "data-bepis-activation-ref";
  var activeSourceRefDomAttr = "data-bepis-active-source-ref";
  var enabledDomValue = "true";
  var sessionKindFieldName = "sessionKind";
  var pointerIdFieldName = "pointerId";
  var pointerTypeFieldName = "pointerType";
  var startClientXFieldName = "startClientX";
  var startClientYFieldName = "startClientY";
  var currentClientXFieldName = "currentClientX";
  var currentClientYFieldName = "currentClientY";
  var deltaXFieldName = "deltaX";
  var deltaYFieldName = "deltaY";
  var InteractionDom = {
    attributes: { surface: surfaceDomAttr, surfaceFamily: surfaceFamilyDomAttr, sessionDisabled: sessionDisabledDomAttr, sessionReadOnly: sessionReadOnlyDomAttr, sessionThreshold: sessionThresholdDomAttr, sessionTimeoutMs: sessionTimeoutMsDomAttr, interactionActive: interactionActiveDomAttr, disposableLayer: disposableLayerDomAttr, conflictPolicies: conflictPoliciesDomAttr, intentForm: intentFormDomAttr, intent: intentDomAttr, intentField: intentFieldDomAttr, fieldPresence: fieldPresenceDomAttr, sourceRef: sourceRefDomAttr, sourceKey: sourceKeyDomAttr, dropzoneRef: dropzoneRefDomAttr, dropzoneKey: dropzoneKeyDomAttr, activationRef: activationRefDomAttr, activeSourceRef: activeSourceRefDomAttr },
    values: { enabled: enabledDomValue },
    pointerFields: { sessionKind: sessionKindFieldName, pointerId: pointerIdFieldName, pointerType: pointerTypeFieldName, startClientX: startClientXFieldName, startClientY: startClientYFieldName, currentClientX: currentClientXFieldName, currentClientY: currentClientYFieldName, deltaX: deltaXFieldName, deltaY: deltaYFieldName }
  };
  function isTimesheetStaffPanelSortRow(value) {
    return isRecord(value) && hasExactKeys(value, ["staffRowKey", "staffName", "staffRole", "entryCount", "approvedCount"], ["staffRowKey", "staffName", "staffRole", "entryCount", "approvedCount"]) && typeof value["staffRowKey"] === "string" && typeof value["staffName"] === "string" && typeof value["staffRole"] === "string" && (typeof value["entryCount"] === "number" && Number.isInteger(value["entryCount"])) && (typeof value["approvedCount"] === "number" && Number.isInteger(value["approvedCount"]));
  }
  function parseTimesheetStaffPanelSortRow(value) {
    if (isTimesheetStaffPanelSortRow(value)) return value;
    throw new Error("Invalid TimesheetStaffPanelSortRow");
  }
  function isRosterStaffPanelSortRow(value) {
    return isRecord(value) && hasExactKeys(value, ["staffRowKey", "staffName", "staffRole", "assignedShifts", "idealShifts"], ["staffRowKey", "staffName", "staffRole", "assignedShifts", "idealShifts"]) && typeof value["staffRowKey"] === "string" && typeof value["staffName"] === "string" && typeof value["staffRole"] === "string" && (typeof value["assignedShifts"] === "number" && Number.isInteger(value["assignedShifts"])) && (typeof value["idealShifts"] === "number" && Number.isInteger(value["idealShifts"]));
  }
  function parseRosterStaffPanelSortRow(value) {
    if (isRosterStaffPanelSortRow(value)) return value;
    throw new Error("Invalid RosterStaffPanelSortRow");
  }
  function isLeaveStaffPanelSortRow(value) {
    return isRecord(value) && hasExactKeys(value, ["staffRowKey", "staffName", "staffRole", "periodCount", "pendingCount"], ["staffRowKey", "staffName", "staffRole", "periodCount", "pendingCount"]) && typeof value["staffRowKey"] === "string" && typeof value["staffName"] === "string" && typeof value["staffRole"] === "string" && (typeof value["periodCount"] === "number" && Number.isInteger(value["periodCount"])) && (typeof value["pendingCount"] === "number" && Number.isInteger(value["pendingCount"]));
  }
  function parseLeaveStaffPanelSortRow(value) {
    if (isLeaveStaffPanelSortRow(value)) return value;
    throw new Error("Invalid LeaveStaffPanelSortRow");
  }
  var timesheetsTimesheetStaffPanelSortRootDomAttr = "data-bepis-timesheets-timesheet-staff-panel-sort-root";
  var timesheetsTimesheetStaffPanelSortRowDomAttr = "data-bepis-timesheets-timesheet-staff-panel-sort-row";
  var timesheetsTimesheetStaffPanelSortControlDomAttr = "data-bepis-timesheets-timesheet-staff-panel-sort-control";
  var timesheetsTimesheetSidePanelTabDomAttr = "data-bepis-timesheets-timesheet-side-panel-tab";
  var timesheetsTimesheetSidePanelRootDomAttr = "data-bepis-timesheets-timesheet-side-panel-root";
  var timesheetsTimesheetSidePanelMainDomAttr = "data-bepis-timesheets-timesheet-side-panel-main";
  var timesheetsTimesheetSidePanelPanelDomAttr = "data-bepis-timesheets-timesheet-side-panel-panel";
  var timesheetsTimesheetSidePanelToggleDomAttr = "data-bepis-timesheets-timesheet-side-panel-toggle";
  var timesheetsTimesheetSidePanelLabelDomAttr = "data-bepis-timesheets-timesheet-side-panel-label";
  var timesheetsTimesheetSidePanelDomAttr = "data-bepis-timesheets-timesheet-side-panel";
  var rosterStaffPanelSortRootDomAttr = "data-bepis-roster-staff-panel-sort-root";
  var rosterStaffPanelSortRowDomAttr = "data-bepis-roster-staff-panel-sort-row";
  var rosterStaffPanelSortControlDomAttr = "data-bepis-roster-staff-panel-sort-control";
  var rosterStaffPanelTabDomAttr = "data-bepis-roster-staff-panel-tab";
  var rosterSelfServicePanelTabDomAttr = "data-bepis-roster-self-service-panel-tab";
  var rosterSidePanelRootDomAttr = "data-bepis-roster-side-panel-root";
  var rosterSidePanelMainDomAttr = "data-bepis-roster-side-panel-main";
  var rosterSidePanelPanelDomAttr = "data-bepis-roster-side-panel-panel";
  var rosterSidePanelToggleDomAttr = "data-bepis-roster-side-panel-toggle";
  var rosterSidePanelLabelDomAttr = "data-bepis-roster-side-panel-label";
  var rosterSidePanelDomAttr = "data-bepis-roster-side-panel";
  var leaveRequestsLeaveStaffPanelSortRootDomAttr = "data-bepis-leave-requests-leave-staff-panel-sort-root";
  var leaveRequestsLeaveStaffPanelSortRowDomAttr = "data-bepis-leave-requests-leave-staff-panel-sort-row";
  var leaveRequestsLeaveStaffPanelSortControlDomAttr = "data-bepis-leave-requests-leave-staff-panel-sort-control";
  var leaveRequestsLeaveSidePanelTabDomAttr = "data-bepis-leave-requests-leave-side-panel-tab";
  var leaveRequestsLeaveSidePanelRootDomAttr = "data-bepis-leave-requests-leave-side-panel-root";
  var leaveRequestsLeaveSidePanelMainDomAttr = "data-bepis-leave-requests-leave-side-panel-main";
  var leaveRequestsLeaveSidePanelPanelDomAttr = "data-bepis-leave-requests-leave-side-panel-panel";
  var leaveRequestsLeaveSidePanelToggleDomAttr = "data-bepis-leave-requests-leave-side-panel-toggle";
  var leaveRequestsLeaveSidePanelLabelDomAttr = "data-bepis-leave-requests-leave-side-panel-label";
  var leaveRequestsLeaveSidePanelDomAttr = "data-bepis-leave-requests-leave-side-panel";
  function isTimesheetsTimesheetSidePanelState(value) {
    return typeof value === "string" && ["collapsed", "expanded"].includes(value);
  }
  function isRosterSidePanelState(value) {
    return typeof value === "string" && ["collapsed", "expanded"].includes(value);
  }
  function isLeaveRequestsLeaveSidePanelState(value) {
    return typeof value === "string" && ["collapsed", "expanded"].includes(value);
  }
  function isTimesheetStaffPanelSortKey(value) {
    return typeof value === "string" && ["name", "role", "count"].includes(value);
  }
  function isRosterStaffPanelSortKey(value) {
    return typeof value === "string" && ["name", "role", "shifts"].includes(value);
  }
  function isLeaveStaffPanelSortKey(value) {
    return typeof value === "string" && ["name", "role", "count"].includes(value);
  }
  function isTimesheetSidePanelTabsKey(value) {
    return typeof value === "string" && ["staff", "settings"].includes(value);
  }
  function isRosterStaffPanelTabsKey(value) {
    return typeof value === "string" && ["staff", "templates", "settings"].includes(value);
  }
  function isRosterSelfServicePanelTabsKey(value) {
    return typeof value === "string" && ["quick-tools", "settings"].includes(value);
  }
  function isLeaveSidePanelTabsKey(value) {
    return typeof value === "string" && ["staff", "settings"].includes(value);
  }
  var FrontendSurfaceCompleteSetSortRegistry = { "timesheets": [{ "name": "timesheet-staff-panel-sort", "rootRoleAttribute": timesheetsTimesheetStaffPanelSortRootDomAttr, "rowRoleAttribute": timesheetsTimesheetStaffPanelSortRowDomAttr, "controlRoleAttribute": timesheetsTimesheetStaffPanelSortControlDomAttr, "parseRow": parseTimesheetStaffPanelSortRow, "isKey": isTimesheetStaffPanelSortKey, "keys": [{ "key": "name", "comparators": [{ "field": "staffName", "valueType": "text", "direction": "selected", "read": (row) => parseTimesheetStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseTimesheetStaffPanelSortRow(row).staffRowKey }] }, { "key": "role", "comparators": [{ "field": "staffRole", "valueType": "text", "direction": "selected", "read": (row) => parseTimesheetStaffPanelSortRow(row).staffRole }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseTimesheetStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseTimesheetStaffPanelSortRow(row).staffRowKey }] }, { "key": "count", "comparators": [{ "field": "entryCount", "valueType": "integer", "direction": "selected", "read": (row) => parseTimesheetStaffPanelSortRow(row).entryCount }, { "field": "approvedCount", "valueType": "integer", "direction": "selected", "read": (row) => parseTimesheetStaffPanelSortRow(row).approvedCount }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseTimesheetStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseTimesheetStaffPanelSortRow(row).staffRowKey }] }], "defaultKey": "name", "defaultDirection": "ascending" }], "roster": [{ "name": "roster-staff-panel-sort", "rootRoleAttribute": rosterStaffPanelSortRootDomAttr, "rowRoleAttribute": rosterStaffPanelSortRowDomAttr, "controlRoleAttribute": rosterStaffPanelSortControlDomAttr, "parseRow": parseRosterStaffPanelSortRow, "isKey": isRosterStaffPanelSortKey, "keys": [{ "key": "name", "comparators": [{ "field": "staffName", "valueType": "text", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffRowKey }] }, { "key": "role", "comparators": [{ "field": "staffRole", "valueType": "text", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).staffRole }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffRowKey }] }, { "key": "shifts", "comparators": [{ "field": "assignedShifts", "valueType": "integer", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).assignedShifts }, { "field": "idealShifts", "valueType": "integer", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).idealShifts }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffRowKey }] }], "defaultKey": "name", "defaultDirection": "ascending" }], "roster-day-timeline": [], "roster-template-designer": [], "leave-requests": [{ "name": "leave-staff-panel-sort", "rootRoleAttribute": leaveRequestsLeaveStaffPanelSortRootDomAttr, "rowRoleAttribute": leaveRequestsLeaveStaffPanelSortRowDomAttr, "controlRoleAttribute": leaveRequestsLeaveStaffPanelSortControlDomAttr, "parseRow": parseLeaveStaffPanelSortRow, "isKey": isLeaveStaffPanelSortKey, "keys": [{ "key": "name", "comparators": [{ "field": "staffName", "valueType": "text", "direction": "selected", "read": (row) => parseLeaveStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseLeaveStaffPanelSortRow(row).staffRowKey }] }, { "key": "role", "comparators": [{ "field": "staffRole", "valueType": "text", "direction": "selected", "read": (row) => parseLeaveStaffPanelSortRow(row).staffRole }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseLeaveStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseLeaveStaffPanelSortRow(row).staffRowKey }] }, { "key": "count", "comparators": [{ "field": "periodCount", "valueType": "integer", "direction": "selected", "read": (row) => parseLeaveStaffPanelSortRow(row).periodCount }, { "field": "pendingCount", "valueType": "integer", "direction": "selected", "read": (row) => parseLeaveStaffPanelSortRow(row).pendingCount }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseLeaveStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseLeaveStaffPanelSortRow(row).staffRowKey }] }], "defaultKey": "name", "defaultDirection": "ascending" }], "self-service-leave": [], "billing": [], "support": [], "profile": [], "staff": [], "admin-page": [], "admin-xero-page": [], "admin-venue-config": [], "admin-invites": [], "admin-exports": [], "admin-shift-types": [], "admin-roster-groups": [], "admin-xero": [] };
  var FrontendSurfaceTabSetRegistry = { "timesheets": [{ "name": "timesheet-side-panel-tabs", "tabRoleAttribute": timesheetsTimesheetSidePanelTabDomAttr, "keys": ["staff", "settings"], "defaultKey": "staff", "isKey": isTimesheetSidePanelTabsKey }], "roster": [{ "name": "roster-staff-panel-tabs", "tabRoleAttribute": rosterStaffPanelTabDomAttr, "keys": ["staff", "templates", "settings"], "defaultKey": "staff", "isKey": isRosterStaffPanelTabsKey }, { "name": "roster-self-service-panel-tabs", "tabRoleAttribute": rosterSelfServicePanelTabDomAttr, "keys": ["quick-tools", "settings"], "defaultKey": "quick-tools", "isKey": isRosterSelfServicePanelTabsKey }], "roster-day-timeline": [], "roster-template-designer": [], "leave-requests": [{ "name": "leave-side-panel-tabs", "tabRoleAttribute": leaveRequestsLeaveSidePanelTabDomAttr, "keys": ["staff", "settings"], "defaultKey": "staff", "isKey": isLeaveSidePanelTabsKey }], "self-service-leave": [], "billing": [], "support": [], "profile": [], "staff": [], "admin-page": [], "admin-xero-page": [], "admin-venue-config": [], "admin-invites": [], "admin-exports": [], "admin-shift-types": [], "admin-roster-groups": [], "admin-xero": [] };
  var FrontendSurfaceSidePanelRegistry = { "timesheets": [{ "name": "timesheet-side-panel", "rootRoleAttribute": timesheetsTimesheetSidePanelRootDomAttr, "mainRoleAttribute": timesheetsTimesheetSidePanelMainDomAttr, "panelRoleAttribute": timesheetsTimesheetSidePanelPanelDomAttr, "toggleRoleAttribute": timesheetsTimesheetSidePanelToggleDomAttr, "labelRoleAttribute": timesheetsTimesheetSidePanelLabelDomAttr, "stateAttribute": timesheetsTimesheetSidePanelDomAttr, "collapsedValue": "collapsed", "expandedValue": "expanded", "isState": isTimesheetsTimesheetSidePanelState }], "roster": [{ "name": "roster-side-panel", "rootRoleAttribute": rosterSidePanelRootDomAttr, "mainRoleAttribute": rosterSidePanelMainDomAttr, "panelRoleAttribute": rosterSidePanelPanelDomAttr, "toggleRoleAttribute": rosterSidePanelToggleDomAttr, "labelRoleAttribute": rosterSidePanelLabelDomAttr, "stateAttribute": rosterSidePanelDomAttr, "collapsedValue": "collapsed", "expandedValue": "expanded", "isState": isRosterSidePanelState }], "roster-day-timeline": [], "roster-template-designer": [], "leave-requests": [{ "name": "leave-side-panel", "rootRoleAttribute": leaveRequestsLeaveSidePanelRootDomAttr, "mainRoleAttribute": leaveRequestsLeaveSidePanelMainDomAttr, "panelRoleAttribute": leaveRequestsLeaveSidePanelPanelDomAttr, "toggleRoleAttribute": leaveRequestsLeaveSidePanelToggleDomAttr, "labelRoleAttribute": leaveRequestsLeaveSidePanelLabelDomAttr, "stateAttribute": leaveRequestsLeaveSidePanelDomAttr, "collapsedValue": "collapsed", "expandedValue": "expanded", "isState": isLeaveRequestsLeaveSidePanelState }], "self-service-leave": [], "billing": [], "support": [], "profile": [], "staff": [], "admin-page": [], "admin-xero-page": [], "admin-venue-config": [], "admin-invites": [], "admin-exports": [], "admin-shift-types": [], "admin-roster-groups": [], "admin-xero": [] };
  var FrontendSurfaceFragmentRegistry = { "timesheets": ["timesheet-toolbar", "timesheet-day-columns", "timesheet-side-panel-content", "timesheet-day-section"], "roster": ["roster-content", "roster-grid-toolbar", "roster-grid-frame", "roster-day-columns", "roster-day-rail", "roster-wage-rail", "roster-slots-grid", "roster-staff-panel", "roster-template-library", "roster-day-section", "roster-row"], "roster-day-timeline": ["roster-day-timeline-content"], "roster-template-designer": [], "leave-requests": ["unavailability-blackouts", "leave-side-panel-content", "leave-availability-warnings", "leave-section-count", "leave-section-list"], "self-service-leave": ["self-service-leave-form", "visible-unavailability-blackouts", "self-service-leave-history"], "billing": ["billing-status"], "support": ["support-award-rates", "support-public-holidays"], "profile": ["profile-details-section", "profile-preferences-section", "profile-security-section", "profile-leave-section"], "staff": ["staff-details-section", "staff-preferences-section", "staff-visible-unavailability-blackouts", "staff-leave-section"], "admin-page": [], "admin-xero-page": [], "admin-venue-config": ["admin-venue-settings"], "admin-invites": ["admin-invites"], "admin-exports": ["admin-exports"], "admin-shift-types": ["admin-shift-types"], "admin-roster-groups": ["admin-roster-groups"], "admin-xero": ["admin-xero-shell", "admin-xero-reference-sync", "admin-xero-timesheet-preparation-wait", "admin-xero-pay-item-import-wait"] };
  function isFrontendSurfaceName(value) {
    return typeof value === "string" && Object.prototype.hasOwnProperty.call(FrontendSurfaceFragmentRegistry, value);
  }
  var FrontendSurfaceInteractionRegistry = { "roster": { "sourceRefs": [{ "ref": "shift-drag-source", "session": "drag", "intent": "move-roster-shift-to-slot", "sourceField": "sourceItemKey", "compatibleDropzones": ["shift-slot-dropzone", "day-column-dropzone", "delete-shift-dropzone"], "modifierVariants": [{ "semantic": "copy", "intent": "duplicate-roster-shift-to-day", "effects": { "global": [{ "className": "bepis-pointer-clone-shadow bepis-pointer-clone-shadow-copy", "kind": "clone-shadow", "layer": "drag-preview", "preserveGrabOffset": true, "source": "pointer-marker" }], "contextual": [{ "className": "bepis-dropzone-highlight", "kind": "dropzone-highlight" }] } }] }, { "ref": "staff-drag-source", "session": "drag", "intent": "drop-roster-staff", "sourceField": "sourceItemKey", "compatibleDropzones": ["existing-shift-dropzone", "shift-slot-dropzone", "staff-create-dropzone"], "modifierVariants": [] }, { "ref": "day-template-drag-source", "session": "drag", "intent": "preview-roster-template-application", "sourceField": "sourceItemKey", "compatibleDropzones": ["day-template-dropzone"], "modifierVariants": [] }, { "ref": "week-template-drag-source", "session": "drag", "intent": "preview-roster-template-application", "sourceField": "sourceItemKey", "compatibleDropzones": ["week-template-dropzone"], "modifierVariants": [] }], "dropzoneRefs": [{ "ref": "shift-slot-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }, { "ref": "staff-create-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }, { "ref": "day-column-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }, { "ref": "existing-shift-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }, { "ref": "delete-shift-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }, { "ref": "day-template-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }, { "ref": "week-template-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }], "activationRefs": [{ "ref": "roster-layout-mode-activation", "intent": "set-roster-layout-mode", "valueField": "rosterLayoutMode", "trigger": "click" }], "sessionKinds": [{ "kind": "drag", "effects": { "global": [{ "className": "bepis-pointer-clone-shadow", "kind": "clone-shadow", "layer": "drag-preview", "preserveGrabOffset": true, "source": "pointer-marker" }], "contextual": [{ "className": "bepis-dropzone-highlight", "kind": "dropzone-highlight" }] } }] }, "roster-day-timeline": { "sourceRefs": [{ "ref": "drag-source", "session": "drag", "intent": "move-roster-timeline-shift", "sourceField": "sourceItemKey", "compatibleDropzones": ["drag-dropzone"], "modifierVariants": [] }], "dropzoneRefs": [{ "ref": "drag-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }], "activationRefs": [], "sessionKinds": [{ "kind": "drag", "effects": { "global": [{ "className": "bepis-pointer-clone-shadow", "kind": "clone-shadow", "layer": "drag-preview", "preserveGrabOffset": true, "source": "pointer-marker" }], "contextual": [{ "className": "bepis-dropzone-highlight", "kind": "dropzone-highlight" }] } }] } };

  // frontend/ts/shared/exhaustive.ts
  function assertNever(value, message = "Unexpected generated union variant") {
    throw new Error(`${message}: ${JSON.stringify(value)}`);
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

  // frontend/ts/shared/surface-mount.ts
  function surfaceMountsWithin(root) {
    const queryRoot = root;
    const mounts = Array.from(queryRoot.querySelectorAll(`[${surfaceDomAttr}]`)).filter(isSurfaceElementLike);
    if (isSurfaceElementLike(root)) {
      const ownerMount = closestSurfaceMount(root);
      if (ownerMount && !mounts.includes(ownerMount)) mounts.unshift(ownerMount);
    }
    return mounts;
  }
  function surfaceDefinitionsForMount(mount, registry) {
    const surface = mount.getAttribute(surfaceDomAttr);
    return isFrontendSurfaceName(surface) ? registry[surface] : [];
  }
  function ownedSurfaceRoleElements(owner, mount, attribute) {
    return Array.from(owner.querySelectorAll(`[${attribute}]`)).filter(isSurfaceElementLike).filter((element) => closestSurfaceMount(element) === mount);
  }
  function closestOwnedSurfaceRole(target, mount, attribute) {
    const candidate = target.closest(`[${attribute}]`);
    return isSurfaceElementLike(candidate) && closestSurfaceMount(candidate) === mount ? candidate : null;
  }
  function closestSurfaceRole(target, attribute) {
    const candidate = target.closest(`[${attribute}]`);
    return isSurfaceElementLike(candidate) ? candidate : null;
  }
  function closestSurfaceMount(target) {
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
  function defaultDiagnosticReporter(diagnostic4) {
    console.error?.("Invalid generated complete-set sort boundary", diagnostic4);
  }
  function diagnostic(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function createCompleteSetSortController(report = defaultDiagnosticReporter) {
    const statesByRoot = /* @__PURE__ */ new WeakMap();
    function stateFor2(root, definition) {
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
        for (const definition of definitionsForMount(mount)) {
          for (const sortRoot of ownedSurfaceRoleElements(mount, mount, definition.rootRoleAttribute)) {
            if (sortRoot.getAttribute(definition.rootRoleAttribute) !== "true") {
              report(diagnostic(sortRoot, "invalid-root-role", "Complete-set sort root role must equal true"));
              continue;
            }
            const state = stateFor2(sortRoot, definition);
            applySort({ mount, root: sortRoot, definition }, state);
          }
        }
      }
    }
    function activate(target) {
      if (!isSurfaceElementLike(target)) return false;
      const mount = closestSurfaceMount(target);
      if (!mount) return false;
      for (const definition of definitionsForMount(mount)) {
        const control = closestOwnedSurfaceRole(target, mount, definition.controlRoleAttribute);
        if (!control) continue;
        const sortRoot = closestSurfaceRole(control, definition.rootRoleAttribute);
        if (!sortRoot || closestSurfaceMount(sortRoot) !== mount) continue;
        const rawKey = control.getAttribute(definition.controlRoleAttribute);
        const key = rawKey !== null && definition.isKey(rawKey) ? definition.keys.find((candidate) => candidate.key === rawKey) : void 0;
        if (!key) {
          report(diagnostic(control, "invalid-control-key", "Complete-set sort control has an undeclared key"));
          return false;
        }
        const current = stateFor2(sortRoot, definition);
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
        report(diagnostic(context.root, "missing-default-key", "Complete-set sort definition has no matching active key"));
        return false;
      }
      const rows = [];
      for (const row of ownedSurfaceRoleElements(context.root, context.mount, context.definition.rowRoleAttribute)) {
        const raw = row.getAttribute(context.definition.rowRoleAttribute);
        try {
          if (raw === null) throw new Error(`Missing ${context.definition.rowRoleAttribute}`);
          rows.push({ element: row, value: context.definition.parseRow(JSON.parse(raw)) });
        } catch (error) {
          report(diagnostic(
            row,
            "invalid-row-payload",
            error instanceof Error ? error.message : String(error)
          ));
          return false;
        }
      }
      const rowParent = rows[0]?.element.parentElement ?? null;
      if (rows.some((row) => row.element.parentElement !== rowParent) || rows.length > 0 && rowParent === null) {
        report(diagnostic(context.root, "invalid-row-parent", "Complete-set sort rows must share one local parent"));
        return false;
      }
      try {
        rows.sort((left, right) => compareRows(left.value, right.value, key.comparators, state.direction));
      } catch (error) {
        report(diagnostic(
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
  function definitionsForMount(mount) {
    return surfaceDefinitionsForMount(mount, FrontendSurfaceCompleteSetSortRegistry);
  }
  var browserRuntimeEnabled = false;
  function enableFrontendSurfaceCompleteSetSort() {
    if (browserRuntimeEnabled || typeof document === "undefined") return;
    browserRuntimeEnabled = true;
    const controller = createCompleteSetSortController();
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      controller.activate(event.target);
    });
    onAppPageReady((event) => controller.reconcile(surfaceRootFromPageReadyEvent(event)));
    controller.reconcile(document);
  }

  // frontend/ts/interaction/form-bridge.ts
  var attrs = InteractionDom.attributes;
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
    return Boolean(element.getAttribute(attrs.surface));
  }
  function closestInteractionMount(element) {
    const closest = element.closest?.(attrSelector(attrs.surface)) ?? null;
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
  function hasOwn(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
  }
  function fail(logger, reason) {
    logger.warn(`[bepis interaction] ${reason}`);
    return { ok: false, reason };
  }

  // frontend/ts/interaction/intent-bus.ts
  var interactionIntentEventName = interactionIntentEvent;
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
  var surfaceActivationSelector = `[${attrs2.activationRef}]`;
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
    const marker = closestSurfaceActivationRef(event.target);
    if (!marker) return null;
    const mount = closestInteractionMount2(marker);
    if (!mount) return null;
    const surface = mount.getAttribute(attrs2.surface);
    if (!isFrontendSurfaceInteractionSurfaceName(surface)) return null;
    const ref = marker.getAttribute(attrs2.activationRef);
    const definition = FrontendSurfaceInteractionRegistry[surface].activationRefs.find((candidate) => candidate.ref === ref);
    if (!definition) return null;
    if (expectedTrigger && definition.trigger !== expectedTrigger) return null;
    const fields = readSurfaceActivationFields(marker, event, definition.valueField);
    if (fields === null) return null;
    return {
      phase: "commit",
      intent: definition.intent,
      fields,
      mount,
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
  function closestSurfaceActivationRef(target) {
    if (!isElementLike2(target)) return null;
    const marker = target.closest(surfaceActivationSelector);
    return isElementLike2(marker) ? marker : null;
  }
  function closestInteractionMount2(marker) {
    const mount = marker.closest(`[${attrs2.surface}]`);
    return isElementLike2(mount) ? mount : null;
  }
  function readSurfaceActivationFields(marker, event, valueField) {
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

  // frontend/ts/interaction/session-state.ts
  var interactionSessionStartEventName = interactionSessionStartEvent;
  var interactionSessionEndEventName = interactionSessionEndEvent;
  var interactionSessionCancelRequestEventName = interactionSessionCancelRequestEvent;
  var attrs3 = InteractionDom.attributes;
  function dispatchInteractionSessionStart(detail, root) {
    const eventRoot = root ?? defaultDocument();
    if (!eventRoot) return;
    eventRoot.dispatchEvent(new CustomEvent(interactionSessionStartEventName, { detail }));
  }
  function dispatchInteractionSessionEnd(detail, root) {
    const eventRoot = root ?? defaultDocument();
    if (!eventRoot) return;
    eventRoot.dispatchEvent(new CustomEvent(interactionSessionEndEventName, { detail }));
  }
  function defaultDocument() {
    return typeof document === "undefined" ? null : document;
  }

  // frontend/ts/interaction/pointer-session.ts
  var attrs4 = InteractionDom.attributes;
  var values = InteractionDom.values;
  var sourceRefSelector = `[${attrs4.sourceRef}]`;
  var interactiveControlSelector = "button,a,input,select,textarea,[role=button],[role=link]";
  var disposableLayerSelector = `[${attrs4.disposableLayer}]`;
  var pointerFields = InteractionDom.pointerFields;
  var defaultThresholdPx = 4;
  var activeSourceRefAttribute = attrs4.activeSourceRef;
  var noOpEffectRunner = {
    activate: () => void 0,
    update: () => void 0,
    cleanup: () => void 0
  };
  function enableGenericPointerSessions(options = {}) {
    if (typeof document === "undefined") return () => void 0;
    const controller = createPointerSessionController(options);
    const root = options.root ?? document;
    root.addEventListener("pointerdown", controller.handlePointerDown);
    root.addEventListener("pointermove", controller.handlePointerMove);
    root.addEventListener("pointerup", controller.handlePointerUp);
    root.addEventListener("pointercancel", controller.handlePointerCancel);
    root.addEventListener("keydown", controller.handleKeyDown);
    root.addEventListener("keyup", controller.handleKeyUp);
    root.addEventListener("click", controller.handleClick, true);
    root.addEventListener("htmx:beforeSwap", controller.handleExternalCleanup);
    root.addEventListener("htmx:beforeCleanupElement", controller.handleExternalCleanup);
    root.addEventListener(interactionSessionCancelRequestEventName, controller.handleCancelRequest);
    return () => {
      root.removeEventListener("pointerdown", controller.handlePointerDown);
      root.removeEventListener("pointermove", controller.handlePointerMove);
      root.removeEventListener("pointerup", controller.handlePointerUp);
      root.removeEventListener("pointercancel", controller.handlePointerCancel);
      root.removeEventListener("keydown", controller.handleKeyDown);
      root.removeEventListener("keyup", controller.handleKeyUp);
      root.removeEventListener("click", controller.handleClick, true);
      root.removeEventListener("htmx:beforeSwap", controller.handleExternalCleanup);
      root.removeEventListener("htmx:beforeCleanupElement", controller.handleExternalCleanup);
      root.removeEventListener(interactionSessionCancelRequestEventName, controller.handleCancelRequest);
      controller.stop();
    };
  }
  function createPointerSessionController(options = {}) {
    const runtime = options.runtime ?? defaultInteractionRuntime;
    const fallbackThresholdPx = options.thresholdPx ?? defaultThresholdPx;
    let activeSession = null;
    let timeoutHandle = null;
    let suppressNextClickMarker = null;
    const clearTimeoutHandle = () => {
      if (timeoutHandle !== null) clearTimeout(timeoutHandle);
      timeoutHandle = null;
    };
    const scheduleTimeout = (session) => {
      clearTimeoutHandle();
      const timeoutMs = numberAttribute(session.marker, attrs4.sessionTimeoutMs);
      if (timeoutMs === null || timeoutMs <= 0) return;
      timeoutHandle = setTimeout(() => {
        if (activeSession === session) cancelSession(session, null);
      }, timeoutMs);
    };
    const cleanupSession = (session, reason) => {
      clearTimeoutHandle();
      session.effects.cleanup(session);
      clearDisposableLayers(session.mount);
      releasePointerCapture(session.marker, session.pointerId);
      setDocumentInteractionActive(session, false);
      if (activeSession === session) activeSession = null;
      dispatchInteractionSessionEnd(sessionSnapshot(session, reason));
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
      if (session.activated) suppressNextClickMarker = session.marker;
      cleanupSession(session, sourceEvent?.type ?? "cancel");
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
      suppressNextClickMarker = session.marker;
      cleanupSession(session, sourceEvent.type);
    };
    const updateSession = (session, event) => {
      session.currentClientX = numberValue(event.clientX);
      session.currentClientY = numberValue(event.clientY);
      if (!session.activated && movementDistance(session) < session.thresholdPx) return;
      const firstActivation = !session.activated;
      session.activated = true;
      if (firstActivation) session.effects.activate(session);
      updateActiveModifierVariant(session, event);
      session.effects.update(session);
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
        setDocumentInteractionActive(start, true);
        if (event.cancelable) event.preventDefault();
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
          cleanupSession(start, "canceled-start");
          return;
        }
        dispatchInteractionSessionStart(sessionSnapshot(start));
        scheduleTimeout(start);
      },
      handlePointerMove(event) {
        if (!activeSession || !isMatchingPointerEvent(event, activeSession)) return;
        if (event.cancelable) event.preventDefault();
        updateSession(activeSession, event);
      },
      handlePointerUp(event) {
        if (!activeSession || !isMatchingPointerEvent(event, activeSession)) return;
        if (event.cancelable && activeSession.activated) event.preventDefault();
        updateSession(activeSession, event);
        if (activeSession.activated) finishSession(activeSession, event);
        else cancelSession(activeSession, event);
      },
      handlePointerCancel(event) {
        if (!activeSession || !isMatchingPointerEvent(event, activeSession)) return;
        cancelSession(activeSession, event);
      },
      handleKeyDown(event) {
        if (!activeSession) return;
        if (isEscapeKeyboardEvent(event)) {
          if (event.cancelable) event.preventDefault();
          cancelSession(activeSession, event);
          return;
        }
        updateSessionModifierFromKeyboard(activeSession, event);
      },
      handleKeyUp(event) {
        if (!activeSession) return;
        updateSessionModifierFromKeyboard(activeSession, event);
      },
      handleExternalCleanup(event) {
        if (!activeSession) return;
        cancelSession(activeSession, event);
      },
      handleCancelRequest(event) {
        if (!activeSession) return;
        const detail = event instanceof CustomEvent ? event.detail : null;
        if (detail?.mountId && detail.mountId !== activeSession.mount.id) return;
        if (detail?.sessionKind && detail.sessionKind !== activeSession.sessionKind) return;
        cancelSession(activeSession, event);
      },
      handleClick(event) {
        if (!suppressNextClickMarker) return;
        const marker = closestSurfaceSourceRef(event.target);
        if (marker !== suppressNextClickMarker) return;
        suppressNextClickMarker = null;
        if (event.cancelable) event.preventDefault();
        event.stopImmediatePropagation?.();
      },
      currentSession() {
        return activeSession;
      },
      stop() {
        if (activeSession) cancelSession(activeSession, null);
        clearTimeoutHandle();
        suppressNextClickMarker = null;
      }
    };
  }
  function readPointerSessionStart(event, fallbackThresholdPx = defaultThresholdPx) {
    const pointerEvent = event;
    if (pointerEvent.pointerType === "touch") return null;
    const marker = closestSurfaceSourceRef(event.target);
    if (!marker) return null;
    if (isDisabled(marker)) return null;
    const interactiveControl = closestInteractiveControl(event.target);
    if (interactiveControl && interactiveControl !== marker) return null;
    const mount = closestInteractionMount3(marker);
    if (!mount) return null;
    const surface = mount.getAttribute(attrs4.surface);
    if (!isFrontendSurfaceInteractionSurfaceName(surface)) return null;
    const sourceRef = marker.getAttribute(attrs4.sourceRef);
    const source = FrontendSurfaceInteractionRegistry[surface].sourceRefs.find((candidate) => candidate.ref === sourceRef);
    if (!source) return null;
    const sourceKey = marker.getAttribute(attrs4.sourceKey);
    if (!sourceKey) return null;
    const compatibleDropzoneRefs = compatibleDropzoneRefsForSource(surface, source);
    const targetField = FrontendSurfaceInteractionRegistry[surface].dropzoneRefs.find((candidate) => compatibleDropzoneRefs.includes(candidate.ref))?.targetField ?? null;
    return buildPointerSession({ event: pointerEvent, marker, mount, intent: source.intent, modifierVariants: source.modifierVariants ?? [], sessionKind: source.session, sourceRef: source.ref, compatibleDropzoneRefs, sourceField: source.sourceField, sourceKey, targetField, fallbackThresholdPx });
  }
  function buildPointerSession(input) {
    const startClientX = numberValue(input.event.clientX);
    const startClientY = numberValue(input.event.clientY);
    const thresholdPx = numberAttribute(input.marker, attrs4.sessionThreshold) ?? input.fallbackThresholdPx;
    const session = {
      mount: input.mount,
      marker: input.marker,
      intent: input.intent,
      defaultIntent: input.intent,
      activeModifierSemantic: null,
      modifierVariants: input.modifierVariants,
      sessionKind: input.sessionKind,
      sourceRef: input.sourceRef,
      compatibleDropzoneRefs: input.compatibleDropzoneRefs,
      sourceField: input.sourceField,
      sourceKey: input.sourceKey,
      targetField: input.targetField,
      pointerId: numberValue(input.event.pointerId),
      pointerType: input.event.pointerType ?? "unknown",
      startClientX,
      startClientY,
      currentClientX: startClientX,
      currentClientY: startClientY,
      thresholdPx: Math.max(0, thresholdPx),
      activated: false,
      effects: noOpEffectRunner
    };
    session.effects = createPointerSessionEffectRunner(session);
    return session;
  }
  function createPointerSessionEffectRunner(session) {
    const sessionEffects = activeSessionEffects(session);
    if (!sessionEffects) return noOpEffectRunner;
    const globalHandlers = sessionEffects.global.map(createGlobalEffectHandler).filter((handler) => handler !== null);
    const contextualHandlers = sessionEffects.contextual.map(createContextualEffectHandler).filter((handler) => handler !== null);
    if (globalHandlers.length === 0 && contextualHandlers.length === 0) return noOpEffectRunner;
    return {
      activate(activeSession) {
        for (const handler of globalHandlers) handler.activate(activeSession);
      },
      update(activeSession) {
        for (const handler of globalHandlers) handler.update(activeSession);
        if (contextualHandlers.length === 0) return;
        const target = activeDropzone(activeSession);
        for (const handler of contextualHandlers) handler.update(activeSession, target);
      },
      cleanup(activeSession) {
        for (const handler of contextualHandlers) handler.cleanup(activeSession);
        for (const handler of globalHandlers) handler.cleanup(activeSession);
      }
    };
  }
  function hitTestClosest(root, clientX, clientY, selector) {
    const doc = ownerDocumentFor(root);
    const elementFromPoint = doc?.elementFromPoint?.bind(doc);
    if (!elementFromPoint) return null;
    const hit = elementFromPoint(clientX, clientY);
    if (!isElementLike3(hit)) return null;
    return hit.closest(selector);
  }
  function activeSessionEffects(session) {
    const variant = activeModifierVariant(session);
    if (variant?.effects) return variant.effects;
    const sessionDefinition = interactionSessionDefinitionFor(session);
    return sessionDefinition?.effects ?? null;
  }
  function activeModifierVariant(session) {
    if (!session.activeModifierSemantic) return null;
    return session.modifierVariants.find((variant) => variant.semantic === session.activeModifierSemantic) ?? null;
  }
  function updateSessionModifierFromKeyboard(session, event) {
    if (!session.activated) return;
    updateActiveModifierVariant(session, event);
    session.effects.update(session);
  }
  function updateActiveModifierVariant(session, event) {
    const nextSemantic = semanticModifierForEvent(event);
    const nextVariant = nextSemantic ? session.modifierVariants.find((variant) => variant.semantic === nextSemantic) ?? null : null;
    const nextIntent = nextVariant?.intent ?? session.defaultIntent;
    const activeSemantic = nextVariant?.semantic ?? null;
    if (session.intent === nextIntent && session.activeModifierSemantic === activeSemantic) return;
    const wasActivated = session.activated;
    if (wasActivated) session.effects.cleanup(session);
    session.intent = nextIntent;
    session.activeModifierSemantic = activeSemantic;
    session.effects = createPointerSessionEffectRunner(session);
    if (wasActivated) session.effects.activate(session);
  }
  function semanticModifierForEvent(event) {
    const pressed = [event.ctrlKey, event.shiftKey, event.altKey, event.metaKey].filter(Boolean).length;
    if (pressed !== 1) return null;
    if (isMacPlatform()) return event.altKey ? "copy" : null;
    return event.ctrlKey ? "copy" : null;
  }
  function isMacPlatform() {
    const nav = typeof navigator === "undefined" ? null : navigator;
    const platform = nav?.platform ?? "";
    const userAgentDataPlatform = nav?.userAgentData?.platform ?? "";
    return /mac|iphone|ipad|ipod/i.test(`${platform} ${userAgentDataPlatform}`);
  }
  function interactionSessionDefinitionFor(session) {
    const family = session.mount.getAttribute(attrs4.surfaceFamily);
    if (!isFrontendSurfaceInteractionSurfaceName(family)) return null;
    return FrontendSurfaceInteractionRegistry[family].sessionKinds.find((candidate) => candidate.kind === session.sessionKind) ?? null;
  }
  function createGlobalEffectHandler(effect) {
    switch (effect.kind) {
      case "clone-shadow":
        return createCloneShadowEffect(effect);
      case "dropzone-highlight":
        return null;
      default:
        return assertNever(effect);
    }
  }
  function createContextualEffectHandler(effect) {
    switch (effect.kind) {
      case "clone-shadow":
        return null;
      case "dropzone-highlight":
        return createDropzoneHighlightEffect(effect.className);
      default:
        return assertNever(effect);
    }
  }
  function createCloneShadowEffect(effect) {
    let shadow = null;
    let grabOffsetX = 0;
    let grabOffsetY = 0;
    const cleanup = () => {
      if (shadow?.parentNode) shadow.parentNode.removeChild(shadow);
      shadow = null;
    };
    return {
      activate(session) {
        cleanup();
        const layer = disposableLayerByName(session.mount, effect.layer);
        const source = cloneShadowSourceElement(effect.source, session);
        const proxy = layer?.ownerDocument?.createElement?.("div");
        if (!layer || !source || !proxy) return;
        const rect = elementRect(source);
        grabOffsetX = effect.preserveGrabOffset ? session.startClientX - rect.left : 0;
        grabOffsetY = effect.preserveGrabOffset ? session.startClientY - rect.top : 0;
        addClass(proxy, effect.className);
        proxy.setAttribute("aria-hidden", "true");
        applyShadowBaseStyle(proxy, rect);
        layer.appendChild(proxy);
        shadow = proxy;
        moveShadow(shadow, session, grabOffsetX, grabOffsetY);
      },
      update(session) {
        if (!shadow) return;
        moveShadow(shadow, session, grabOffsetX, grabOffsetY);
      },
      cleanup
    };
  }
  function createDropzoneHighlightEffect(className) {
    let activeTarget = null;
    const clear = () => {
      if (activeTarget) removeClass(activeTarget, className);
      activeTarget = null;
    };
    return {
      update(_session, target) {
        if (target === activeTarget) return;
        clear();
        activeTarget = target;
        if (activeTarget) addClass(activeTarget, className);
      },
      cleanup() {
        clear();
      }
    };
  }
  function cloneShadowSourceElement(source, session) {
    switch (source) {
      case "pointer-marker":
        return session.marker;
      default:
        return assertNever(source);
    }
  }
  function sessionSnapshot(session, reason) {
    return {
      mount: session.mount,
      mountId: session.mount.id,
      sessionKind: session.sessionKind,
      intent: session.intent,
      reason: reason ?? null
    };
  }
  function pointerSessionFields(session) {
    const deltaX = session.currentClientX - session.startClientX;
    const deltaY = session.currentClientY - session.startClientY;
    const fields = {
      [pointerFields.sessionKind]: session.sessionKind,
      [pointerFields.pointerId]: String(session.pointerId),
      [pointerFields.pointerType]: session.pointerType,
      [pointerFields.startClientX]: String(session.startClientX),
      [pointerFields.startClientY]: String(session.startClientY),
      [pointerFields.currentClientX]: String(session.currentClientX),
      [pointerFields.currentClientY]: String(session.currentClientY),
      [pointerFields.deltaX]: String(deltaX),
      [pointerFields.deltaY]: String(deltaY)
    };
    if (session.sourceField && session.sourceKey) fields[session.sourceField] = session.sourceKey;
    const targetDropzone = activeDropzone(session);
    const targetDropzoneKey = targetDropzoneKeyForTarget(targetDropzone);
    const targetField = targetDropzoneFieldForSession(session, targetDropzone) ?? session.targetField;
    if (targetField && targetDropzoneKey) fields[targetField] = targetDropzoneKey;
    return fields;
  }
  function activeDropzone(session) {
    return hitTestClosest(session.mount, session.currentClientX, session.currentClientY, surfaceDropzoneSelectorForSession(session));
  }
  function surfaceDropzoneSelectorForSession(session) {
    const compatibleRefs = session.compatibleDropzoneRefs;
    if (compatibleRefs.length === 0) return `[${attrs4.dropzoneRef}]`;
    return compatibleRefs.map((ref) => `[${attrs4.dropzoneRef}="${cssString(ref)}"]`).join(",");
  }
  function compatibleDropzoneRefsForSource(surface, source) {
    const explicitRefs = source.compatibleDropzones ?? [];
    if (explicitRefs.length > 0) return explicitRefs;
    return FrontendSurfaceInteractionRegistry[surface].dropzoneRefs.filter((candidate) => candidate.session === source.session).map((candidate) => candidate.ref);
  }
  function targetDropzoneFieldForSession(session, target) {
    if (!target) return null;
    const surface = session.mount.getAttribute(attrs4.surface);
    if (!isFrontendSurfaceInteractionSurfaceName(surface)) return null;
    const ref = target.getAttribute(attrs4.dropzoneRef);
    if (!ref) return null;
    return FrontendSurfaceInteractionRegistry[surface].dropzoneRefs.find((candidate) => candidate.ref === ref)?.targetField ?? null;
  }
  function targetDropzoneKeyForTarget(target) {
    if (!target) return null;
    return target.getAttribute(attrs4.dropzoneKey);
  }
  function cssString(value) {
    return value.replace(/\\/g, "\\\\").replace(/\"/g, '\\"');
  }
  function disposableLayerByName(mount, layerName) {
    for (const layer of mount.querySelectorAll(disposableLayerSelector)) {
      if (layer.getAttribute(attrs4.disposableLayer) === layerName) return layer;
    }
    return null;
  }
  function applyShadowBaseStyle(element, rect) {
    const style = element.style;
    if (!style) return;
    style.position = "fixed";
    style.left = "0px";
    style.top = "0px";
    style.width = `${Math.max(0, rect.width)}px`;
    style.height = `${Math.max(0, rect.height)}px`;
    style.pointerEvents = "none";
    style.zIndex = "1100";
    style.overflow = "hidden";
    style.contain = "layout paint";
  }
  function moveShadow(element, session, offsetX, offsetY) {
    const style = element.style;
    if (!style) return;
    const x = session.currentClientX - offsetX;
    const y = session.currentClientY - offsetY;
    style.transform = `translate3d(${x}px, ${y}px, 0)`;
  }
  function elementRect(element) {
    const rect = element.getBoundingClientRect?.();
    return {
      left: numberValue(rect?.left),
      top: numberValue(rect?.top),
      width: numberValue(rect?.width),
      height: numberValue(rect?.height)
    };
  }
  function movementDistance(session) {
    const deltaX = session.currentClientX - session.startClientX;
    const deltaY = session.currentClientY - session.startClientY;
    return Math.hypot(deltaX, deltaY);
  }
  function closestSurfaceSourceRef(target) {
    if (!isElementLike3(target)) return null;
    const marker = target.closest(sourceRefSelector);
    return isElementLike3(marker) ? marker : null;
  }
  function closestInteractiveControl(target) {
    if (!isElementLike3(target)) return null;
    const control = target.closest(interactiveControlSelector);
    return isElementLike3(control) ? control : null;
  }
  function closestInteractionMount3(marker) {
    const mount = marker.closest(`[${attrs4.surface}]`);
    return isElementLike3(mount) ? mount : null;
  }
  function clearDisposableLayers(mount) {
    for (const layer of mount.querySelectorAll(disposableLayerSelector)) clearElement(layer);
  }
  function setDocumentInteractionActive(session, active) {
    const root = session.mount.ownerDocument?.documentElement;
    if (!root) return;
    if (active) {
      root.setAttribute(attrs4.interactionActive, values.enabled);
      root.setAttribute(activeSourceRefAttribute, session.sourceRef);
    } else {
      root.removeAttribute(attrs4.interactionActive);
      root.removeAttribute(activeSourceRefAttribute);
    }
  }
  function clearElement(element) {
    const mutable = element;
    if (typeof mutable.replaceChildren === "function") {
      mutable.replaceChildren();
      return;
    }
    if (typeof mutable.innerHTML === "string") mutable.innerHTML = "";
  }
  function addClass(element, className) {
    if (!className) return;
    if (element.classList) {
      element.classList.add(...className.split(/\s+/).filter(Boolean));
      return;
    }
    const existing = element.getAttribute("class")?.split(/\s+/).filter(Boolean) ?? [];
    const merged = /* @__PURE__ */ new Set([...existing, ...className.split(/\s+/).filter(Boolean)]);
    element.setAttribute("class", Array.from(merged).join(" "));
  }
  function removeClass(element, className) {
    if (!className) return;
    const names = className.split(/\s+/).filter(Boolean);
    if (element.classList) {
      element.classList.remove(...names);
      return;
    }
    const remaining = (element.getAttribute("class")?.split(/\s+/).filter(Boolean) ?? []).filter((name) => !names.includes(name));
    if (remaining.length > 0) element.setAttribute("class", remaining.join(" "));
    else element.removeAttribute("class");
  }
  function isDisabled(marker) {
    return marker.getAttribute(attrs4.sessionDisabled) === values.enabled || marker.getAttribute(attrs4.sessionReadOnly) === values.enabled;
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
  function ownerDocumentFor(root) {
    if ("elementFromPoint" in root) return root;
    return root.ownerDocument ?? (typeof document !== "undefined" ? document : null);
  }
  function isElementLike3(value) {
    if (value === null || typeof value !== "object") return false;
    const maybe = value;
    return typeof maybe.getAttribute === "function" && typeof maybe.closest === "function" && typeof maybe.querySelectorAll === "function";
  }

  // frontend/ts/side-panel/runtime.ts
  function defaultDiagnosticReporter2(diagnostic4) {
    console.error?.("Invalid generated Surface side-panel boundary", diagnostic4);
  }
  function diagnostic2(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function definitionRoots(mount, definition) {
    return ownedSurfaceRoleElements(mount, mount, definition.rootRoleAttribute);
  }
  function resolveRoot(root) {
    const mount = closestSurfaceMount(root);
    if (!mount) return null;
    for (const definition of surfaceDefinitionsForMount(mount, FrontendSurfaceSidePanelRegistry)) {
      const candidate = closestOwnedSurfaceRole(root, mount, definition.rootRoleAttribute);
      if (candidate) return { mount, root: candidate, definition };
    }
    return null;
  }
  function resolveToggle(target) {
    const mount = closestSurfaceMount(target);
    if (!mount) return null;
    for (const definition of surfaceDefinitionsForMount(mount, FrontendSurfaceSidePanelRegistry)) {
      const toggle = closestOwnedSurfaceRole(target, mount, definition.toggleRoleAttribute);
      if (!toggle) continue;
      const root = closestOwnedSurfaceRole(toggle, mount, definition.rootRoleAttribute);
      if (root) return { resolved: { mount, root, definition }, toggle };
    }
    return null;
  }
  function ownedElements(resolved, attribute) {
    return ownedSurfaceRoleElements(resolved.root, resolved.mount, attribute).filter((element) => closestOwnedSurfaceRole(element, resolved.mount, resolved.definition.rootRoleAttribute) === resolved.root);
  }
  function validateStructure(resolved, report) {
    if (resolved.root.getAttribute(resolved.definition.rootRoleAttribute) !== "true") {
      report(diagnostic2(resolved.root, "invalid-root-role", "Side-panel root role must equal true"));
      return false;
    }
    const required = [
      [resolved.definition.mainRoleAttribute, "invalid-main-role"],
      [resolved.definition.panelRoleAttribute, "invalid-panel-role"]
    ];
    for (const [attribute, code] of required) {
      const elements = ownedElements(resolved, attribute);
      if (elements.length !== 1 || elements[0]?.getAttribute(attribute) !== "true") {
        report(diagnostic2(resolved.root, code, "Side-panel root must own exactly one generated region role"));
        return false;
      }
    }
    return true;
  }
  function stateFor(resolved, report) {
    if (!validateStructure(resolved, report)) return null;
    const state = resolved.root.getAttribute(resolved.definition.stateAttribute);
    if (!resolved.definition.isState(state)) {
      report(diagnostic2(resolved.root, "invalid-state", "Side-panel state is not declared by the Surface contract"));
      return null;
    }
    return state;
  }
  function validateToggle(resolved, toggle, report) {
    if (toggle.getAttribute(resolved.definition.toggleRoleAttribute) !== "true") {
      report(diagnostic2(toggle, "invalid-toggle-role", "Side-panel toggle role must equal true"));
      return null;
    }
    const labels = Array.from(toggle.querySelectorAll(`[${resolved.definition.labelRoleAttribute}]`)).filter(isSurfaceElementLike).filter((label) => closestOwnedSurfaceRole(label, resolved.mount, resolved.definition.toggleRoleAttribute) === toggle);
    if (labels.length !== 1 || labels[0]?.getAttribute(resolved.definition.labelRoleAttribute) !== "true") {
      report(diagnostic2(toggle, "invalid-label-role", "Side-panel toggle must own one generated label role"));
      return null;
    }
    return { toggle, label: labels[0] };
  }
  function updateToggle(validated, resolved, state) {
    const expanded = state === resolved.definition.expandedValue;
    const rootClassList = resolved.root.classList;
    rootClassList?.toggle("is-side-panel-expanded", expanded);
    const label = expanded ? "Show side panel" : "Expand main content";
    validated.toggle.setAttribute("aria-pressed", expanded ? "true" : "false");
    validated.toggle.setAttribute("aria-label", label);
    validated.toggle.setAttribute("title", label);
    validated.label.textContent = label;
    const icon = Array.from(validated.toggle.querySelectorAll(".bi"))[0];
    if (typeof Element !== "undefined" && icon instanceof Element || isSurfaceElementLike(icon)) {
      const classList = icon.classList;
      classList?.toggle("bi-fullscreen", !expanded);
      classList?.toggle("bi-fullscreen-exit", expanded);
    }
  }
  function createSidePanelController(report = defaultDiagnosticReporter2) {
    function validatedToggles(resolved) {
      const toggles = ownedElements(resolved, resolved.definition.toggleRoleAttribute);
      const validated = toggles.map((toggle2) => validateToggle(resolved, toggle2, report));
      return validated.some((toggle2) => toggle2 === null) ? null : validated;
    }
    function reconcile(root) {
      if (!isSurfaceElementLike(root)) return false;
      const resolved = resolveRoot(root);
      if (!resolved) return false;
      const state = stateFor(resolved, report);
      const toggles = validatedToggles(resolved);
      if (!state || !toggles) return false;
      toggles.forEach((toggle2) => updateToggle(toggle2, resolved, state));
      return true;
    }
    function setState(resolved, state, focusToggle) {
      if (!stateFor(resolved, report)) return false;
      const toggles = validatedToggles(resolved);
      if (!toggles) return false;
      resolved.root.setAttribute(resolved.definition.stateAttribute, state);
      toggles.forEach((toggle2) => updateToggle(toggle2, resolved, state));
      if (focusToggle) {
        const focus = focusToggle.focus;
        if (typeof focus === "function") focus.call(focusToggle, { preventScroll: true });
      }
      return true;
    }
    function toggle(target) {
      if (!isSurfaceElementLike(target)) return false;
      const match = resolveToggle(target);
      if (!match || !validateToggle(match.resolved, match.toggle, report)) return false;
      const state = stateFor(match.resolved, report);
      if (!state) return false;
      const nextState = state === match.resolved.definition.expandedValue ? match.resolved.definition.collapsedValue : match.resolved.definition.expandedValue;
      return setState(match.resolved, nextState, match.toggle);
    }
    function collapse(root) {
      if (!isSurfaceElementLike(root)) return false;
      const resolved = resolveRoot(root);
      return resolved ? setState(resolved, resolved.definition.collapsedValue, null) : false;
    }
    function dispose(root) {
      if (!isSurfaceElementLike(root)) return;
      const resolved = resolveRoot(root);
      if (resolved?.root === root) collapse(root);
    }
    return { reconcile, toggle, collapse, dispose };
  }
  function expandedSidePanelRootForEscape(target) {
    if (!target || !isSurfaceElementLike(target)) return null;
    const focused = resolveRoot(target);
    if (!focused) return null;
    return focused.root.getAttribute(focused.definition.stateAttribute) === focused.definition.expandedValue ? focused.root : null;
  }
  function rootsWithin(root) {
    const roots = [];
    for (const mount of surfaceMountsWithin(root)) {
      for (const definition of surfaceDefinitionsForMount(mount, FrontendSurfaceSidePanelRegistry)) {
        for (const sidePanelRoot of definitionRoots(mount, definition)) {
          if (!roots.includes(sidePanelRoot)) roots.push(sidePanelRoot);
        }
      }
    }
    return roots;
  }
  function installSidePanelEventListeners(source, controller, reconcileWithin) {
    source.addEventListener("click", (event) => {
      if (isSurfaceElementLike(event.target)) controller.toggle(event.target);
    });
    source.addEventListener("keydown", (event) => {
      if (event.key !== "Escape" || !isSurfaceElementLike(source.activeElement)) return;
      const focused = expandedSidePanelRootForEscape(source.activeElement);
      if (focused) controller.collapse(focused);
    });
    source.addEventListener("htmx:afterSwap", (event) => {
      const target = event.detail?.target;
      if (target && typeof target.querySelectorAll === "function") {
        reconcileWithin(target);
      }
    });
    source.addEventListener("htmx:beforeCleanupElement", (event) => {
      const target = event.detail?.target;
      if (isSurfaceElementLike(target)) controller.dispose(target);
    });
  }
  var browserRuntimeEnabled2 = false;
  function enableSidePanels() {
    if (browserRuntimeEnabled2 || typeof document === "undefined") return;
    browserRuntimeEnabled2 = true;
    const controller = createSidePanelController();
    const reconcileWithin = (root) => rootsWithin(root).forEach((panelRoot) => controller.reconcile(panelRoot));
    installSidePanelEventListeners(document, controller, reconcileWithin);
    onAppPageReady((event) => reconcileWithin(detailRoot(event, "target")));
    if (document.readyState !== "loading") reconcileWithin(document);
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
  function defaultDiagnosticReporter3(diagnostic4) {
    console.error?.("Invalid generated Surface tab-set boundary", diagnostic4);
  }
  function diagnostic3(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function createSurfaceTabSetController(showTab = defaultShowTab, report = defaultDiagnosticReporter3) {
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
      const mount = closestSurfaceMount(target);
      if (!mount) return false;
      for (const definition of definitionsForMount2(mount)) {
        const tab = closestOwnedSurfaceRole(target, mount, definition.tabRoleAttribute);
        if (!tab) continue;
        const key = tab.getAttribute(definition.tabRoleAttribute);
        if (key === null || !definition.isKey(key)) {
          report(diagnostic3(tab, "invalid-tab-key", "Surface tab has an undeclared key"));
          return false;
        }
        setRememberedKey(mount, definition, key);
        return true;
      }
      return false;
    }
    function reconcile(root) {
      for (const mount of surfaceMountsWithin(root)) {
        for (const definition of definitionsForMount2(mount)) {
          const tabs = ownedSurfaceRoleElements(mount, mount, definition.tabRoleAttribute);
          if (tabs.length === 0) continue;
          const tabsByKey = /* @__PURE__ */ new Map();
          let valid = true;
          for (const tab of tabs) {
            const key = tab.getAttribute(definition.tabRoleAttribute);
            if (key === null || !definition.isKey(key)) {
              report(diagnostic3(tab, "invalid-tab-key", "Surface tab has an undeclared key"));
              valid = false;
              continue;
            }
            const matchingTabs = tabsByKey.get(key) ?? [];
            matchingTabs.push(tab);
            tabsByKey.set(key, matchingTabs);
          }
          for (const [key, matchingTabs] of tabsByKey) {
            if (matchingTabs.length <= 1) continue;
            report(diagnostic3(mount, "duplicate-tab-key", `Surface tab set renders key ${key} more than once`));
            valid = false;
          }
          if (!valid) continue;
          const remembered = rememberedKey(mount, definition);
          const desiredKey = tabsByKey.has(remembered) ? remembered : definition.defaultKey;
          if (desiredKey !== remembered) {
            report(diagnostic3(mount, "missing-tab-key", `Surface tab set is missing rendered key ${remembered}; restoring ${desiredKey}`));
            setRememberedKey(mount, definition, desiredKey);
          }
          const desiredTabs = tabsByKey.get(desiredKey) ?? [];
          if (desiredTabs.length === 0) {
            report(diagnostic3(mount, "missing-tab-key", `Surface tab set is missing rendered default key ${definition.defaultKey}`));
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
  function definitionsForMount2(mount) {
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

  // frontend/ts/app-interactions.ts
  enableGenericInteractionActivations();
  enableFrontendSurfaceCompleteSetSort();
  enableGenericPointerSessions();
  enableFrontendSurfaceTabSets();
  enableSidePanels();
})();
