"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  function isRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function hasExactKeys(value, keys) {
    return Object.keys(value).every((key) => keys.includes(key));
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
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "lab-shell" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "lab-panel" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["panelId"]) && typeof value["params"]["panelId"] === "string");
  }
  function isTimesheetsSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-toolbar" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-day-columns" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-day-section" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["dayOffset"]) && (typeof value["params"]["dayOffset"] === "number" && Number.isInteger(value["params"]["dayOffset"])));
  }
  function isRosterSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-content" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-grid-toolbar" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-grid-frame" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-columns" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-rail" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-wage-rail" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-slots-grid" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-staff-panel" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-staff-self-service-leave-form" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-week-overview" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-section" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["rosterDayId"]) && typeof value["params"]["rosterDayId"] === "string") || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-row" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["rosterDayId", "rowIndex"]) && typeof value["params"]["rosterDayId"] === "string" && (typeof value["params"]["rowIndex"] === "number" && Number.isInteger(value["params"]["rowIndex"])));
  }
  function isRosterDayTimelineSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-timeline-content" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["rosterDayId"]) && typeof value["params"]["rosterDayId"] === "string");
  }
  function isLeaveRequestsSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "leave-section-count" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["leaveSection"]) && typeof value["params"]["leaveSection"] === "string") || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "leave-section-list" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["leaveSection"]) && typeof value["params"]["leaveSection"] === "string");
  }
  function isBillingSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "billing-status" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], []));
  }
  function isSupportSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "support-award-rates" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "support-public-holidays" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], []));
  }
  function isProfileSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "profile-details-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "profile-preferences-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "profile-security-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "profile-leave-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "profile-rsa-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], []));
  }
  function isStaffSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "staff-details-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "staff-preferences-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "staff-leave-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], []));
  }
  function isAdminPageSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-page-content" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], []));
  }
  function isAdminXeroPageSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-xero-page-content" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], []));
  }
  function isAdminVenueConfigSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-venue-settings" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], []));
  }
  function isAdminInvitesSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-invites" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], []));
  }
  function isAdminExportsSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-exports" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], []));
  }
  function isAdminShiftTypesSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-shift-types" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], []));
  }
  function isAdminRosterGroupsSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-roster-groups" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], []));
  }
  function isAdminXeroSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-xero-shell" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], []));
  }
  function isSurfaceScope(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "surface-lab" && isSurfaceLabSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "timesheets" && isTimesheetsSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "roster" && isRosterSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "roster-day-timeline" && isRosterDayTimelineSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "leave-requests" && isLeaveRequestsSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "billing" && isBillingSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "support" && isSupportSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "profile" && isProfileSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "staff" && isStaffSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-page" && isAdminPageSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-xero-page" && isAdminXeroPageSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-venue-config" && isAdminVenueConfigSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-invites" && isAdminInvitesSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-exports" && isAdminExportsSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-shift-types" && isAdminShiftTypesSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-roster-groups" && isAdminRosterGroupsSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-xero" && isAdminXeroSurfaceScope(value.scope);
  }
  function isSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "surface-lab" && isSurfaceLabSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "timesheets" && isTimesheetsSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "roster" && isRosterSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "roster-day-timeline" && isRosterDayTimelineSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "leave-requests" && isLeaveRequestsSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "billing" && isBillingSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "support" && isSupportSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "profile" && isProfileSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "staff" && isStaffSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-page" && isAdminPageSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-xero-page" && isAdminXeroPageSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-venue-config" && isAdminVenueConfigSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-invites" && isAdminInvitesSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-exports" && isAdminExportsSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-shift-types" && isAdminShiftTypesSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-roster-groups" && isAdminRosterGroupsSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-xero" && isAdminXeroSurfaceFragmentKey({ kind: value.kind, params: value.params });
  }
  function __canonicalFrontendContractJson(value) {
    if (Array.isArray(value)) return `[${value.map(__canonicalFrontendContractJson).join(",")}]`;
    if (isRecord(value)) return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${__canonicalFrontendContractJson(value[key])}`).join(",")}}`;
    return JSON.stringify(value) ?? "null";
  }
  function surfaceFragmentKeyIdentity(value) {
    return __canonicalFrontendContractJson([value.surface, value.kind, value.params]);
  }
  var pageReadyEvent = "bepis:page-ready";
  function isLiveFragmentsRefreshEventDetail(value) {
    return isRecord(value) && hasExactKeys(value, ["scope", "scopeKey", "fragments"]) && isSurfaceScope(value["scope"]) && typeof value["scopeKey"] === "string" && (Array.isArray(value["fragments"]) && value["fragments"].every((item) => isSurfaceFragmentKey(item)));
  }
  function parseLiveFragmentsRefreshEventDetail(value) {
    if (isLiveFragmentsRefreshEventDetail(value)) return value;
    throw new Error("Invalid LiveFragmentsRefreshEventDetail");
  }
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
  var liveUpdateSocketPath = "live-updates";
  var liveUpdateClientIdHeader = "X-Live-Update-Client-Id";
  var surfaceConfigDomAttr = "data-bepis-surface-config";
  var surfaceActionDomAttr = "data-bepis-surface-action";
  function encodeLiveUpdateCommand(value) {
    return value;
  }
  function isLiveUpdateMessage(value) {
    return isRecord(value) && hasExactKeys(value, ["type", "scope", "scopeKey", "currentVersion", "resync"]) && value["type"] === "subscribed" && isSurfaceScope(value["scope"]) && typeof value["scopeKey"] === "string" && (typeof value["currentVersion"] === "number" && Number.isInteger(value["currentVersion"])) && typeof value["resync"] === "boolean" || isRecord(value) && hasExactKeys(value, ["type", "scope", "scopeKey", "version", "fragments", "sourceClientId"]) && value["type"] === "invalidate" && isSurfaceScope(value["scope"]) && typeof value["scopeKey"] === "string" && (typeof value["version"] === "number" && Number.isInteger(value["version"])) && (Array.isArray(value["fragments"]) && value["fragments"].every((item) => isSurfaceFragmentKey(item))) && (value["sourceClientId"] === null || typeof value["sourceClientId"] === "string") || isRecord(value) && hasExactKeys(value, ["type", "message"]) && value["type"] === "error" && typeof value["message"] === "string";
  }
  function parseLiveUpdateMessage(value) {
    if (isLiveUpdateMessage(value)) return value;
    throw new Error("Invalid LiveUpdateMessage");
  }
  function isSurfaceLabLabScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "weekOffset"]) && typeof value["venueId"] === "string" && (typeof value["weekOffset"] === "number" && Number.isInteger(value["weekOffset"]));
  }
  function isTimesheetsTimesheetWeekScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "weekOffset"]) && typeof value["venueId"] === "string" && (typeof value["weekOffset"] === "number" && Number.isInteger(value["weekOffset"]));
  }
  function isRosterRosterWeekScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "rosterGroupId", "weekOffset"]) && typeof value["venueId"] === "string" && typeof value["rosterGroupId"] === "string" && (typeof value["weekOffset"] === "number" && Number.isInteger(value["weekOffset"]));
  }
  function isRosterDayTimelineRosterDayTimelineScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "rosterGroupId", "weekOffset", "rosterDayId"]) && typeof value["venueId"] === "string" && typeof value["rosterGroupId"] === "string" && (typeof value["weekOffset"] === "number" && Number.isInteger(value["weekOffset"])) && typeof value["rosterDayId"] === "string";
  }
  function isLeaveRequestsLeaveRequestsScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isBillingBillingVenueScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isSupportSupportPlatformScope(value) {
    return isRecord(value) && hasExactKeys(value, []);
  }
  function isProfileProfileScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "staffId"]) && typeof value["venueId"] === "string" && typeof value["staffId"] === "string";
  }
  function isStaffStaffScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "staffId"]) && typeof value["venueId"] === "string" && typeof value["staffId"] === "string";
  }
  function isAdminPageAdminPageScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isAdminXeroPageAdminXeroPageScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isAdminVenueConfigAdminVenueConfigScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isAdminInvitesAdminInvitesScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isAdminExportsAdminExportsScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isAdminShiftTypesAdminShiftTypesScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isAdminRosterGroupsAdminRosterGroupsScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isAdminXeroAdminXeroScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"]) && typeof value["venueId"] === "string";
  }
  var surfaceLabSurfaceManifest = { "surface": "surface-lab", "scopes": ["lab"], "fragments": ["lab-shell", "lab-panel"], "liveFragments": [], "htmxActions": [{ "name": "refresh-panel", "fields": ["panelId"], "htmx": { "method": "post", "trigger": null, "include": "#lab-panel-include", "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#lab-panel-target", "swap": "outerHTML", "pushUrl": false, "custom": [{ "name": "lab-panel-custom-htmx", "reason": "lab fixture covers auditable custom HTMX metadata" }] } }], "intents": ["move-lab-card"], "sessions": ["drag"], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": ["drag-preview"], "domTokens": ["lab-root", "lab-dropzone", "lab-panel-target", "lab-panel-include"], "overlayLanes": [], "containedSurfaces": {} };
  var timesheetsSurfaceManifest = { "surface": "timesheets", "scopes": ["timesheet-week"], "fragments": ["timesheet-toolbar", "timesheet-day-columns", "timesheet-day-section"], "liveFragments": ["timesheet-toolbar", "timesheet-day-columns", "timesheet-day-section"], "htmxActions": [{ "name": "navigate-timesheet-week", "fields": ["weekOffset", "showApproved", "showAllStaff", "staffFilterId"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": "closest #timesheet-week-shell:replace", "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": true, "custom": [] } }, { "name": "update-timesheet-filters", "fields": ["weekOffset", "showApproved", "showAllStaff", "staffFilterId"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": "closest #timesheet-week-shell:replace", "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": true, "custom": [] } }, { "name": "approve-timesheet-entry", "fields": ["weekOffset", "showApproved", "showAllStaff", "staffFilterId"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": false, "custom": [] } }, { "name": "unapprove-timesheet-entry", "fields": ["weekOffset", "showApproved", "showAllStaff", "staffFilterId"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": false, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["timesheet-week-shell"], "overlayLanes": [], "containedSurfaces": {} };
  var rosterSurfaceManifest = { "surface": "roster", "scopes": ["roster-week"], "fragments": ["roster-content", "roster-grid-toolbar", "roster-grid-frame", "roster-day-columns", "roster-day-rail", "roster-wage-rail", "roster-slots-grid", "roster-staff-panel", "roster-staff-self-service-leave-form", "roster-week-overview", "roster-day-section", "roster-row"], "liveFragments": ["roster-content", "roster-grid-toolbar", "roster-grid-frame", "roster-day-columns", "roster-day-rail", "roster-wage-rail", "roster-slots-grid", "roster-staff-panel", "roster-staff-self-service-leave-form", "roster-day-section", "roster-row"], "htmxActions": [{ "name": "navigate-roster-week", "fields": ["weekOffset", "rosterGroupId"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#roster-week-shell", "swap": null, "pushUrl": true, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "roster week navigation serializes through the stable roster week shell" }] } }, { "name": "toggle-roster-warnings", "fields": ["showRosterWarnings"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "preference toggles serialize through the stable roster week shell" }] } }, { "name": "toggle-roster-wage-estimates", "fields": ["showWageEstimates"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "preference toggles serialize through the stable roster week shell" }] } }, { "name": "sort-roster-week", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#roster-content", "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "sort mutations serialize through the stable roster week shell" }] } }, { "name": "toggle-roster-week-live-status", "fields": ["isLive"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#roster-content", "swap": "outerHTML", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "live toggle serializes through the stable roster week shell" }] } }, { "name": "toggle-roster-assignment-filters", "fields": ["hideStaffAtIdealShifts", "hideStaffUnavailable", "hideStaffOnApprovedLeave", "hideStaffAlreadyAssignedToday"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "assignment filter toggles serialize through the stable roster week shell" }] } }, { "name": "copy-roster-week", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#roster-content", "swap": "outerHTML", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "copy mutations serialize through the stable roster week shell" }, { "name": "copy-roster-week-custom-htmx", "reason": "copy previous week requires a destructive overwrite confirmation" }] } }, { "name": "create-roster-self-service-leave-request", "fields": ["startDate", "endDate", "reason"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#roster-staff-self-service-leave-form-fragment", "swap": "outerHTML", "pushUrl": false, "custom": [] } }, { "name": "create-roster-week-slot-definition", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#roster-content", "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "slot-definition mutations serialize through the stable roster week shell" }] } }, { "name": "delete-roster-week-slot-definition", "fields": [], "htmx": { "method": "delete", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#roster-content", "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "slot-definition mutations serialize through the stable roster week shell" }] } }, { "name": "toggle-roster-day-closed", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "day row mutations serialize through the stable roster week shell" }] } }, { "name": "add-roster-row", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "day row mutations serialize through the stable roster week shell" }] } }, { "name": "remove-roster-row", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": "none", "pushUrl": false, "custom": [{ "name": "roster-week-shell-sync-custom-htmx", "reason": "day row mutations serialize through the stable roster week shell" }] } }, { "name": "toggle-roster-staff-scope", "fields": ["staffScope"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#roster-staff-panel", "swap": "outerHTML", "pushUrl": false, "custom": [] } }, { "name": "set-roster-layout-mode", "fields": ["rosterLayoutMode"], "htmx": { "method": null, "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": null, "custom": [] } }, { "name": "move-roster-shift-to-slot", "fields": ["sourceItemKey", "targetDropzoneKey", "sessionKind", "pointerId", "pointerType", "startClientX", "startClientY", "currentClientX", "currentClientY", "deltaX", "deltaY"], "htmx": { "method": null, "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": null, "custom": [] } }, { "name": "duplicate-roster-shift-to-day", "fields": ["sourceItemKey", "targetDropzoneKey", "sessionKind", "pointerId", "pointerType", "startClientX", "startClientY", "currentClientX", "currentClientY", "deltaX", "deltaY"], "htmx": { "method": null, "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": null, "custom": [] } }, { "name": "drop-roster-staff", "fields": ["sourceItemKey", "targetDropzoneKey", "sessionKind", "pointerId", "pointerType", "startClientX", "startClientY", "currentClientX", "currentClientY", "deltaX", "deltaY"], "htmx": { "method": null, "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": null, "custom": [] } }], "intents": ["set-roster-layout-mode", "move-roster-shift-to-slot", "duplicate-roster-shift-to-day", "drop-roster-staff"], "sessions": ["drag"], "interaction": { "sourceRefs": [{ "ref": "shift-drag-source", "session": "drag", "intent": "move-roster-shift-to-slot", "sourceField": "sourceItemKey", "compatibleDropzones": ["shift-slot-dropzone", "day-column-dropzone", "delete-shift-dropzone"], "modifierVariants": [{ "semantic": "copy", "intent": "duplicate-roster-shift-to-day", "effects": { "global": [{ "className": "bepis-pointer-clone-shadow bepis-pointer-clone-shadow-copy", "kind": "clone-shadow", "layer": "drag-preview", "preserveGrabOffset": true, "source": "pointer-marker" }], "contextual": [{ "className": "bepis-dropzone-highlight", "kind": "dropzone-highlight" }] } }] }, { "ref": "staff-drag-source", "session": "drag", "intent": "drop-roster-staff", "sourceField": "sourceItemKey", "compatibleDropzones": ["existing-shift-dropzone", "staff-create-dropzone"], "modifierVariants": [] }], "dropzoneRefs": [{ "ref": "shift-slot-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }, { "ref": "staff-create-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }, { "ref": "day-column-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }, { "ref": "existing-shift-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }, { "ref": "delete-shift-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }], "activationRefs": [{ "ref": "roster-layout-mode-activation", "intent": "set-roster-layout-mode", "valueField": "rosterLayoutMode", "trigger": "click" }] }, "layers": ["drag-preview"], "domTokens": ["roster-content", "roster-week-shell", "roster-day-section", "roster-staff-panel", "roster-staff-self-service-leave-form-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var rosterDayTimelineSurfaceManifest = { "surface": "roster-day-timeline", "scopes": ["roster-day-timeline"], "fragments": ["roster-day-timeline-content"], "liveFragments": ["roster-day-timeline-content"], "htmxActions": [{ "name": "move-roster-timeline-shift", "fields": ["sourceItemKey", "targetDropzoneKey", "sessionKind", "pointerId", "pointerType", "startClientX", "startClientY", "currentClientX", "currentClientY", "deltaX", "deltaY"], "htmx": { "method": null, "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": null, "custom": [] } }], "intents": ["move-roster-timeline-shift"], "sessions": ["drag"], "interaction": { "sourceRefs": [{ "ref": "drag-source", "session": "drag", "intent": "move-roster-timeline-shift", "sourceField": "sourceItemKey", "compatibleDropzones": ["drag-dropzone"], "modifierVariants": [] }], "dropzoneRefs": [{ "ref": "drag-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }], "activationRefs": [] }, "layers": ["drag-preview"], "domTokens": ["roster-day-timeline-content"], "overlayLanes": [], "containedSurfaces": {} };
  var leaveRequestsSurfaceManifest = { "surface": "leave-requests", "scopes": ["leave-requests"], "fragments": ["leave-section-count", "leave-section-list"], "liveFragments": ["leave-section-count", "leave-section-list"], "htmxActions": [{ "name": "archive-leave-requests-page", "fields": ["archivePage"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#leave-archive-page-content", "swap": "none", "pushUrl": true, "custom": [] } }, { "name": "approve-leave-request", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#leave-requests-content", "swap": "none", "pushUrl": false, "custom": [] } }, { "name": "deny-leave-request", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#leave-requests-content", "swap": "none", "pushUrl": false, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["leave-requests-content", "leave-section-count", "leave-section-list", "leave-archive-page-content"], "overlayLanes": [], "containedSurfaces": {} };
  var billingSurfaceManifest = { "surface": "billing", "scopes": ["billing-venue"], "fragments": ["billing-status"], "liveFragments": ["billing-status"], "htmxActions": [], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": [], "overlayLanes": [], "containedSurfaces": {} };
  var supportSurfaceManifest = { "surface": "support", "scopes": ["support-platform"], "fragments": ["support-award-rates", "support-public-holidays"], "liveFragments": ["support-award-rates", "support-public-holidays"], "htmxActions": [{ "name": "create-public-holiday-refresh-job", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#support-public-holidays", "swap": "outerHTML", "pushUrl": null, "custom": [] } }, { "name": "create-fwc-mapd-refresh-job", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#support-award-rates", "swap": "outerHTML", "pushUrl": null, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["support-public-holidays", "support-award-rates"], "overlayLanes": [], "containedSurfaces": {} };
  var profileSurfaceManifest = { "surface": "profile", "scopes": ["profile"], "fragments": ["profile-details-section", "profile-preferences-section", "profile-security-section", "profile-leave-section", "profile-rsa-section"], "liveFragments": ["profile-details-section", "profile-preferences-section", "profile-security-section", "profile-leave-section", "profile-rsa-section"], "htmxActions": [{ "name": "update-profile-details", "fields": ["firstName", "lastName", "preferredName", "phone", "idealShiftsPerWeek", "emergencyContactName", "emergencyContactPhone", "section", "weekOffset", "rosterGroupId", "venueRole", "employmentBasis", "payRateSelection", "isActive", "rosterGroupIds"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": false, "custom": [{ "name": "staff-profile-section-htmx-attrs", "reason": "profile and staff forms provide their concrete section target and swap modifier at the route boundary" }] } }, { "name": "update-profile-shift-preferences", "fields": ["section", "weekOffset", "rosterGroupId", "shiftPreferenceKeys"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": false, "custom": [{ "name": "staff-profile-section-htmx-attrs", "reason": "profile and staff forms provide their concrete section target and swap modifier at the route boundary" }] } }, { "name": "create-profile-leave-request", "fields": ["startDate", "endDate", "reason"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#profile-leave-request-form-fragment", "swap": "outerHTML", "pushUrl": false, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["profile-details", "profile-preferences", "profile-leave-request-form-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var staffSurfaceManifest = { "surface": "staff", "scopes": ["staff"], "fragments": ["staff-details-section", "staff-preferences-section", "staff-leave-section"], "liveFragments": ["staff-details-section", "staff-preferences-section", "staff-leave-section"], "htmxActions": [{ "name": "update-staff-profile", "fields": ["firstName", "lastName", "preferredName", "phone", "idealShiftsPerWeek", "emergencyContactName", "emergencyContactPhone", "section", "weekOffset", "rosterGroupId", "venueRole", "employmentBasis", "payRateSelection", "isActive", "rosterGroupIds"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": false, "custom": [{ "name": "staff-profile-section-htmx-attrs", "reason": "profile and staff forms provide their concrete section target and swap modifier at the route boundary" }] } }, { "name": "update-staff-shift-preferences", "fields": ["section", "weekOffset", "rosterGroupId", "shiftPreferenceKeys"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": null, "swap": null, "pushUrl": false, "custom": [{ "name": "staff-profile-section-htmx-attrs", "reason": "profile and staff forms provide their concrete section target and swap modifier at the route boundary" }] } }, { "name": "create-staff-leave-request", "fields": ["startDate", "endDate", "reason"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#staff-leave-request-form-fragment", "swap": "outerHTML", "pushUrl": false, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["staff-details-target", "staff-preferences-target", "staff-leave-request-form-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var adminPageSurfaceManifest = { "surface": "admin-page", "scopes": ["admin-page"], "fragments": ["admin-page-content"], "liveFragments": [], "htmxActions": [], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": [], "overlayLanes": [], "containedSurfaces": { "admin-page-content": ["admin-invites", "admin-venue-config", "admin-exports", "admin-shift-types", "admin-roster-groups"] } };
  var adminXeroPageSurfaceManifest = { "surface": "admin-xero-page", "scopes": ["admin-xero-page"], "fragments": ["admin-xero-page-content"], "liveFragments": [], "htmxActions": [], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": [], "overlayLanes": [], "containedSurfaces": { "admin-xero-page-content": ["admin-xero"] } };
  var adminVenueConfigSurfaceManifest = { "surface": "admin-venue-config", "scopes": ["admin-venue-config"], "fragments": ["admin-venue-settings"], "liveFragments": ["admin-venue-settings"], "htmxActions": [{ "name": "update-venue-config", "fields": ["configField", "rosterEndTimesEnabled", "autoTimesheetCreationEnabled"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-venue-settings-fragment", "swap": "none", "pushUrl": false, "custom": [{ "name": "change-autosave-custom-htmx", "reason": "venue setting toggles submit the containing form on change" }] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["admin-venue-settings-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var adminInvitesSurfaceManifest = { "surface": "admin-invites", "scopes": ["admin-invites"], "fragments": ["admin-invites"], "liveFragments": ["admin-invites"], "htmxActions": [{ "name": "create-venue-invitation", "fields": ["email"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-invites-fragment", "swap": "none", "pushUrl": null, "custom": [] } }, { "name": "revoke-venue-invitation", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-invites-fragment", "swap": "none", "pushUrl": null, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["admin-invites-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var adminExportsSurfaceManifest = { "surface": "admin-exports", "scopes": ["admin-exports"], "fragments": ["admin-exports"], "liveFragments": ["admin-exports"], "htmxActions": [{ "name": "create-export-job", "fields": ["rangeStart", "rangeEnd", "exportType"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-exports-fragment", "swap": "none", "pushUrl": false, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["admin-exports-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var adminShiftTypesSurfaceManifest = { "surface": "admin-shift-types", "scopes": ["admin-shift-types"], "fragments": ["admin-shift-types"], "liveFragments": ["admin-shift-types"], "htmxActions": [{ "name": "create-shift-type", "fields": ["showInactiveShiftTypes", "name", "payRateSelection", "colourKey", "isActive"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-shift-types-fragment", "swap": "outerHTML", "pushUrl": null, "custom": [] } }, { "name": "update-shift-type", "fields": ["showInactiveShiftTypes", "name", "payRateSelection", "colourKey", "isActive"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-shift-types-fragment", "swap": "outerHTML", "pushUrl": null, "custom": [] } }, { "name": "move-shift-type-up", "fields": ["showInactiveShiftTypes"], "htmx": { "method": "post", "trigger": "click", "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-shift-types-fragment", "swap": "outerHTML", "pushUrl": false, "custom": [{ "name": "closest-form-custom-htmx", "reason": "move buttons submit the containing row form via hx-include=closest form" }] } }, { "name": "move-shift-type-down", "fields": ["showInactiveShiftTypes"], "htmx": { "method": "post", "trigger": "click", "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-shift-types-fragment", "swap": "outerHTML", "pushUrl": false, "custom": [{ "name": "closest-form-custom-htmx", "reason": "move buttons submit the containing row form via hx-include=closest form" }] } }, { "name": "autosave-shift-type-name", "fields": ["showInactiveShiftTypes", "name", "payRateSelection", "colourKey", "isActive"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-shift-types-fragment", "swap": "outerHTML", "pushUrl": null, "custom": [{ "name": "input-changed-autosave-custom-htmx", "reason": "name input autosave uses HTMX input changed delay:600ms, blur changed trigger and hx-include=closest form" }] } }, { "name": "autosave-shift-type-selection", "fields": ["showInactiveShiftTypes", "name", "payRateSelection", "colourKey", "isActive"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-shift-types-fragment", "swap": "outerHTML", "pushUrl": null, "custom": [{ "name": "change-autosave-custom-htmx", "reason": "select autosave uses HTMX change trigger and hx-include=closest form" }] } }, { "name": "toggle-inactive-shift-types", "fields": ["showInactiveShiftTypes"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-shift-types-fragment", "swap": "outerHTML", "pushUrl": null, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["admin-shift-types-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var adminRosterGroupsSurfaceManifest = { "surface": "admin-roster-groups", "scopes": ["admin-roster-groups"], "fragments": ["admin-roster-groups"], "liveFragments": ["admin-roster-groups"], "htmxActions": [{ "name": "create-roster-group", "fields": ["showInactiveRosterGroups", "name", "isActive"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-roster-groups-fragment", "swap": "none", "pushUrl": false, "custom": [] } }, { "name": "update-roster-group", "fields": ["showInactiveRosterGroups", "name", "isActive"], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-roster-groups-fragment", "swap": "none", "pushUrl": false, "custom": [] } }, { "name": "move-roster-group-up", "fields": ["showInactiveRosterGroups"], "htmx": { "method": "post", "trigger": "click", "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-roster-groups-fragment", "swap": "none", "pushUrl": false, "custom": [{ "name": "closest-form-custom-htmx", "reason": "move buttons submit the containing row form via hx-include=closest form" }] } }, { "name": "move-roster-group-down", "fields": ["showInactiveRosterGroups"], "htmx": { "method": "post", "trigger": "click", "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-roster-groups-fragment", "swap": "none", "pushUrl": false, "custom": [{ "name": "closest-form-custom-htmx", "reason": "move buttons submit the containing row form via hx-include=closest form" }] } }, { "name": "toggle-inactive-roster-groups", "fields": ["showInactiveRosterGroups"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-roster-groups-fragment", "swap": "outerHTML", "pushUrl": false, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["admin-roster-groups-fragment"], "overlayLanes": [], "containedSurfaces": {} };
  var adminXeroSurfaceManifest = { "surface": "admin-xero", "scopes": ["admin-xero"], "fragments": ["admin-xero-shell"], "liveFragments": ["admin-xero-shell"], "htmxActions": [{ "name": "sync-xero-payroll-reference-data", "fields": [], "htmx": { "method": "post", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#admin-xero-fragment", "swap": "none", "pushUrl": null, "custom": [{ "name": "load-reference-sync-custom-htmx", "reason": "automatic post-connect sync supplies load/push-url/indicator attributes; the manual shell action supplies this marker with no extra attributes" }] } }, { "name": "show-xero-timesheet-preparation-staff-mappings", "fields": ["showMatched", "editStaffId"], "htmx": { "method": "get", "trigger": null, "include": null, "sync": null, "indicator": null, "confirm": null, "select": null, "target": "#xero-preparation-staff-mappings", "swap": "outerHTML", "pushUrl": null, "custom": [] } }], "intents": [], "sessions": [], "interaction": { "sourceRefs": [], "dropzoneRefs": [], "activationRefs": [] }, "layers": [], "domTokens": ["admin-xero-fragment", "xero-preparation-staff-mappings"], "overlayLanes": [], "containedSurfaces": {} };
  function isFrontendSurfaceFragmentProtection(value) {
    return isRecord(value) && hasExactKeys(value, ["kind"]) && value["kind"] === "replace" || isRecord(value) && hasExactKeys(value, ["kind", "activeSelector", "fieldKeyAttr", "fieldNameFallback", "containerSelector"]) && value["kind"] === "focused-field" && typeof value["activeSelector"] === "string" && typeof value["fieldKeyAttr"] === "string" && typeof value["fieldNameFallback"] === "boolean" && (value["containerSelector"] === null || typeof value["containerSelector"] === "string");
  }
  function isSurfaceLabMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "surface-lab" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isTimesheetsMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "timesheets" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isRosterMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "roster" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isRosterDayTimelineMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "roster-day-timeline" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isLeaveRequestsMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "leave-requests" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isBillingMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "billing" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isSupportMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "support" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isProfileMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "profile" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isStaffMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "staff" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isAdminPageMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "admin-page" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isAdminXeroPageMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "admin-xero-page" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isAdminVenueConfigMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "admin-venue-config" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isAdminInvitesMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "admin-invites" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isAdminExportsMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "admin-exports" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isAdminShiftTypesMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "admin-shift-types" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isAdminRosterGroupsMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "admin-roster-groups" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isAdminXeroMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "admin-xero" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isSurfaceLabMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "surface-lab" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isSurfaceLabMountedFragmentConfig(fragment)) && value["subscription"] === null;
  }
  function isTimesheetsMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "timesheets" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isTimesheetsMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => ["timesheet-toolbar", "timesheet-day-columns", "timesheet-day-section"].includes(fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope"]) && isSurfaceScope(value["subscription"].scope) && value["subscription"].scope.surface === "timesheets" && value["fragments"].some((fragment) => ["timesheet-toolbar", "timesheet-day-columns", "timesheet-day-section"].includes(fragment.fragmentKey.kind)));
  }
  function isRosterMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "roster" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isRosterMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => ["roster-content", "roster-grid-toolbar", "roster-grid-frame", "roster-day-columns", "roster-day-rail", "roster-wage-rail", "roster-slots-grid", "roster-staff-panel", "roster-staff-self-service-leave-form", "roster-day-section", "roster-row"].includes(fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope"]) && isSurfaceScope(value["subscription"].scope) && value["subscription"].scope.surface === "roster" && value["fragments"].some((fragment) => ["roster-content", "roster-grid-toolbar", "roster-grid-frame", "roster-day-columns", "roster-day-rail", "roster-wage-rail", "roster-slots-grid", "roster-staff-panel", "roster-staff-self-service-leave-form", "roster-day-section", "roster-row"].includes(fragment.fragmentKey.kind)));
  }
  function isRosterDayTimelineMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "roster-day-timeline" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isRosterDayTimelineMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => ["roster-day-timeline-content"].includes(fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope"]) && isSurfaceScope(value["subscription"].scope) && value["subscription"].scope.surface === "roster-day-timeline" && value["fragments"].some((fragment) => ["roster-day-timeline-content"].includes(fragment.fragmentKey.kind)));
  }
  function isLeaveRequestsMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "leave-requests" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isLeaveRequestsMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => ["leave-section-count", "leave-section-list"].includes(fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope"]) && isSurfaceScope(value["subscription"].scope) && value["subscription"].scope.surface === "leave-requests" && value["fragments"].some((fragment) => ["leave-section-count", "leave-section-list"].includes(fragment.fragmentKey.kind)));
  }
  function isBillingMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "billing" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isBillingMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => ["billing-status"].includes(fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope"]) && isSurfaceScope(value["subscription"].scope) && value["subscription"].scope.surface === "billing" && value["fragments"].some((fragment) => ["billing-status"].includes(fragment.fragmentKey.kind)));
  }
  function isSupportMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "support" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isSupportMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => ["support-award-rates", "support-public-holidays"].includes(fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope"]) && isSurfaceScope(value["subscription"].scope) && value["subscription"].scope.surface === "support" && value["fragments"].some((fragment) => ["support-award-rates", "support-public-holidays"].includes(fragment.fragmentKey.kind)));
  }
  function isProfileMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "profile" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isProfileMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => ["profile-details-section", "profile-preferences-section", "profile-security-section", "profile-leave-section", "profile-rsa-section"].includes(fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope"]) && isSurfaceScope(value["subscription"].scope) && value["subscription"].scope.surface === "profile" && value["fragments"].some((fragment) => ["profile-details-section", "profile-preferences-section", "profile-security-section", "profile-leave-section", "profile-rsa-section"].includes(fragment.fragmentKey.kind)));
  }
  function isStaffMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "staff" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isStaffMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => ["staff-details-section", "staff-preferences-section", "staff-leave-section"].includes(fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope"]) && isSurfaceScope(value["subscription"].scope) && value["subscription"].scope.surface === "staff" && value["fragments"].some((fragment) => ["staff-details-section", "staff-preferences-section", "staff-leave-section"].includes(fragment.fragmentKey.kind)));
  }
  function isAdminPageMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-page" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminPageMountedFragmentConfig(fragment)) && value["subscription"] === null;
  }
  function isAdminXeroPageMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-xero-page" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminXeroPageMountedFragmentConfig(fragment)) && value["subscription"] === null;
  }
  function isAdminVenueConfigMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-venue-config" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminVenueConfigMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => ["admin-venue-settings"].includes(fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope"]) && isSurfaceScope(value["subscription"].scope) && value["subscription"].scope.surface === "admin-venue-config" && value["fragments"].some((fragment) => ["admin-venue-settings"].includes(fragment.fragmentKey.kind)));
  }
  function isAdminInvitesMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-invites" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminInvitesMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => ["admin-invites"].includes(fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope"]) && isSurfaceScope(value["subscription"].scope) && value["subscription"].scope.surface === "admin-invites" && value["fragments"].some((fragment) => ["admin-invites"].includes(fragment.fragmentKey.kind)));
  }
  function isAdminExportsMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-exports" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminExportsMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => ["admin-exports"].includes(fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope"]) && isSurfaceScope(value["subscription"].scope) && value["subscription"].scope.surface === "admin-exports" && value["fragments"].some((fragment) => ["admin-exports"].includes(fragment.fragmentKey.kind)));
  }
  function isAdminShiftTypesMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-shift-types" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminShiftTypesMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => ["admin-shift-types"].includes(fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope"]) && isSurfaceScope(value["subscription"].scope) && value["subscription"].scope.surface === "admin-shift-types" && value["fragments"].some((fragment) => ["admin-shift-types"].includes(fragment.fragmentKey.kind)));
  }
  function isAdminRosterGroupsMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-roster-groups" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminRosterGroupsMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => ["admin-roster-groups"].includes(fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope"]) && isSurfaceScope(value["subscription"].scope) && value["subscription"].scope.surface === "admin-roster-groups" && value["fragments"].some((fragment) => ["admin-roster-groups"].includes(fragment.fragmentKey.kind)));
  }
  function isAdminXeroMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-xero" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminXeroMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => ["admin-xero-shell"].includes(fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope"]) && isSurfaceScope(value["subscription"].scope) && value["subscription"].scope.surface === "admin-xero" && value["fragments"].some((fragment) => ["admin-xero-shell"].includes(fragment.fragmentKey.kind)));
  }
  function isFrontendSurfaceMountConfig(value) {
    return isSurfaceLabMountConfig(value) || isTimesheetsMountConfig(value) || isRosterMountConfig(value) || isRosterDayTimelineMountConfig(value) || isLeaveRequestsMountConfig(value) || isBillingMountConfig(value) || isSupportMountConfig(value) || isProfileMountConfig(value) || isStaffMountConfig(value) || isAdminPageMountConfig(value) || isAdminXeroPageMountConfig(value) || isAdminVenueConfigMountConfig(value) || isAdminInvitesMountConfig(value) || isAdminExportsMountConfig(value) || isAdminShiftTypesMountConfig(value) || isAdminRosterGroupsMountConfig(value) || isAdminXeroMountConfig(value);
  }
  function parseFrontendSurfaceMountConfig(value) {
    if (isFrontendSurfaceMountConfig(value)) return value;
    throw new Error("Invalid FrontendSurfaceMountConfig");
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
  function isFrontendSurfaceLiveFragmentName(surface, value) {
    return typeof value === "string" && FrontendSurfaceRegistry[surface].liveFragments.some((fragment) => fragment === value);
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
    let config;
    try {
      config = parseFrontendSurfaceMountConfig(value);
    } catch {
      return null;
    }
    if (!config.subscription) return null;
    const resyncFragments = config.fragments.filter((fragment) => isFrontendSurfaceLiveFragmentName(config.surface, fragment.fragmentKey.kind));
    if (resyncFragments.length === 0) return null;
    return {
      surface: config.surface,
      scope: config.subscription.scope,
      scopeKey: config.scopeKey,
      mountKey: config.mountKey,
      socketPath: `/${liveUpdateSocketPath}`,
      resyncFragments,
      decorateRequestsWithin: resyncFragments.map((fragment) => `#${fragment.targetId}`)
    };
  }
  function readFrontendSurfaceMountElement(ownerEl, reportError) {
    const rawConfig = ownerEl.getAttribute(surfaceConfigDomAttr);
    if (!rawConfig) return null;
    let config;
    try {
      config = parseFrontendSurfaceMountConfig(JSON.parse(rawConfig));
    } catch (error) {
      reportError?.(ownerEl, error instanceof Error ? error : new Error(String(error)));
      return null;
    }
    const ownerSurface = ownerEl.getAttribute(surfaceDomAttr);
    if (!frontendSurfaceMountMatchesOwnerSurface(config, ownerSurface)) {
      reportError?.(ownerEl, new Error(`FrontendSurface DOM/config mismatch: ${ownerSurface ?? "missing"} != ${config.surface}`));
      return null;
    }
    return config;
  }
  function frontendSurfaceMountMatchesOwnerSurface(config, ownerSurface) {
    return ownerSurface === config.surface;
  }
  function frontendSurfaceInstanceId(config) {
    return `${config.surface}:${config.scopeKey}:${config.mountKey}`;
  }
  function scanFrontendSurfaceMountInstances(root, reportError) {
    const scanRoot = root ?? (typeof document !== "undefined" ? document : null);
    if (!scanRoot) return [];
    const instances = [];
    scanRoot.querySelectorAll(`[${surfaceConfigDomAttr}]`).forEach((ownerEl) => {
      if (!(ownerEl instanceof HTMLElement)) return;
      const config = readFrontendSurfaceMountElement(ownerEl, reportError);
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
      if (current.hasAttribute(surfaceConfigDomAttr)) depth += 1;
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
    return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : null;
  }
  function serverPayloadFromHtmxTriggeredEvent(detail, eventTarget) {
    if (!isRecord2(detail)) return null;
    if ("elt" in detail && detail.elt !== eventTarget) return null;
    const serverPayload = Object.assign({}, detail);
    Reflect.deleteProperty(serverPayload, "elt");
    return serverPayload;
  }
  function isRecord2(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }
  function buildSurfaceSubscription(scope, scopeKey, fragments) {
    return {
      scope,
      scopeKey,
      fragments
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
    return `${surfaceFragmentKeyIdentity(fragment.fragmentKey)}:${fragment.targetId}`;
  }
  function liveUpdateInvalidationIsOwnEcho(sourceClientId, activeClientId) {
    return Boolean(sourceClientId && activeClientId && sourceClientId === activeClientId);
  }
  function resolveMountedFragmentsForInvalidation(subscriptions, fragments, scopeKey = null) {
    if (scopeKey === null || scopeKey.length === 0) return [];
    const mountedSubscriptions = Array.from(subscriptions);
    const resolved = [];
    const seen = /* @__PURE__ */ new Set();
    fragments.forEach((fragmentKey) => {
      const semanticKey = surfaceFragmentKeyIdentity(fragmentKey);
      const matches = [];
      for (const subscription of mountedSubscriptions) {
        if (subscription.scopeKey !== scopeKey) continue;
        subscription.resyncFragments.forEach((mountedFragment) => {
          if (surfaceFragmentKeyIdentity(mountedFragment.fragmentKey) === semanticKey) {
            matches.push(mountedFragment);
          }
        });
      }
      matches.forEach((candidate) => {
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
    const surfaceConfigSelector = `[${surfaceConfigDomAttr}]`;
    const surfaceOwnedControlSelector = `[${surfaceActionDomAttr}], [${intentFormDomAttr}]`;
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
      document.querySelectorAll(surfaceConfigSelector).forEach(function(ownerEl) {
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
      if (nextNode instanceof HTMLTemplateElement) {
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
        deferUntilBlur: fragment.protection.kind === "focused-field"
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
            fragment && target instanceof HTMLElement
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
      switch (fragment.protection.kind) {
        case "focused-field":
          return focusedFieldProtection(fragment.protection);
        case "replace":
          return null;
        default:
          return assertNever(fragment.protection);
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
      if (resolvedFragment.protection.kind === "focused-field" && hasProtectedActiveInput(target, resolvedFragment)) {
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
      if (typeof version !== "number" || !Number.isInteger(version) || version < 0) return;
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
      return buildSurfaceSubscription(subscription.scope, subscription.scopeKey, subscription.resyncFragments.map((fragment) => fragment.fragmentKey));
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
      const config = readFrontendSurfaceMountElement(ownerEl, reportSurfaceConfigError);
      if (!config) return null;
      const parsedConfig = parseFrontendSurfaceSubscriptionConfig(config);
      if (!parsedConfig) return null;
      return {
        surface: parsedConfig.surface,
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
        surface: ownerEl.getAttribute(surfaceDomAttr),
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
      document.querySelectorAll(surfaceConfigSelector).forEach(function(ownerEl) {
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
      const ownerEl = sourceEl.closest(surfaceConfigSelector);
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
      const surfaceOwnedControl = sourceEl.closest(surfaceOwnedControlSelector);
      if (!(surfaceOwnedControl instanceof HTMLElement)) return false;
      return surfaceOwnedControl.closest(surfaceConfigSelector) === ownerEl;
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
        surface: existing.surface || next.surface,
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
        scopeKind: message.scope.surface,
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
      const reconciliation = reconcileFrontendSurfaceInstances(activeSurfaceInstances, scanFrontendSurfaceMountInstances(document, reportSurfaceConfigError));
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
        htmxEvent.detail.headers[liveUpdateClientIdHeader] = clientId;
      }
    });
    function handleActorFragmentRefreshEvent(event) {
      if (!(event instanceof CustomEvent)) return;
      const actorDetail = serverPayloadFromHtmxTriggeredEvent(event.detail, event.target);
      if (!actorDetail) return;
      let detail;
      try {
        detail = parseLiveFragmentsRefreshEventDetail(actorDetail);
      } catch {
        return;
      }
      resolveMountedFragmentsForInvalidation(activeSubscriptions.values(), detail.fragments, detail.scopeKey).forEach(handleFragmentRefreshRequest);
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
