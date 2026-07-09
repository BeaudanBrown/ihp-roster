"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  function isRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function isSurfaceLabSurfaceScope(value) {
    return isSurfaceLabLabScopeScope(value);
  }
  function isTimesheetsSurfaceScope(value) {
    return isTimesheetsTimesheetWeekScope(value);
  }
  function isRosterSurfaceScope(value) {
    return isRosterRosterWeekScope(value);
  }
  function isRosterDayTimelineSurfaceScope(value) {
    return isRosterDayTimelineRosterDayTimelineScope(value);
  }
  function isLeaveRequestsSurfaceScope(value) {
    return isLeaveRequestsLeaveRequestsScopeScope(value);
  }
  function isBillingSurfaceScope(value) {
    return isBillingBillingVenueScope(value);
  }
  function isSupportSurfaceScope(value) {
    return isSupportSupportPlatformScope(value);
  }
  function isProfileSurfaceScope(value) {
    return isProfileProfileScopeScope(value);
  }
  function isStaffSurfaceScope(value) {
    return isStaffStaffScopeScope(value);
  }
  function isAdminPageSurfaceScope(value) {
    return isAdminPageAdminPageScopeScope(value);
  }
  function isAdminXeroPageSurfaceScope(value) {
    return isAdminXeroPageAdminXeroPageScopeScope(value);
  }
  function isAdminVenueConfigSurfaceScope(value) {
    return isAdminVenueConfigAdminVenueConfigScopeScope(value);
  }
  function isAdminInvitesSurfaceScope(value) {
    return isAdminInvitesAdminInvitesScopeScope(value);
  }
  function isAdminExportsSurfaceScope(value) {
    return isAdminExportsAdminExportsScopeScope(value);
  }
  function isAdminShiftTypesSurfaceScope(value) {
    return isAdminShiftTypesAdminShiftTypesScopeScope(value);
  }
  function isAdminRosterGroupsSurfaceScope(value) {
    return isAdminRosterGroupsAdminRosterGroupsScopeScope(value);
  }
  function isAdminXeroSurfaceScope(value) {
    return isAdminXeroAdminXeroScopeScope(value);
  }
  function isSurfaceLabSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "lab-shell" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "lab-panel" && (isRecord(value["params"]) && typeof value["params"]["panelId"] === "string");
  }
  function isTimesheetsSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "timesheet-toolbar" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "timesheet-day-columns" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "timesheet-day-section" && (isRecord(value["params"]) && (typeof value["params"]["dayOffset"] === "number" && Number.isInteger(value["params"]["dayOffset"])));
  }
  function isRosterSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "roster-content" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "roster-grid-toolbar" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "roster-grid-frame" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "roster-day-columns" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "roster-day-rail" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "roster-wage-rail" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "roster-slots-grid" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "roster-staff-panel" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "roster-week-overview" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "roster-day-section" && (isRecord(value["params"]) && typeof value["params"]["rosterDayId"] === "string") || isRecord(value) && value.kind === "roster-row" && (isRecord(value["params"]) && typeof value["params"]["rosterDayId"] === "string" && (typeof value["params"]["rowIndex"] === "number" && Number.isInteger(value["params"]["rowIndex"])));
  }
  function isRosterDayTimelineSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "roster-day-timeline-content" && (isRecord(value["params"]) && typeof value["params"]["rosterDayId"] === "string");
  }
  function isLeaveRequestsSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "leave-section-count" && (isRecord(value["params"]) && typeof value["params"]["leaveSection"] === "string") || isRecord(value) && value.kind === "leave-section-list" && (isRecord(value["params"]) && typeof value["params"]["leaveSection"] === "string");
  }
  function isBillingSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "billing-status" && (value["params"] === null || isRecord(value["params"]));
  }
  function isSupportSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "support-award-rates" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "support-public-holidays" && (value["params"] === null || isRecord(value["params"]));
  }
  function isProfileSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "profile-details-section" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "profile-preferences-section" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "profile-security-section" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "profile-leave-section" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "profile-rsa-section" && (value["params"] === null || isRecord(value["params"]));
  }
  function isStaffSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "staff-details-section" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "staff-preferences-section" && (value["params"] === null || isRecord(value["params"]));
  }
  function isAdminPageSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "admin-page-content" && (value["params"] === null || isRecord(value["params"]));
  }
  function isAdminXeroPageSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "admin-xero-page-content" && (value["params"] === null || isRecord(value["params"]));
  }
  function isAdminVenueConfigSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "admin-venue-settings" && (value["params"] === null || isRecord(value["params"]));
  }
  function isAdminInvitesSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "admin-invites" && (value["params"] === null || isRecord(value["params"]));
  }
  function isAdminExportsSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "admin-exports" && (value["params"] === null || isRecord(value["params"]));
  }
  function isAdminShiftTypesSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "admin-shift-types" && (value["params"] === null || isRecord(value["params"]));
  }
  function isAdminRosterGroupsSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "admin-roster-groups" && (value["params"] === null || isRecord(value["params"]));
  }
  function isAdminXeroSurfaceFragmentKey(value) {
    return isRecord(value) && value.kind === "admin-xero-shell" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "admin-xero-staff-mappings" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "admin-xero-pay-items" && (value["params"] === null || isRecord(value["params"])) || isRecord(value) && value.kind === "admin-xero-timesheets" && (value["params"] === null || isRecord(value["params"]));
  }
  function isSurfaceScope(value) {
    return isRecord(value) && value.surface === "surface-lab" && isSurfaceLabSurfaceScope(value.scope) || isRecord(value) && value.surface === "timesheets" && isTimesheetsSurfaceScope(value.scope) || isRecord(value) && value.surface === "roster" && isRosterSurfaceScope(value.scope) || isRecord(value) && value.surface === "roster-day-timeline" && isRosterDayTimelineSurfaceScope(value.scope) || isRecord(value) && value.surface === "leave-requests" && isLeaveRequestsSurfaceScope(value.scope) || isRecord(value) && value.surface === "billing" && isBillingSurfaceScope(value.scope) || isRecord(value) && value.surface === "support" && isSupportSurfaceScope(value.scope) || isRecord(value) && value.surface === "profile" && isProfileSurfaceScope(value.scope) || isRecord(value) && value.surface === "staff" && isStaffSurfaceScope(value.scope) || isRecord(value) && value.surface === "admin-page" && isAdminPageSurfaceScope(value.scope) || isRecord(value) && value.surface === "admin-xero-page" && isAdminXeroPageSurfaceScope(value.scope) || isRecord(value) && value.surface === "admin-venue-config" && isAdminVenueConfigSurfaceScope(value.scope) || isRecord(value) && value.surface === "admin-invites" && isAdminInvitesSurfaceScope(value.scope) || isRecord(value) && value.surface === "admin-exports" && isAdminExportsSurfaceScope(value.scope) || isRecord(value) && value.surface === "admin-shift-types" && isAdminShiftTypesSurfaceScope(value.scope) || isRecord(value) && value.surface === "admin-roster-groups" && isAdminRosterGroupsSurfaceScope(value.scope) || isRecord(value) && value.surface === "admin-xero" && isAdminXeroSurfaceScope(value.scope);
  }
  function isSurfaceFragmentKey(value) {
    return isRecord(value) && value.surface === "surface-lab" && isSurfaceLabSurfaceFragmentKey(value) || isRecord(value) && value.surface === "timesheets" && isTimesheetsSurfaceFragmentKey(value) || isRecord(value) && value.surface === "roster" && isRosterSurfaceFragmentKey(value) || isRecord(value) && value.surface === "roster-day-timeline" && isRosterDayTimelineSurfaceFragmentKey(value) || isRecord(value) && value.surface === "leave-requests" && isLeaveRequestsSurfaceFragmentKey(value) || isRecord(value) && value.surface === "billing" && isBillingSurfaceFragmentKey(value) || isRecord(value) && value.surface === "support" && isSupportSurfaceFragmentKey(value) || isRecord(value) && value.surface === "profile" && isProfileSurfaceFragmentKey(value) || isRecord(value) && value.surface === "staff" && isStaffSurfaceFragmentKey(value) || isRecord(value) && value.surface === "admin-page" && isAdminPageSurfaceFragmentKey(value) || isRecord(value) && value.surface === "admin-xero-page" && isAdminXeroPageSurfaceFragmentKey(value) || isRecord(value) && value.surface === "admin-venue-config" && isAdminVenueConfigSurfaceFragmentKey(value) || isRecord(value) && value.surface === "admin-invites" && isAdminInvitesSurfaceFragmentKey(value) || isRecord(value) && value.surface === "admin-exports" && isAdminExportsSurfaceFragmentKey(value) || isRecord(value) && value.surface === "admin-shift-types" && isAdminShiftTypesSurfaceFragmentKey(value) || isRecord(value) && value.surface === "admin-roster-groups" && isAdminRosterGroupsSurfaceFragmentKey(value) || isRecord(value) && value.surface === "admin-xero" && isAdminXeroSurfaceFragmentKey(value);
  }
  var pageReadyEvent = "bepis:page-ready";
  var liveFragmentsRefreshEvent = "bepis:live-fragments-refresh";
  var interactionSessionStartEvent = "bepis:interaction-session-start";
  var interactionSessionEndEvent = "bepis:interaction-session-end";
  var interactionSessionCancelRequestEvent = "bepis:interaction-session-cancel-request";
  function isUiRegionTransitionProfile(value) {
    return typeof value === "string" && ["none", "fade", "fade-slide", "panel"].includes(value);
  }
  function isUiRegionLifecycleEvent(value) {
    return typeof value === "string" && ["request-start", "before-swap", "after-swap", "settle", "error"].includes(value);
  }
  var regionRequestStartEvent = "bepis:region-request-start";
  var regionBeforeSwapEvent = "bepis:region-before-swap";
  var regionAfterSwapEvent = "bepis:region-after-swap";
  var regionSettleEvent = "bepis:region-settle";
  var regionErrorEvent = "bepis:region-error";
  var fragmentDomAttr = "data-bepis-fragment";
  var lazySurfaceDomAttr = "data-bepis-lazy-surface";
  var lazyRetryDomAttr = "data-bepis-lazy-retry";
  var regionTransitionDomAttr = "data-bepis-region-transition";
  function isInteractionConflictResolution(value) {
    return typeof value === "string" && ["apply", "defer", "cancel"].includes(value);
  }
  var surfaceDomAttr = "data-bepis-surface";
  var surfaceFamilyDomAttr = "data-bepis-surface-family";
  var scopeKeyDomAttr = "data-bepis-scope-key";
  var mountKeyDomAttr = "data-bepis-mount-key";
  var sessionDisabledDomAttr = "data-bepis-session-disabled";
  var sessionReadOnlyDomAttr = "data-bepis-session-read-only";
  var sessionThresholdDomAttr = "data-bepis-session-threshold";
  var sessionTimeoutMsDomAttr = "data-bepis-session-timeout-ms";
  var interactionActiveDomAttr = "data-bepis-interaction-active";
  var serverLayerDomAttr = "data-bepis-server-layer";
  var disposableLayerDomAttr = "data-bepis-disposable-layer";
  var layerDomAttr = "data-bepis-layer";
  var conflictPoliciesDomAttr = "data-bepis-conflict-policies";
  var intentFormDomAttr = "data-bepis-intent-form";
  var intentDomAttr = "data-bepis-intent";
  var intentFieldDomAttr = "data-bepis-intent-field";
  var fieldPresenceDomAttr = "data-bepis-field-presence";
  var intentHiddenFieldDomAttr = "data-bepis-intent-hidden-field";
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
  var sourceItemKeyFieldName = "sourceItemKey";
  var targetDropzoneKeyFieldName = "targetDropzoneKey";
  var InteractionDom = {
    attributes: { surface: surfaceDomAttr, surfaceFamily: surfaceFamilyDomAttr, scopeKey: scopeKeyDomAttr, mountKey: mountKeyDomAttr, sessionDisabled: sessionDisabledDomAttr, sessionReadOnly: sessionReadOnlyDomAttr, sessionThreshold: sessionThresholdDomAttr, sessionTimeoutMs: sessionTimeoutMsDomAttr, interactionActive: interactionActiveDomAttr, serverLayer: serverLayerDomAttr, disposableLayer: disposableLayerDomAttr, layer: layerDomAttr, conflictPolicies: conflictPoliciesDomAttr, intentForm: intentFormDomAttr, intent: intentDomAttr, intentField: intentFieldDomAttr, fieldPresence: fieldPresenceDomAttr, intentHiddenField: intentHiddenFieldDomAttr },
    values: { enabled: enabledDomValue },
    pointerFields: { sessionKind: sessionKindFieldName, pointerId: pointerIdFieldName, pointerType: pointerTypeFieldName, startClientX: startClientXFieldName, startClientY: startClientYFieldName, currentClientX: currentClientXFieldName, currentClientY: currentClientYFieldName, deltaX: deltaXFieldName, deltaY: deltaYFieldName, sourceItemKey: sourceItemKeyFieldName, targetDropzoneKey: targetDropzoneKeyFieldName }
  };
  function isSurfaceFragmentProtection(value) {
    return isRecord(value) && value["kind"] === "none" || isRecord(value) && value["kind"] === "focused-field" && typeof value["activeSelector"] === "string" && typeof value["fieldKeyAttr"] === "string" && typeof value["fieldNameFallback"] === "boolean" && (value["containerSelector"] === null || typeof value["containerSelector"] === "string");
  }
  function isSurfaceWireFragment(value) {
    return isRecord(value) && isSurfaceFragmentKey(value["fragmentKey"]) && typeof value["targetId"] === "string" && typeof value["url"] === "string" && typeof value["deferUntilBlur"] === "boolean" && isSurfaceFragmentProtection(value["protectionPolicy"]);
  }
  function encodeLiveUpdateCommand(value) {
    return value;
  }
  function isLiveUpdateMessage(value) {
    return isRecord(value) && value["type"] === "subscribed" && isSurfaceScope(value["scope"]) && typeof value["scopeKey"] === "string" && (typeof value["currentVersion"] === "number" && Number.isInteger(value["currentVersion"])) && typeof value["resync"] === "boolean" || isRecord(value) && value["type"] === "invalidate" && isSurfaceScope(value["scope"]) && typeof value["scopeKey"] === "string" && (typeof value["version"] === "number" && Number.isInteger(value["version"])) && (Array.isArray(value["fragments"]) && value["fragments"].every((item) => isSurfaceWireFragment(item))) && (value["sourceClientId"] === null || typeof value["sourceClientId"] === "string") || isRecord(value) && value["type"] === "error" && typeof value["message"] === "string";
  }
  function parseLiveUpdateMessage(value) {
    if (isLiveUpdateMessage(value)) return value;
    throw new Error("Invalid LiveUpdateMessage");
  }
  function isSurfaceLabLabScopeScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string" && (typeof value["weekOffset"] === "number" && Number.isInteger(value["weekOffset"]));
  }
  function isTimesheetsTimesheetWeekScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string" && (typeof value["weekOffset"] === "number" && Number.isInteger(value["weekOffset"]));
  }
  function isRosterRosterWeekScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string" && typeof value["rosterGroupId"] === "string" && (typeof value["weekOffset"] === "number" && Number.isInteger(value["weekOffset"]));
  }
  function isRosterDayTimelineRosterDayTimelineScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string" && typeof value["rosterGroupId"] === "string" && (typeof value["weekOffset"] === "number" && Number.isInteger(value["weekOffset"])) && typeof value["rosterDayId"] === "string";
  }
  function isLeaveRequestsLeaveRequestsScopeScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string";
  }
  function isBillingBillingVenueScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string";
  }
  function isSupportSupportPlatformScope(value) {
    return isRecord(value);
  }
  function isProfileProfileScopeScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string" && typeof value["staffId"] === "string";
  }
  function isStaffStaffScopeScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string" && typeof value["staffId"] === "string";
  }
  function isAdminPageAdminPageScopeScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string";
  }
  function isAdminXeroPageAdminXeroPageScopeScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string";
  }
  function isAdminVenueConfigAdminVenueConfigScopeScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string";
  }
  function isAdminInvitesAdminInvitesScopeScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string";
  }
  function isAdminExportsAdminExportsScopeScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string";
  }
  function isAdminShiftTypesAdminShiftTypesScopeScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string";
  }
  function isAdminRosterGroupsAdminRosterGroupsScopeScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string";
  }
  function isAdminXeroAdminXeroScopeScope(value) {
    return isRecord(value) && typeof value["venueId"] === "string";
  }
  var surfaceLabSurfaceManifest = { "surface": "surface-lab", "scopes": ["lab"], "fragments": ["lab-shell", "lab-panel"], "liveFragments": [], "htmxActions": [{ "name": "refresh-panel", "fields": ["panelId"], "htmx": { "method": "post", "trigger": null, "include": "lab-panel-include", "sync": null, "indicator": null, "confirm": null, "select": null, "target": "lab-panel-target", "swap": "outer-html", "pushUrl": false, "custom": [{ "name": "lab-panel-custom-htmx", "reason": "lab fixture covers auditable custom HTMX metadata" }] } }], "intents": ["move-lab-card"], "sessions": ["drag"], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": ["drag-preview"], "domTokens": ["lab-root", "lab-dropzone", "lab-panel-target", "lab-panel-include"], "overlayLanes": [], "containedSurfaces": {} };
  var timesheetsSurfaceManifest = { "surface": "timesheets", "scopes": ["timesheet-week"], "fragments": ["timesheet-toolbar", "timesheet-day-columns", "timesheet-day-section"], "liveFragments": ["timesheet-toolbar", "timesheet-day-columns", "timesheet-day-section"], "htmxActions": [{ "name": "navigate-timesheet-week", "fields": ["weekOffset", "showApproved", "showAllStaff", "staffFilterId"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": true, "custom": [{ "name": "timesheet-week-shell-sync-custom-htmx", "reason": "week navigation serializes through the timesheet week shell with hx-sync=closest shell:replace" }] } }, { "name": "update-timesheet-filters", "fields": ["weekOffset", "showApproved", "showAllStaff", "staffFilterId"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": true, "custom": [{ "name": "timesheet-week-shell-sync-custom-htmx", "reason": "filter changes serialize through the timesheet week shell with hx-sync=closest shell:replace" }] } }, { "name": "approve-timesheet-entry", "fields": ["weekOffset", "showApproved", "showAllStaff", "staffFilterId"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": false, "custom": [] } }, { "name": "unapprove-timesheet-entry", "fields": ["weekOffset", "showApproved", "showAllStaff", "staffFilterId"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": false, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": [], "overlayLanes": [], "containedSurfaces": {} };
  var rosterSurfaceManifest = { "surface": "roster", "scopes": ["roster-week"], "fragments": ["roster-content", "roster-grid-toolbar", "roster-grid-frame", "roster-day-columns", "roster-day-rail", "roster-wage-rail", "roster-slots-grid", "roster-staff-panel", "roster-week-overview", "roster-day-section", "roster-row"], "liveFragments": ["roster-content", "roster-grid-toolbar", "roster-grid-frame", "roster-day-columns", "roster-day-rail", "roster-wage-rail", "roster-slots-grid", "roster-staff-panel", "roster-day-section", "roster-row"], "htmxActions": [{ "name": "navigate-roster-week", "fields": ["weekOffset", "rosterGroupId"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "roster-week-shell", "swap": null, "pushUrl": true, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "roster week navigation serializes through the stable roster week shell" }] } }, { "name": "toggle-roster-warnings", "fields": ["showRosterWarnings"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "preference toggles serialize through the stable roster week shell" }] } }, { "name": "toggle-roster-wage-estimates", "fields": ["showWageEstimates"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "preference toggles serialize through the stable roster week shell" }] } }, { "name": "sort-roster-week", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "roster-content", "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "sort mutations serialize through the stable roster week shell" }] } }, { "name": "toggle-roster-week-live-status", "fields": ["isLive"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "roster-content", "swap": "outer-html", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "live toggle serializes through the stable roster week shell" }] } }, { "name": "toggle-roster-assignment-filters", "fields": ["hideStaffAtIdealShifts", "hideStaffUnavailable", "hideStaffOnApprovedLeave", "hideStaffAlreadyAssignedToday"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "assignment filter toggles serialize through the stable roster week shell" }] } }, { "name": "copy-roster-week", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "roster-content", "swap": "outer-html", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "copy mutations serialize through the stable roster week shell" }, { "name": "copy-roster-week-custom-htmx", "reason": "copy previous week requires a destructive overwrite confirmation" }] } }, { "name": "create-roster-self-service-leave-request", "fields": ["startDate", "endDate", "reason"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "roster-staff-self-service-leave-form-fragment", "swap": "outer-html", "pushUrl": false, "custom": [] } }, { "name": "create-roster-week-slot-definition", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "roster-content", "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "slot-definition mutations serialize through the stable roster week shell" }] } }, { "name": "delete-roster-week-slot-definition", "fields": [], "htmx": { "method": "delete", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "roster-content", "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "slot-definition mutations serialize through the stable roster week shell" }] } }, { "name": "toggle-roster-day-closed", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "roster-day-section", "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "day row mutations serialize through the stable roster week shell" }] } }, { "name": "add-roster-row", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "roster-day-section", "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "day row mutations serialize through the stable roster week shell" }] } }, { "name": "remove-roster-row", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "roster-day-section", "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "day row mutations serialize through the stable roster week shell" }] } }, { "name": "toggle-roster-staff-scope", "fields": ["staffScope"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "roster-staff-panel", "swap": "outer-html", "pushUrl": false, "custom": [] } }, { "name": "set-roster-layout-mode", "fields": ["rosterLayoutMode"], "htmx": { "method": null, "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": null, "custom": [] } }, { "name": "move-roster-shift-to-slot", "fields": ["sourceItemKey", "targetDropzoneKey", "sessionKind", "pointerId", "pointerType", "startClientX", "startClientY", "currentClientX", "currentClientY", "deltaX", "deltaY"], "htmx": { "method": null, "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": null, "custom": [] } }, { "name": "duplicate-roster-shift-to-day", "fields": ["sourceItemKey", "targetDropzoneKey", "sessionKind", "pointerId", "pointerType", "startClientX", "startClientY", "currentClientX", "currentClientY", "deltaX", "deltaY"], "htmx": { "method": null, "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": null, "custom": [] } }], "intents": ["set-roster-layout-mode", "move-roster-shift-to-slot", "duplicate-roster-shift-to-day"], "sessions": ["drag"], "interaction": { "sourceRefs": [{ "ref": "drag-source", "session": "drag", "intent": "move-roster-shift-to-slot", "sourceField": "sourceItemKey", "compatibleDropzones": [], "modifierVariants": [{ "semantic": "copy", "intent": "duplicate-roster-shift-to-day", "effects": { "global": [{ "className": "bepis-pointer-clone-shadow bepis-pointer-clone-shadow-copy", "kind": "clone-shadow", "layer": "drag-preview", "preserveGrabOffset": true, "source": "pointer-marker" }], "contextual": [{ "className": "bepis-dropzone-highlight", "kind": "dropzone-highlight" }] } }] }], "dropzoneRefs": [{ "ref": "drag-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }], "activationRefs": [{ "ref": "roster-layout-mode-activation", "intent": "set-roster-layout-mode", "valueField": "rosterLayoutMode", "trigger": "click" }] }, "layers": ["drag-preview"], "domTokens": ["roster-content", "roster-week-shell", "roster-day-section", "roster-staff-panel", "roster-staff-self-service-leave-form-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var rosterDayTimelineSurfaceManifest = { "surface": "roster-day-timeline", "scopes": ["roster-day-timeline"], "fragments": ["roster-day-timeline-content"], "liveFragments": ["roster-day-timeline-content"], "htmxActions": [{ "name": "move-roster-timeline-shift", "fields": ["sourceItemKey", "targetDropzoneKey", "sessionKind", "pointerId", "pointerType", "startClientX", "startClientY", "currentClientX", "currentClientY", "deltaX", "deltaY"], "htmx": { "method": null, "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": null, "custom": [] } }], "intents": ["move-roster-timeline-shift"], "sessions": ["drag"], "interaction": { "sourceRefs": [{ "ref": "drag-source", "session": "drag", "intent": "move-roster-timeline-shift", "sourceField": "sourceItemKey", "compatibleDropzones": [], "modifierVariants": [] }], "dropzoneRefs": [{ "ref": "drag-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }], "activationRefs": [] }, "layers": ["drag-preview"], "domTokens": ["roster-day-timeline-content"], "overlayLanes": [], "containedSurfaces": {} };
  var leaveRequestsSurfaceManifest = { "surface": "leave-requests", "scopes": ["leave-requests"], "fragments": ["leave-section-count", "leave-section-list"], "liveFragments": ["leave-section-count", "leave-section-list"], "htmxActions": [{ "name": "archive-leave-requests-page", "fields": ["archivePage"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "leave-archive-page-content", "swap": "none", "pushUrl": true, "custom": [] } }, { "name": "approve-leave-request", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "leave-requests-content", "swap": "none", "pushUrl": false, "custom": [] } }, { "name": "deny-leave-request", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "leave-requests-content", "swap": "none", "pushUrl": false, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["leave-requests-content", "leave-section-count", "leave-section-list", "leave-archive-page-content"], "overlayLanes": [], "containedSurfaces": {} };
  var billingSurfaceManifest = { "surface": "billing", "scopes": ["billing-venue"], "fragments": ["billing-status"], "liveFragments": ["billing-status"], "htmxActions": [], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": [], "overlayLanes": [], "containedSurfaces": {} };
  var supportSurfaceManifest = { "surface": "support", "scopes": ["support-platform"], "fragments": ["support-award-rates", "support-public-holidays"], "liveFragments": ["support-award-rates", "support-public-holidays"], "htmxActions": [{ "name": "create-public-holiday-refresh-job", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "support-public-holidays", "swap": "outer-html", "pushUrl": null, "custom": [] } }, { "name": "create-fwc-mapd-refresh-job", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "support-award-rates", "swap": "outer-html", "pushUrl": null, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["support-public-holidays", "support-award-rates"], "overlayLanes": [], "containedSurfaces": {} };
  var profileSurfaceManifest = { "surface": "profile", "scopes": ["profile"], "fragments": ["profile-details-section", "profile-preferences-section", "profile-security-section", "profile-leave-section", "profile-rsa-section"], "liveFragments": ["profile-details-section", "profile-preferences-section", "profile-security-section", "profile-leave-section", "profile-rsa-section"], "htmxActions": [{ "name": "update-profile-details", "fields": ["firstName", "lastName", "preferredName", "phone", "idealShiftsPerWeek", "emergencyContactName", "emergencyContactPhone", "section", "weekOffset", "rosterGroupId", "venueRole", "employmentBasis", "payRateSelection", "isActive", "rosterGroupIds"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": false, "custom": [{ "name": "staff-profile-section-htmx-attrs", "reason": "profile and staff forms provide their concrete section target and swap modifier at the route boundary" }] } }, { "name": "update-profile-shift-preferences", "fields": ["section", "weekOffset", "rosterGroupId", "shiftPreferenceKeys"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": false, "custom": [{ "name": "staff-profile-section-htmx-attrs", "reason": "profile and staff forms provide their concrete section target and swap modifier at the route boundary" }] } }, { "name": "create-profile-leave-request", "fields": ["startDate", "endDate", "reason"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "profile-leave-request-form-fragment", "swap": "outer-html", "pushUrl": false, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["profile-details", "profile-preferences", "profile-leave-request-form-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var staffSurfaceManifest = { "surface": "staff", "scopes": ["staff"], "fragments": ["staff-details-section", "staff-preferences-section"], "liveFragments": ["staff-details-section", "staff-preferences-section"], "htmxActions": [{ "name": "update-staff-profile", "fields": ["firstName", "lastName", "preferredName", "phone", "idealShiftsPerWeek", "emergencyContactName", "emergencyContactPhone", "section", "weekOffset", "rosterGroupId", "venueRole", "employmentBasis", "payRateSelection", "isActive", "rosterGroupIds"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": false, "custom": [{ "name": "staff-profile-section-htmx-attrs", "reason": "profile and staff forms provide their concrete section target and swap modifier at the route boundary" }] } }, { "name": "update-staff-shift-preferences", "fields": ["section", "weekOffset", "rosterGroupId", "shiftPreferenceKeys"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": false, "custom": [{ "name": "staff-profile-section-htmx-attrs", "reason": "profile and staff forms provide their concrete section target and swap modifier at the route boundary" }] } }, { "name": "create-staff-leave-request", "fields": ["startDate", "endDate", "reason"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "staff-leave-request-form-fragment", "swap": "outer-html", "pushUrl": false, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["staff-details-target", "staff-preferences-target", "staff-leave-request-form-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var adminPageSurfaceManifest = { "surface": "admin-page", "scopes": ["admin-page"], "fragments": ["admin-page-content"], "liveFragments": [], "htmxActions": [], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": [], "overlayLanes": [], "containedSurfaces": { "admin-page-content": ["admin-invites", "admin-venue-config", "admin-exports", "admin-shift-types", "admin-roster-groups"] } };
  var adminXeroPageSurfaceManifest = { "surface": "admin-xero-page", "scopes": ["admin-xero-page"], "fragments": ["admin-xero-page-content"], "liveFragments": [], "htmxActions": [], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": [], "overlayLanes": [], "containedSurfaces": { "admin-xero-page-content": ["admin-xero"] } };
  var adminVenueConfigSurfaceManifest = { "surface": "admin-venue-config", "scopes": ["admin-venue-config"], "fragments": ["admin-venue-settings"], "liveFragments": ["admin-venue-settings"], "htmxActions": [{ "name": "update-venue-config", "fields": ["configField", "rosterEndTimesEnabled", "autoTimesheetCreationEnabled"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-venue-settings-fragment", "swap": "none", "pushUrl": false, "custom": [{ "name": "change-autosave-custom-htmx", "reason": "venue setting toggles submit the containing form on change" }] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["admin-venue-settings-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var adminInvitesSurfaceManifest = { "surface": "admin-invites", "scopes": ["admin-invites"], "fragments": ["admin-invites"], "liveFragments": ["admin-invites"], "htmxActions": [{ "name": "create-venue-invitation", "fields": ["email"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-invites-fragment", "swap": "none", "pushUrl": null, "custom": [] } }, { "name": "revoke-venue-invitation", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-invites-fragment", "swap": "none", "pushUrl": null, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["admin-invites-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var adminExportsSurfaceManifest = { "surface": "admin-exports", "scopes": ["admin-exports"], "fragments": ["admin-exports"], "liveFragments": ["admin-exports"], "htmxActions": [{ "name": "create-export-job", "fields": ["rangeStart", "rangeEnd", "exportType"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-exports-fragment", "swap": "none", "pushUrl": false, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["admin-exports-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var adminShiftTypesSurfaceManifest = { "surface": "admin-shift-types", "scopes": ["admin-shift-types"], "fragments": ["admin-shift-types"], "liveFragments": ["admin-shift-types"], "htmxActions": [{ "name": "create-shift-type", "fields": ["showInactiveShiftTypes", "name", "payRateSelection", "colourKey", "isActive"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-shift-types-fragment", "swap": "outer-html", "pushUrl": null, "custom": [] } }, { "name": "update-shift-type", "fields": ["showInactiveShiftTypes", "name", "payRateSelection", "colourKey", "isActive"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-shift-types-fragment", "swap": "outer-html", "pushUrl": null, "custom": [] } }, { "name": "move-shift-type-up", "fields": ["showInactiveShiftTypes"], "htmx": { "method": "post", "trigger": "click", "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-shift-types-fragment", "swap": "outer-html", "pushUrl": false, "custom": [{ "name": "closest-form-custom-htmx", "reason": "move buttons submit the containing row form via hx-include=closest form" }] } }, { "name": "move-shift-type-down", "fields": ["showInactiveShiftTypes"], "htmx": { "method": "post", "trigger": "click", "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-shift-types-fragment", "swap": "outer-html", "pushUrl": false, "custom": [{ "name": "closest-form-custom-htmx", "reason": "move buttons submit the containing row form via hx-include=closest form" }] } }, { "name": "autosave-shift-type-name", "fields": ["showInactiveShiftTypes", "name", "payRateSelection", "colourKey", "isActive"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-shift-types-fragment", "swap": "outer-html", "pushUrl": null, "custom": [{ "name": "input-changed-autosave-custom-htmx", "reason": "name input autosave uses HTMX input changed delay:600ms, blur changed trigger and hx-include=closest form" }] } }, { "name": "autosave-shift-type-selection", "fields": ["showInactiveShiftTypes", "name", "payRateSelection", "colourKey", "isActive"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-shift-types-fragment", "swap": "outer-html", "pushUrl": null, "custom": [{ "name": "change-autosave-custom-htmx", "reason": "select autosave uses HTMX change trigger and hx-include=closest form" }] } }, { "name": "toggle-inactive-shift-types", "fields": ["showInactiveShiftTypes"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-shift-types-fragment", "swap": "outer-html", "pushUrl": null, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["admin-shift-types-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var adminRosterGroupsSurfaceManifest = { "surface": "admin-roster-groups", "scopes": ["admin-roster-groups"], "fragments": ["admin-roster-groups"], "liveFragments": ["admin-roster-groups"], "htmxActions": [{ "name": "create-roster-group", "fields": ["showInactiveRosterGroups", "name", "isActive"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-roster-groups-fragment", "swap": "none", "pushUrl": false, "custom": [] } }, { "name": "update-roster-group", "fields": ["showInactiveRosterGroups", "name", "isActive"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-roster-groups-fragment", "swap": "none", "pushUrl": false, "custom": [] } }, { "name": "move-roster-group-up", "fields": ["showInactiveRosterGroups"], "htmx": { "method": "post", "trigger": "click", "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-roster-groups-fragment", "swap": "none", "pushUrl": false, "custom": [{ "name": "closest-form-custom-htmx", "reason": "move buttons submit the containing row form via hx-include=closest form" }] } }, { "name": "move-roster-group-down", "fields": ["showInactiveRosterGroups"], "htmx": { "method": "post", "trigger": "click", "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-roster-groups-fragment", "swap": "none", "pushUrl": false, "custom": [{ "name": "closest-form-custom-htmx", "reason": "move buttons submit the containing row form via hx-include=closest form" }] } }, { "name": "toggle-inactive-roster-groups", "fields": ["showInactiveRosterGroups"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-roster-groups-fragment", "swap": "outer-html", "pushUrl": false, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["admin-roster-groups-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var adminXeroSurfaceManifest = { "surface": "admin-xero", "scopes": ["admin-xero"], "fragments": ["admin-xero-shell", "admin-xero-staff-mappings", "admin-xero-pay-items", "admin-xero-timesheets"], "liveFragments": ["admin-xero-shell", "admin-xero-staff-mappings", "admin-xero-pay-items", "admin-xero-timesheets"], "htmxActions": [{ "name": "sync-xero-payroll-reference-data", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-xero-fragment", "swap": "outer-html", "pushUrl": null, "custom": [{ "name": "load-reference-sync-custom-htmx", "reason": "automatic post-connect reference sync uses hx-trigger=load, a concrete Xero page push URL, and the connection status indicator" }] } }, { "name": "save-xero-payroll-calendar-selection", "fields": ["xeroPayrollCalendarSelection"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-xero-fragment", "swap": "none", "pushUrl": null, "custom": [{ "name": "change-autosave-custom-htmx", "reason": "payroll calendar selection submits on change" }] } }, { "name": "save-xero-pay-item-account-code-selection", "fields": ["xeroPayItemAccountCodeSelection"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-xero-fragment", "swap": "none", "pushUrl": null, "custom": [{ "name": "change-autosave-custom-htmx", "reason": "pay item account-code selection submits on change" }] } }, { "name": "create-missing-xero-pay-items", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": "xero-pay-items-sync-indicator", "confirm": null, "select": null, "target": "xero-pay-items-data", "swap": "none", "pushUrl": null, "custom": [] } }, { "name": "archive-xero-imported-pay-item", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "xero-pay-items-data", "swap": "none", "pushUrl": null, "custom": [] } }, { "name": "save-xero-staff-mapping", "fields": ["staffId", "xeroEmployeeSelection"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-xero-fragment", "swap": "none", "pushUrl": null, "custom": [{ "name": "change-autosave-custom-htmx", "reason": "staff mapping selection submits on change" }] } }, { "name": "suggest-xero-staff-mapping", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "admin-xero-fragment", "swap": "none", "pushUrl": null, "custom": [] } }, { "name": "show-xero-timesheet-preparation-staff-mappings", "fields": ["showMatched", "editStaffId"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "xero-preparation-staff-mappings", "swap": "outer-html", "pushUrl": null, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["admin-xero-fragment", "xero-pay-items-data", "xero-pay-items-sync-indicator", "xero-preparation-staff-mappings"], "overlayLanes": [], "containedSurfaces": {} };
  function isFrontendSurfaceScope(value) {
    if (!isRecord(value)) return false;
    if (!isFrontendSurfaceName(value.surface)) return false;
    return isRecord(value.scope);
  }
  function isFrontendSurfaceLiveFragment(value) {
    if (!isRecord(value)) return false;
    if (!isFrontendSurfaceName(value.surface)) return false;
    if (!isRecord(value.fragment)) return false;
    return typeof value.fragment.kind === "string" && __surfaceHasFragment(value.surface, value.fragment.kind);
  }
  function isFrontendSurfaceSurfaceFragmentProtection(value) {
    return isRecord(value) && value["kind"] === "none" || isRecord(value) && value["kind"] === "focused-field" && typeof value["activeSelector"] === "string" && typeof value["fieldKeyAttr"] === "string" && typeof value["fieldNameFallback"] === "boolean" && (value["containerSelector"] === null || typeof value["containerSelector"] === "string");
  }
  function isFrontendSurfaceLiveWireFragment(value) {
    return isRecord(value) && isFrontendSurfaceLiveFragment(value["fragment"]) && typeof value["targetId"] === "string" && typeof value["url"] === "string" && typeof value["deferUntilBlur"] === "boolean" && isFrontendSurfaceSurfaceFragmentProtection(value["protectionPolicy"]);
  }
  function isFrontendSurfaceLiveSubscription(value) {
    return isRecord(value) && isFrontendSurfaceScope(value["scope"]) && typeof value["scopeKey"] === "string" && (Array.isArray(value["resyncFragments"]) && value["resyncFragments"].every((item) => isFrontendSurfaceLiveWireFragment(item)));
  }
  function __surfaceHasFragment(surface, fragment) {
    return FrontendSurfaceRegistry[surface].fragments.includes(fragment);
  }
  var FrontendSurfaceRegistry = {
    "surface-lab": surfaceLabSurfaceManifest,
    timesheets: timesheetsSurfaceManifest,
    roster: rosterSurfaceManifest,
    "roster-day-timeline": rosterDayTimelineSurfaceManifest,
    "leave-requests": leaveRequestsSurfaceManifest,
    billing: billingSurfaceManifest,
    support: supportSurfaceManifest,
    profile: profileSurfaceManifest,
    staff: staffSurfaceManifest,
    "admin-page": adminPageSurfaceManifest,
    "admin-xero-page": adminXeroPageSurfaceManifest,
    "admin-venue-config": adminVenueConfigSurfaceManifest,
    "admin-invites": adminInvitesSurfaceManifest,
    "admin-exports": adminExportsSurfaceManifest,
    "admin-shift-types": adminShiftTypesSurfaceManifest,
    "admin-roster-groups": adminRosterGroupsSurfaceManifest,
    "admin-xero": adminXeroSurfaceManifest
  };
  function isFrontendSurfaceName(value) {
    return typeof value === "string" && Object.prototype.hasOwnProperty.call(FrontendSurfaceRegistry, value);
  }

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
  var uiRegionFragmentSelector = `[${fragmentDomAttr}="true"]`;
  function closestUiRegionFragment(value) {
    if (isHTMLElement(value)) {
      if (value.matches(uiRegionFragmentSelector)) return value;
      return closestHTMLElement(value, uiRegionFragmentSelector);
    }
    return closestHTMLElement(value, uiRegionFragmentSelector);
  }

  // frontend/ts/fragments/events.ts
  function uiRegionEventName(lifecycleEvent) {
    switch (lifecycleEvent) {
      case "request-start":
        return regionRequestStartEvent;
      case "before-swap":
        return regionBeforeSwapEvent;
      case "after-swap":
        return regionAfterSwapEvent;
      case "settle":
        return regionSettleEvent;
      case "error":
        return regionErrorEvent;
    }
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
    { htmxEventName: "htmx:beforeRequest", lifecycleEvent: regionLifecycleEvent("request-start") },
    { htmxEventName: "htmx:beforeSwap", lifecycleEvent: regionLifecycleEvent("before-swap") },
    { htmxEventName: "htmx:afterSwap", lifecycleEvent: regionLifecycleEvent("after-swap") },
    { htmxEventName: "htmx:afterSettle", lifecycleEvent: regionLifecycleEvent("settle") },
    { htmxEventName: "htmx:responseError", lifecycleEvent: regionLifecycleEvent("error"), errorKind: "response-error" },
    { htmxEventName: "htmx:sendError", lifecycleEvent: regionLifecycleEvent("error"), errorKind: "send-error" },
    { htmxEventName: "htmx:timeout", lifecycleEvent: regionLifecycleEvent("error"), errorKind: "timeout" }
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
    const rawProfile = region.getAttribute(regionTransitionDomAttr);
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
    root.addEventListener(regionBeforeSwapEvent, onBeforeSwap);
    root.addEventListener(regionAfterSwapEvent, onAfterSwap);
    root.addEventListener(regionSettleEvent, onDone);
    root.addEventListener(regionErrorEvent, onDone);
    return function disableUiRegionTransitions() {
      root.removeEventListener(regionBeforeSwapEvent, onBeforeSwap);
      root.removeEventListener(regionAfterSwapEvent, onAfterSwap);
      root.removeEventListener(regionSettleEvent, onDone);
      root.removeEventListener(regionErrorEvent, onDone);
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
    const mount = target.closest(`[${attrs.surface}]`);
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
  var interactionSessionStartEventName = interactionSessionStartEvent;
  var interactionSessionEndEventName = interactionSessionEndEvent;
  var interactionSessionCancelRequestEventName = interactionSessionCancelRequestEvent;
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
        const mount = target.closest(`[${attrs2.surface}]`);
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

  // frontend/ts/live-updates/frontend-surface.ts
  function parseFrontendSurfaceSubscriptionConfig(value) {
    const config = parseFrontendSurfaceMountConfig(value);
    if (!config?.subscription) return null;
    const resyncFragments = config.subscription.resyncFragments.map(surfaceLiveFragmentToWire);
    if (resyncFragments.length === 0) return null;
    return {
      feature: config.surface,
      surface: config.surface,
      scope: config.subscription.scope,
      scopeKey: config.subscription.scopeKey,
      mountKey: config.mountKey,
      socketPath: "/live-updates",
      resyncFragments,
      decorateRequestsWithin: config.subscription.resyncFragments.map((fragment) => `#${fragment.targetId}`)
    };
  }
  function parseFrontendSurfaceMountConfig(value) {
    if (!isFrontendSurfaceMountConfig(value)) return null;
    return {
      ...value,
      subscription: value.subscription ?? null,
      fragments: value.fragments.map((fragment) => ({
        ...fragment,
        protection: fragment.protection ?? null,
        loadPolicy: fragment.loadPolicy ?? null
      }))
    };
  }
  function isFrontendSurfaceMountConfig(value) {
    if (!isRecord2(value)) return false;
    if (!isFrontendSurfaceName(value.surface)) return false;
    if (typeof value.scopeKey !== "string" || typeof value.mountKey !== "string") return false;
    if (!Array.isArray(value.fragments) || !value.fragments.every((fragment) => isFrontendSurfaceMountedFragmentConfigForSurface(value.surface, fragment))) return false;
    if (value.subscription !== null && value.subscription !== void 0 && !isFrontendSurfaceLiveSubscription(value.subscription)) return false;
    return true;
  }
  function isFrontendSurfaceMountedFragmentConfigForSurface(surface, value) {
    if (!isRecord2(value)) return false;
    if (!isRecord2(value.key)) return false;
    if (typeof value.key.kind !== "string" || !surfaceHasFragment(surface, value.key.kind)) return false;
    if (typeof value.targetId !== "string" || typeof value.url !== "string") return false;
    if (value.protection !== null && value.protection !== void 0 && !isRecord2(value.protection)) return false;
    if (value.loadPolicy !== null && value.loadPolicy !== void 0 && typeof value.loadPolicy !== "string") return false;
    return true;
  }
  function surfaceHasFragment(surface, fragment) {
    return FrontendSurfaceRegistry[surface].fragments.includes(fragment);
  }
  function isRecord2(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function surfaceLiveFragmentToWire(fragment) {
    return {
      fragmentKey: {
        surface: fragment.fragment.surface,
        kind: fragment.fragment.fragment.kind,
        params: fragment.fragment.fragment.params
      },
      targetId: fragment.targetId,
      url: fragment.url,
      deferUntilBlur: fragment.deferUntilBlur,
      protectionPolicy: fragmentProtectionToWire(fragment.protectionPolicy)
    };
  }
  function fragmentProtectionToWire(protection) {
    if (protection.kind !== "focused-field") return { kind: "none" };
    if (typeof protection.activeSelector !== "string") return { kind: "none" };
    if (typeof protection.fieldKeyAttr !== "string") return { kind: "none" };
    if (typeof protection.fieldNameFallback !== "boolean") return { kind: "none" };
    if (protection.containerSelector !== null && protection.containerSelector !== void 0 && typeof protection.containerSelector !== "string") return { kind: "none" };
    return {
      kind: "focused-field",
      activeSelector: protection.activeSelector,
      fieldKeyAttr: protection.fieldKeyAttr,
      fieldNameFallback: protection.fieldNameFallback,
      containerSelector: protection.containerSelector ?? null
    };
  }
  function frontendSurfaceInstanceId(config) {
    return `${config.surface}:${config.scopeKey}:${config.mountKey}`;
  }
  function scanFrontendSurfaceMountInstances(root) {
    const scanRoot = root ?? (typeof document !== "undefined" ? document : null);
    if (!scanRoot) return [];
    const instances = [];
    scanRoot.querySelectorAll("[data-bepis-surface-config]").forEach((ownerEl) => {
      if (!(ownerEl instanceof HTMLElement)) return;
      const rawConfig = ownerEl.getAttribute("data-bepis-surface-config");
      if (!rawConfig) return;
      let parsedJson;
      try {
        parsedJson = JSON.parse(rawConfig);
      } catch (_error) {
        return;
      }
      const config = parseFrontendSurfaceMountConfig(parsedJson);
      if (!config) return;
      instances.push({
        instanceId: frontendSurfaceInstanceId(config),
        surface: config.surface,
        scopeKey: config.scopeKey,
        mountKey: config.mountKey,
        ownerEl,
        depth: surfaceMountDepth(ownerEl)
      });
    });
    return instances;
  }
  function reconcileFrontendSurfaceInstances(activeInstances, currentInstances) {
    const currentById = /* @__PURE__ */ new Map();
    currentInstances.forEach((instance) => currentById.set(instance.instanceId, instance));
    const removed = [];
    activeInstances.forEach((instance, instanceId) => {
      if (!currentById.has(instanceId)) removed.push(instance);
    });
    const added = [];
    const retained = [];
    currentById.forEach((instance, instanceId) => {
      if (activeInstances.has(instanceId)) retained.push(instance);
      else added.push(instance);
    });
    removed.sort((left, right) => right.depth - left.depth);
    return { added, removed, retained };
  }
  function surfaceMountDepth(ownerEl) {
    let depth = 0;
    let current = ownerEl.parentElement;
    while (current) {
      if (current.hasAttribute("data-bepis-surface-config")) depth += 1;
      current = current.parentElement;
    }
    return depth;
  }

  // frontend/ts/live-updates/diagnostics.ts
  function createLiveUpdateDiagnostics(targetWindow, targetDocument) {
    let nextPerfToken = 0;
    function supportsPerformanceTimeline() {
      return Boolean(targetWindow.performance && typeof targetWindow.performance.mark === "function" && typeof targetWindow.performance.measure === "function");
    }
    function perfToken(prefix) {
      nextPerfToken += 1;
      return `${prefix}-${Date.now()}-${nextPerfToken}`;
    }
    function beginPerfSpan(name, detail) {
      if (!supportsPerformanceTimeline()) return null;
      const token = perfToken(name);
      const startMark = `${token}:start`;
      targetWindow.performance.mark(startMark, detail ? { detail } : void 0);
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
      targetWindow.performance.mark(endMark, detail ? { detail } : void 0);
      let duration = null;
      try {
        targetWindow.performance.measure(span.name, {
          start: span.startMark,
          end: endMark,
          detail: detail || void 0
        });
        const entries = targetWindow.performance.getEntriesByName(span.name, "measure");
        const entry = entries[entries.length - 1];
        duration = entry ? entry.duration : null;
      } catch (_error) {
        duration = null;
      }
      targetWindow.performance.clearMarks(span.startMark);
      targetWindow.performance.clearMarks(endMark);
      targetDocument.dispatchEvent(new CustomEvent("app:live-update-performance", {
        detail: {
          name: span.name,
          duration,
          ...detail
        }
      }));
      return duration;
    }
    function emitDebugEvent(name, detail) {
      targetDocument.dispatchEvent(new CustomEvent("app:live-update-debug", {
        detail: {
          name,
          ...detail || {}
        }
      }));
    }
    return {
      beginPerfSpan,
      endPerfSpan,
      emitDebugEvent
    };
  }

  // frontend/ts/live-updates/lazy-surface.ts
  var lazySurfaceSelector = `[${lazySurfaceDomAttr}="true"]`;
  var lazySurfaceRetrySelector = `[${lazySurfaceDomAttr}="true"][${lazyRetryDomAttr}="true"]`;
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
    root.addEventListener(regionRequestStartEvent, onRequestStart);
    root.addEventListener(regionErrorEvent, onRegionError);
    return function disableLazySurfaceErrorHandling() {
      root.removeEventListener(regionRequestStartEvent, onRequestStart);
      root.removeEventListener(regionErrorEvent, onRegionError);
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
  function buildSurfaceSubscription(scope, scopeKey, mountedFragments) {
    return {
      scope,
      scopeKey,
      mountedFragments
    };
  }
  function buildLiveUpdateSubscribeCommand(subscription, clientId, lastSeenVersion) {
    return encodeLiveUpdateCommand({
      type: "subscribe",
      subscription,
      clientId,
      lastSeenVersion
    });
  }
  function buildLiveUpdateUnsubscribeCommand(subscription) {
    return encodeLiveUpdateCommand({
      type: "unsubscribe",
      subscription
    });
  }
  function liveUpdateFragmentMergeKey(fragment) {
    if (!fragment || !fragment.targetId) return null;
    const fragmentKey = fragment.fragmentKey ? JSON.stringify(fragment.fragmentKey) : "";
    return `${fragmentKey}:${fragment.targetId}`;
  }
  function liveUpdateFragmentSemanticKey(fragment) {
    return fragment && fragment.fragmentKey ? JSON.stringify(fragment.fragmentKey) : null;
  }
  function liveUpdateInvalidationIsOwnEcho(sourceClientId, activeClientId) {
    return Boolean(sourceClientId && activeClientId && sourceClientId === activeClientId);
  }
  function resolveMountedFragmentsForInvalidation(subscriptions, fragments, scopeKey = null) {
    const resolved = [];
    const seen = /* @__PURE__ */ new Set();
    fragments.forEach((fragment) => {
      const semanticKey = liveUpdateFragmentSemanticKey(fragment);
      const matches = [];
      for (const subscription of subscriptions) {
        if (scopeKey && subscription.scopeKey !== scopeKey) continue;
        subscription.resyncFragments.forEach((mountedFragment) => {
          if (liveUpdateFragmentSemanticKey(mountedFragment) === semanticKey) {
            matches.push({ ...fragment, ...mountedFragment });
          }
        });
      }
      const selected = matches.length > 0 ? matches : [fragment];
      selected.forEach((candidate) => {
        const mergeKey = liveUpdateFragmentMergeKey(candidate);
        if (mergeKey && seen.has(mergeKey)) return;
        if (mergeKey) seen.add(mergeKey);
        resolved.push(candidate);
      });
    });
    return resolved;
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
    const actorFragmentRefreshEventName = liveFragmentsRefreshEvent;
    const pendingDeferredFragments = /* @__PURE__ */ new Map();
    const pendingInteractionDeferredFragments = /* @__PURE__ */ new Map();
    const pendingInteractionTimers = /* @__PURE__ */ new Map();
    const activeInteractionSessions = createActiveInteractionSessionTracker(document);
    const inFlightFragments = /* @__PURE__ */ new Map();
    const activeSubscriptions = /* @__PURE__ */ new Map();
    const activeSurfaceInstances = /* @__PURE__ */ new Map();
    const scopeVersions = /* @__PURE__ */ new Map();
    let socket = null;
    let socketPath = null;
    let reconnectTimer = null;
    let reconnectAttempt = 0;
    let activeClientId = null;
    const { beginPerfSpan, endPerfSpan, emitDebugEvent } = createLiveUpdateDiagnostics(window, document);
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
      document.querySelectorAll("[data-bepis-surface-config]").forEach(function(ownerEl) {
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
        case "focused-field":
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
      const resolvedFragment = fragment;
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
    function wireSubscription(subscription) {
      return buildSurfaceSubscription(subscription.scope, subscription.scopeKey, subscription.resyncFragments);
    }
    function subscribeScope(subscription) {
      const lastSeenVersion = getScopeVersion(subscription.scopeKey);
      sendCommand(buildLiveUpdateSubscribeCommand(wireSubscription(subscription), ensureClientId(), lastSeenVersion));
    }
    function unsubscribeScope(subscription) {
      sendCommand(buildLiveUpdateUnsubscribeCommand(wireSubscription(subscription)));
    }
    function readFrontendSurface(ownerEl) {
      if (!(ownerEl instanceof HTMLElement)) return null;
      const rawConfig = ownerEl.getAttribute("data-bepis-surface-config");
      if (!rawConfig) return null;
      let config = null;
      try {
        config = JSON.parse(rawConfig);
      } catch (error) {
        reportSurfaceConfigError(ownerEl, error);
        return null;
      }
      const parsedConfig = parseFrontendSurfaceSubscriptionConfig(config);
      if (parsedConfig === null) {
        if (parseFrontendSurfaceMountConfig(config) !== null) return null;
        reportSurfaceConfigError(ownerEl, new Error("Invalid FrontendSurface config"));
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
      document.querySelectorAll("[data-bepis-surface-config]").forEach(function(ownerEl) {
        if (!(ownerEl instanceof HTMLElement)) return;
        const scopeInfo = readFrontendSurface(ownerEl);
        if (!scopeInfo || !scopeInfo.scopeKey) return;
        subscriptions.push({ ...scopeInfo, ownerEl });
      });
      return subscriptions;
    }
    function shouldDecorateDeclarativeRequest(event) {
      const sourceEl = event.detail && event.detail.elt;
      if (!(sourceEl instanceof HTMLElement)) return false;
      const ownerEl = sourceEl.closest("[data-bepis-surface-config]");
      if (!(ownerEl instanceof HTMLElement)) return false;
      const scopeInfo = readFrontendSurface(ownerEl);
      if (!scopeInfo) return false;
      if (isSurfaceOwnedHtmxRequest(sourceEl, ownerEl)) return true;
      if (scopeInfo.decorateRequestsWithin.length === 0) return true;
      return scopeInfo.decorateRequestsWithin.some(function(selector) {
        return Boolean(selector && sourceEl.closest(selector));
      });
    }
    function isSurfaceOwnedHtmxRequest(sourceEl, ownerEl) {
      const surfaceOwnedControl = sourceEl.closest("[data-bepis-surface-action], [data-bepis-intent-form]");
      if (!(surfaceOwnedControl instanceof HTMLElement)) return false;
      return surfaceOwnedControl.closest("[data-bepis-surface-config]") === ownerEl;
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
      if (liveUpdateInvalidationIsOwnEcho(message.sourceClientId, activeClientId)) return;
      const perfSpan = beginPerfSpan("live_updates.handle_invalidate", {
        fragmentCount: message.fragments.length,
        scopeKind: message.scope && typeof message.scope.surface === "string" ? message.scope.surface : null,
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
      resolveMountedFragmentsForInvalidation([subscription], message.fragments, scopeKey).forEach(handleFragmentRefreshRequest);
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
    function reconcileSurfaceMountInstances() {
      const reconciliation = reconcileFrontendSurfaceInstances(activeSurfaceInstances, scanFrontendSurfaceMountInstances(document));
      reconciliation.removed.forEach(function(instance) {
        activeSurfaceInstances.delete(instance.instanceId);
        emitDebugEvent("surface_disposed", {
          instanceId: instance.instanceId,
          surface: instance.surface,
          scopeKey: instance.scopeKey,
          mountKey: instance.mountKey,
          depth: instance.depth
        });
      });
      reconciliation.retained.forEach(function(instance) {
        activeSurfaceInstances.set(instance.instanceId, instance);
      });
      reconciliation.added.forEach(function(instance) {
        activeSurfaceInstances.set(instance.instanceId, instance);
        emitDebugEvent("surface_initialized", {
          instanceId: instance.instanceId,
          surface: instance.surface,
          scopeKey: instance.scopeKey,
          mountKey: instance.mountKey,
          depth: instance.depth
        });
      });
    }
    function subscriptionSignature(subscription) {
      const fragments = subscription.resyncFragments.map((fragment) => ({ key: liveUpdateFragmentMergeKey(fragment) || JSON.stringify(fragment.fragmentKey), fragment })).sort((left, right) => left.key.localeCompare(right.key)).map((entry) => entry.fragment);
      return JSON.stringify({ path: subscription.path, scope: subscription.scope, resyncFragments: fragments });
    }
    function subscriptionsEquivalent(left, right) {
      return Boolean(left && subscriptionSignature(left) === subscriptionSignature(right));
    }
    function syncConnection() {
      ensureClientId();
      reconcileSurfaceMountInstances();
      const desired = desiredSubscriptions();
      const firstDesired = desired.values().next().value;
      const nextPath = firstDesired?.path ?? null;
      if (desired.size === 0 || !nextPath) {
        activeSubscriptions.clear();
        activeSurfaceInstances.clear();
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
      const changed = [];
      desired.forEach(function(subscription, scopeKey) {
        const active = activeSubscriptions.get(scopeKey);
        if (!active) {
          added.push(subscription);
        } else if (!subscriptionsEquivalent(active, subscription)) {
          changed.push({ previous: active, next: subscription });
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
      changed.forEach(function(change) {
        unsubscribeScope(change.previous);
        clearScopeVersion(change.previous.scopeKey);
        emitDebugEvent("subscription_changed", {
          scopeKey: change.previous.scopeKey,
          previousFragmentCount: change.previous.resyncFragments.length,
          nextFragmentCount: change.next.resyncFragments.length
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
        changed.forEach(function(change) {
          subscribeScope(change.next);
        });
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
      const scopeKey = detail && typeof detail.scopeKey === "string" ? detail.scopeKey : null;
      resolveMountedFragmentsForInvalidation(activeSubscriptions.values(), fragments, scopeKey).forEach(handleFragmentRefreshRequest);
    }
    document.addEventListener(actorFragmentRefreshEventName, handleActorFragmentRefreshEvent);
    document.addEventListener(interactionSessionEndEvent, function() {
      flushInteractionDeferredFragmentsWithoutActiveSessions();
      flushDeferredFragmentsWithoutActiveInputs();
    });
    document.addEventListener("htmx:afterSwap", function() {
      flushInteractionDeferredFragmentsWithoutActiveSessions();
      window.setTimeout(syncConnection, 0);
    });
    document.addEventListener("htmx:afterSettle", function() {
      window.setTimeout(syncConnection, 0);
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
    document.addEventListener(pageReadyEvent, syncConnection);
  })();
})();
