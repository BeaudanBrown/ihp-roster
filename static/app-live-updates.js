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
  function isTimesheetsSurfaceScope(value) {
    return isTimesheetsTimesheetWeekScope(value);
  }
  function isRosterSurfaceScope(value) {
    return isRosterRosterWeekScope(value);
  }
  function isRosterDayTimelineSurfaceScope(value) {
    return isRosterDayTimelineRosterDayTimelineScope(value);
  }
  function isRosterTemplateDesignerSurfaceScope(value) {
    return isRosterTemplateDesignerRosterTemplateDesignerScopeScope(value);
  }
  function isLeaveRequestsSurfaceScope(value) {
    return isLeaveRequestsLeaveRequestsScopeScope(value);
  }
  function isSelfServiceLeaveSurfaceScope(value) {
    return isSelfServiceLeaveSelfServiceLeaveScopeScope(value);
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
  function isTimesheetsSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-toolbar" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-day-columns" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-side-panel-content" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-day-section" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["dayOffset"], ["dayOffset"]) && (typeof value["params"]["dayOffset"] === "number" && Number.isInteger(value["params"]["dayOffset"])));
  }
  function isRosterSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-layout" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-content" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-grid-toolbar" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-grid-frame" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-columns" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-rail" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-wage-rail" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-slots-grid" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-staff-panel" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-week-overview" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-template-library" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["userId"], ["userId"]) && typeof value["params"]["userId"] === "string") || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-template-record" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["templateId"], ["templateId"]) && typeof value["params"]["templateId"] === "string") || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-template-draft" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["userId"], ["userId"]) && typeof value["params"]["userId"] === "string") || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-section" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["rosterDayId"], ["rosterDayId"]) && typeof value["params"]["rosterDayId"] === "string") || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-row" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["rosterDayId", "rowIndex"], ["rosterDayId", "rowIndex"]) && typeof value["params"]["rosterDayId"] === "string" && (typeof value["params"]["rowIndex"] === "number" && Number.isInteger(value["params"]["rowIndex"])));
  }
  function isRosterDayTimelineSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-timeline-content" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["rosterDayId"], ["rosterDayId"]) && typeof value["params"]["rosterDayId"] === "string");
  }
  function isRosterTemplateDesignerSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-template-designer-content" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isLeaveRequestsSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "unavailability-blackouts" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "leave-side-panel-content" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "leave-availability-warnings" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "leave-section-count" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["leaveSection"], ["leaveSection"]) && isLeaveSectionValue(value["params"]["leaveSection"])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "leave-section-list" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["leaveSection"], ["leaveSection"]) && isLeaveSectionValue(value["params"]["leaveSection"]));
  }
  function isSelfServiceLeaveSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "self-service-leave-form" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "visible-unavailability-blackouts" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "self-service-leave-history" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isBillingSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "billing-status" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isSupportSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "support-award-rates" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "support-public-holidays" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isProfileSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "profile-details-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "profile-preferences-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "profile-security-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "profile-leave-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isStaffSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "staff-details-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "staff-preferences-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "staff-visible-unavailability-blackouts" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "staff-leave-section" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isAdminPageSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-page-content" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isAdminXeroPageSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-xero-page-content" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isAdminVenueConfigSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-venue-settings" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isAdminInvitesSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-invites" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isAdminExportsSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-exports" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isAdminShiftTypesSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-shift-types" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isAdminRosterGroupsSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-roster-groups" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isAdminXeroSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-xero-shell" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-xero-reference-sync" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-xero-timesheet-preparation-wait" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-xero-pay-item-import-wait" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isSurfaceScope(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "timesheets" && isTimesheetsSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "roster" && isRosterSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "roster-day-timeline" && isRosterDayTimelineSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "roster-template-designer" && isRosterTemplateDesignerSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "leave-requests" && isLeaveRequestsSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "self-service-leave" && isSelfServiceLeaveSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "billing" && isBillingSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "support" && isSupportSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "profile" && isProfileSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "staff" && isStaffSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-page" && isAdminPageSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-xero-page" && isAdminXeroPageSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-venue-config" && isAdminVenueConfigSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-invites" && isAdminInvitesSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-exports" && isAdminExportsSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-shift-types" && isAdminShiftTypesSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-roster-groups" && isAdminRosterGroupsSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-xero" && isAdminXeroSurfaceScope(value.scope);
  }
  function isSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "timesheets" && isTimesheetsSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "roster" && isRosterSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "roster-day-timeline" && isRosterDayTimelineSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "roster-template-designer" && isRosterTemplateDesignerSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "leave-requests" && isLeaveRequestsSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "self-service-leave" && isSelfServiceLeaveSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "billing" && isBillingSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "support" && isSupportSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "profile" && isProfileSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "staff" && isStaffSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-page" && isAdminPageSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-xero-page" && isAdminXeroPageSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-venue-config" && isAdminVenueConfigSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-invites" && isAdminInvitesSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-exports" && isAdminExportsSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-shift-types" && isAdminShiftTypesSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-roster-groups" && isAdminRosterGroupsSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-xero" && isAdminXeroSurfaceFragmentKey({ kind: value.kind, params: value.params });
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
    return isRecord(value) && hasExactKeys(value, ["scope", "scopeKey", "fragments"], ["scope", "scopeKey", "fragments"]) && isSurfaceScope(value["scope"]) && typeof value["scopeKey"] === "string" && (Array.isArray(value["fragments"]) && value["fragments"].every((item) => isSurfaceFragmentKey(item)));
  }
  function parseLiveFragmentsRefreshEventDetail(value) {
    if (isLiveFragmentsRefreshEventDetail(value)) return value;
    throw new Error("Invalid LiveFragmentsRefreshEventDetail");
  }
  var liveFragmentsRefreshEvent = "bepis:live-fragments-refresh";
  var interactionSessionStartEvent = "bepis:interaction-session-start";
  var interactionSessionEndEvent = "bepis:interaction-session-end";
  var interactionSessionCancelRequestEvent = "bepis:interaction-session-cancel-request";
  function isLeaveSectionValue(value) {
    return typeof value === "string" && ["pending", "approved", "denied", "archive"].includes(value);
  }
  var dialogDismissedEvent = "bepis:dialog-dismissed";
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
  var liveUpdateSocketPath = "live-updates";
  var liveUpdateClientIdHeader = "X-Live-Update-Client-Id";
  var surfaceConfigDomAttr = "data-bepis-surface-config";
  var surfaceActionDomAttr = "data-bepis-surface-action";
  function encodeLiveUpdateCommand(value) {
    return value;
  }
  function isLiveUpdateMessage(value) {
    return isRecord(value) && hasExactKeys(value, ["type", "scope", "scopeKey", "currentVersion", "resync"], ["type", "scope", "scopeKey", "currentVersion", "resync"]) && value["type"] === "subscribed" && isSurfaceScope(value["scope"]) && typeof value["scopeKey"] === "string" && (typeof value["currentVersion"] === "number" && Number.isInteger(value["currentVersion"])) && typeof value["resync"] === "boolean" || isRecord(value) && hasExactKeys(value, ["type", "scope", "scopeKey", "version", "fragments", "sourceClientId"], ["type", "scope", "scopeKey", "version", "fragments", "sourceClientId"]) && value["type"] === "invalidate" && isSurfaceScope(value["scope"]) && typeof value["scopeKey"] === "string" && (typeof value["version"] === "number" && Number.isInteger(value["version"])) && (Array.isArray(value["fragments"]) && value["fragments"].every((item) => isSurfaceFragmentKey(item))) && (value["sourceClientId"] === null || typeof value["sourceClientId"] === "string") || isRecord(value) && hasExactKeys(value, ["type", "message"], ["type", "message"]) && value["type"] === "error" && typeof value["message"] === "string";
  }
  function parseLiveUpdateMessage(value) {
    if (isLiveUpdateMessage(value)) return value;
    throw new Error("Invalid LiveUpdateMessage");
  }
  function isTimesheetsTimesheetWeekScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "weekOffset"], ["venueId", "weekOffset"]) && typeof value["venueId"] === "string" && (typeof value["weekOffset"] === "number" && Number.isInteger(value["weekOffset"]));
  }
  function isRosterRosterWeekScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "rosterGroupId", "weekOffset"], ["venueId", "rosterGroupId", "weekOffset"]) && typeof value["venueId"] === "string" && typeof value["rosterGroupId"] === "string" && (typeof value["weekOffset"] === "number" && Number.isInteger(value["weekOffset"]));
  }
  function isRosterDayTimelineRosterDayTimelineScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "rosterGroupId", "weekOffset", "rosterDayId"], ["venueId", "rosterGroupId", "weekOffset", "rosterDayId"]) && typeof value["venueId"] === "string" && typeof value["rosterGroupId"] === "string" && (typeof value["weekOffset"] === "number" && Number.isInteger(value["weekOffset"])) && typeof value["rosterDayId"] === "string";
  }
  function isRosterTemplateDesignerRosterTemplateDesignerScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "rosterGroupId", "userId"], ["venueId", "rosterGroupId", "userId"]) && typeof value["venueId"] === "string" && typeof value["rosterGroupId"] === "string" && typeof value["userId"] === "string";
  }
  function isLeaveRequestsLeaveRequestsScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"], ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isSelfServiceLeaveSelfServiceLeaveScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "staffId"], ["venueId", "staffId"]) && typeof value["venueId"] === "string" && typeof value["staffId"] === "string";
  }
  function isBillingBillingVenueScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"], ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isSupportSupportPlatformScope(value) {
    return isRecord(value) && hasExactKeys(value, [], []);
  }
  function isProfileProfileScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "staffId"], ["venueId", "staffId"]) && typeof value["venueId"] === "string" && typeof value["staffId"] === "string";
  }
  function isStaffStaffScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "staffId"], ["venueId", "staffId"]) && typeof value["venueId"] === "string" && typeof value["staffId"] === "string";
  }
  function isAdminPageAdminPageScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"], ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isAdminXeroPageAdminXeroPageScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"], ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isAdminVenueConfigAdminVenueConfigScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"], ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isAdminInvitesAdminInvitesScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"], ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isAdminExportsAdminExportsScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"], ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isAdminShiftTypesAdminShiftTypesScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"], ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isAdminRosterGroupsAdminRosterGroupsScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"], ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isAdminXeroAdminXeroScopeScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"], ["venueId"]) && typeof value["venueId"] === "string";
  }
  var FrontendSurfaceFragmentRegistry = { "timesheets": ["timesheet-toolbar", "timesheet-day-columns", "timesheet-side-panel-content", "timesheet-day-section"], "roster": ["roster-content", "roster-grid-toolbar", "roster-grid-frame", "roster-day-columns", "roster-day-rail", "roster-wage-rail", "roster-slots-grid", "roster-staff-panel", "roster-template-library", "roster-day-section", "roster-row"], "roster-day-timeline": ["roster-day-timeline-content"], "roster-template-designer": [], "leave-requests": ["unavailability-blackouts", "leave-side-panel-content", "leave-availability-warnings", "leave-section-count", "leave-section-list"], "self-service-leave": ["self-service-leave-form", "visible-unavailability-blackouts", "self-service-leave-history"], "billing": ["billing-status"], "support": ["support-award-rates", "support-public-holidays"], "profile": ["profile-details-section", "profile-preferences-section", "profile-security-section", "profile-leave-section"], "staff": ["staff-details-section", "staff-preferences-section", "staff-visible-unavailability-blackouts", "staff-leave-section"], "admin-page": [], "admin-xero-page": [], "admin-venue-config": ["admin-venue-settings"], "admin-invites": ["admin-invites"], "admin-exports": ["admin-exports"], "admin-shift-types": ["admin-shift-types"], "admin-roster-groups": ["admin-roster-groups"], "admin-xero": ["admin-xero-shell", "admin-xero-reference-sync", "admin-xero-timesheet-preparation-wait", "admin-xero-pay-item-import-wait"] };
  function isFrontendSurfaceLiveFragmentName(surface, value) {
    return typeof value === "string" && FrontendSurfaceFragmentRegistry[surface].includes(value);
  }
  function isFrontendSurfaceFragmentProtection(value) {
    return isRecord(value) && hasExactKeys(value, ["kind"], ["kind"]) && value["kind"] === "replace" || isRecord(value) && hasExactKeys(value, ["kind", "activeSelector", "fieldKeyAttr", "fieldNameFallback", "containerSelector"], ["kind", "activeSelector", "fieldKeyAttr", "fieldNameFallback", "containerSelector"]) && value["kind"] === "focused-field" && typeof value["activeSelector"] === "string" && typeof value["fieldKeyAttr"] === "string" && typeof value["fieldNameFallback"] === "boolean" && (value["containerSelector"] === null || typeof value["containerSelector"] === "string");
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
  function isRosterTemplateDesignerMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "roster-template-designer" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isLeaveRequestsMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "leave-requests" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isSelfServiceLeaveMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "self-service-leave" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
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
  function isTimesheetsMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "timesheets" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isTimesheetsMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("timesheets", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "timesheets" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("timesheets", fragment.fragmentKey.kind)));
  }
  function isRosterMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "roster" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isRosterMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("roster", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "roster" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("roster", fragment.fragmentKey.kind)));
  }
  function isRosterDayTimelineMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "roster-day-timeline" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isRosterDayTimelineMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("roster-day-timeline", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "roster-day-timeline" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("roster-day-timeline", fragment.fragmentKey.kind)));
  }
  function isRosterTemplateDesignerMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "roster-template-designer" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isRosterTemplateDesignerMountedFragmentConfig(fragment)) && value["subscription"] === null;
  }
  function isLeaveRequestsMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "leave-requests" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isLeaveRequestsMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("leave-requests", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "leave-requests" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("leave-requests", fragment.fragmentKey.kind)));
  }
  function isSelfServiceLeaveMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "self-service-leave" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isSelfServiceLeaveMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("self-service-leave", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "self-service-leave" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("self-service-leave", fragment.fragmentKey.kind)));
  }
  function isBillingMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "billing" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isBillingMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("billing", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "billing" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("billing", fragment.fragmentKey.kind)));
  }
  function isSupportMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "support" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isSupportMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("support", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "support" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("support", fragment.fragmentKey.kind)));
  }
  function isProfileMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "profile" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isProfileMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("profile", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "profile" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("profile", fragment.fragmentKey.kind)));
  }
  function isStaffMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "staff" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isStaffMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("staff", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "staff" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("staff", fragment.fragmentKey.kind)));
  }
  function isAdminPageMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-page" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminPageMountedFragmentConfig(fragment)) && value["subscription"] === null;
  }
  function isAdminXeroPageMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-xero-page" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminXeroPageMountedFragmentConfig(fragment)) && value["subscription"] === null;
  }
  function isAdminVenueConfigMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-venue-config" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminVenueConfigMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("admin-venue-config", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "admin-venue-config" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("admin-venue-config", fragment.fragmentKey.kind)));
  }
  function isAdminInvitesMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-invites" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminInvitesMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("admin-invites", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "admin-invites" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("admin-invites", fragment.fragmentKey.kind)));
  }
  function isAdminExportsMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-exports" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminExportsMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("admin-exports", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "admin-exports" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("admin-exports", fragment.fragmentKey.kind)));
  }
  function isAdminShiftTypesMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-shift-types" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminShiftTypesMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("admin-shift-types", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "admin-shift-types" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("admin-shift-types", fragment.fragmentKey.kind)));
  }
  function isAdminRosterGroupsMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-roster-groups" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminRosterGroupsMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("admin-roster-groups", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "admin-roster-groups" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("admin-roster-groups", fragment.fragmentKey.kind)));
  }
  function isAdminXeroMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "admin-xero" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isAdminXeroMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("admin-xero", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "admin-xero" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("admin-xero", fragment.fragmentKey.kind)));
  }
  function isFrontendSurfaceMountConfig(value) {
    return isTimesheetsMountConfig(value) || isRosterMountConfig(value) || isRosterDayTimelineMountConfig(value) || isRosterTemplateDesignerMountConfig(value) || isLeaveRequestsMountConfig(value) || isSelfServiceLeaveMountConfig(value) || isBillingMountConfig(value) || isSupportMountConfig(value) || isProfileMountConfig(value) || isStaffMountConfig(value) || isAdminPageMountConfig(value) || isAdminXeroPageMountConfig(value) || isAdminVenueConfigMountConfig(value) || isAdminInvitesMountConfig(value) || isAdminExportsMountConfig(value) || isAdminShiftTypesMountConfig(value) || isAdminRosterGroupsMountConfig(value) || isAdminXeroMountConfig(value);
  }
  function parseFrontendSurfaceMountConfig(value) {
    if (isFrontendSurfaceMountConfig(value)) return value;
    throw new Error("Invalid FrontendSurfaceMountConfig");
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
  function isConnectedRoot(root) {
    return root instanceof Document || root.isConnected;
  }
  function detailRoot(event, key, fallback = document) {
    const detailCandidate = detailTarget(event, key);
    if (isDomRoot(detailCandidate) && isConnectedRoot(detailCandidate)) return detailCandidate;
    if (isDomRoot(event.target) && isConnectedRoot(event.target)) return event.target;
    return fallback;
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
    const target = detailRoot(event, "target");
    return isHTMLElement(target) ? target : null;
  }
  function regionFromHtmxEvent(event) {
    const source = htmxRegionEventSource(event);
    return closestUiRegionFragment(htmxRegionEventTarget(event)) || closestUiRegionFragment(source?.isConnected ? source : null);
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

  // frontend/ts/interaction/session-state.ts
  var interactionSessionStartEventName = interactionSessionStartEvent;
  var interactionSessionEndEventName = interactionSessionEndEvent;
  var interactionSessionCancelRequestEventName = interactionSessionCancelRequestEvent;
  var attrs = InteractionDom.attributes;
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
        const mount = target.closest(`[${attrs.surface}]`);
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
  function buildSurfaceSubscription(scope, scopeKey, fragments, renderedDependencyWatermark) {
    return {
      scope,
      scopeKey,
      fragments,
      renderedDependencyWatermark
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

  // frontend/ts/live-updates/mount.ts
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
      scope: config.subscription.scope,
      scopeKey: config.scopeKey,
      socketPath: `/${liveUpdateSocketPath}`,
      resyncFragments,
      decorateRequestsWithin: resyncFragments.map((fragment) => `#${fragment.targetId}`),
      renderedDependencyWatermark: config.subscription.renderedDependencyWatermark
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

  // frontend/ts/live-updates/subscription.ts
  var surfaceConfigSelector = `[${surfaceConfigDomAttr}]`;
  var surfaceOwnedControlSelector = `[${surfaceActionDomAttr}], [${intentFormDomAttr}]`;
  function createSurfaceConfigErrorReporter(targetDocument) {
    return (ownerEl, error) => {
      const detail = {
        id: ownerEl.id || null,
        surface: ownerEl.getAttribute(surfaceDomAttr),
        error: error.message
      };
      console.error?.("Invalid live-update surface config", detail);
      targetDocument.dispatchEvent(new CustomEvent("app:live-update-surface-config-failed", { detail }));
    };
  }
  function readSurfaceSubscription(ownerEl, requestRefresh, reportError) {
    const config = readFrontendSurfaceMountElement(ownerEl, reportError);
    if (!config) return null;
    const parsed = parseFrontendSurfaceSubscriptionConfig(config);
    if (!parsed) return null;
    return {
      scope: parsed.scope,
      scopeKey: parsed.scopeKey,
      path: parsed.socketPath,
      resyncFragments: parsed.resyncFragments,
      decorateRequestsWithin: parsed.decorateRequestsWithin,
      renderedDependencyWatermark: parsed.renderedDependencyWatermark,
      ownerEls: [ownerEl],
      resync: (subscription) => subscription.resyncFragments.forEach(requestRefresh)
    };
  }
  function collectDesiredSurfaceSubscriptions(targetDocument, requestRefresh, reportError) {
    const desired = /* @__PURE__ */ new Map();
    targetDocument.querySelectorAll(surfaceConfigSelector).forEach((ownerEl) => {
      if (!(ownerEl instanceof HTMLElement)) return;
      const subscription = readSurfaceSubscription(ownerEl, requestRefresh, reportError);
      if (!subscription?.scopeKey) return;
      desired.set(subscription.scopeKey, mergeSubscription(desired.get(subscription.scopeKey), subscription));
    });
    return desired;
  }
  function shouldDecorateSurfaceRequest(event, requestRefresh, reportError) {
    const sourceEl = event.detail?.elt;
    if (!(sourceEl instanceof HTMLElement)) return false;
    const ownerEl = sourceEl.closest(surfaceConfigSelector);
    if (!(ownerEl instanceof HTMLElement)) return false;
    const subscription = readSurfaceSubscription(ownerEl, requestRefresh, reportError);
    if (!subscription) return false;
    if (isSurfaceOwnedHtmxRequest(sourceEl, ownerEl)) return true;
    if (subscription.decorateRequestsWithin.length === 0) return true;
    return subscription.decorateRequestsWithin.some((selector) => Boolean(selector && sourceEl.closest(selector)));
  }
  function isSurfaceOwnedHtmxRequest(sourceEl, ownerEl) {
    const control = sourceEl.closest(surfaceOwnedControlSelector);
    return control instanceof HTMLElement && control.closest(surfaceConfigSelector) === ownerEl;
  }
  function wireSurfaceSubscription(subscription) {
    return buildSurfaceSubscription(
      subscription.scope,
      subscription.scopeKey,
      subscription.resyncFragments.map((fragment) => fragment.fragmentKey),
      subscription.renderedDependencyWatermark
    );
  }
  function subscriptionsEquivalent(left, right) {
    return Boolean(left && subscriptionSignature(left) === subscriptionSignature(right));
  }
  function subscriptionSignature(subscription) {
    const fragments = subscription.resyncFragments.map((fragment) => ({ key: liveUpdateFragmentMergeKey(fragment) || JSON.stringify(fragment.fragmentKey), fragment })).sort((left, right) => left.key.localeCompare(right.key)).map((entry) => entry.fragment);
    return JSON.stringify({ path: subscription.path, scope: subscription.scope, resyncFragments: fragments, renderedDependencyWatermark: subscription.renderedDependencyWatermark });
  }
  function mergeSubscription(existing, next) {
    if (!existing) return next;
    return {
      ...existing,
      resyncFragments: mergeFragments(existing.resyncFragments, next.resyncFragments),
      decorateRequestsWithin: mergeStrings(existing.decorateRequestsWithin, next.decorateRequestsWithin),
      ownerEls: existing.ownerEls.concat(next.ownerEls),
      renderedDependencyWatermark: Math.min(existing.renderedDependencyWatermark, next.renderedDependencyWatermark)
    };
  }
  function mergeFragments(existing, next) {
    const merged = [];
    const seen = /* @__PURE__ */ new Set();
    existing.concat(next).forEach((fragment) => {
      const key = liveUpdateFragmentMergeKey(fragment);
      if (!key || seen.has(key)) return;
      seen.add(key);
      merged.push(fragment);
    });
    return merged;
  }
  function mergeStrings(existing, next) {
    return Array.from(new Set(existing.concat(next).filter(Boolean)));
  }

  // frontend/ts/live-updates/connection.ts
  function createLiveUpdateConnection(options) {
    const { targetWindow, activeSubscriptions, versions, handleMessage, requestSync, diagnostics } = options;
    let socket = null;
    let socketPath = null;
    let reconnectTimer = null;
    let reconnectAttempt = 0;
    let clientId = null;
    function ensureClientId() {
      if (!clientId) {
        clientId = targetWindow.crypto?.randomUUID?.() ?? `live-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      }
      return clientId;
    }
    function buildWebSocketUrl(path) {
      const protocol = targetWindow.location.protocol === "https:" ? "wss:" : "ws:";
      return `${protocol}//${targetWindow.location.host}${path}`;
    }
    function sendCommand(command) {
      if (!socket || socket.readyState !== targetWindow.WebSocket.OPEN) return;
      socket.send(JSON.stringify(command));
    }
    function subscribe(subscription) {
      sendCommand(buildLiveUpdateSubscribeCommand(
        wireSurfaceSubscription(subscription),
        ensureClientId(),
        versions.get(subscription.scopeKey)
      ));
    }
    function unsubscribe(subscription) {
      sendCommand(buildLiveUpdateUnsubscribeCommand(wireSurfaceSubscription(subscription)));
    }
    function scheduleReconnect() {
      if (reconnectTimer) return;
      reconnectAttempt += 1;
      const cappedAttempt = Math.min(reconnectAttempt, 6);
      const delayMs = Math.floor(Math.random() * Math.min(250 * 2 ** cappedAttempt, 1e4));
      diagnostics.emitDebugEvent("reconnect_scheduled", { attempt: reconnectAttempt, delayMs });
      reconnectTimer = targetWindow.setTimeout(() => {
        reconnectTimer = null;
        requestSync();
      }, delayMs);
    }
    function close() {
      if (reconnectTimer) targetWindow.clearTimeout(reconnectTimer);
      reconnectTimer = null;
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
    function open(path) {
      const perfSpan = diagnostics.beginPerfSpan("live_updates.open_socket", { path });
      socket = new targetWindow.WebSocket(buildWebSocketUrl(path));
      socketPath = path;
      socket.onopen = () => {
        reconnectAttempt = 0;
        activeSubscriptions.forEach((subscription) => {
          subscribe(subscription);
          diagnostics.emitDebugEvent("subscription_added", {
            scopeKey: subscription.scopeKey,
            fragmentCount: subscription.resyncFragments.length,
            ownerCount: subscription.ownerEls.length
          });
        });
        diagnostics.endPerfSpan(perfSpan, { outcome: "open", subscriptionCount: activeSubscriptions.size });
      };
      socket.onmessage = (event) => {
        try {
          handleMessage(parseLiveUpdateMessage(JSON.parse(event.data)));
        } catch {
          return;
        }
      };
      socket.onclose = () => {
        diagnostics.endPerfSpan(perfSpan, { outcome: "closed_before_open" });
        socket = null;
        if (activeSubscriptions.size > 0) scheduleReconnect();
      };
      socket.onerror = () => {
        diagnostics.endPerfSpan(perfSpan, { outcome: "error" });
        socket?.close();
      };
    }
    function sync(desired) {
      ensureClientId();
      const nextPath = desired.values().next().value?.path ?? null;
      if (desired.size === 0 || !nextPath) {
        activeSubscriptions.forEach((subscription) => versions.clear(subscription.scopeKey));
        activeSubscriptions.clear();
        close();
        return;
      }
      const removed = [];
      activeSubscriptions.forEach((subscription, scopeKey) => {
        if (!desired.has(scopeKey)) removed.push(subscription);
      });
      const added = [];
      const changed = [];
      desired.forEach((subscription, scopeKey) => {
        const active = activeSubscriptions.get(scopeKey);
        if (!active) added.push(subscription);
        else if (!subscriptionsEquivalent(active, subscription)) changed.push({ previous: active, next: subscription });
      });
      removed.forEach((subscription) => {
        unsubscribe(subscription);
        activeSubscriptions.delete(subscription.scopeKey);
        versions.clear(subscription.scopeKey);
        diagnostics.emitDebugEvent("subscription_removed", { scopeKey: subscription.scopeKey });
      });
      changed.forEach(({ previous, next }) => {
        unsubscribe(previous);
        versions.clear(previous.scopeKey);
        diagnostics.emitDebugEvent("subscription_changed", {
          scopeKey: previous.scopeKey,
          previousFragmentCount: previous.resyncFragments.length,
          nextFragmentCount: next.resyncFragments.length
        });
      });
      desired.forEach((subscription, scopeKey) => activeSubscriptions.set(scopeKey, subscription));
      if (!socket || socket.readyState > targetWindow.WebSocket.OPEN || socketPath !== nextPath) {
        close();
        open(nextPath);
        return;
      }
      if (socket.readyState === targetWindow.WebSocket.OPEN) {
        changed.forEach(({ next }) => subscribe(next));
        added.forEach((subscription) => {
          subscribe(subscription);
          diagnostics.emitDebugEvent("subscription_added", {
            scopeKey: subscription.scopeKey,
            fragmentCount: subscription.resyncFragments.length,
            ownerCount: subscription.ownerEls.length
          });
        });
      }
    }
    return { ensureClientId, activeClientId: () => clientId, sync, close };
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

  // frontend/ts/shared/exhaustive.ts
  function assertNever(value, message = "Unexpected generated union variant") {
    throw new Error(`${message}: ${JSON.stringify(value)}`);
  }

  // frontend/ts/live-updates/invalidation.ts
  function createLiveUpdateInvalidationRuntime(options) {
    const { activeSubscriptions, activeClientId, refresher, diagnostics } = options;
    const scopeVersions = /* @__PURE__ */ new Map();
    const versions = {
      get(scopeKey) {
        const version = scopeVersions.get(scopeKey);
        return Number.isInteger(version) ? version ?? null : null;
      },
      set(scopeKey, version) {
        const normalized = normalizeLiveUpdateVersion(version);
        if (normalized !== null) scopeVersions.set(scopeKey, normalized);
      },
      clear(scopeKey) {
        scopeVersions.delete(scopeKey);
      }
    };
    function handleSubscribedMessage(message) {
      const scopeKey = liveUpdateMessageScopeKey(message);
      if (!scopeKey) return;
      const subscription = activeSubscriptions.get(scopeKey);
      if (!subscription) return;
      versions.set(scopeKey, message.currentVersion);
      if (message.resync) subscription.resync(subscription);
    }
    function handleInvalidateMessage(message) {
      if (liveUpdateInvalidationIsOwnEcho(message.sourceClientId, activeClientId())) return;
      const nextVersion = normalizeLiveUpdateVersion(message.version);
      const perfSpan = diagnostics.beginPerfSpan("live_updates.handle_invalidate", {
        fragmentCount: message.fragments.length,
        scopeKind: message.scope.surface,
        version: nextVersion
      });
      const scopeKey = liveUpdateMessageScopeKey(message);
      if (!scopeKey) {
        diagnostics.endPerfSpan(perfSpan, { outcome: "invalid_scope" });
        return;
      }
      const subscription = activeSubscriptions.get(scopeKey);
      if (!subscription) {
        diagnostics.endPerfSpan(perfSpan, { outcome: "unsubscribed_scope", scopeKey });
        return;
      }
      const previousVersion = versions.get(scopeKey);
      if (nextVersion !== null) {
        if (previousVersion !== null && nextVersion <= previousVersion) {
          diagnostics.endPerfSpan(perfSpan, { outcome: "stale", scopeKey, previousVersion, nextVersion });
          return;
        }
        versions.set(scopeKey, nextVersion);
      }
      if (message.fragments.length === 0) {
        subscription.resync(subscription);
        diagnostics.endPerfSpan(perfSpan, { outcome: "resync_empty_fragments", scopeKey });
        return;
      }
      resolveMountedFragmentsForInvalidation([subscription], message.fragments, scopeKey).forEach(refresher.request);
      diagnostics.endPerfSpan(perfSpan, { outcome: "queued_fragments", scopeKey });
    }
    function handleMessage(message) {
      switch (message.type) {
        case "subscribed":
          handleSubscribedMessage(message);
          return;
        case "invalidate":
          handleInvalidateMessage(message);
          return;
        case "error":
          return;
        default:
          return assertNever(message);
      }
    }
    function handleActorEvent(event) {
      if (!(event instanceof CustomEvent)) return;
      const actorDetail = serverPayloadFromHtmxTriggeredEvent(event.detail, event.target);
      if (!actorDetail) return;
      try {
        const detail = parseLiveFragmentsRefreshEventDetail(actorDetail);
        resolveMountedFragmentsForInvalidation(activeSubscriptions.values(), detail.fragments, detail.scopeKey).forEach(refresher.request);
      } catch {
        return;
      }
    }
    return { versions, handleMessage, handleActorEvent };
  }

  // frontend/ts/interaction/live-conflicts.ts
  var attrs2 = InteractionDom.attributes;
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
    const raw = mount.getAttribute(attrs2.conflictPolicies);
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
    const mount = target.closest(`[${attrs2.surface}]`);
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

  // frontend/ts/live-updates/focus.ts
  function createFocusedFieldProtection(targetWindow, targetDocument) {
    const css = targetWindow.CSS;
    function findPreservedField(root, preserveField) {
      if (!(root instanceof HTMLElement)) return null;
      if (preserveField.fieldKey) {
        const escapedKey = css && typeof css.escape === "function" ? css.escape(preserveField.fieldKey) : preserveField.fieldKey;
        const keyedField = root.querySelector(`[${preserveField.fieldKeyAttr}="${escapedKey}"]`);
        if (isFormField(keyedField)) return keyedField;
      }
      if (!preserveField.name) return null;
      const escapedName = css && typeof css.escape === "function" ? css.escape(preserveField.name) : preserveField.name;
      const namedField = root.querySelector(`[name="${escapedName}"]`);
      return isFormField(namedField) ? namedField : null;
    }
    function focusedFieldProtection(policy) {
      const { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector } = policy;
      function findActiveInput(target) {
        const activeInput = target.querySelector(activeSelector);
        return isFormField(activeInput) ? activeInput : null;
      }
      return {
        hasActiveInput: (target) => Boolean(findActiveInput(target)),
        captureState(target, fragment) {
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
        restoreState(target, fragment) {
          if (!fragment.preserveField) return;
          const root = fragment.preserveField.rowId ? targetDocument.getElementById(fragment.preserveField.rowId) : target;
          const field = findPreservedField(root, fragment.preserveField);
          if (field) field.value = fragment.preserveField.value ?? "";
        }
      };
    }
    function matchingProtection(fragment) {
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
    return {
      hasProtectedActiveInput(target, fragment) {
        return Boolean(matchingProtection(fragment)?.hasActiveInput(target));
      },
      captureDeferredState(target, fragment) {
        return matchingProtection(fragment)?.captureState(target, fragment) ?? fragment;
      },
      restoreDeferredState(fragment) {
        const target = targetDocument.getElementById(fragment.targetId);
        if (!(target instanceof HTMLElement)) return;
        matchingProtection(fragment)?.restoreState(target, fragment);
      }
    };
  }
  function isFormField(value) {
    return value instanceof HTMLInputElement || value instanceof HTMLSelectElement || value instanceof HTMLTextAreaElement;
  }

  // frontend/ts/live-updates/request-context.ts
  function decorators() {
    const runtimeGlobal = globalThis;
    runtimeGlobal.__bepisSurfaceFragmentRequestDecorators ?? (runtimeGlobal.__bepisSurfaceFragmentRequestDecorators = /* @__PURE__ */ new Set());
    return runtimeGlobal.__bepisSurfaceFragmentRequestDecorators;
  }
  function decorateSurfaceFragmentRequest(url, fragment, target) {
    let decoratedUrl = url;
    for (const decorator of decorators()) decoratedUrl = decorator(decoratedUrl, fragment, target);
    return decoratedUrl;
  }

  // frontend/ts/live-updates/refresh.ts
  function createLiveFragmentRefresher(options) {
    const { targetWindow, targetDocument, diagnostics, activeInteractionSessions } = options;
    const { beginPerfSpan, endPerfSpan, emitDebugEvent } = diagnostics;
    const focus = createFocusedFieldProtection(targetWindow, targetDocument);
    const pendingFocusedFragments = /* @__PURE__ */ new Map();
    const pendingInteractionFragments = /* @__PURE__ */ new Map();
    const pendingInteractionTimers = /* @__PURE__ */ new Map();
    const inFlightFragments = /* @__PURE__ */ new Map();
    async function swapFragmentHtml(targetId, html) {
      const perfSpan = beginPerfSpan("live_updates.swap_fragment", { targetId });
      const target = targetDocument.getElementById(targetId);
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
      const template = targetDocument.createElement("template");
      template.innerHTML = trimmed;
      let nextNode = template.content.firstElementChild;
      if (nextNode instanceof HTMLTemplateElement) nextNode = nextNode.content.firstElementChild;
      if (!(nextNode instanceof Element)) {
        endPerfSpan(perfSpan, { outcome: "no_element" });
        return;
      }
      target.replaceWith(nextNode);
      targetWindow.htmx?.process?.(nextNode);
      targetWindow.appPageLifecycle?.dispatchPageReady?.({
        source: "live-fragment-refetch",
        target: nextNode,
        isFullPage: false
      });
      endPerfSpan(perfSpan, { outcome: "swapped", nextTagName: nextNode.tagName });
    }
    async function refetchFragment(fragment) {
      const perfSpan = beginPerfSpan("live_updates.refetch_fragment", {
        targetId: fragment.targetId,
        url: fragment.url,
        focusProtected: fragment.protection.kind === "focused-field"
      });
      const target = targetDocument.getElementById(fragment.targetId);
      const requestUrl = target instanceof HTMLElement ? decorateSurfaceFragmentRequest(fragment.url, fragment, target) : fragment.url;
      const response = await targetWindow.fetch(requestUrl, {
        credentials: "same-origin",
        headers: { "HX-Request": "true" }
      });
      if (!response.ok) {
        endPerfSpan(perfSpan, { outcome: "http_error", status: response.status });
        throw new Error(`Fragment fetch failed with ${response.status}`);
      }
      const html = await response.text();
      await swapFragmentHtml(fragment.targetId, html);
      focus.restoreDeferredState(fragment);
      endPerfSpan(perfSpan, { outcome: "ok", status: response.status, responseBytes: html.length });
    }
    function reportFragmentRefreshError(fragment, error) {
      const detail = {
        targetId: fragment.targetId || null,
        url: fragment.url || null,
        error: error instanceof Error ? error.message : String(error)
      };
      targetWindow.console?.error?.("Live fragment refresh failed", detail);
      targetDocument.dispatchEvent(new CustomEvent("app:live-update-fragment-refresh-failed", { detail }));
    }
    function queueFragment(fragment) {
      const existing = inFlightFragments.get(fragment.targetId);
      if (existing) {
        inFlightFragments.set(fragment.targetId, { ...existing, next: fragment });
        emitDebugEvent("fragment_deduped", { targetId: fragment.targetId, url: fragment.url });
        return;
      }
      inFlightFragments.set(fragment.targetId, { next: null });
      void refetchFragment(fragment).catch((error) => reportFragmentRefreshError(fragment, error)).finally(() => {
        const next = inFlightFragments.get(fragment.targetId)?.next;
        inFlightFragments.delete(fragment.targetId);
        if (next) queueFragment(next);
      });
    }
    function clearInteractionDeferredFragment(targetId) {
      const timer = pendingInteractionTimers.get(targetId);
      if (timer) targetWindow.clearTimeout(timer);
      pendingInteractionTimers.delete(targetId);
      pendingInteractionFragments.delete(targetId);
    }
    function flushInteractionDeferredFragment(targetId, reason) {
      const fragment = pendingInteractionFragments.get(targetId);
      if (!fragment) return;
      clearInteractionDeferredFragment(targetId);
      emitDebugEvent("deferred_fragment_flush", { targetId, reason });
      queueFragment(fragment);
    }
    function scheduleInteractionFallback(targetId, timeoutMs) {
      const existing = pendingInteractionTimers.get(targetId);
      if (existing) targetWindow.clearTimeout(existing);
      if (timeoutMs === null || timeoutMs <= 0) return;
      pendingInteractionTimers.set(targetId, targetWindow.setTimeout(() => {
        const fragment = pendingInteractionFragments.get(targetId);
        const target = targetDocument.getElementById(targetId);
        if (fragment && target instanceof HTMLElement) {
          const conflict = resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions);
          if (conflict) activeInteractionSessions.requestCancel(conflict.session, "live-fragment-defer-fallback-timeout");
        }
        flushInteractionDeferredFragment(targetId, "interaction_fallback_timeout");
      }, timeoutMs));
    }
    function request(fragment) {
      if (!fragment.targetId || !fragment.url) return;
      const target = targetDocument.getElementById(fragment.targetId);
      if (!(target instanceof HTMLElement)) return;
      const conflict = resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions);
      if (conflict?.action === "cancel") activeInteractionSessions.requestCancel(conflict.session, "live-fragment-conflict");
      if (conflict?.action === "defer") {
        pendingInteractionFragments.set(fragment.targetId, fragment);
        scheduleInteractionFallback(fragment.targetId, conflict.timeoutMs);
        targetDocument.dispatchEvent(new CustomEvent("app:live-update-performance", {
          detail: { name: "live_updates.defer_fragment", duration: 0, targetId: fragment.targetId, reason: "interaction_session" }
        }));
        return;
      }
      clearInteractionDeferredFragment(fragment.targetId);
      if (fragment.protection.kind === "focused-field" && focus.hasProtectedActiveInput(target, fragment)) {
        pendingFocusedFragments.set(fragment.targetId, focus.captureDeferredState(target, fragment));
        targetDocument.dispatchEvent(new CustomEvent("app:live-update-performance", {
          detail: { name: "live_updates.defer_fragment", duration: 0, targetId: fragment.targetId, reason: "active_input" }
        }));
        return;
      }
      pendingFocusedFragments.delete(fragment.targetId);
      queueFragment(fragment);
    }
    function flushInteractionDeferredFragmentsWithoutActiveSessions() {
      Array.from(pendingInteractionFragments.entries()).forEach(([targetId, fragment]) => {
        const target = targetDocument.getElementById(targetId);
        if (!(target instanceof HTMLElement)) {
          flushInteractionDeferredFragment(targetId, "target_missing");
          return;
        }
        if (!resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions)) {
          flushInteractionDeferredFragment(targetId, "interaction_session_end");
        }
      });
    }
    function flushFocusedFragment(targetId) {
      const fragment = pendingFocusedFragments.get(targetId);
      if (!fragment) return;
      pendingFocusedFragments.delete(targetId);
      emitDebugEvent("deferred_fragment_flush", { targetId, reason: "inactive_input" });
      queueFragment(fragment);
    }
    function flushFocusedFragmentsWithoutActiveInputs() {
      Array.from(pendingFocusedFragments.entries()).forEach(([targetId, fragment]) => {
        const target = targetDocument.getElementById(targetId);
        if (target instanceof HTMLElement && resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions)) return;
        if (!(target instanceof HTMLElement) || !focus.hasProtectedActiveInput(target, fragment)) flushFocusedFragment(targetId);
      });
    }
    function stop() {
      pendingInteractionTimers.forEach((timer) => targetWindow.clearTimeout(timer));
      pendingInteractionTimers.clear();
      pendingInteractionFragments.clear();
      pendingFocusedFragments.clear();
      inFlightFragments.clear();
    }
    return { request, flushInteractionDeferredFragmentsWithoutActiveSessions, flushFocusedFragmentsWithoutActiveInputs, stop };
  }

  // frontend/ts/live-updates/request-decoration.ts
  function enableLiveUpdateRequestDecoration(options) {
    const { targetDocument, ensureClientId, requestRefresh, reportSurfaceConfigError } = options;
    const handleConfigRequest = (event) => {
      const htmxEvent = event;
      if (!shouldDecorateSurfaceRequest(htmxEvent, requestRefresh, reportSurfaceConfigError)) return;
      if (htmxEvent.detail?.headers) {
        htmxEvent.detail.headers[liveUpdateClientIdHeader] = ensureClientId();
      }
    };
    targetDocument.addEventListener("htmx:configRequest", handleConfigRequest);
    return () => targetDocument.removeEventListener("htmx:configRequest", handleConfigRequest);
  }

  // frontend/ts/live-updates/runtime.ts
  function enableLiveUpdateRuntime() {
    if (typeof window === "undefined") return;
    const activeSubscriptions = /* @__PURE__ */ new Map();
    const activeSurfaceInstances = /* @__PURE__ */ new Map();
    const diagnostics = createLiveUpdateDiagnostics(window, document);
    const activeInteractionSessions = createActiveInteractionSessionTracker(document);
    const refresher = createLiveFragmentRefresher({
      targetWindow: window,
      targetDocument: document,
      diagnostics,
      activeInteractionSessions
    });
    let connection = null;
    const invalidation = createLiveUpdateInvalidationRuntime({
      activeSubscriptions,
      activeClientId: () => connection?.activeClientId() ?? null,
      refresher,
      diagnostics
    });
    const reportSurfaceConfigError = createSurfaceConfigErrorReporter(document);
    function reconcileMounts() {
      const current = scanFrontendSurfaceMountInstances(document, reportSurfaceConfigError);
      const reconciliation = reconcileFrontendSurfaceInstances(activeSurfaceInstances, current);
      reconciliation.removed.forEach((instance) => {
        activeSurfaceInstances.delete(instance.instanceId);
        diagnostics.emitDebugEvent("surface_disposed", instanceDebugDetail(instance));
      });
      reconciliation.retained.forEach((instance) => activeSurfaceInstances.set(instance.instanceId, instance));
      reconciliation.added.forEach((instance) => {
        activeSurfaceInstances.set(instance.instanceId, instance);
        diagnostics.emitDebugEvent("surface_initialized", instanceDebugDetail(instance));
      });
    }
    function syncRuntime() {
      reconcileMounts();
      const desired = collectDesiredSurfaceSubscriptions(document, refresher.request, reportSurfaceConfigError);
      if (desired.size === 0) activeSurfaceInstances.clear();
      connection?.sync(desired);
    }
    connection = createLiveUpdateConnection({
      targetWindow: window,
      activeSubscriptions,
      versions: invalidation.versions,
      handleMessage: invalidation.handleMessage,
      requestSync: syncRuntime,
      diagnostics
    });
    enableLiveUpdateRequestDecoration({
      targetDocument: document,
      ensureClientId: connection.ensureClientId,
      requestRefresh: refresher.request,
      reportSurfaceConfigError
    });
    document.addEventListener(liveFragmentsRefreshEvent, invalidation.handleActorEvent);
    document.addEventListener(interactionSessionEndEvent, () => {
      refresher.flushInteractionDeferredFragmentsWithoutActiveSessions();
      refresher.flushFocusedFragmentsWithoutActiveInputs();
    });
    document.addEventListener("htmx:afterSwap", () => {
      refresher.flushInteractionDeferredFragmentsWithoutActiveSessions();
      window.setTimeout(syncRuntime, 0);
    });
    document.addEventListener("htmx:afterSettle", () => window.setTimeout(syncRuntime, 0));
    document.addEventListener("htmx:responseError", refresher.flushInteractionDeferredFragmentsWithoutActiveSessions);
    document.addEventListener(dialogDismissedEvent, () => window.setTimeout(syncRuntime, 0));
    const scheduleFocusedFlush = () => window.setTimeout(refresher.flushFocusedFragmentsWithoutActiveInputs, 0);
    document.addEventListener("focusout", scheduleFocusedFlush);
    document.addEventListener("input", scheduleFocusedFlush);
    document.addEventListener("change", scheduleFocusedFlush);
    document.addEventListener(pageReadyEvent, syncRuntime);
  }
  function instanceDebugDetail(instance) {
    return {
      instanceId: instance.instanceId,
      surface: instance.surface,
      scopeKey: instance.scopeKey,
      mountKey: instance.mountKey,
      depth: instance.depth
    };
  }

  // frontend/ts/app-live-updates.ts
  enableHtmxUiRegionEventAdapter();
  enableUiRegionTransitions();
  enableLazySurfaceErrorHandling();
  enableLiveUpdateRuntime();
})();
