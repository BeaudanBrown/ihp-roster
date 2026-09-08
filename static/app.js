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
  function isFeedbackSurfaceScope(value) {
    return isFeedbackFeedbackVenueScope(value);
  }
  function isFeedbackModerationSurfaceScope(value) {
    return isFeedbackModerationFeedbackPlatformScope(value);
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
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-toolbar" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-day-columns" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-side-panel-content" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-day-section" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["operationalDate"], ["operationalDate"]) && typeof value["params"]["operationalDate"] === "string");
  }
  function isRosterSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-layout" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-content" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-grid-toolbar" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-grid-frame" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-columns" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-rail" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-wage-rail" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-slots-grid" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-staff-panel" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-week-overview" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-template-library" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-section" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["rosterDayId"], ["rosterDayId"]) && typeof value["params"]["rosterDayId"] === "string") || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-row" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["rosterDayId", "rowIndex"], ["rosterDayId", "rowIndex"]) && typeof value["params"]["rosterDayId"] === "string" && (typeof value["params"]["rowIndex"] === "number" && Number.isInteger(value["params"]["rowIndex"])));
  }
  function isRosterDayTimelineSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-timeline-content" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["rosterDayId"], ["rosterDayId"]) && typeof value["params"]["rosterDayId"] === "string");
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
  function isFeedbackSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "feedback-board" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
  }
  function isFeedbackModerationSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "feedback-desktop-count" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "feedback-mobile-count" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "feedback-review" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], []));
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
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-xero-shell" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-xero-reference-sync" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-xero-timesheet-preparation-wait" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-xero-pay-item-import-wait" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "admin-xero-staff-mappings-wait" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["referenceSyncJobId"], ["referenceSyncJobId"]) && typeof value["params"]["referenceSyncJobId"] === "string");
  }
  function isSurfaceScope(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "timesheets" && isTimesheetsSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "roster" && isRosterSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "roster-day-timeline" && isRosterDayTimelineSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "leave-requests" && isLeaveRequestsSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "self-service-leave" && isSelfServiceLeaveSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "billing" && isBillingSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "support" && isSupportSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "feedback" && isFeedbackSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "feedback-moderation" && isFeedbackModerationSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "profile" && isProfileSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "staff" && isStaffSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-page" && isAdminPageSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-xero-page" && isAdminXeroPageSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-venue-config" && isAdminVenueConfigSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-invites" && isAdminInvitesSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-exports" && isAdminExportsSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-shift-types" && isAdminShiftTypesSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-roster-groups" && isAdminRosterGroupsSurfaceScope(value.scope) || isRecord(value) && hasExactKeys(value, ["surface", "scope"]) && value.surface === "admin-xero" && isAdminXeroSurfaceScope(value.scope);
  }
  function isSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "timesheets" && isTimesheetsSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "roster" && isRosterSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "roster-day-timeline" && isRosterDayTimelineSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "leave-requests" && isLeaveRequestsSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "self-service-leave" && isSelfServiceLeaveSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "billing" && isBillingSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "support" && isSupportSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "feedback" && isFeedbackSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "feedback-moderation" && isFeedbackModerationSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "profile" && isProfileSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "staff" && isStaffSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-page" && isAdminPageSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-xero-page" && isAdminXeroPageSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-venue-config" && isAdminVenueConfigSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-invites" && isAdminInvitesSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-exports" && isAdminExportsSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-shift-types" && isAdminShiftTypesSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-roster-groups" && isAdminRosterGroupsSurfaceFragmentKey({ kind: value.kind, params: value.params }) || isRecord(value) && hasExactKeys(value, ["surface", "kind", "params"]) && value.surface === "admin-xero" && isAdminXeroSurfaceFragmentKey({ kind: value.kind, params: value.params });
  }
  function __canonicalFrontendContractJson(value) {
    if (Array.isArray(value)) return `[${value.map(__canonicalFrontendContractJson).join(",")}]`;
    if (isRecord(value)) return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${__canonicalFrontendContractJson(value[key])}`).join(",")}}`;
    return JSON.stringify(value) ?? "null";
  }
  function surfaceFragmentKeyIdentity(value) {
    return __canonicalFrontendContractJson([value.surface, value.kind, value.params]);
  }
  function isFrontendSurfaceInteractionSurfaceName(value) {
    return typeof value === "string" && ["roster", "roster-day-timeline"].includes(value);
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
  var interactionIntentEvent = "bepis:interaction-intent";
  var interactionSessionStartEvent = "bepis:interaction-session-start";
  var interactionSessionEndEvent = "bepis:interaction-session-end";
  var interactionSessionCancelRequestEvent = "bepis:interaction-session-cancel-request";
  function isRosterImageExportStyle(value) {
    return typeof value === "string" && ["colour", "print"].includes(value);
  }
  function isLeaveSectionValue(value) {
    return typeof value === "string" && ["pending", "approved", "denied", "archive"].includes(value);
  }
  function isDialogSubmitConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["loadingLabel"], ["loadingLabel"]) && typeof value["loadingLabel"] === "string";
  }
  function parseDialogSubmitConfig(value) {
    if (isDialogSubmitConfig(value)) return value;
    throw new Error("Invalid DialogSubmitConfig");
  }
  function isNavigationLoadingConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["loadingTitle", "loadingMessage"], ["loadingTitle", "loadingMessage"]) && typeof value["loadingTitle"] === "string" && typeof value["loadingMessage"] === "string";
  }
  function parseNavigationLoadingConfig(value) {
    if (isNavigationLoadingConfig(value)) return value;
    throw new Error("Invalid NavigationLoadingConfig");
  }
  function isToastConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["autoHideMs"], ["autoHideMs"]) && (typeof value["autoHideMs"] === "number" && Number.isInteger(value["autoHideMs"]));
  }
  function parseToastConfig(value) {
    if (isToastConfig(value)) return value;
    throw new Error("Invalid ToastConfig");
  }
  var dialogOverlayMountDomId = "dialog-overlay-mount";
  var toastOverlayMountDomId = "toast-overlay-mount";
  var dialogDismissedEvent = "bepis:dialog-dismissed";
  var dialogMountDomAttr = "data-bepis-dialog-mount";
  var dialogBackdropDomAttr = "data-bepis-dialog-backdrop";
  var dialogCloseDomAttr = "data-bepis-dialog-close";
  var dialogSubmitDomAttr = "data-bepis-dialog-submit";
  var dialogSubmitConfigDomAttr = "data-bepis-dialog-submit-config";
  var dialogBlockingDomAttr = "data-bepis-dialog-blocking";
  var dialogKeyboardDomAttr = "data-bepis-dialog-keyboard";
  var dialogFocusRegionDomAttr = "data-bepis-dialog-focus-region";
  var navigationLoadingDomAttr = "data-bepis-navigation-loading";
  var navigationLoadingConfigDomAttr = "data-bepis-navigation-loading-config";
  var toastMountDomAttr = "data-bepis-toast-mount";
  var toastCloseDomAttr = "data-bepis-toast-close";
  var toastConfigDomAttr = "data-bepis-toast-config";
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
  function isInteractionFieldPresence(value) {
    return typeof value === "string" && ["required", "optional"].includes(value);
  }
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
  function isTogglePresentationState(value) {
    return typeof value === "string" && ["checked", "unchecked"].includes(value);
  }
  function isToggleSubmissionPolicy(value) {
    return typeof value === "string" && ["deferred", "immediate"].includes(value);
  }
  function isToggleTarget(value) {
    return isRecord(value) && hasExactKeys(value, ["tag", "value"], ["tag", "value"]) && value["tag"] === "value" && typeof value["value"] === "string" || isRecord(value) && hasExactKeys(value, ["tag"], ["tag"]) && value["tag"] === "omitted";
  }
  function isToggleConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["presentationState", "checkedTarget", "uncheckedTarget", "transportKey", "submissionPolicy", "breakRegionKey"], ["presentationState", "checkedTarget", "uncheckedTarget", "transportKey", "submissionPolicy", "breakRegionKey"]) && isTogglePresentationState(value["presentationState"]) && isToggleTarget(value["checkedTarget"]) && isToggleTarget(value["uncheckedTarget"]) && typeof value["transportKey"] === "string" && isToggleSubmissionPolicy(value["submissionPolicy"]) && (value["breakRegionKey"] === null || typeof value["breakRegionKey"] === "string");
  }
  function parseToggleConfig(value) {
    if (isToggleConfig(value)) return value;
    throw new Error("Invalid ToggleConfig");
  }
  var toggleRootDomAttr = "data-bepis-toggle-root";
  var toggleInputDomAttr = "data-bepis-toggle-input";
  var toggleLabelStateDomAttr = "data-bepis-toggle-label-state";
  var toggleTransportDomAttr = "data-bepis-toggle-transport";
  var toggleBreakRegionDomAttr = "data-bepis-toggle-break-region";
  var toggleConfigDomAttr = "data-bepis-toggle-config";
  function isTimePickerConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["rangeStart", "rangeEnd", "stepMinutes", "emptyLabel"], ["rangeStart", "rangeEnd", "stepMinutes", "emptyLabel"]) && typeof value["rangeStart"] === "string" && typeof value["rangeEnd"] === "string" && (typeof value["stepMinutes"] === "number" && Number.isInteger(value["stepMinutes"])) && typeof value["emptyLabel"] === "string";
  }
  function parseTimePickerConfig(value) {
    if (isTimePickerConfig(value)) return value;
    throw new Error("Invalid TimePickerConfig");
  }
  function isTimePickerOption(value) {
    return isRecord(value) && hasExactKeys(value, ["value", "label"], ["value", "label"]) && typeof value["value"] === "string" && typeof value["label"] === "string";
  }
  function parseTimePickerOption(value) {
    if (isTimePickerOption(value)) return value;
    throw new Error("Invalid TimePickerOption");
  }
  var timePickerModalDomId = "time-picker-modal";
  var timePickerFieldDomAttr = "data-bepis-time-picker-field";
  var timePickerConfigDomAttr = "data-bepis-time-picker-config";
  var timePickerTriggerDomAttr = "data-bepis-time-picker-trigger";
  var timePickerKeyboardDomAttr = "data-bepis-time-picker-keyboard";
  var timePickerValueDomAttr = "data-bepis-time-picker-value";
  var timePickerLabelDomAttr = "data-bepis-time-picker-label";
  var timePickerStepDownDomAttr = "data-bepis-time-picker-step-down";
  var timePickerStepUpDomAttr = "data-bepis-time-picker-step-up";
  var timePickerOptionsDomAttr = "data-bepis-time-picker-options";
  var timePickerOptionDomAttr = "data-bepis-time-picker-option";
  var timePickerClearDomAttr = "data-bepis-time-picker-clear";
  function isOrderedRangeCrossingPolicy(value) {
    return typeof value === "string" && ["clamp-other-endpoint"].includes(value);
  }
  function isOrderedRangeConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["minimumValue", "maximumValue", "stepValue", "defaultStartValue", "defaultEndValue", "valueLabels", "crossingPolicy"], ["minimumValue", "maximumValue", "stepValue", "defaultStartValue", "defaultEndValue", "valueLabels", "crossingPolicy"]) && (typeof value["minimumValue"] === "number" && Number.isInteger(value["minimumValue"])) && (typeof value["maximumValue"] === "number" && Number.isInteger(value["maximumValue"])) && (typeof value["stepValue"] === "number" && Number.isInteger(value["stepValue"])) && (typeof value["defaultStartValue"] === "number" && Number.isInteger(value["defaultStartValue"])) && (typeof value["defaultEndValue"] === "number" && Number.isInteger(value["defaultEndValue"])) && (Array.isArray(value["valueLabels"]) && value["valueLabels"].every((item) => typeof item === "string")) && isOrderedRangeCrossingPolicy(value["crossingPolicy"]);
  }
  function parseOrderedRangeConfig(value) {
    if (isOrderedRangeConfig(value)) return value;
    throw new Error("Invalid OrderedRangeConfig");
  }
  function isOrderedRangeState(value) {
    return isRecord(value) && hasExactKeys(value, ["startValue", "endValue", "available"], ["startValue", "endValue", "available"]) && (typeof value["startValue"] === "number" && Number.isInteger(value["startValue"])) && (typeof value["endValue"] === "number" && Number.isInteger(value["endValue"])) && typeof value["available"] === "boolean";
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
  function isHorizontalSnapMode(value) {
    return typeof value === "string" && ["equal-groups", "nearest-item"].includes(value);
  }
  function isHorizontalSnapConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["snapMode", "itemSelector", "groupCount", "groupProperty", "groupScopeSelector"], ["snapMode", "itemSelector", "groupCount", "groupProperty", "groupScopeSelector"]) && isHorizontalSnapMode(value["snapMode"]) && (value["itemSelector"] === null || typeof value["itemSelector"] === "string") && (value["groupCount"] === null || typeof value["groupCount"] === "number" && Number.isInteger(value["groupCount"])) && (value["groupProperty"] === null || typeof value["groupProperty"] === "string") && (value["groupScopeSelector"] === null || typeof value["groupScopeSelector"] === "string");
  }
  function parseHorizontalSnapConfig(value) {
    if (isHorizontalSnapConfig(value)) return value;
    throw new Error("Invalid HorizontalSnapConfig");
  }
  function isHorizontalDragConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["ignoreSelector"], ["ignoreSelector"]) && (value["ignoreSelector"] === null || typeof value["ignoreSelector"] === "string");
  }
  function parseHorizontalDragConfig(value) {
    if (isHorizontalDragConfig(value)) return value;
    throw new Error("Invalid HorizontalDragConfig");
  }
  var horizontalScrollSnapDomAttr = "data-bepis-horizontal-scroll-snap";
  var horizontalSnapConfigDomAttr = "data-bepis-horizontal-snap-config";
  var horizontalScrollDragDomAttr = "data-bepis-horizontal-scroll-drag";
  var horizontalDragConfigDomAttr = "data-bepis-horizontal-drag-config";
  function isPasskeySetupPromptMode(value) {
    return typeof value === "string" && ["first-passkey", "additional-device"].includes(value);
  }
  function isPasskeyFlowConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["tag", "beginUrl", "finishUrl", "successRedirect", "statusKey", "waitingMessage", "successMessage", "unsupportedMessage", "failureMessage", "pendingLabel", "cancelledMessage", "autoStart", "closeOverlayOnSuccess"], ["tag", "beginUrl", "finishUrl", "statusKey", "waitingMessage", "successMessage", "unsupportedMessage", "failureMessage", "pendingLabel", "cancelledMessage", "autoStart", "closeOverlayOnSuccess"]) && value["tag"] === "login" && typeof value["beginUrl"] === "string" && typeof value["finishUrl"] === "string" && (!("successRedirect" in value) || typeof value["successRedirect"] === "string") && typeof value["statusKey"] === "string" && typeof value["waitingMessage"] === "string" && typeof value["successMessage"] === "string" && typeof value["unsupportedMessage"] === "string" && typeof value["failureMessage"] === "string" && typeof value["pendingLabel"] === "string" && typeof value["cancelledMessage"] === "string" && typeof value["autoStart"] === "boolean" && typeof value["closeOverlayOnSuccess"] === "boolean" || isRecord(value) && hasExactKeys(value, ["tag", "beginUrl", "finishUrl", "successRedirect", "statusKey", "waitingMessage", "successMessage", "unsupportedMessage", "failureMessage", "pendingLabel", "cancelledMessage", "autoStart", "closeOverlayOnSuccess"], ["tag", "beginUrl", "finishUrl", "statusKey", "waitingMessage", "successMessage", "unsupportedMessage", "failureMessage", "pendingLabel", "cancelledMessage", "autoStart", "closeOverlayOnSuccess"]) && value["tag"] === "registration" && typeof value["beginUrl"] === "string" && typeof value["finishUrl"] === "string" && (!("successRedirect" in value) || typeof value["successRedirect"] === "string") && typeof value["statusKey"] === "string" && typeof value["waitingMessage"] === "string" && typeof value["successMessage"] === "string" && typeof value["unsupportedMessage"] === "string" && typeof value["failureMessage"] === "string" && typeof value["pendingLabel"] === "string" && typeof value["cancelledMessage"] === "string" && typeof value["autoStart"] === "boolean" && typeof value["closeOverlayOnSuccess"] === "boolean" || isRecord(value) && hasExactKeys(value, ["tag", "promptUserKey", "setupPromptMode"], ["tag", "promptUserKey", "setupPromptMode"]) && value["tag"] === "setup-prompt" && typeof value["promptUserKey"] === "string" && isPasskeySetupPromptMode(value["setupPromptMode"]);
  }
  function parsePasskeyFlowConfig(value) {
    if (isPasskeyFlowConfig(value)) return value;
    throw new Error("Invalid PasskeyFlowConfig");
  }
  function isPasskeyCredentialType(value) {
    return typeof value === "string" && ["public-key"].includes(value);
  }
  function isPasskeyAuthenticatorAttachment(value) {
    return typeof value === "string" && ["platform", "cross-platform"].includes(value);
  }
  function isPasskeyResidentKeyRequirement(value) {
    return typeof value === "string" && ["discouraged", "preferred", "required"].includes(value);
  }
  function isPasskeyUserVerificationRequirement(value) {
    return typeof value === "string" && ["discouraged", "preferred", "required"].includes(value);
  }
  function isPasskeyAttestationConveyancePreference(value) {
    return typeof value === "string" && ["none", "indirect", "direct", "enterprise"].includes(value);
  }
  function isPasskeyRelyingParty(value) {
    return isRecord(value) && hasExactKeys(value, ["id", "name"], ["id", "name"]) && typeof value["id"] === "string" && typeof value["name"] === "string";
  }
  function isPasskeyUserEntity(value) {
    return isRecord(value) && hasExactKeys(value, ["id", "displayName", "name"], ["id", "displayName", "name"]) && typeof value["id"] === "string" && typeof value["displayName"] === "string" && typeof value["name"] === "string";
  }
  function isPasskeyCredentialParameter(value) {
    return isRecord(value) && hasExactKeys(value, ["type", "alg"], ["type", "alg"]) && isPasskeyCredentialType(value["type"]) && (typeof value["alg"] === "number" && Number.isInteger(value["alg"]));
  }
  function isPasskeyCredentialDescriptor(value) {
    return isRecord(value) && hasExactKeys(value, ["type", "id"], ["type", "id"]) && isPasskeyCredentialType(value["type"]) && typeof value["id"] === "string";
  }
  function isPasskeyAuthenticatorSelection(value) {
    return isRecord(value) && hasExactKeys(value, ["authenticatorAttachment", "residentKey", "requireResidentKey", "userVerification"], ["residentKey", "requireResidentKey", "userVerification"]) && (!("authenticatorAttachment" in value) || isPasskeyAuthenticatorAttachment(value["authenticatorAttachment"])) && isPasskeyResidentKeyRequirement(value["residentKey"]) && typeof value["requireResidentKey"] === "boolean" && isPasskeyUserVerificationRequirement(value["userVerification"]);
  }
  function isPasskeyRegistrationOptions(value) {
    return isRecord(value) && hasExactKeys(value, ["rp", "user", "challenge", "pubKeyCredParams", "timeout", "excludeCredentials", "authenticatorSelection", "attestation"], ["rp", "user", "challenge", "pubKeyCredParams", "timeout", "excludeCredentials", "authenticatorSelection", "attestation"]) && isPasskeyRelyingParty(value["rp"]) && isPasskeyUserEntity(value["user"]) && typeof value["challenge"] === "string" && (Array.isArray(value["pubKeyCredParams"]) && value["pubKeyCredParams"].every((item) => isPasskeyCredentialParameter(item))) && (typeof value["timeout"] === "number" && Number.isInteger(value["timeout"])) && (Array.isArray(value["excludeCredentials"]) && value["excludeCredentials"].every((item) => isPasskeyCredentialDescriptor(item))) && isPasskeyAuthenticatorSelection(value["authenticatorSelection"]) && isPasskeyAttestationConveyancePreference(value["attestation"]);
  }
  function parsePasskeyRegistrationOptions(value) {
    if (isPasskeyRegistrationOptions(value)) return value;
    throw new Error("Invalid PasskeyRegistrationOptions");
  }
  function isPasskeyAuthenticationOptions(value) {
    return isRecord(value) && hasExactKeys(value, ["challenge", "timeout", "rpId", "allowCredentials", "userVerification"], ["challenge", "timeout", "rpId", "allowCredentials", "userVerification"]) && typeof value["challenge"] === "string" && (typeof value["timeout"] === "number" && Number.isInteger(value["timeout"])) && typeof value["rpId"] === "string" && (Array.isArray(value["allowCredentials"]) && value["allowCredentials"].every((item) => isPasskeyCredentialDescriptor(item))) && isPasskeyUserVerificationRequirement(value["userVerification"]);
  }
  function parsePasskeyAuthenticationOptions(value) {
    if (isPasskeyAuthenticationOptions(value)) return value;
    throw new Error("Invalid PasskeyAuthenticationOptions");
  }
  function encodePasskeyRegistrationRequest(value) {
    return value;
  }
  function encodePasskeyAuthenticationRequest(value) {
    return value;
  }
  function isPasskeyFinishResponse(value) {
    return isRecord(value) && hasExactKeys(value, ["tag", "userId", "redirectTo"], ["tag", "userId", "redirectTo"]) && value["tag"] === "authenticated" && typeof value["userId"] === "string" && typeof value["redirectTo"] === "string" || isRecord(value) && hasExactKeys(value, ["tag", "userId", "recoveryCode"], ["tag", "userId", "recoveryCode"]) && value["tag"] === "registered" && typeof value["userId"] === "string" && (value["recoveryCode"] === null || typeof value["recoveryCode"] === "string") || isRecord(value) && hasExactKeys(value, ["tag", "userId", "redirectTo"], ["tag", "userId", "redirectTo"]) && value["tag"] === "setup-registered" && typeof value["userId"] === "string" && typeof value["redirectTo"] === "string";
  }
  function parsePasskeyFinishResponse(value) {
    if (isPasskeyFinishResponse(value)) return value;
    throw new Error("Invalid PasskeyFinishResponse");
  }
  function isPasskeyErrorResponse(value) {
    return isRecord(value) && hasExactKeys(value, ["tag", "error"], ["tag", "error"]) && value["tag"] === "failure" && typeof value["error"] === "string" || isRecord(value) && hasExactKeys(value, ["tag", "error", "redirectTo"], ["tag", "error", "redirectTo"]) && value["tag"] === "redirect" && typeof value["error"] === "string" && typeof value["redirectTo"] === "string";
  }
  function parsePasskeyErrorResponse(value) {
    if (isPasskeyErrorResponse(value)) return value;
    throw new Error("Invalid PasskeyErrorResponse");
  }
  var passkeyFirstPasskeyMode = "first-passkey";
  var passkeyAdditionalDeviceMode = "additional-device";
  var passkeyLoginDomAttr = "data-bepis-passkey-login";
  var passkeyRegistrationDomAttr = "data-bepis-passkey-registration";
  var passkeySetupPromptDomAttr = "data-bepis-passkey-setup-prompt";
  var passkeyActionButtonDomAttr = "data-bepis-passkey-action-button";
  var passkeyDeviceNameDomAttr = "data-bepis-passkey-device-name";
  var passkeyStatusDomAttr = "data-bepis-passkey-status";
  var passkeyRecoveryDomAttr = "data-bepis-passkey-recovery";
  var passkeyDismissalDomAttr = "data-bepis-passkey-dismissal";
  var passkeyFlowConfigDomAttr = "data-bepis-passkey-flow-config";
  function isPwaInstallState(value) {
    return typeof value === "string" && ["accepted", "dismissed", "failed"].includes(value);
  }
  var pwaInstallPageDomAttr = "data-bepis-pwa-install-page";
  var pwaInstallButtonDomAttr = "data-bepis-pwa-install-button";
  var pwaInstallResultDomAttr = "data-bepis-pwa-install-result";
  var pwaInstallResultStateDomAttr = "data-bepis-pwa-install-result-state";
  var pwaInstalledStatusDomAttr = "data-bepis-pwa-installed-status";
  function isXeroCandidateFilterConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["searchProjection"], ["searchProjection"]) && typeof value["searchProjection"] === "string";
  }
  function parseXeroCandidateFilterConfig(value) {
    if (isXeroCandidateFilterConfig(value)) return value;
    throw new Error("Invalid XeroCandidateFilterConfig");
  }
  var xeroCandidateFilterRootDomAttr = "data-bepis-xero-candidate-filter-root";
  var xeroCandidateFilterSearchDomAttr = "data-bepis-xero-candidate-filter-search";
  var xeroCandidateFilterCandidateDomAttr = "data-bepis-xero-candidate-filter-candidate";
  var xeroCandidateFilterConfigDomAttr = "data-bepis-xero-candidate-filter-config";
  var xeroCandidateFilterEmptyDomAttr = "data-bepis-xero-candidate-filter-empty";
  var liveUpdateSocketPath = "live-updates";
  var surfaceConfigDomAttr = "data-bepis-surface-config";
  function encodeLiveUpdateCommand(value) {
    return value;
  }
  function isLiveUpdateMessage(value) {
    return isRecord(value) && hasExactKeys(value, ["type", "scope", "scopeKey", "currentVersion", "resync"], ["type", "scope", "scopeKey", "currentVersion", "resync"]) && value["type"] === "subscribed" && isSurfaceScope(value["scope"]) && typeof value["scopeKey"] === "string" && (typeof value["currentVersion"] === "number" && Number.isInteger(value["currentVersion"])) && typeof value["resync"] === "boolean" || isRecord(value) && hasExactKeys(value, ["type", "scope", "scopeKey", "version", "fragments"], ["type", "scope", "scopeKey", "version", "fragments"]) && value["type"] === "invalidate" && isSurfaceScope(value["scope"]) && typeof value["scopeKey"] === "string" && (typeof value["version"] === "number" && Number.isInteger(value["version"])) && (Array.isArray(value["fragments"]) && value["fragments"].every((item) => isSurfaceFragmentKey(item))) || isRecord(value) && hasExactKeys(value, ["type", "message"], ["type", "message"]) && value["type"] === "error" && typeof value["message"] === "string";
  }
  function parseLiveUpdateMessage(value) {
    if (isLiveUpdateMessage(value)) return value;
    throw new Error("Invalid LiveUpdateMessage");
  }
  function isTimesheetStaffPanelSortRow(value) {
    return isRecord(value) && hasExactKeys(value, ["staffRowKey", "staffName", "staffRole", "entryCount", "approvedCount"], ["staffRowKey", "staffName", "staffRole", "entryCount", "approvedCount"]) && typeof value["staffRowKey"] === "string" && typeof value["staffName"] === "string" && typeof value["staffRole"] === "string" && (typeof value["entryCount"] === "number" && Number.isInteger(value["entryCount"])) && (typeof value["approvedCount"] === "number" && Number.isInteger(value["approvedCount"]));
  }
  function parseTimesheetStaffPanelSortRow(value) {
    if (isTimesheetStaffPanelSortRow(value)) return value;
    throw new Error("Invalid TimesheetStaffPanelSortRow");
  }
  function isTimesheetsTimesheetWeekScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "windowStartDate", "windowEndDate", "rosterCalendarRevision"], ["venueId", "windowStartDate", "windowEndDate", "rosterCalendarRevision"]) && typeof value["venueId"] === "string" && typeof value["windowStartDate"] === "string" && typeof value["windowEndDate"] === "string" && (typeof value["rosterCalendarRevision"] === "number" && Number.isInteger(value["rosterCalendarRevision"]));
  }
  function isRosterStaffPanelSortRow(value) {
    return isRecord(value) && hasExactKeys(value, ["staffRowKey", "staffName", "staffRole", "assignedShifts", "idealShifts"], ["staffRowKey", "staffName", "staffRole", "assignedShifts", "idealShifts"]) && typeof value["staffRowKey"] === "string" && typeof value["staffName"] === "string" && typeof value["staffRole"] === "string" && (typeof value["assignedShifts"] === "number" && Number.isInteger(value["assignedShifts"])) && (typeof value["idealShifts"] === "number" && Number.isInteger(value["idealShifts"]));
  }
  function parseRosterStaffPanelSortRow(value) {
    if (isRosterStaffPanelSortRow(value)) return value;
    throw new Error("Invalid RosterStaffPanelSortRow");
  }
  function isRosterImageExportConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["imageExportFilename", "imageExportStyle", "imageExportMimeType", "imageExportQualityPercent", "imageExportPixelRatio", "imageExportMinimumWidth", "imageExportMaximumWidth", "imageExportIdleLabel", "imageExportPreparingLabel", "imageExportDownloadedLabel", "imageExportFailedLabel", "imageExportFailureMessage", "imageExportMissingProjectionMessage", "imageExportCloneFailureMessage", "imageExportRenderFailureMessage", "imageExportCanvasFailureMessage", "imageExportEncodingFailureMessage"], ["imageExportFilename", "imageExportStyle", "imageExportMimeType", "imageExportQualityPercent", "imageExportPixelRatio", "imageExportMinimumWidth", "imageExportMaximumWidth", "imageExportIdleLabel", "imageExportPreparingLabel", "imageExportDownloadedLabel", "imageExportFailedLabel", "imageExportFailureMessage", "imageExportMissingProjectionMessage", "imageExportCloneFailureMessage", "imageExportRenderFailureMessage", "imageExportCanvasFailureMessage", "imageExportEncodingFailureMessage"]) && typeof value["imageExportFilename"] === "string" && isRosterImageExportStyle(value["imageExportStyle"]) && typeof value["imageExportMimeType"] === "string" && (typeof value["imageExportQualityPercent"] === "number" && Number.isInteger(value["imageExportQualityPercent"])) && (typeof value["imageExportPixelRatio"] === "number" && Number.isInteger(value["imageExportPixelRatio"])) && (typeof value["imageExportMinimumWidth"] === "number" && Number.isInteger(value["imageExportMinimumWidth"])) && (typeof value["imageExportMaximumWidth"] === "number" && Number.isInteger(value["imageExportMaximumWidth"])) && typeof value["imageExportIdleLabel"] === "string" && typeof value["imageExportPreparingLabel"] === "string" && typeof value["imageExportDownloadedLabel"] === "string" && typeof value["imageExportFailedLabel"] === "string" && typeof value["imageExportFailureMessage"] === "string" && typeof value["imageExportMissingProjectionMessage"] === "string" && typeof value["imageExportCloneFailureMessage"] === "string" && typeof value["imageExportRenderFailureMessage"] === "string" && typeof value["imageExportCanvasFailureMessage"] === "string" && typeof value["imageExportEncodingFailureMessage"] === "string";
  }
  function parseRosterImageExportConfig(value) {
    if (isRosterImageExportConfig(value)) return value;
    throw new Error("Invalid RosterImageExportConfig");
  }
  function isRosterImageExportCell(value) {
    return isRecord(value) && hasExactKeys(value, ["imageExportText", "imageExportEndEllipsis"], ["imageExportText", "imageExportEndEllipsis"]) && typeof value["imageExportText"] === "string" && typeof value["imageExportEndEllipsis"] === "boolean";
  }
  function parseRosterImageExportCell(value) {
    if (isRosterImageExportCell(value)) return value;
    throw new Error("Invalid RosterImageExportCell");
  }
  function isRosterWageFilterConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["wageFilterEnabled", "wageFilterRefreshTargetIds", "wageFilterRequestTargetIds"], ["wageFilterEnabled", "wageFilterRefreshTargetIds", "wageFilterRequestTargetIds"]) && typeof value["wageFilterEnabled"] === "boolean" && (Array.isArray(value["wageFilterRefreshTargetIds"]) && value["wageFilterRefreshTargetIds"].every((item) => typeof item === "string")) && (Array.isArray(value["wageFilterRequestTargetIds"]) && value["wageFilterRequestTargetIds"].every((item) => typeof item === "string"));
  }
  function parseRosterWageFilterConfig(value) {
    if (isRosterWageFilterConfig(value)) return value;
    throw new Error("Invalid RosterWageFilterConfig");
  }
  function encodeRosterWageFilterRequest(value) {
    return value;
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
  function isRosterRosterWeekScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "rosterGroupId", "windowStartDate", "windowEndDate", "rosterCalendarRevision"], ["venueId", "rosterGroupId", "windowStartDate", "windowEndDate", "rosterCalendarRevision"]) && typeof value["venueId"] === "string" && typeof value["rosterGroupId"] === "string" && typeof value["windowStartDate"] === "string" && typeof value["windowEndDate"] === "string" && (typeof value["rosterCalendarRevision"] === "number" && Number.isInteger(value["rosterCalendarRevision"]));
  }
  function isRosterDayTimelineRosterDayTimelineScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "rosterGroupId", "windowStartDate", "windowEndDate", "rosterCalendarRevision", "rosterDayId"], ["venueId", "rosterGroupId", "windowStartDate", "windowEndDate", "rosterCalendarRevision", "rosterDayId"]) && typeof value["venueId"] === "string" && typeof value["rosterGroupId"] === "string" && typeof value["windowStartDate"] === "string" && typeof value["windowEndDate"] === "string" && (typeof value["rosterCalendarRevision"] === "number" && Number.isInteger(value["rosterCalendarRevision"])) && typeof value["rosterDayId"] === "string";
  }
  function isLeaveStaffPanelSortRow(value) {
    return isRecord(value) && hasExactKeys(value, ["staffRowKey", "staffName", "staffRole", "periodCount", "pendingCount"], ["staffRowKey", "staffName", "staffRole", "periodCount", "pendingCount"]) && typeof value["staffRowKey"] === "string" && typeof value["staffName"] === "string" && typeof value["staffRole"] === "string" && (typeof value["periodCount"] === "number" && Number.isInteger(value["periodCount"])) && (typeof value["pendingCount"] === "number" && Number.isInteger(value["pendingCount"]));
  }
  function parseLeaveStaffPanelSortRow(value) {
    if (isLeaveStaffPanelSortRow(value)) return value;
    throw new Error("Invalid LeaveStaffPanelSortRow");
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
  function isFeedbackFeedbackVenueScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId"], ["venueId"]) && typeof value["venueId"] === "string";
  }
  function isFeedbackModerationFeedbackPlatformScope(value) {
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
  var timesheetWeekShellDomToken = "timesheet-week-shell";
  var timesheetsTimesheetStaffPanelSortRootDomAttr = "data-bepis-timesheets-timesheet-staff-panel-sort-root";
  var timesheetsTimesheetStaffPanelSortRowDomAttr = "data-bepis-timesheets-timesheet-staff-panel-sort-row";
  var timesheetsTimesheetStaffPanelSortControlDomAttr = "data-bepis-timesheets-timesheet-staff-panel-sort-control";
  var timesheetsTimesheetSidePanelTabDomAttr = "data-bepis-timesheets-timesheet-side-panel-tab";
  var timesheetsTimesheetSidePanelRootDomAttr = "data-bepis-timesheets-timesheet-side-panel-root";
  var timesheetsTimesheetSidePanelMainDomAttr = "data-bepis-timesheets-timesheet-side-panel-main";
  var timesheetsTimesheetSidePanelPanelDomAttr = "data-bepis-timesheets-timesheet-side-panel-panel";
  var timesheetsTimesheetSidePanelToggleDomAttr = "data-bepis-timesheets-timesheet-side-panel-toggle";
  var timesheetsTimesheetSidePanelLabelDomAttr = "data-bepis-timesheets-timesheet-side-panel-label";
  var timesheetsTimesheetStaffHighlightSourceDomAttr = "data-bepis-timesheets-timesheet-staff-highlight-source";
  var timesheetsTimesheetStaffHighlightMemberDomAttr = "data-bepis-timesheets-timesheet-staff-highlight-member";
  var timesheetsTimesheetStaffHighlightPinDomAttr = "data-bepis-timesheets-timesheet-staff-highlight-pin";
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
  var rosterColumnEditorDomAttr = "data-bepis-roster-column-editor";
  var rosterColumnEditStartDomAttr = "data-bepis-roster-column-edit-start";
  var rosterColumnEditDoneDomAttr = "data-bepis-roster-column-edit-done";
  var rosterImageExportTriggerDomAttr = "data-bepis-roster-image-export-trigger";
  var rosterImageExportConfigDomAttr = "data-bepis-roster-image-export-config";
  var rosterImageExportProjectionDomAttr = "data-bepis-roster-image-export-projection";
  var rosterImageExportRowDomAttr = "data-bepis-roster-image-export-row";
  var rosterImageExportCellDomAttr = "data-bepis-roster-image-export-cell";
  var rosterWageFilterConfigDomAttr = "data-bepis-roster-wage-filter-config";
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
  var rosterStaffHighlightDefaultDomAttr = "data-bepis-roster-staff-highlight-default";
  var rosterShiftGroupHighlightSourceDomAttr = "data-bepis-roster-shift-group-highlight-source";
  var rosterShiftGroupHighlightMemberDomAttr = "data-bepis-roster-shift-group-highlight-member";
  var rosterSidePanelDomAttr = "data-bepis-roster-side-panel";
  var rosterColumnEditingDomAttr = "data-bepis-roster-column-editing";
  var rosterImageExportFormatDomAttr = "data-bepis-roster-image-export-format";
  var rosterWeekOverviewAvailabilityDomAttr = "data-bepis-roster-week-overview-availability";
  var rosterWeekOverviewClosureDomAttr = "data-bepis-roster-week-overview-closure";
  var rosterWeekOverviewCalendarDayDomAttr = "data-bepis-roster-week-overview-calendar-day";
  var rosterStaffHighlightOrderDomAttr = "data-bepis-roster-staff-highlight-order";
  var rosterDayTimelineShiftGroupHighlightSourceDomAttr = "data-bepis-roster-day-timeline-shift-group-highlight-source";
  var rosterDayTimelineShiftGroupHighlightMemberDomAttr = "data-bepis-roster-day-timeline-shift-group-highlight-member";
  var leaveRequestsLeaveStaffPanelSortRootDomAttr = "data-bepis-leave-requests-leave-staff-panel-sort-root";
  var leaveRequestsLeaveStaffPanelSortRowDomAttr = "data-bepis-leave-requests-leave-staff-panel-sort-row";
  var leaveRequestsLeaveStaffPanelSortControlDomAttr = "data-bepis-leave-requests-leave-staff-panel-sort-control";
  var leaveRequestsLeaveRequestTabDomAttr = "data-bepis-leave-requests-leave-request-tab";
  var leaveRequestsLeaveArchiveRequestTabDomAttr = "data-bepis-leave-requests-leave-archive-request-tab";
  var leaveRequestsLeaveSidePanelTabDomAttr = "data-bepis-leave-requests-leave-side-panel-tab";
  var leaveRequestsLeaveSidePanelRootDomAttr = "data-bepis-leave-requests-leave-side-panel-root";
  var leaveRequestsLeaveSidePanelMainDomAttr = "data-bepis-leave-requests-leave-side-panel-main";
  var leaveRequestsLeaveSidePanelPanelDomAttr = "data-bepis-leave-requests-leave-side-panel-panel";
  var leaveRequestsLeaveSidePanelToggleDomAttr = "data-bepis-leave-requests-leave-side-panel-toggle";
  var leaveRequestsLeaveSidePanelLabelDomAttr = "data-bepis-leave-requests-leave-side-panel-label";
  var leaveRequestsLeaveStaffHighlightSourceDomAttr = "data-bepis-leave-requests-leave-staff-highlight-source";
  var leaveRequestsLeaveStaffHighlightMemberDomAttr = "data-bepis-leave-requests-leave-staff-highlight-member";
  var leaveRequestsLeaveStaffHighlightPinDomAttr = "data-bepis-leave-requests-leave-staff-highlight-pin";
  var leaveRequestsLeaveSidePanelDomAttr = "data-bepis-leave-requests-leave-side-panel";
  function isTimesheetsTimesheetSidePanelState(value) {
    return typeof value === "string" && ["collapsed", "expanded"].includes(value);
  }
  function isRosterSidePanelState(value) {
    return typeof value === "string" && ["collapsed", "expanded"].includes(value);
  }
  var rosterColumnEditingStates = { "inactive": "inactive", "active": "active" };
  function isRosterColumnEditingState(value) {
    return typeof value === "string" && ["inactive", "active"].includes(value);
  }
  var rosterImageExportFormatStates = { "png": "png" };
  function isRosterImageExportFormatState(value) {
    return typeof value === "string" && ["png"].includes(value);
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
  function isLeaveRequestTabsKey(value) {
    return typeof value === "string" && ["pending", "approved", "denied", "archive"].includes(value);
  }
  function isLeaveArchiveRequestTabsKey(value) {
    return typeof value === "string" && ["pending", "approved", "denied", "archive"].includes(value);
  }
  function isLeaveSidePanelTabsKey(value) {
    return typeof value === "string" && ["staff", "settings"].includes(value);
  }
  var FrontendSurfaceLinkedHighlightRegistry = { "timesheets": [{ "name": "timesheet-staff-cards-highlight", "sourceRoleAttribute": timesheetsTimesheetStaffHighlightSourceDomAttr, "memberRoleAttribute": timesheetsTimesheetStaffHighlightMemberDomAttr, "pinRoleAttribute": timesheetsTimesheetStaffHighlightPinDomAttr, "defaultRoleAttribute": null, "orderStateAttribute": null, "activations": ["hover", "focus", "keyboard", "pin"], "effects": ["matching-source", "matching-member"] }], "roster": [{ "name": "staff-shifts-highlight", "sourceRoleAttribute": rosterStaffHighlightSourceDomAttr, "memberRoleAttribute": rosterStaffHighlightMemberDomAttr, "pinRoleAttribute": rosterStaffHighlightPinDomAttr, "defaultRoleAttribute": rosterStaffHighlightDefaultDomAttr, "orderStateAttribute": rosterStaffHighlightOrderDomAttr, "activations": ["hover", "focus", "keyboard", "pin", "default"], "effects": ["matching-source", "matching-member", "ordered-member-bounds"] }, { "name": "shift-group-highlight", "sourceRoleAttribute": rosterShiftGroupHighlightSourceDomAttr, "memberRoleAttribute": rosterShiftGroupHighlightMemberDomAttr, "pinRoleAttribute": null, "defaultRoleAttribute": null, "orderStateAttribute": null, "activations": ["hover", "focus", "keyboard"], "effects": ["matching-member"] }], "roster-day-timeline": [{ "name": "shift-group-highlight", "sourceRoleAttribute": rosterDayTimelineShiftGroupHighlightSourceDomAttr, "memberRoleAttribute": rosterDayTimelineShiftGroupHighlightMemberDomAttr, "pinRoleAttribute": null, "defaultRoleAttribute": null, "orderStateAttribute": null, "activations": ["hover", "focus", "keyboard"], "effects": ["matching-member"] }], "leave-requests": [{ "name": "leave-staff-periods-highlight", "sourceRoleAttribute": leaveRequestsLeaveStaffHighlightSourceDomAttr, "memberRoleAttribute": leaveRequestsLeaveStaffHighlightMemberDomAttr, "pinRoleAttribute": leaveRequestsLeaveStaffHighlightPinDomAttr, "defaultRoleAttribute": null, "orderStateAttribute": null, "activations": ["hover", "focus", "keyboard", "pin"], "effects": ["matching-source", "matching-member"] }], "self-service-leave": [], "billing": [], "support": [], "feedback": [], "feedback-moderation": [], "profile": [], "staff": [], "admin-page": [], "admin-xero-page": [], "admin-venue-config": [], "admin-invites": [], "admin-exports": [], "admin-shift-types": [], "admin-roster-groups": [], "admin-xero": [] };
  var FrontendSurfaceCompleteSetSortRegistry = { "timesheets": [{ "name": "timesheet-staff-panel-sort", "rootRoleAttribute": timesheetsTimesheetStaffPanelSortRootDomAttr, "rowRoleAttribute": timesheetsTimesheetStaffPanelSortRowDomAttr, "controlRoleAttribute": timesheetsTimesheetStaffPanelSortControlDomAttr, "parseRow": parseTimesheetStaffPanelSortRow, "isKey": isTimesheetStaffPanelSortKey, "keys": [{ "key": "name", "comparators": [{ "field": "staffName", "valueType": "text", "direction": "selected", "read": (row) => parseTimesheetStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseTimesheetStaffPanelSortRow(row).staffRowKey }] }, { "key": "role", "comparators": [{ "field": "staffRole", "valueType": "text", "direction": "selected", "read": (row) => parseTimesheetStaffPanelSortRow(row).staffRole }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseTimesheetStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseTimesheetStaffPanelSortRow(row).staffRowKey }] }, { "key": "count", "comparators": [{ "field": "entryCount", "valueType": "integer", "direction": "selected", "read": (row) => parseTimesheetStaffPanelSortRow(row).entryCount }, { "field": "approvedCount", "valueType": "integer", "direction": "selected", "read": (row) => parseTimesheetStaffPanelSortRow(row).approvedCount }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseTimesheetStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseTimesheetStaffPanelSortRow(row).staffRowKey }] }], "defaultKey": "name", "defaultDirection": "ascending" }], "roster": [{ "name": "roster-staff-panel-sort", "rootRoleAttribute": rosterStaffPanelSortRootDomAttr, "rowRoleAttribute": rosterStaffPanelSortRowDomAttr, "controlRoleAttribute": rosterStaffPanelSortControlDomAttr, "parseRow": parseRosterStaffPanelSortRow, "isKey": isRosterStaffPanelSortKey, "keys": [{ "key": "name", "comparators": [{ "field": "staffName", "valueType": "text", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffRowKey }] }, { "key": "role", "comparators": [{ "field": "staffRole", "valueType": "text", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).staffRole }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffRowKey }] }, { "key": "shifts", "comparators": [{ "field": "assignedShifts", "valueType": "integer", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).assignedShifts }, { "field": "idealShifts", "valueType": "integer", "direction": "selected", "read": (row) => parseRosterStaffPanelSortRow(row).idealShifts }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseRosterStaffPanelSortRow(row).staffRowKey }] }], "defaultKey": "name", "defaultDirection": "ascending" }], "roster-day-timeline": [], "leave-requests": [{ "name": "leave-staff-panel-sort", "rootRoleAttribute": leaveRequestsLeaveStaffPanelSortRootDomAttr, "rowRoleAttribute": leaveRequestsLeaveStaffPanelSortRowDomAttr, "controlRoleAttribute": leaveRequestsLeaveStaffPanelSortControlDomAttr, "parseRow": parseLeaveStaffPanelSortRow, "isKey": isLeaveStaffPanelSortKey, "keys": [{ "key": "name", "comparators": [{ "field": "staffName", "valueType": "text", "direction": "selected", "read": (row) => parseLeaveStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseLeaveStaffPanelSortRow(row).staffRowKey }] }, { "key": "role", "comparators": [{ "field": "staffRole", "valueType": "text", "direction": "selected", "read": (row) => parseLeaveStaffPanelSortRow(row).staffRole }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseLeaveStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseLeaveStaffPanelSortRow(row).staffRowKey }] }, { "key": "count", "comparators": [{ "field": "periodCount", "valueType": "integer", "direction": "selected", "read": (row) => parseLeaveStaffPanelSortRow(row).periodCount }, { "field": "pendingCount", "valueType": "integer", "direction": "selected", "read": (row) => parseLeaveStaffPanelSortRow(row).pendingCount }, { "field": "staffName", "valueType": "text", "direction": "ascending", "read": (row) => parseLeaveStaffPanelSortRow(row).staffName }, { "field": "staffRowKey", "valueType": "opaque", "direction": "ascending", "read": (row) => parseLeaveStaffPanelSortRow(row).staffRowKey }] }], "defaultKey": "name", "defaultDirection": "ascending" }], "self-service-leave": [], "billing": [], "support": [], "feedback": [], "feedback-moderation": [], "profile": [], "staff": [], "admin-page": [], "admin-xero-page": [], "admin-venue-config": [], "admin-invites": [], "admin-exports": [], "admin-shift-types": [], "admin-roster-groups": [], "admin-xero": [] };
  var FrontendSurfaceTabSetRegistry = { "timesheets": [{ "name": "timesheet-side-panel-tabs", "tabRoleAttribute": timesheetsTimesheetSidePanelTabDomAttr, "keys": ["staff", "settings"], "defaultKey": "staff", "isKey": isTimesheetSidePanelTabsKey }], "roster": [{ "name": "roster-staff-panel-tabs", "tabRoleAttribute": rosterStaffPanelTabDomAttr, "keys": ["staff", "templates", "settings"], "defaultKey": "staff", "isKey": isRosterStaffPanelTabsKey }, { "name": "roster-self-service-panel-tabs", "tabRoleAttribute": rosterSelfServicePanelTabDomAttr, "keys": ["quick-tools", "settings"], "defaultKey": "quick-tools", "isKey": isRosterSelfServicePanelTabsKey }], "roster-day-timeline": [], "leave-requests": [{ "name": "leave-request-tabs", "tabRoleAttribute": leaveRequestsLeaveRequestTabDomAttr, "keys": ["pending", "approved", "denied", "archive"], "defaultKey": "pending", "isKey": isLeaveRequestTabsKey }, { "name": "leave-archive-request-tabs", "tabRoleAttribute": leaveRequestsLeaveArchiveRequestTabDomAttr, "keys": ["pending", "approved", "denied", "archive"], "defaultKey": "archive", "isKey": isLeaveArchiveRequestTabsKey }, { "name": "leave-side-panel-tabs", "tabRoleAttribute": leaveRequestsLeaveSidePanelTabDomAttr, "keys": ["staff", "settings"], "defaultKey": "staff", "isKey": isLeaveSidePanelTabsKey }], "self-service-leave": [], "billing": [], "support": [], "feedback": [], "feedback-moderation": [], "profile": [], "staff": [], "admin-page": [], "admin-xero-page": [], "admin-venue-config": [], "admin-invites": [], "admin-exports": [], "admin-shift-types": [], "admin-roster-groups": [], "admin-xero": [] };
  var FrontendSurfaceSidePanelRegistry = { "timesheets": [{ "name": "timesheet-side-panel", "rootRoleAttribute": timesheetsTimesheetSidePanelRootDomAttr, "mainRoleAttribute": timesheetsTimesheetSidePanelMainDomAttr, "panelRoleAttribute": timesheetsTimesheetSidePanelPanelDomAttr, "toggleRoleAttribute": timesheetsTimesheetSidePanelToggleDomAttr, "labelRoleAttribute": timesheetsTimesheetSidePanelLabelDomAttr, "stateAttribute": timesheetsTimesheetSidePanelDomAttr, "collapsedValue": "collapsed", "expandedValue": "expanded", "isState": isTimesheetsTimesheetSidePanelState }], "roster": [{ "name": "roster-side-panel", "rootRoleAttribute": rosterSidePanelRootDomAttr, "mainRoleAttribute": rosterSidePanelMainDomAttr, "panelRoleAttribute": rosterSidePanelPanelDomAttr, "toggleRoleAttribute": rosterSidePanelToggleDomAttr, "labelRoleAttribute": rosterSidePanelLabelDomAttr, "stateAttribute": rosterSidePanelDomAttr, "collapsedValue": "collapsed", "expandedValue": "expanded", "isState": isRosterSidePanelState }], "roster-day-timeline": [], "leave-requests": [{ "name": "leave-side-panel", "rootRoleAttribute": leaveRequestsLeaveSidePanelRootDomAttr, "mainRoleAttribute": leaveRequestsLeaveSidePanelMainDomAttr, "panelRoleAttribute": leaveRequestsLeaveSidePanelPanelDomAttr, "toggleRoleAttribute": leaveRequestsLeaveSidePanelToggleDomAttr, "labelRoleAttribute": leaveRequestsLeaveSidePanelLabelDomAttr, "stateAttribute": leaveRequestsLeaveSidePanelDomAttr, "collapsedValue": "collapsed", "expandedValue": "expanded", "isState": isLeaveRequestsLeaveSidePanelState }], "self-service-leave": [], "billing": [], "support": [], "feedback": [], "feedback-moderation": [], "profile": [], "staff": [], "admin-page": [], "admin-xero-page": [], "admin-venue-config": [], "admin-invites": [], "admin-exports": [], "admin-shift-types": [], "admin-roster-groups": [], "admin-xero": [] };
  var FrontendSurfaceFragmentRegistry = { "timesheets": ["timesheet-toolbar", "timesheet-day-columns", "timesheet-side-panel-content", "timesheet-day-section"], "roster": ["roster-content", "roster-grid-toolbar", "roster-grid-frame", "roster-day-columns", "roster-day-rail", "roster-wage-rail", "roster-slots-grid", "roster-staff-panel", "roster-template-library", "roster-day-section", "roster-row"], "roster-day-timeline": ["roster-day-timeline-content"], "leave-requests": ["unavailability-blackouts", "leave-side-panel-content", "leave-availability-warnings", "leave-section-count", "leave-section-list"], "self-service-leave": ["self-service-leave-form", "visible-unavailability-blackouts", "self-service-leave-history"], "billing": ["billing-status"], "support": ["support-award-rates", "support-public-holidays"], "feedback": ["feedback-board"], "feedback-moderation": ["feedback-desktop-count", "feedback-mobile-count", "feedback-review"], "profile": ["profile-details-section", "profile-preferences-section", "profile-security-section", "profile-leave-section"], "staff": ["staff-details-section", "staff-preferences-section", "staff-visible-unavailability-blackouts", "staff-leave-section"], "admin-page": [], "admin-xero-page": [], "admin-venue-config": ["admin-venue-settings"], "admin-invites": ["admin-invites"], "admin-exports": ["admin-exports"], "admin-shift-types": ["admin-shift-types"], "admin-roster-groups": ["admin-roster-groups"], "admin-xero": ["admin-xero-shell", "admin-xero-reference-sync", "admin-xero-timesheet-preparation-wait", "admin-xero-pay-item-import-wait", "admin-xero-staff-mappings-wait"] };
  function isFrontendSurfaceName(value) {
    return typeof value === "string" && Object.prototype.hasOwnProperty.call(FrontendSurfaceFragmentRegistry, value);
  }
  function isFrontendSurfaceLiveFragmentName(surface, value) {
    return typeof value === "string" && FrontendSurfaceFragmentRegistry[surface].includes(value);
  }
  var FrontendSurfaceInteractionRegistry = { "roster": { "sourceRefs": [{ "ref": "shift-drag-source", "session": "drag", "intent": "move-roster-shift-to-slot", "sourceField": "sourceItemKey", "compatibleDropzones": ["shift-slot-dropzone", "day-column-dropzone", "delete-shift-dropzone"], "modifierVariants": [{ "semantic": "copy", "intent": "duplicate-roster-shift-to-day", "effects": { "global": [{ "className": "bepis-pointer-clone-shadow bepis-pointer-clone-shadow-copy", "kind": "clone-shadow", "layer": "drag-preview", "preserveGrabOffset": true, "source": "pointer-marker" }], "contextual": [{ "className": "bepis-dropzone-highlight", "kind": "dropzone-highlight" }] } }] }, { "ref": "staff-drag-source", "session": "drag", "intent": "drop-roster-staff", "sourceField": "sourceItemKey", "compatibleDropzones": ["existing-shift-dropzone", "shift-slot-dropzone", "staff-create-dropzone"], "modifierVariants": [] }], "dropzoneRefs": [{ "ref": "shift-slot-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }, { "ref": "staff-create-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }, { "ref": "day-column-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }, { "ref": "existing-shift-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }, { "ref": "delete-shift-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }], "activationRefs": [{ "ref": "roster-layout-mode-activation", "intent": "set-roster-layout-mode", "valueField": "rosterLayoutMode", "trigger": "click" }], "sessionKinds": [{ "kind": "drag", "effects": { "global": [{ "className": "bepis-pointer-clone-shadow", "kind": "clone-shadow", "layer": "drag-preview", "preserveGrabOffset": true, "source": "pointer-marker" }], "contextual": [{ "className": "bepis-dropzone-highlight", "kind": "dropzone-highlight" }] } }] }, "roster-day-timeline": { "sourceRefs": [{ "ref": "drag-source", "session": "drag", "intent": "move-roster-timeline-shift", "sourceField": "sourceItemKey", "compatibleDropzones": ["drag-dropzone"], "modifierVariants": [] }], "dropzoneRefs": [{ "ref": "drag-dropzone", "session": "drag", "targetField": "targetDropzoneKey" }], "activationRefs": [], "sessionKinds": [{ "kind": "drag", "effects": { "global": [{ "className": "bepis-pointer-clone-shadow", "kind": "clone-shadow", "layer": "drag-preview", "preserveGrabOffset": true, "source": "pointer-marker" }], "contextual": [{ "className": "bepis-dropzone-highlight", "kind": "dropzone-highlight" }] } }] } };
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
  function isFeedbackMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "feedback" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
  }
  function isFeedbackModerationMountedFragmentConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["fragmentKey", "targetId", "url", "protection"]) && isSurfaceFragmentKey(value["fragmentKey"]) && value["fragmentKey"].surface === "feedback-moderation" && typeof value["targetId"] === "string" && value["targetId"].length > 0 && typeof value["url"] === "string" && value["url"].length > 0 && isFrontendSurfaceFragmentProtection(value["protection"]);
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
  function isFeedbackMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "feedback" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isFeedbackMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("feedback", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "feedback" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("feedback", fragment.fragmentKey.kind)));
  }
  function isFeedbackModerationMountConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["surface", "scopeKey", "mountKey", "fragments", "subscription"]) && value["surface"] === "feedback-moderation" && typeof value["scopeKey"] === "string" && value["scopeKey"].length > 0 && typeof value["mountKey"] === "string" && value["mountKey"].length > 0 && Array.isArray(value["fragments"]) && value["fragments"].every((fragment) => isFeedbackModerationMountedFragmentConfig(fragment)) && (value["subscription"] === null && !value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("feedback-moderation", fragment.fragmentKey.kind)) || isRecord(value["subscription"]) && hasExactKeys(value["subscription"], ["scope", "renderedDependencyWatermark"]) && isSurfaceScope(value["subscription"].scope) && typeof value["subscription"].renderedDependencyWatermark === "number" && Number.isInteger(value["subscription"].renderedDependencyWatermark) && value["subscription"].renderedDependencyWatermark >= 0 && value["subscription"].scope.surface === "feedback-moderation" && value["fragments"].some((fragment) => isFrontendSurfaceLiveFragmentName("feedback-moderation", fragment.fragmentKey.kind)));
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
    return isTimesheetsMountConfig(value) || isRosterMountConfig(value) || isRosterDayTimelineMountConfig(value) || isLeaveRequestsMountConfig(value) || isSelfServiceLeaveMountConfig(value) || isBillingMountConfig(value) || isSupportMountConfig(value) || isFeedbackMountConfig(value) || isFeedbackModerationMountConfig(value) || isProfileMountConfig(value) || isStaffMountConfig(value) || isAdminPageMountConfig(value) || isAdminXeroPageMountConfig(value) || isAdminVenueConfigMountConfig(value) || isAdminInvitesMountConfig(value) || isAdminExportsMountConfig(value) || isAdminShiftTypesMountConfig(value) || isAdminRosterGroupsMountConfig(value) || isAdminXeroMountConfig(value);
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
  function rootFromTarget(target, fallback = document) {
    return isDomRoot(target) ? target : fallback;
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
  function onAppPageReady(handler) {
    if (typeof document === "undefined") return;
    document.addEventListener(pageReadyEvent, handler);
  }
  function onHtmxLoad(handler) {
    if (typeof document === "undefined") return;
    document.addEventListener("htmx:load", handler);
  }

  // frontend/ts/app-bootstrap.ts
  var appPageReadyEventName = pageReadyEvent;
  function detailRecord(detail) {
    return detail !== null && typeof detail === "object" ? detail : {};
  }
  function pageReadyDetailFrom(detail) {
    const record = detailRecord(detail);
    const source = record.source;
    return {
      source: typeof source === "string" && source !== "" ? source : "unknown",
      isFullPage: Boolean(record.isFullPage)
    };
  }
  (function enableAppPageLifecycle() {
    if (typeof window === "undefined") return;
    const pageReadyEventName = appPageReadyEventName;
    function normalizeTarget(target) {
      if (isHTMLElement(target)) return target;
      if (isDocument(target)) return document.body;
      return document.body;
    }
    function dispatchPageReady(detail) {
      const target = normalizeTarget(detailRecord(detail).target);
      const event = new CustomEvent(pageReadyEventName, {
        detail: {
          target,
          ...pageReadyDetailFrom(detail)
        }
      });
      document.dispatchEvent(event);
    }
    window.appPageLifecycle = {
      eventName: pageReadyEventName,
      dispatchPageReady
    };
    document.addEventListener("DOMContentLoaded", function() {
      dispatchPageReady({
        source: "dom-content-loaded",
        target: document.body,
        isFullPage: true
      });
    });
    document.addEventListener("htmx:afterSwap", function(event) {
      dispatchPageReady({
        source: "htmx-after-swap",
        target: detailRoot(event, "target"),
        isFullPage: false
      });
    });
    document.addEventListener("htmx:oobAfterSwap", function(event) {
      dispatchPageReady({
        source: "htmx-oob-after-swap",
        target: detailRoot(event, "target"),
        isFullPage: false
      });
    });
    const scrollPreservingRequests = /* @__PURE__ */ new WeakSet();
    const preservedScrollPositions = /* @__PURE__ */ new WeakMap();
    function requestToken(event) {
      const xhr = detailTarget(event, "xhr");
      return xhr !== null && typeof xhr === "object" ? xhr : null;
    }
    function requestDisablesShowScrolling(event) {
      const requestElement = detailTarget(event, "elt");
      if (!(requestElement instanceof Element)) return false;
      const swapOwner = requestElement.closest("[hx-swap]");
      return swapOwner?.getAttribute("hx-swap")?.split(/\s+/).includes("show:none") ?? false;
    }
    document.addEventListener("htmx:beforeRequest", function(event) {
      const token = requestToken(event);
      if (token !== null && requestDisablesShowScrolling(event)) {
        scrollPreservingRequests.add(token);
      }
    });
    document.addEventListener("htmx:beforeSwap", function(event) {
      const token = requestToken(event);
      if (token !== null && scrollPreservingRequests.has(token)) {
        preservedScrollPositions.set(token, { left: window.scrollX, top: window.scrollY });
      }
    });
    function restorePreservedScroll(event, cleanup) {
      const token = requestToken(event);
      if (token === null) return;
      const position = preservedScrollPositions.get(token);
      if (position !== void 0) window.scrollTo(position.left, position.top);
      if (cleanup) {
        preservedScrollPositions.delete(token);
        scrollPreservingRequests.delete(token);
      }
    }
    document.addEventListener("htmx:afterSwap", (event) => restorePreservedScroll(event, false));
    document.addEventListener("htmx:oobAfterSwap", (event) => restorePreservedScroll(event, false));
    document.addEventListener("htmx:afterSettle", (event) => restorePreservedScroll(event, true));
    for (const eventName of ["htmx:responseError", "htmx:sendError", "htmx:timeout"]) {
      document.addEventListener(eventName, function(event) {
        const token = requestToken(event);
        if (token === null) return;
        preservedScrollPositions.delete(token);
        scrollPreservingRequests.delete(token);
      });
    }
    if (document.readyState !== "loading") {
      dispatchPageReady({
        source: "document-ready",
        target: document.body,
        isFullPage: true
      });
    }
  })();

  // frontend/ts/app-pwa.ts
  function parsePwaInstallState(value) {
    if (isPwaInstallState(value)) return value;
    throw new Error("Invalid PwaInstallState");
  }
  var deferredInstallPrompt = null;
  var installationCompleted = false;
  function roleSelector(attribute) {
    return `[${attribute}]`;
  }
  function isBeforeInstallPromptEvent(event) {
    const candidate = event;
    return typeof candidate.prompt === "function" && typeof candidate.userChoice?.then === "function";
  }
  function isStandalone() {
    return window.matchMedia("(display-mode: standalone)").matches || navigator.standalone === true || installationCompleted;
  }
  function installPage() {
    return document.querySelector(roleSelector(pwaInstallPageDomAttr));
  }
  function renderInstallState() {
    const page = installPage();
    if (!page) return;
    const installed = isStandalone();
    const installedStatus = page.querySelector(roleSelector(pwaInstalledStatusDomAttr));
    const installButton = page.querySelector(roleSelector(pwaInstallButtonDomAttr));
    if (installedStatus) installedStatus.hidden = !installed;
    if (installButton) installButton.hidden = installed || deferredInstallPrompt === null;
  }
  function installResultElements(result) {
    const elements = Array.from(
      result.querySelectorAll(roleSelector(pwaInstallResultStateDomAttr))
    );
    const byState = /* @__PURE__ */ new Map();
    for (const element of elements) {
      let state;
      try {
        state = parsePwaInstallState(element.getAttribute(pwaInstallResultStateDomAttr));
      } catch (error) {
        console.error?.("Invalid generated PWA install result state", error);
        return null;
      }
      if (byState.has(state)) {
        console.error?.("Invalid generated PWA install result state", `Duplicate state: ${state}`);
        return null;
      }
      byState.set(state, element);
    }
    return byState;
  }
  function renderInstallResult(page, state) {
    const result = page.querySelector(roleSelector(pwaInstallResultDomAttr));
    if (!result) return;
    const elements = installResultElements(result);
    const selected = elements?.get(state);
    if (!elements || !selected) {
      console.error?.("Invalid generated PWA install result state", `Missing state: ${state}`);
      return;
    }
    for (const element of elements.values()) {
      element.hidden = element !== selected;
    }
  }
  async function promptForInstallation(page) {
    const installPrompt = deferredInstallPrompt;
    if (!installPrompt || isStandalone()) return;
    deferredInstallPrompt = null;
    renderInstallState();
    try {
      await installPrompt.prompt();
      const choice = await installPrompt.userChoice;
      renderInstallResult(page, parsePwaInstallState(choice.outcome));
    } catch {
      renderInstallResult(page, parsePwaInstallState("failed"));
    }
  }
  (function enablePwaInstallation() {
    if (typeof window === "undefined") return;
    window.addEventListener("beforeinstallprompt", (event) => {
      if (!isBeforeInstallPromptEvent(event)) return;
      event.preventDefault();
      deferredInstallPrompt = event;
      renderInstallState();
    });
    window.addEventListener("appinstalled", () => {
      deferredInstallPrompt = null;
      installationCompleted = true;
      renderInstallState();
    });
    document.addEventListener("click", (event) => {
      const target = event.target;
      if (!(target instanceof Element)) return;
      const button = target.closest(roleSelector(pwaInstallButtonDomAttr));
      const page = button?.closest(roleSelector(pwaInstallPageDomAttr));
      if (!button || !page) return;
      void promptForInstallation(page);
    });
    document.addEventListener("DOMContentLoaded", renderInstallState, { once: true });
    if (document.readyState !== "loading") renderInstallState();
  })();

  // frontend/ts/app-scrollbars.ts
  var activeClass = "app-scrollbar-active";
  var hideDelayMs = 2e3;
  function scrollElementFromEventTarget(target) {
    if (target === document || target === window || target === document.body || target === document.documentElement) {
      return document.documentElement;
    }
    if (target instanceof Element) return target;
    return document.documentElement;
  }
  function enableAppScrollbars() {
    if (typeof window === "undefined") return;
    const timers = /* @__PURE__ */ new WeakMap();
    function markScrollbarActive(element) {
      element.classList.add(activeClass);
      const existingTimer = timers.get(element);
      if (existingTimer !== void 0) {
        window.clearTimeout(existingTimer);
      }
      const nextTimer = window.setTimeout(() => {
        element.classList.remove(activeClass);
        timers.delete(element);
      }, hideDelayMs);
      timers.set(element, nextTimer);
    }
    document.addEventListener("scroll", (event) => {
      markScrollbarActive(scrollElementFromEventTarget(event.target));
    }, true);
  }
  enableAppScrollbars();

  // frontend/ts/app-date-pickers.ts
  var initializedKey = "appDatePickerInitialized";
  function datePickerConfigFor(inputType) {
    return inputType === "datetime-local" ? {
      enableTime: true,
      time_24hr: true,
      dateFormat: "Z",
      altInput: true,
      altFormat: "d/m/Y, H:i"
    } : {
      dateFormat: "Y-m-d",
      altInput: true,
      altFormat: "d/m/Y"
    };
  }
  function initInput(inputEl) {
    if (typeof window.flatpickr !== "function") return;
    if (inputEl.dataset[initializedKey] === "true") return;
    if (inputEl._flatpickr !== void 0) {
      inputEl.dataset[initializedKey] = "true";
      return;
    }
    window.flatpickr(inputEl, datePickerConfigFor(inputEl.type));
    inputEl.dataset[initializedKey] = "true";
  }
  function initWithin(root) {
    if (root instanceof HTMLInputElement && (root.type === "date" || root.type === "datetime-local")) {
      initInput(root);
    }
    root.querySelectorAll("input[type='date'], input[type='datetime-local']").forEach(initInput);
  }
  function handleSwap(event) {
    initWithin(detailRoot(event, "target"));
  }
  function enableDatePickers() {
    if (typeof window === "undefined") return;
    onAppPageReady((event) => {
      initWithin(detailRoot(event, "target"));
    });
    document.addEventListener("htmx:afterSwap", handleSwap);
    document.addEventListener("htmx:oobAfterSwap", handleSwap);
  }
  enableDatePickers();

  // frontend/ts/dialog-overlays/lifecycle.ts
  function dialogDismissedDetail(event) {
    if (!(event instanceof CustomEvent)) return null;
    const detail = event.detail;
    if (detail === null || typeof detail !== "object") return null;
    const candidate = detail;
    if (!(candidate.dialog instanceof Element)) return null;
    if (candidate.replacement !== void 0 && candidate.replacement !== null && !(candidate.replacement instanceof Element)) return null;
    return { dialog: candidate.dialog, replacement: candidate.replacement ?? null };
  }
  function createDialogDismissalLifecycle(eventName) {
    const activeDialogs = /* @__PURE__ */ new WeakMap();
    const dismissedDialogs = /* @__PURE__ */ new WeakSet();
    function dismiss(dialog, eventOwner, replacement = null) {
      if (dismissedDialogs.has(dialog)) return false;
      dismissedDialogs.add(dialog);
      eventOwner.dispatchEvent(new CustomEvent(eventName, {
        bubbles: true,
        detail: { dialog, replacement }
      }));
      return true;
    }
    function reconcile(mount, activeDialog) {
      const previousDialog = activeDialogs.get(mount) ?? null;
      activeDialogs.set(mount, activeDialog);
      if (previousDialog === null || previousDialog === activeDialog) return false;
      return dismiss(previousDialog, mount, activeDialog);
    }
    return { dismiss, reconcile };
  }

  // frontend/ts/passkeys/base64url.ts
  function base64UrlToArrayBuffer(value) {
    const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized + "=".repeat((4 - normalized.length % 4) % 4);
    const binary = globalThis.atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes.buffer;
  }
  function arrayBufferToBase64Url(buffer) {
    const bytes = new Uint8Array(buffer);
    let binary = "";
    bytes.forEach(function(byte) {
      binary += String.fromCharCode(byte);
    });
    return globalThis.btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
  }

  // frontend/ts/passkeys/storage.ts
  function localStorageKeyForPasskey(userId, key) {
    return `ihpRoster.${key}.${userId}`;
  }

  // frontend/ts/passkeys/wire.ts
  function safePasskeyRedirectPath(value, origin) {
    if (!value.startsWith("/") || value.startsWith("//")) return null;
    try {
      return new URL(value, origin).origin === origin ? value : null;
    } catch (_error) {
      return null;
    }
  }
  function registrationOptionsToNative(options) {
    const authenticatorAttachment = options.authenticatorSelection.authenticatorAttachment;
    return {
      rp: {
        id: options.rp.id,
        name: options.rp.name
      },
      user: {
        id: base64UrlToArrayBuffer(options.user.id),
        displayName: options.user.displayName,
        name: options.user.name
      },
      challenge: base64UrlToArrayBuffer(options.challenge),
      pubKeyCredParams: options.pubKeyCredParams.map((parameter) => ({
        type: parameter.type,
        alg: parameter.alg
      })),
      timeout: options.timeout,
      excludeCredentials: options.excludeCredentials.map((descriptor) => ({
        type: descriptor.type,
        id: base64UrlToArrayBuffer(descriptor.id)
      })),
      authenticatorSelection: {
        ...authenticatorAttachment === void 0 ? {} : { authenticatorAttachment },
        residentKey: options.authenticatorSelection.residentKey,
        requireResidentKey: options.authenticatorSelection.requireResidentKey,
        userVerification: options.authenticatorSelection.userVerification
      },
      attestation: options.attestation
    };
  }
  function authenticationOptionsToNative(options) {
    return {
      challenge: base64UrlToArrayBuffer(options.challenge),
      timeout: options.timeout,
      rpId: options.rpId,
      allowCredentials: options.allowCredentials.map((descriptor) => ({
        type: descriptor.type,
        id: base64UrlToArrayBuffer(descriptor.id)
      })),
      userVerification: options.userVerification
    };
  }
  function serializeRegistrationCredential(credential, name) {
    const response = credential.response;
    if (!(response instanceof AuthenticatorAttestationResponse)) {
      throw new Error("Invalid registration credential response.");
    }
    return encodePasskeyRegistrationRequest({
      rawId: arrayBufferToBase64Url(credential.rawId),
      response: {
        clientDataJSON: arrayBufferToBase64Url(response.clientDataJSON),
        attestationObject: arrayBufferToBase64Url(response.attestationObject),
        transports: typeof response.getTransports === "function" ? response.getTransports() : []
      },
      clientExtensionResults: credential.getClientExtensionResults(),
      ...name === void 0 ? {} : { name }
    });
  }
  function serializeAuthenticationCredential(credential) {
    const response = credential.response;
    if (!(response instanceof AuthenticatorAssertionResponse)) {
      throw new Error("Invalid authentication credential response.");
    }
    return encodePasskeyAuthenticationRequest({
      rawId: arrayBufferToBase64Url(credential.rawId),
      response: {
        clientDataJSON: arrayBufferToBase64Url(response.clientDataJSON),
        authenticatorData: arrayBufferToBase64Url(response.authenticatorData),
        signature: arrayBufferToBase64Url(response.signature),
        userHandle: response.userHandle === null ? null : arrayBufferToBase64Url(response.userHandle)
      },
      clientExtensionResults: credential.getClientExtensionResults()
    });
  }

  // frontend/ts/shared/exhaustive.ts
  function assertNever(value, message = "Unexpected generated union variant") {
    throw new Error(`${message}: ${JSON.stringify(value)}`);
  }

  // frontend/ts/app-passkeys.ts
  var PasskeyStatusError = class extends Error {
    constructor(statusMessage) {
      super(statusMessage);
      this.statusMessage = statusMessage;
    }
  };
  var initializedPasskeyFlows = /* @__PURE__ */ new WeakSet();
  var automaticPromptDismissals = /* @__PURE__ */ new WeakSet();
  var passkeyFlowSelector = [
    passkeyLoginDomAttr,
    passkeyRegistrationDomAttr,
    passkeySetupPromptDomAttr
  ].map(roleSelector2).join(",");
  function parsePasskeyFlowConfiguration(raw) {
    const config = parsePasskeyFlowConfig(JSON.parse(raw));
    switch (config.tag) {
      case "login":
      case "registration":
        requirePasskeyConfigText("begin URL", config.beginUrl);
        requirePasskeyConfigText("finish URL", config.finishUrl);
        if (config.successRedirect !== void 0) {
          requirePasskeyConfigText("success redirect", config.successRedirect);
        }
        requirePasskeyConfigText("status relationship", config.statusKey);
        requirePasskeyConfigText("waiting message", config.waitingMessage);
        requirePasskeyConfigText("success message", config.successMessage);
        requirePasskeyConfigText("unsupported message", config.unsupportedMessage);
        requirePasskeyConfigText("failure message", config.failureMessage);
        requirePasskeyConfigText("pending label", config.pendingLabel);
        requirePasskeyConfigText("cancelled message", config.cancelledMessage);
        return config;
      case "setup-prompt":
        requirePasskeyConfigText("prompt user key", config.promptUserKey);
        return config;
      default:
        return assertNever(config, "Unexpected generated passkey flow");
    }
  }
  function requirePasskeyConfigText(fieldName, value) {
    if (value.trim().length === 0) {
      throw new Error(`PasskeyFlowConfig ${fieldName} must not be empty`);
    }
  }
  function roleSelector2(attribute) {
    return `[${attribute}]`;
  }
  function defaultDiagnosticReporter(diagnostic11) {
    console.error?.("Invalid generated passkey configuration", diagnostic11);
  }
  function diagnostic(element, code, message) {
    return {
      code,
      elementId: element.id || null,
      message
    };
  }
  function rootsWithRole(root, attribute) {
    const selector = roleSelector2(attribute);
    const roots = Array.from(root.querySelectorAll(selector));
    if (root instanceof HTMLElement && root.matches(selector)) roots.unshift(root);
    return roots;
  }
  function ownedElements(root, attribute) {
    return Array.from(root.querySelectorAll(roleSelector2(attribute))).filter((element) => element.closest(passkeyFlowSelector) === root);
  }
  function roleIsTrue(element, attribute) {
    return element.getAttribute(attribute) === "true";
  }
  function parseFlowForRoot(root, report) {
    const rawConfig = root.getAttribute(passkeyFlowConfigDomAttr);
    try {
      if (rawConfig === null) throw new Error(`Missing ${passkeyFlowConfigDomAttr}`);
      return parsePasskeyFlowConfiguration(rawConfig);
    } catch (error) {
      report(diagnostic(
        root,
        "invalid-flow-config",
        error instanceof Error ? error.message : String(error)
      ));
      return null;
    }
  }
  function expectedFlowRole(config) {
    switch (config.tag) {
      case "login":
        return passkeyLoginDomAttr;
      case "registration":
        return passkeyRegistrationDomAttr;
      case "setup-prompt":
        return passkeySetupPromptDomAttr;
      default:
        return assertNever(config, "Unexpected generated passkey flow");
    }
  }
  function validateFlowRole(root, config, report) {
    const expected = expectedFlowRole(config);
    const roleAttributes = [
      passkeyLoginDomAttr,
      passkeyRegistrationDomAttr,
      passkeySetupPromptDomAttr
    ].filter((attribute) => root.hasAttribute(attribute));
    if (roleAttributes.length !== 1 || roleAttributes[0] !== expected || !roleIsTrue(root, expected)) {
      report(diagnostic(root, "invalid-flow-role", `Passkey flow ${config.tag} must have exactly its generated root role`));
      return false;
    }
    return true;
  }
  function readAction(root, report) {
    const actions = ownedElements(root, passkeyActionButtonDomAttr);
    if (actions.length !== 1 || !(actions[0] instanceof HTMLButtonElement) || !roleIsTrue(actions[0], passkeyActionButtonDomAttr)) {
      report(diagnostic(root, "invalid-action-relationship", "Passkey login or registration requires one local generated action button"));
      return null;
    }
    return actions[0];
  }
  function readStatus(root, config, expectsRecovery, report) {
    const messages = ownedElements(root, passkeyStatusDomAttr).filter((element) => element.getAttribute(passkeyStatusDomAttr) === config.statusKey);
    if (messages.length !== 1) {
      report(diagnostic(root, "invalid-status-relationship", "Passkey flow requires one matching local generated status relationship"));
      return null;
    }
    const message = messages[0];
    const region = message.parentElement;
    if (!(region instanceof HTMLElement) || region.getAttribute("role") !== "status" || message.closest(passkeyFlowSelector) !== root) {
      report(diagnostic(message, "invalid-status-relationship", "Passkey status must be inside its local native status region"));
      return null;
    }
    const recoveries = ownedElements(root, passkeyRecoveryDomAttr).filter((element) => element.getAttribute(passkeyRecoveryDomAttr) === config.statusKey);
    if (recoveries.length !== (expectsRecovery ? 1 : 0)) {
      report(diagnostic(root, "invalid-recovery-relationship", `Passkey flow requires ${expectsRecovery ? 1 : 0} local recovery region(s)`));
      return null;
    }
    if (!expectsRecovery) {
      return { message, region, recovery: null, recoveryCode: null };
    }
    const recovery = recoveries[0];
    const recoveryCodes = Array.from(recovery.querySelectorAll("code")).filter((element) => element.closest(passkeyFlowSelector) === root);
    const recoveryLinks = Array.from(recovery.querySelectorAll("a")).filter((element) => element.closest(passkeyFlowSelector) === root);
    const expectedLinkCount = config.successRedirect === void 0 ? 0 : 1;
    if (recoveryCodes.length !== 1 || recoveryLinks.length !== expectedLinkCount) {
      report(diagnostic(recovery, "invalid-recovery-relationship", "Passkey recovery region must contain its server-rendered code and continuation copy"));
      return null;
    }
    return {
      message,
      region,
      recovery,
      recoveryCode: recoveryCodes[0]
    };
  }
  function readOverlayClose(root, config, report) {
    if (!config.closeOverlayOnSuccess) return null;
    const dialog = root.closest(`[${dialogMountDomAttr}]`);
    if (!(dialog instanceof HTMLElement)) {
      report(diagnostic(root, "invalid-overlay-close-relationship", "In-place passkey login must be inside one generated dialog"));
      return null;
    }
    const closes = Array.from(dialog.querySelectorAll(`[${dialogCloseDomAttr}]`)).filter((element) => element instanceof HTMLButtonElement && roleIsTrue(element, dialogCloseDomAttr));
    if (closes.length === 0) {
      report(diagnostic(root, "invalid-overlay-close-relationship", "In-place passkey login requires a generated dialog close button"));
      return null;
    }
    return closes[0];
  }
  function readLoginControl(root, config, report) {
    const action = readAction(root, report);
    const status = readStatus(root, config, false, report);
    if (action === null || status === null) return null;
    if (ownedElements(root, passkeyDeviceNameDomAttr).length !== 0) {
      report(diagnostic(root, "invalid-device-name-relationship", "Passkey login must not contain a registration device-name role"));
      return null;
    }
    const overlayClose = readOverlayClose(root, config, report);
    if (config.closeOverlayOnSuccess && overlayClose === null) return null;
    return { root, action, config, status, overlayClose };
  }
  function readRegistrationControl(root, config, report) {
    const action = readAction(root, report);
    const status = readStatus(root, config, true, report);
    const deviceNames = ownedElements(root, passkeyDeviceNameDomAttr);
    if (deviceNames.length !== 1 || !(deviceNames[0] instanceof HTMLInputElement) || !roleIsTrue(deviceNames[0], passkeyDeviceNameDomAttr)) {
      report(diagnostic(root, "invalid-device-name-relationship", "Passkey registration requires one local generated device-name input"));
      return null;
    }
    if (action === null || status === null) return null;
    return { root, action, config, deviceName: deviceNames[0], status };
  }
  function readPromptControl(root, config, report) {
    const dismissals = ownedElements(root, passkeyDismissalDomAttr);
    if (dismissals.length !== 1 || !(dismissals[0] instanceof HTMLButtonElement) || !roleIsTrue(dismissals[0], passkeyDismissalDomAttr)) {
      report(diagnostic(root, "invalid-dismissal-relationship", "Passkey setup prompt requires one local generated dismissal control"));
      return null;
    }
    if (!roleIsTrue(dismissals[0], dialogCloseDomAttr)) {
      report(diagnostic(dismissals[0], "invalid-overlay-dismissal-role", "Passkey prompt dismissal must use the generated dialog-close role"));
      return null;
    }
    return { root, config, dismissal: dismissals[0] };
  }
  function initializePasskeyRoot(root, report = defaultDiagnosticReporter) {
    if (initializedPasskeyFlows.has(root)) return;
    initializedPasskeyFlows.add(root);
    const config = parseFlowForRoot(root, report);
    if (config === null || !validateFlowRole(root, config, report)) return;
    switch (config.tag) {
      case "login": {
        const control = readLoginControl(root, config, report);
        if (control === null) return;
        control.action.addEventListener("click", () => {
          void runPasskeyLogin(control);
        });
        if (control.config.autoStart) void runPasskeyLogin(control);
        return;
      }
      case "registration": {
        const control = readRegistrationControl(root, config, report);
        if (control === null) return;
        control.action.addEventListener("click", () => {
          void runPasskeyRegistration(control);
        });
        return;
      }
      case "setup-prompt": {
        const control = readPromptControl(root, config, report);
        if (control === null) return;
        initializePasskeySetupPrompt(control);
        return;
      }
      default:
        assertNever(config, "Unexpected generated passkey flow");
    }
  }
  function listenForContainingDialogDismissal(element, handler) {
    const listener = (event) => {
      const detail = dialogDismissedDetail(event);
      if (detail === null || !(detail.dialog.contains(element) || element.contains(detail.dialog))) return;
      document.removeEventListener(dialogDismissedEvent, listener);
      handler();
    };
    document.addEventListener(dialogDismissedEvent, listener);
    return () => document.removeEventListener(dialogDismissedEvent, listener);
  }
  function initializePasskeySetupPrompt(control) {
    listenForContainingDialogDismissal(control.root, () => {
      if (automaticPromptDismissals.has(control.root)) {
        automaticPromptDismissals.delete(control.root);
        return;
      }
      dismissPasskeyPrompt(control.config.promptUserKey);
    });
    if (!passkeysAreAvailable() || isPasskeyPromptDismissed(control.config.promptUserKey) || promptModeAlreadyConfigured(control.config)) {
      automaticPromptDismissals.add(control.root);
      control.dismissal.click();
    }
  }
  function promptModeAlreadyConfigured(config) {
    switch (config.setupPromptMode) {
      case passkeyFirstPasskeyMode:
        return false;
      case passkeyAdditionalDeviceMode:
        return hasPasskeySeen(config.promptUserKey);
      default:
        return assertNever(config.setupPromptMode, "Unexpected generated passkey setup prompt mode");
    }
  }
  async function runPasskeyLogin(control) {
    const abortController = control.overlayClose === null ? null : new AbortController();
    const dialog = control.root.closest(`[${dialogMountDomAttr}]`);
    const abortPendingRequest = () => abortController?.abort();
    const stopListeningForDismissal = dialog !== null && abortController !== null ? listenForContainingDialogDismissal(dialog, abortPendingRequest) : () => void 0;
    try {
      await withPasskeyButton(control, async () => {
        setPasskeyStatus(control.status, "info", control.config.waitingMessage);
        const beginResponse = await postJson(
          control.config.beginUrl,
          control.config.failureMessage,
          parsePasskeyAuthenticationOptions
        );
        const credential = await window.navigator.credentials.get({
          publicKey: authenticationOptionsToNative(beginResponse),
          signal: abortController?.signal
        });
        if (!(credential instanceof PublicKeyCredential)) throw new PasskeyStatusError(control.config.cancelledMessage);
        const finishResponse = await postJson(
          control.config.finishUrl,
          control.config.failureMessage,
          parsePasskeyFinishResponse,
          serializeAuthenticationCredential(credential)
        );
        if (finishResponse.tag !== "authenticated") {
          throw new PasskeyStatusError(control.config.failureMessage);
        }
        markPasskeySeen(requirePasskeyResponseText("user id", finishResponse.userId));
        setPasskeyStatus(control.status, "success", control.config.successMessage);
        if (control.config.closeOverlayOnSuccess) {
          control.overlayClose?.click();
        } else {
          redirectToPasskeyDestination(finishResponse.redirectTo);
        }
      });
    } finally {
      stopListeningForDismissal();
    }
  }
  async function runPasskeyRegistration(control) {
    await withPasskeyButton(control, async () => {
      setPasskeyStatus(control.status, "info", control.config.waitingMessage);
      const beginResponse = await postJson(
        control.config.beginUrl,
        control.config.failureMessage,
        parsePasskeyRegistrationOptions
      );
      const credential = await window.navigator.credentials.create({
        publicKey: registrationOptionsToNative(beginResponse)
      });
      if (!(credential instanceof PublicKeyCredential)) throw new PasskeyStatusError(control.config.cancelledMessage);
      const submittedName = control.deviceName.value.trim();
      const finishResponse = await postJson(
        control.config.finishUrl,
        control.config.failureMessage,
        parsePasskeyFinishResponse,
        serializeRegistrationCredential(
          credential,
          submittedName === "" ? void 0 : submittedName
        )
      );
      handleRegistrationFinishResponse(control, finishResponse);
    });
  }
  function handleRegistrationFinishResponse(control, response) {
    switch (response.tag) {
      case "registered":
        markPasskeySeen(requirePasskeyResponseText("user id", response.userId));
        if (response.recoveryCode !== null) {
          setRecoveryCodeStatus(
            control.status,
            requirePasskeyResponseText("recovery code", response.recoveryCode)
          );
          return;
        }
        setPasskeyStatus(control.status, "success", control.config.successMessage);
        redirectToPasskeyDestination(control.config.successRedirect);
        return;
      case "setup-registered":
        markPasskeySeen(requirePasskeyResponseText("user id", response.userId));
        setPasskeyStatus(control.status, "success", control.config.successMessage);
        redirectToPasskeyDestination(response.redirectTo);
        return;
      case "authenticated":
        throw new PasskeyStatusError(control.config.failureMessage);
      default:
        return assertNever(response, "Unexpected generated passkey finish response");
    }
  }
  async function withPasskeyButton(control, callback) {
    if (!passkeysAreAvailable()) {
      setPasskeyStatus(control.status, "danger", control.config.unsupportedMessage);
      return;
    }
    const originalHtml = control.action.innerHTML;
    control.action.disabled = true;
    const spinner = document.createElement("span");
    spinner.className = "spinner-border spinner-border-sm me-2";
    spinner.setAttribute("aria-hidden", "true");
    control.action.replaceChildren(spinner, document.createTextNode(control.config.pendingLabel));
    try {
      await callback();
    } catch (error) {
      setPasskeyStatus(
        control.status,
        "danger",
        passkeyStatusMessageForError(control.config, error)
      );
    } finally {
      control.action.disabled = false;
      control.action.innerHTML = originalHtml;
    }
  }
  function passkeyStatusMessageForError(config, error) {
    if (error instanceof PasskeyStatusError) return error.statusMessage;
    if (isPasskeyCancellation(error)) return config.cancelledMessage;
    return config.failureMessage;
  }
  function isPasskeyCancellation(error) {
    return typeof DOMException !== "undefined" && error instanceof DOMException && (error.name === "AbortError" || error.name === "NotAllowedError");
  }
  async function postJson(url, failureMessage, parseResponse, payload) {
    const hasPayload = payload !== void 0;
    const response = await window.fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: hasPayload ? {
        Accept: "application/json",
        "Content-Type": "application/json"
      } : {
        Accept: "application/json"
      },
      body: hasPayload ? JSON.stringify(payload) : void 0
    });
    let json;
    try {
      json = await response.json();
    } catch (_error) {
      throw new PasskeyStatusError(failureMessage);
    }
    if (!response.ok) {
      let errorResponse;
      try {
        errorResponse = parsePasskeyErrorResponse(json);
      } catch (_error) {
        throw new PasskeyStatusError(failureMessage);
      }
      switch (errorResponse.tag) {
        case "failure":
          break;
        case "redirect":
          redirectToPasskeyDestination(errorResponse.redirectTo);
          break;
        default:
          assertNever(errorResponse, "Unexpected generated passkey error response");
      }
      throw new PasskeyStatusError(failureMessage);
    }
    try {
      return parseResponse(json);
    } catch (_error) {
      throw new PasskeyStatusError(failureMessage);
    }
  }
  function setPasskeyStatus(status, tone, message) {
    status.message.hidden = false;
    status.message.textContent = message;
    if (status.recovery !== null) status.recovery.hidden = true;
    setPasskeyStatusTone(status.region, tone);
  }
  function setRecoveryCodeStatus(status, recoveryCode) {
    if (status.recovery === null || status.recoveryCode === null) return;
    status.message.hidden = true;
    status.recoveryCode.textContent = recoveryCode;
    status.recovery.hidden = false;
    setPasskeyStatusTone(status.region, "warning");
  }
  function setPasskeyStatusTone(region, tone) {
    region.classList.remove("d-none", "alert-info", "alert-success", "alert-danger", "alert-warning");
    region.classList.add(`alert-${tone}`);
  }
  function requirePasskeyResponseText(fieldName, value) {
    if (value.trim() === "") {
      throw new Error(`Invalid empty passkey ${fieldName}`);
    }
    return value;
  }
  function redirectToPasskeyDestination(redirectTo) {
    if (redirectTo === void 0) return;
    const safeRedirect = safePasskeyRedirectPath(redirectTo, window.location.origin);
    if (safeRedirect === null) {
      throw new Error("Invalid passkey redirect");
    }
    window.location.assign(safeRedirect);
  }
  function localStorageKey(userId, key) {
    return localStorageKeyForPasskey(userId, key);
  }
  function markPasskeySeen(userId) {
    try {
      window.localStorage.setItem(localStorageKey(userId, "passkeySeen"), "1");
    } catch (_error) {
    }
  }
  function hasPasskeySeen(userId) {
    try {
      return window.localStorage.getItem(localStorageKey(userId, "passkeySeen")) === "1";
    } catch (_error) {
      return false;
    }
  }
  function dismissPasskeyPrompt(userId) {
    const thirtyDaysMs = 30 * 24 * 60 * 60 * 1e3;
    try {
      window.localStorage.setItem(
        localStorageKey(userId, "passkeyPromptDismissedUntil"),
        String(Date.now() + thirtyDaysMs)
      );
    } catch (_error) {
    }
  }
  function isPasskeyPromptDismissed(userId) {
    try {
      const dismissedUntil = Number(window.localStorage.getItem(localStorageKey(userId, "passkeyPromptDismissedUntil")) || "0");
      return dismissedUntil > Date.now();
    } catch (_error) {
      return false;
    }
  }
  function passkeysAreAvailable() {
    return typeof window.PublicKeyCredential === "function" && window.navigator.credentials !== void 0;
  }
  (function enablePasskeys() {
    if (typeof window === "undefined") return;
    function initPasskeys(event) {
      const target = detailTarget(event, "target");
      const root = isDomRoot(target) ? target : document;
      rootsWithRole(root, passkeyLoginDomAttr).forEach((element) => initializePasskeyRoot(element));
      rootsWithRole(root, passkeyRegistrationDomAttr).forEach((element) => initializePasskeyRoot(element));
      rootsWithRole(root, passkeySetupPromptDomAttr).forEach((element) => initializePasskeyRoot(element));
    }
    onAppPageReady(initPasskeys);
  })();

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
  function buildLiveUpdateSubscribeCommand(subscription, lastSeenVersion) {
    return encodeLiveUpdateCommand({
      type: "subscribe",
      subscription,
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
      renderedDependencyWatermark: config.subscription.renderedDependencyWatermark
    };
  }
  function readFrontendSurfaceMountElement(ownerEl, reportError2) {
    const rawConfig = ownerEl.getAttribute(surfaceConfigDomAttr);
    if (!rawConfig) return null;
    let config;
    try {
      config = parseFrontendSurfaceMountConfig(JSON.parse(rawConfig));
    } catch (error) {
      reportError2?.(ownerEl, error instanceof Error ? error : new Error(String(error)));
      return null;
    }
    const ownerSurface = ownerEl.getAttribute(surfaceDomAttr);
    if (!frontendSurfaceMountMatchesOwnerSurface(config, ownerSurface)) {
      reportError2?.(ownerEl, new Error(`FrontendSurface DOM/config mismatch: ${ownerSurface ?? "missing"} != ${config.surface}`));
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
  function scanFrontendSurfaceMountInstances(root, reportError2) {
    const scanRoot = root ?? (typeof document !== "undefined" ? document : null);
    if (!scanRoot) return [];
    const instances = [];
    scanRoot.querySelectorAll(`[${surfaceConfigDomAttr}]`).forEach((ownerEl) => {
      if (!(ownerEl instanceof HTMLElement)) return;
      const config = readFrontendSurfaceMountElement(ownerEl, reportError2);
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
  function readSurfaceSubscription(ownerEl, requestRefresh, reportError2) {
    const config = readFrontendSurfaceMountElement(ownerEl, reportError2);
    if (!config) return null;
    const parsed = parseFrontendSurfaceSubscriptionConfig(config);
    if (!parsed) return null;
    return {
      scope: parsed.scope,
      scopeKey: parsed.scopeKey,
      path: parsed.socketPath,
      resyncFragments: parsed.resyncFragments,
      renderedDependencyWatermark: parsed.renderedDependencyWatermark,
      ownerEls: [ownerEl],
      resync: (subscription) => subscription.resyncFragments.forEach(requestRefresh)
    };
  }
  function collectDesiredSurfaceSubscriptions(targetDocument, requestRefresh, reportError2) {
    const desired = /* @__PURE__ */ new Map();
    targetDocument.querySelectorAll(surfaceConfigSelector).forEach((ownerEl) => {
      if (!(ownerEl instanceof HTMLElement)) return;
      const subscription = readSurfaceSubscription(ownerEl, requestRefresh, reportError2);
      if (!subscription?.scopeKey) return;
      desired.set(subscription.scopeKey, mergeSubscription(desired.get(subscription.scopeKey), subscription));
    });
    return desired;
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

  // frontend/ts/live-updates/connection.ts
  function createLiveUpdateConnection(options) {
    const { targetWindow, activeSubscriptions, versions, handleMessage, requestSync, diagnostics } = options;
    let socket = null;
    let socketPath = null;
    let reconnectTimer = null;
    let reconnectAttempt = 0;
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
    return { sync, close };
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

  // frontend/ts/live-updates/invalidation.ts
  function createLiveUpdateInvalidationRuntime(options) {
    const { activeSubscriptions, refresher, diagnostics } = options;
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
      diagnostics.emitDebugEvent("subscription_acknowledged", { scopeKey, resync: message.resync });
    }
    function handleInvalidateMessage(message) {
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
      // Capture at swap time, not request time: a slow response must not
      // reclaim focus from a control the user moved to while awaiting it.
      // Stable native ids are Haskell-owned; no feature selectors or state
      // enter this generic replacement mechanic.
      captureReplacementFocus(target) {
        const active = targetDocument.activeElement;
        if (!(active instanceof HTMLElement) || !active.id || !target.contains(active)) return () => void 0;
        const id = active.id;
        const before = active.getBoundingClientRect();
        return (replacement) => {
          const next = targetDocument.getElementById(id);
          if (!(next instanceof HTMLElement) || !replacement.contains(next)) return;
          next.focus({ preventScroll: true });
          if (targetDocument.activeElement !== next) return;
          const after = next.getBoundingClientRect();
          targetWindow.scrollBy({ top: after.top - before.top, left: after.left - before.left, behavior: "instant" });
        };
      },
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
  function registerSurfaceFragmentRequestDecorator(decorator) {
    decorators().add(decorator);
    return () => decorators().delete(decorator);
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
      const restoreFocus = focus.captureReplacementFocus(target);
      target.replaceWith(nextNode);
      targetWindow.htmx?.process?.(nextNode);
      targetWindow.appPageLifecycle?.dispatchPageReady?.({
        source: "live-fragment-refetch",
        target: nextNode,
        isFullPage: false
      });
      restoreFocus(nextNode);
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
      if (response.headers.get("HX-Refresh")?.toLowerCase() === "true") {
        endPerfSpan(perfSpan, { outcome: "calendar_revision_reload", status: response.status });
        targetWindow.location.reload();
        return;
      }
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
  function defaultDiagnosticReporter2(diagnostic11) {
    console.error?.("Invalid generated complete-set sort boundary", diagnostic11);
  }
  function diagnostic2(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function createCompleteSetSortController(report = defaultDiagnosticReporter2) {
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
        for (const definition of definitionsForMount(mount)) {
          for (const sortRoot of ownedSurfaceRoleElements(mount, mount, definition.rootRoleAttribute)) {
            if (sortRoot.getAttribute(definition.rootRoleAttribute) !== "true") {
              report(diagnostic2(sortRoot, "invalid-root-role", "Complete-set sort root role must equal true"));
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
          report(diagnostic2(control, "invalid-control-key", "Complete-set sort control has an undeclared key"));
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
        report(diagnostic2(context.root, "missing-default-key", "Complete-set sort definition has no matching active key"));
        return false;
      }
      const rows = [];
      for (const row of ownedSurfaceRoleElements(context.root, context.mount, context.definition.rowRoleAttribute)) {
        const raw = row.getAttribute(context.definition.rowRoleAttribute);
        try {
          if (raw === null) throw new Error(`Missing ${context.definition.rowRoleAttribute}`);
          rows.push({ element: row, value: context.definition.parseRow(JSON.parse(raw)) });
        } catch (error) {
          report(diagnostic2(
            row,
            "invalid-row-payload",
            error instanceof Error ? error.message : String(error)
          ));
          return false;
        }
      }
      const rowParent = rows[0]?.element.parentElement ?? null;
      if (rows.some((row) => row.element.parentElement !== rowParent) || rows.length > 0 && rowParent === null) {
        report(diagnostic2(context.root, "invalid-row-parent", "Complete-set sort rows must share one local parent"));
        return false;
      }
      try {
        rows.sort((left, right) => compareRows(left.value, right.value, key.comparators, state.direction));
      } catch (error) {
        report(diagnostic2(
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
  var attrs3 = InteractionDom.attributes;
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
    if (isElementLike2(intent.mount) && isInteractionMount(intent.mount)) return intent.mount;
    if (isElementLike2(intent.marker)) return closestInteractionMount(intent.marker);
    const sourceTarget = intent.sourceEvent?.target;
    if (isElementLike2(sourceTarget)) return closestInteractionMount(sourceTarget);
    return null;
  }
  function isInteractionMount(element) {
    return Boolean(element.getAttribute(attrs3.surface));
  }
  function closestInteractionMount(element) {
    const closest = element.closest?.(attrSelector(attrs3.surface)) ?? null;
    return isElementLike2(closest) ? closest : null;
  }
  function findIntentForm(mount, intentName) {
    for (const form of queryAll(mount, attrSelector(attrs3.intentForm))) {
      if (form.getAttribute(attrs3.intent) === intentName || form.getAttribute(attrs3.intentForm) === intentName) {
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
      if (field.presence === "required" && !hasOwn(emittedFields, field.name) && field.input.value === "") {
        return { ok: false, reason: `Missing required intent field ${field.name}` };
      }
    }
    return { ok: true, fields };
  }
  function readFieldContracts(form) {
    return queryAll(form, attrSelector(attrs3.intentField)).flatMap((element) => {
      if (!isFieldInput(element)) return [];
      const name = element.getAttribute(attrs3.intentField);
      const presence = element.getAttribute(attrs3.fieldPresence);
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
    return Array.from(root.querySelectorAll(selector)).filter(isElementLike2);
  }
  function isElementLike2(value) {
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
  var attrs4 = InteractionDom.attributes;
  var surfaceActivationSelector = `[${attrs4.activationRef}]`;
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
    const surface = mount.getAttribute(attrs4.surface);
    if (!isFrontendSurfaceInteractionSurfaceName(surface)) return null;
    const ref = marker.getAttribute(attrs4.activationRef);
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
    if (!isElementLike3(target)) return null;
    const marker = target.closest(surfaceActivationSelector);
    return isElementLike3(marker) ? marker : null;
  }
  function closestInteractionMount2(marker) {
    const mount = marker.closest(`[${attrs4.surface}]`);
    return isElementLike3(mount) ? mount : null;
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
    return isElementLike3(value) && typeof value.value === "string";
  }
  function isElementLike3(value) {
    if (value === null || typeof value !== "object") return false;
    const maybe = value;
    return typeof maybe.getAttribute === "function" && typeof maybe.closest === "function" && typeof maybe.querySelector === "function";
  }

  // frontend/ts/interaction/pointer-session.ts
  var attrs5 = InteractionDom.attributes;
  var values = InteractionDom.values;
  var sourceRefSelector = `[${attrs5.sourceRef}]`;
  var interactiveControlSelector = "button,a,input,select,textarea,[role=button],[role=link]";
  var disposableLayerSelector = `[${attrs5.disposableLayer}]`;
  var pointerFields = InteractionDom.pointerFields;
  var defaultThresholdPx = 4;
  var activeSourceRefAttribute = attrs5.activeSourceRef;
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
      const timeoutMs = numberAttribute(session.marker, attrs5.sessionTimeoutMs);
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
    const surface = mount.getAttribute(attrs5.surface);
    if (!isFrontendSurfaceInteractionSurfaceName(surface)) return null;
    const sourceRef = marker.getAttribute(attrs5.sourceRef);
    const source = FrontendSurfaceInteractionRegistry[surface].sourceRefs.find((candidate) => candidate.ref === sourceRef);
    if (!source) return null;
    const sourceKey = marker.getAttribute(attrs5.sourceKey);
    if (!sourceKey) return null;
    const compatibleDropzoneRefs = compatibleDropzoneRefsForSource(surface, source);
    const targetField = FrontendSurfaceInteractionRegistry[surface].dropzoneRefs.find((candidate) => compatibleDropzoneRefs.includes(candidate.ref))?.targetField ?? null;
    return buildPointerSession({ event: pointerEvent, marker, mount, intent: source.intent, modifierVariants: source.modifierVariants ?? [], sessionKind: source.session, sourceRef: source.ref, compatibleDropzoneRefs, sourceField: source.sourceField, sourceKey, targetField, fallbackThresholdPx });
  }
  function buildPointerSession(input) {
    const startClientX = numberValue(input.event.clientX);
    const startClientY = numberValue(input.event.clientY);
    const thresholdPx = numberAttribute(input.marker, attrs5.sessionThreshold) ?? input.fallbackThresholdPx;
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
    if (!isElementLike4(hit)) return null;
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
    const family = session.mount.getAttribute(attrs5.surfaceFamily);
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
    if (compatibleRefs.length === 0) return `[${attrs5.dropzoneRef}]`;
    return compatibleRefs.map((ref) => `[${attrs5.dropzoneRef}="${cssString(ref)}"]`).join(",");
  }
  function compatibleDropzoneRefsForSource(surface, source) {
    const explicitRefs = source.compatibleDropzones ?? [];
    if (explicitRefs.length > 0) return explicitRefs;
    return FrontendSurfaceInteractionRegistry[surface].dropzoneRefs.filter((candidate) => candidate.session === source.session).map((candidate) => candidate.ref);
  }
  function targetDropzoneFieldForSession(session, target) {
    if (!target) return null;
    const surface = session.mount.getAttribute(attrs5.surface);
    if (!isFrontendSurfaceInteractionSurfaceName(surface)) return null;
    const ref = target.getAttribute(attrs5.dropzoneRef);
    if (!ref) return null;
    return FrontendSurfaceInteractionRegistry[surface].dropzoneRefs.find((candidate) => candidate.ref === ref)?.targetField ?? null;
  }
  function targetDropzoneKeyForTarget(target) {
    if (!target) return null;
    return target.getAttribute(attrs5.dropzoneKey);
  }
  function cssString(value) {
    return value.replace(/\\/g, "\\\\").replace(/\"/g, '\\"');
  }
  function disposableLayerByName(mount, layerName) {
    for (const layer of mount.querySelectorAll(disposableLayerSelector)) {
      if (layer.getAttribute(attrs5.disposableLayer) === layerName) return layer;
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
    if (!isElementLike4(target)) return null;
    const marker = target.closest(sourceRefSelector);
    return isElementLike4(marker) ? marker : null;
  }
  function closestInteractiveControl(target) {
    if (!isElementLike4(target)) return null;
    const control = target.closest(interactiveControlSelector);
    return isElementLike4(control) ? control : null;
  }
  function closestInteractionMount3(marker) {
    const mount = marker.closest(`[${attrs5.surface}]`);
    return isElementLike4(mount) ? mount : null;
  }
  function clearDisposableLayers(mount) {
    for (const layer of mount.querySelectorAll(disposableLayerSelector)) clearElement(layer);
  }
  function setDocumentInteractionActive(session, active) {
    const root = session.mount.ownerDocument?.documentElement;
    if (!root) return;
    if (active) {
      root.setAttribute(attrs5.interactionActive, values.enabled);
      root.setAttribute(activeSourceRefAttribute, session.sourceRef);
    } else {
      root.removeAttribute(attrs5.interactionActive);
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
    return marker.getAttribute(attrs5.sessionDisabled) === values.enabled || marker.getAttribute(attrs5.sessionReadOnly) === values.enabled;
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
  function isElementLike4(value) {
    if (value === null || typeof value !== "object") return false;
    const maybe = value;
    return typeof maybe.getAttribute === "function" && typeof maybe.closest === "function" && typeof maybe.querySelectorAll === "function";
  }

  // frontend/ts/side-panel/runtime.ts
  function defaultDiagnosticReporter3(diagnostic11) {
    console.error?.("Invalid generated Surface side-panel boundary", diagnostic11);
  }
  function diagnostic3(element, code, message) {
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
  function ownedElements2(resolved, attribute) {
    return ownedSurfaceRoleElements(resolved.root, resolved.mount, attribute).filter((element) => closestOwnedSurfaceRole(element, resolved.mount, resolved.definition.rootRoleAttribute) === resolved.root);
  }
  function validateStructure(resolved, report) {
    if (resolved.root.getAttribute(resolved.definition.rootRoleAttribute) !== "true") {
      report(diagnostic3(resolved.root, "invalid-root-role", "Side-panel root role must equal true"));
      return false;
    }
    const required = [
      [resolved.definition.mainRoleAttribute, "invalid-main-role"],
      [resolved.definition.panelRoleAttribute, "invalid-panel-role"]
    ];
    for (const [attribute, code] of required) {
      const elements = ownedElements2(resolved, attribute);
      if (elements.length !== 1 || elements[0]?.getAttribute(attribute) !== "true") {
        report(diagnostic3(resolved.root, code, "Side-panel root must own exactly one generated region role"));
        return false;
      }
    }
    return true;
  }
  function stateFor(resolved, report) {
    if (!validateStructure(resolved, report)) return null;
    const state = resolved.root.getAttribute(resolved.definition.stateAttribute);
    if (!resolved.definition.isState(state)) {
      report(diagnostic3(resolved.root, "invalid-state", "Side-panel state is not declared by the Surface contract"));
      return null;
    }
    return state;
  }
  function validateToggle(resolved, toggle, report) {
    if (toggle.getAttribute(resolved.definition.toggleRoleAttribute) !== "true") {
      report(diagnostic3(toggle, "invalid-toggle-role", "Side-panel toggle role must equal true"));
      return null;
    }
    const labels = Array.from(toggle.querySelectorAll(`[${resolved.definition.labelRoleAttribute}]`)).filter(isSurfaceElementLike).filter((label) => closestOwnedSurfaceRole(label, resolved.mount, resolved.definition.toggleRoleAttribute) === toggle);
    if (labels.length !== 1 || labels[0]?.getAttribute(resolved.definition.labelRoleAttribute) !== "true") {
      report(diagnostic3(toggle, "invalid-label-role", "Side-panel toggle must own one generated label role"));
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
  function createSidePanelController(report = defaultDiagnosticReporter3) {
    function validatedToggles(resolved) {
      const toggles = ownedElements2(resolved, resolved.definition.toggleRoleAttribute);
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
  function defaultDiagnosticReporter4(diagnostic11) {
    console.error?.("Invalid generated Surface tab-set boundary", diagnostic11);
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
      const mount = closestSurfaceMount(target);
      if (!mount) return false;
      for (const definition of definitionsForMount2(mount)) {
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
    function capture(root) {
      const mountIndexes = /* @__PURE__ */ new Map();
      const snapshots = [];
      for (const mount of surfaceMountsWithin(root)) {
        const surface = mount.getAttribute(surfaceDomAttr);
        if (surface === null) continue;
        const mountIndex = mountIndexes.get(surface) ?? 0;
        mountIndexes.set(surface, mountIndex + 1);
        for (const definition of definitionsForMount2(mount)) {
          const selectedTab = ownedSurfaceRoleElements(mount, mount, definition.tabRoleAttribute).find((tab) => tab.getAttribute("aria-selected") === "true");
          const key = selectedTab?.getAttribute(definition.tabRoleAttribute) ?? rememberedKey(mount, definition);
          if (!definition.isKey(key)) continue;
          snapshots.push({ surface, mountIndex, tabSet: definition.name, key });
        }
      }
      return snapshots;
    }
    function restore(root, snapshots) {
      const mountIndexes = /* @__PURE__ */ new Map();
      for (const mount of surfaceMountsWithin(root)) {
        const surface = mount.getAttribute(surfaceDomAttr);
        if (surface === null) continue;
        const mountIndex = mountIndexes.get(surface) ?? 0;
        mountIndexes.set(surface, mountIndex + 1);
        for (const definition of definitionsForMount2(mount)) {
          const snapshot = snapshots.find((candidate) => candidate.surface === surface && candidate.mountIndex === mountIndex && candidate.tabSet === definition.name && definition.isKey(candidate.key));
          if (snapshot) setRememberedKey(mount, definition, snapshot.key);
        }
      }
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
          if (desiredTab && tabPresentationMatchesSelection(desiredTab)) continue;
          showTab(desiredTab);
        }
      }
    }
    return { remember, capture, restore, reconcile };
  }
  function definitionsForMount2(mount) {
    return surfaceDefinitionsForMount(mount, FrontendSurfaceTabSetRegistry);
  }
  var browserRuntimeEnabled3 = false;
  function enableFrontendSurfaceTabSets() {
    if (browserRuntimeEnabled3 || typeof document === "undefined") return;
    browserRuntimeEnabled3 = true;
    const controller = createSurfaceTabSetController();
    const pendingSwapSnapshots = /* @__PURE__ */ new WeakMap();
    document.addEventListener("shown.bs.tab", (event) => {
      if (!(event.target instanceof Element)) return;
      controller.remember(event.target);
    });
    document.addEventListener("htmx:beforeSwap", (event) => {
      const request = detailTarget(event, "xhr");
      if (request === null || typeof request !== "object") return;
      pendingSwapSnapshots.set(request, controller.capture(detailRoot(event, "target")));
    });
    document.addEventListener("htmx:afterSwap", (event) => {
      const request = detailTarget(event, "xhr");
      if (request === null || typeof request !== "object") return;
      const snapshots = pendingSwapSnapshots.get(request);
      if (snapshots === void 0) return;
      const root = detailRoot(event, "target");
      controller.restore(root, snapshots);
      controller.reconcile(root);
      pendingSwapSnapshots.delete(request);
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

  // frontend/ts/app-dialog-overlays.ts
  var dialogMountSelector = `[${dialogMountDomAttr}]`;
  var dialogKeyboardSelector = `[${dialogKeyboardDomAttr}]`;
  var dialogFocusRegionSelector = `[${dialogFocusRegionDomAttr}]`;
  var dialogBackdropSelector = `[${dialogBackdropDomAttr}]`;
  var dialogCloseSelector = `[${dialogCloseDomAttr}]`;
  var navigationLoadingSelector = `form[${navigationLoadingDomAttr}]`;
  var originalSubmitHtml = /* @__PURE__ */ new WeakMap();
  var dialogLoadingStates = /* @__PURE__ */ new WeakMap();
  var checkboxControlledHiddenOptions = /* @__PURE__ */ new WeakMap();
  function syncCheckboxControlledHiddenSelectOptions(checkbox) {
    if (checkbox.type !== "checkbox") return;
    const controlledId = checkbox.getAttribute("aria-controls")?.trim();
    if (controlledId === void 0 || controlledId.length === 0 || /\s/.test(controlledId)) return;
    const controlled = checkbox.ownerDocument.getElementById(controlledId);
    if (!(controlled instanceof HTMLSelectElement)) return;
    let hiddenOptions = checkboxControlledHiddenOptions.get(checkbox);
    if (hiddenOptions === void 0) {
      hiddenOptions = Array.from(controlled.options).filter((option) => option.hidden);
      checkboxControlledHiddenOptions.set(checkbox, hiddenOptions);
    }
    hiddenOptions.forEach((option) => {
      option.hidden = !checkbox.checked;
    });
    if (!checkbox.checked && hiddenOptions.some((option) => option.selected)) {
      controlled.value = "";
    }
    checkbox.setAttribute("aria-expanded", checkbox.checked ? "true" : "false");
  }
  function dialogSubmitLoadingHtml(label) {
    return '<span class="spinner-border spinner-border-sm" aria-hidden="true"></span><span>' + label + "</span>";
  }
  function parseDialogSubmitConfiguration(raw) {
    const config = parseDialogSubmitConfig(JSON.parse(raw));
    if (config.loadingLabel.trim().length === 0) {
      throw new Error("DialogSubmitConfig loadingLabel must not be empty");
    }
    return config;
  }
  function parseNavigationLoadingConfiguration(raw) {
    const config = parseNavigationLoadingConfig(JSON.parse(raw));
    if (config.loadingTitle.trim().length === 0) {
      throw new Error("NavigationLoadingConfig loadingTitle must not be empty");
    }
    if (config.loadingMessage.trim().length === 0) {
      throw new Error("NavigationLoadingConfig loadingMessage must not be empty");
    }
    return config;
  }
  function navigationLoadingConfiguration(form) {
    const rawConfig = form.getAttribute(navigationLoadingConfigDomAttr);
    try {
      if (rawConfig === null) throw new Error(`Missing ${navigationLoadingConfigDomAttr}`);
      return parseNavigationLoadingConfiguration(rawConfig);
    } catch (error) {
      console.error?.("Invalid generated navigation loading configuration", {
        code: "invalid-navigation-loading-config",
        message: error instanceof Error ? error.message : String(error)
      });
      return null;
    }
  }
  function dialogSubmitConfiguration(submitter) {
    const rawConfig = submitter.getAttribute(dialogSubmitConfigDomAttr);
    try {
      if (rawConfig === null) throw new Error(`Missing ${dialogSubmitConfigDomAttr}`);
      return parseDialogSubmitConfiguration(rawConfig);
    } catch (error) {
      console.error?.("Invalid generated dialog submit configuration", {
        code: "invalid-dialog-submit-config",
        message: error instanceof Error ? error.message : String(error)
      });
      return null;
    }
  }
  function showDialogSubmitLoading(dialog, config) {
    if (dialogLoadingStates.has(dialog)) return;
    const content = dialog.querySelector(":scope > .modal-dialog > .modal-content");
    if (!(content instanceof HTMLElement)) return;
    const contentChildren = Array.from(content.children).filter(isHTMLElement).map((element) => ({ element, hidden: element.hidden }));
    contentChildren.forEach(({ element }) => {
      element.hidden = true;
    });
    const loadingPanel = document.createElement("div");
    loadingPanel.className = "modal-body d-flex align-items-center justify-content-center gap-3 py-5";
    loadingPanel.setAttribute("role", "status");
    loadingPanel.setAttribute("aria-live", "polite");
    const spinner = document.createElement("span");
    spinner.className = "spinner-border text-primary";
    spinner.setAttribute("aria-hidden", "true");
    const label = document.createElement("span");
    label.className = "fw-semibold";
    label.textContent = config.loadingLabel;
    loadingPanel.append(spinner, label);
    content.append(loadingPanel);
    const state = {
      contentChildren,
      loadingPanel,
      previousAriaBusy: dialog.getAttribute("aria-busy"),
      wasBlocking: dialog.hasAttribute(dialogBlockingDomAttr)
    };
    dialogLoadingStates.set(dialog, state);
    dialog.setAttribute("aria-busy", "true");
    dialog.setAttribute(dialogBlockingDomAttr, "true");
    dialog.focus({ preventScroll: true });
  }
  function restoreDialogSubmitLoading(dialog) {
    const state = dialogLoadingStates.get(dialog);
    if (state === void 0) return;
    state.loadingPanel.remove();
    state.contentChildren.forEach(({ element, hidden }) => {
      element.hidden = hidden;
    });
    if (state.previousAriaBusy === null) {
      dialog.removeAttribute("aria-busy");
    } else {
      dialog.setAttribute("aria-busy", state.previousAriaBusy);
    }
    if (!state.wasBlocking) dialog.removeAttribute(dialogBlockingDomAttr);
    dialogLoadingStates.delete(dialog);
  }
  (function enableDialogOverlayMount() {
    if (typeof window === "undefined") return;
    const mountId = dialogOverlayMountDomId;
    const dismissalLifecycle = createDialogDismissalLifecycle(dialogDismissedEvent);
    const blockingBackgroundInertStates = /* @__PURE__ */ new Map();
    let blockingDialogReturnFocus = null;
    function getMount() {
      const mountEl = document.getElementById(mountId);
      return isHTMLElement(mountEl) ? mountEl : null;
    }
    function getActiveDialog() {
      const dialogs = Array.from(document.querySelectorAll(dialogMountSelector)).filter(isHTMLElement);
      return dialogs.length === 0 ? null : dialogs[dialogs.length - 1];
    }
    function getMountedDialog(mountEl) {
      const dialogs = Array.from(mountEl.querySelectorAll(dialogMountSelector)).filter(isHTMLElement);
      return dialogs.length === 0 ? null : dialogs[dialogs.length - 1];
    }
    function reconcileDialogDismissal(mountEl) {
      dismissalLifecycle.reconcile(mountEl, getMountedDialog(mountEl));
    }
    function keyboardFocusRegion(dialog) {
      if (!dialog.matches(dialogKeyboardSelector)) return null;
      const regions = Array.from(dialog.querySelectorAll(dialogFocusRegionSelector));
      return regions.length === 1 && regions[0] instanceof HTMLElement ? regions[0] : null;
    }
    function focusableDialogControls(region) {
      const selector = [
        "input:not([type='hidden']):not([disabled])",
        "select:not([disabled])",
        "textarea:not([disabled])",
        "button:not([disabled])",
        "a[href]",
        "[contenteditable='true']",
        "[tabindex]:not([tabindex='-1'])"
      ].join(",");
      return Array.from(region.querySelectorAll(selector)).filter((element) => {
        if (!(element instanceof HTMLElement)) return false;
        if (element.hidden || element.closest("[hidden], [inert]") !== null) return false;
        return element.tabIndex >= 0;
      });
    }
    function focusKeyboardDialog(dialog) {
      const region = keyboardFocusRegion(dialog);
      if (region === null) return;
      const controls2 = focusableDialogControls(region);
      const firstInvalid = controls2.find((control) => control.getAttribute("aria-invalid") === "true");
      const autofocus = controls2.find((control) => control.hasAttribute("autofocus"));
      (firstInvalid ?? autofocus ?? controls2[0] ?? dialog).focus({ preventScroll: true });
    }
    function initializeKeyboardDialogs(root) {
      if (root instanceof HTMLElement && root.matches(dialogKeyboardSelector)) focusKeyboardDialog(root);
      root.querySelectorAll(dialogKeyboardSelector).forEach((dialog) => {
        if (dialog instanceof HTMLElement) focusKeyboardDialog(dialog);
      });
    }
    function hasVisibleBootstrapModal() {
      return Boolean(document.querySelector(`.modal.show:not(${dialogMountSelector})`));
    }
    function syncDialogState() {
      const hasDialog = getActiveDialog() !== null;
      const shouldLockBody = hasDialog || hasVisibleBootstrapModal();
      document.body.classList.toggle("modal-open", shouldLockBody);
      document.body.style.overflow = shouldLockBody ? "hidden" : "";
    }
    function showNavigationLoadingDialog(config) {
      const mountEl = getMount();
      if (mountEl === null) return;
      const dialogEl = document.createElement("div");
      dialogEl.className = "modal fade show d-block";
      dialogEl.setAttribute(dialogMountDomAttr, "true");
      dialogEl.setAttribute(dialogBlockingDomAttr, "true");
      dialogEl.setAttribute("tabindex", "-1");
      dialogEl.setAttribute("role", "dialog");
      dialogEl.setAttribute("aria-modal", "true");
      dialogEl.setAttribute("aria-label", config.loadingTitle);
      const modalDialog = document.createElement("div");
      modalDialog.className = "modal-dialog modal-dialog-centered";
      modalDialog.setAttribute("role", "document");
      const content = document.createElement("div");
      content.className = "modal-content shadow";
      const body = document.createElement("div");
      body.className = "modal-body d-flex align-items-center gap-3 py-4";
      body.setAttribute("role", "status");
      body.setAttribute("aria-live", "polite");
      const spinner = document.createElement("span");
      spinner.className = "spinner-border text-primary";
      spinner.setAttribute("aria-hidden", "true");
      const copy = document.createElement("div");
      const title = document.createElement("h2");
      title.className = "h5 mb-1";
      title.textContent = config.loadingTitle;
      const message = document.createElement("p");
      message.className = "mb-0 app-muted";
      message.textContent = config.loadingMessage;
      copy.append(title, message);
      body.append(spinner, copy);
      content.append(body);
      modalDialog.append(content);
      dialogEl.append(modalDialog);
      const backdrop = document.createElement("div");
      backdrop.className = "modal-backdrop fade show";
      backdrop.setAttribute(dialogBackdropDomAttr, "true");
      blockingDialogReturnFocus = isHTMLElement(document.activeElement) ? document.activeElement : null;
      const replacedDialog = getMountedDialog(mountEl);
      if (replacedDialog !== null) dismissalLifecycle.dismiss(replacedDialog, mountEl, dialogEl);
      mountEl.replaceChildren(dialogEl, backdrop);
      reconcileDialogDismissal(mountEl);
      setBlockingBackgroundInert(mountEl, true);
      syncDialogState();
      dialogEl.focus();
    }
    function setBlockingBackgroundInert(mountEl, inert) {
      Array.from(document.body.children).forEach((element) => {
        if (!(element instanceof HTMLElement) || element === mountEl) return;
        if (inert) {
          if (!blockingBackgroundInertStates.has(element)) {
            blockingBackgroundInertStates.set(element, element.inert);
          }
          element.inert = true;
          return;
        }
        const previous = blockingBackgroundInertStates.get(element);
        if (previous !== void 0) element.inert = previous;
        blockingBackgroundInertStates.delete(element);
      });
    }
    function clearDialog(dialogEl) {
      const mountEl = getMount();
      const eventOwner = mountEl !== null && mountEl.contains(dialogEl) ? mountEl : dialogEl;
      dismissalLifecycle.dismiss(dialogEl, eventOwner);
      const wasBlocking = dialogEl.hasAttribute(dialogBlockingDomAttr);
      const inheritedBlockingState = blockingBackgroundInertStates.size > 0;
      if ((wasBlocking || inheritedBlockingState) && mountEl !== null) setBlockingBackgroundInert(mountEl, false);
      const returnFocus = wasBlocking || inheritedBlockingState ? blockingDialogReturnFocus : null;
      if (wasBlocking || inheritedBlockingState) blockingDialogReturnFocus = null;
      if (mountEl !== null && mountEl.contains(dialogEl)) {
        mountEl.innerHTML = "";
        reconcileDialogDismissal(mountEl);
        syncDialogState();
        if (returnFocus?.isConnected) returnFocus.focus();
        return;
      }
      const localOwner = dialogEl.parentElement;
      dialogEl.remove();
      if (localOwner !== null) {
        Array.from(localOwner.children).forEach((element) => {
          if (element.matches(dialogBackdropSelector)) element.remove();
        });
      }
      syncDialogState();
      if (returnFocus?.isConnected) returnFocus.focus();
    }
    function releaseInheritedBlockingStateWhenDialogAbsent(mountEl) {
      if (getActiveDialog() !== null || blockingBackgroundInertStates.size === 0) return;
      setBlockingBackgroundInert(mountEl, false);
      const returnFocus = blockingDialogReturnFocus;
      blockingDialogReturnFocus = null;
      if (returnFocus?.isConnected) returnFocus.focus();
    }
    document.addEventListener("click", function(event) {
      const closeEl = closestHTMLElement(event.target, dialogCloseSelector);
      const closeDialog = closeEl?.closest(dialogMountSelector);
      if (closeEl !== null && isHTMLElement(closeDialog)) {
        event.preventDefault();
        clearDialog(closeDialog);
        return;
      }
      const backdropEl = closestHTMLElement(event.target, dialogBackdropSelector);
      const backdropDialog = backdropEl?.parentElement?.querySelector(dialogMountSelector);
      if (backdropEl !== null && isHTMLElement(backdropDialog)) {
        event.preventDefault();
        if (backdropDialog.hasAttribute(dialogBlockingDomAttr)) return;
        clearDialog(backdropDialog);
        return;
      }
      const activeDialog = getActiveDialog();
      if (activeDialog !== null && event.target === activeDialog) {
        event.preventDefault();
        if (activeDialog.hasAttribute(dialogBlockingDomAttr)) return;
        clearDialog(activeDialog);
      }
    });
    document.addEventListener("keydown", function(event) {
      const activeDialog = getActiveDialog();
      if (activeDialog === null) return;
      if (event.key === "Tab" && activeDialog.hasAttribute(dialogBlockingDomAttr)) {
        event.preventDefault();
        activeDialog.focus();
        return;
      }
      const focusRegion = keyboardFocusRegion(activeDialog);
      if (event.key === "Tab" && focusRegion !== null) {
        const controls2 = focusableDialogControls(focusRegion);
        event.preventDefault();
        if (controls2.length === 0) {
          activeDialog.focus();
          return;
        }
        const currentIndex = controls2.indexOf(document.activeElement);
        const nextIndex = event.shiftKey ? currentIndex <= 0 ? controls2.length - 1 : currentIndex - 1 : currentIndex < 0 || currentIndex === controls2.length - 1 ? 0 : currentIndex + 1;
        controls2[nextIndex]?.focus();
        return;
      }
      if (event.key === "Enter" && focusRegion !== null && !event.isComposing && !event.ctrlKey && !event.metaKey && !event.altKey) {
        const target = event.target;
        if (target instanceof HTMLTextAreaElement || target instanceof HTMLElement && target.isContentEditable) return;
        const submitter = activeDialog.querySelector(`[${dialogSubmitDomAttr}]`);
        if (submitter instanceof HTMLButtonElement && !submitter.disabled && submitter.form !== null) {
          event.preventDefault();
          submitter.form.requestSubmit(submitter);
        }
        return;
      }
      if (event.key !== "Escape") return;
      event.preventDefault();
      if (!activeDialog.hasAttribute(dialogBlockingDomAttr)) clearDialog(activeDialog);
    });
    document.addEventListener("change", function(event) {
      const target = event.target;
      if (target instanceof HTMLInputElement) syncCheckboxControlledHiddenSelectOptions(target);
    });
    document.addEventListener("submit", function(event) {
      if (event.defaultPrevented) return;
      const submittedForm = event.target;
      if (submittedForm instanceof HTMLFormElement && submittedForm.matches(navigationLoadingSelector)) {
        const navigationConfig = navigationLoadingConfiguration(submittedForm);
        if (navigationConfig !== null) showNavigationLoadingDialog(navigationConfig);
      }
      const activeDialog = getActiveDialog();
      if (activeDialog === null) return;
      const form = event.target;
      if (!(form instanceof HTMLFormElement)) return;
      const submitter = event instanceof SubmitEvent ? event.submitter : null;
      if (!(submitter instanceof HTMLButtonElement)) return;
      if (!submitter.hasAttribute(dialogSubmitDomAttr)) return;
      const config = dialogSubmitConfiguration(submitter);
      if (config === null) return;
      activeDialog.querySelectorAll("button, a.btn").forEach(function(control) {
        if (control instanceof HTMLButtonElement) {
          control.disabled = true;
        } else if (isHTMLElement(control)) {
          control.classList.add("disabled");
          control.setAttribute("aria-disabled", "true");
        }
      });
      if (!originalSubmitHtml.has(submitter)) {
        originalSubmitHtml.set(submitter, submitter.innerHTML);
      }
      submitter.innerHTML = dialogSubmitLoadingHtml(config.loadingLabel);
      submitter.classList.add("d-inline-flex", "align-items-center", "gap-2");
      showDialogSubmitLoading(activeDialog, config);
    }, true);
    document.addEventListener("htmx:afterRequest", function(event) {
      const activeDialog = getActiveDialog();
      if (activeDialog === null) return;
      const elt = detailTarget(event, "elt");
      if (!isHTMLElement(elt)) return;
      if (!activeDialog.contains(elt)) return;
      restoreDialogSubmitLoading(activeDialog);
      activeDialog.querySelectorAll("button, a.btn").forEach(function(control) {
        if (control instanceof HTMLButtonElement) {
          control.disabled = false;
        } else if (isHTMLElement(control)) {
          control.classList.remove("disabled");
          control.removeAttribute("aria-disabled");
        }
      });
      activeDialog.querySelectorAll(`[${dialogSubmitDomAttr}]`).forEach(function(control) {
        if (!(control instanceof HTMLButtonElement)) return;
        const originalHtml = originalSubmitHtml.get(control);
        if (originalHtml !== void 0) {
          control.innerHTML = originalHtml;
        }
        control.classList.remove("d-inline-flex", "align-items-center", "gap-2");
      });
    });
    document.addEventListener("htmx:afterSwap", function(event) {
      const target = detailRoot(event, "target");
      if (!isHTMLElement(target)) return;
      if (target.id !== mountId) return;
      initializeKeyboardDialogs(target);
      reconcileDialogDismissal(target);
      releaseInheritedBlockingStateWhenDialogAbsent(target);
      syncDialogState();
    });
    document.addEventListener("htmx:oobAfterSwap", function(event) {
      const target = detailRoot(event, "target");
      if (!isHTMLElement(target)) return;
      if (target.id !== mountId) return;
      initializeKeyboardDialogs(target);
      reconcileDialogDismissal(target);
      releaseInheritedBlockingStateWhenDialogAbsent(target);
      syncDialogState();
    });
    window.addEventListener("pageshow", function(event) {
      if (!event.persisted) return;
      const activeDialog = getActiveDialog();
      if (activeDialog !== null && activeDialog.hasAttribute(dialogBlockingDomAttr)) {
        clearDialog(activeDialog);
      }
    });
    document.addEventListener("shown.bs.modal", syncDialogState);
    document.addEventListener("hidden.bs.modal", syncDialogState);
    document.addEventListener(pageReadyEvent, (event) => {
      const mountEl = getMount();
      if (mountEl !== null) reconcileDialogDismissal(mountEl);
      syncDialogState();
      const target = detailTarget(event, "target");
      if (target instanceof HTMLElement || target instanceof Document) initializeKeyboardDialogs(target);
    });
  })();

  // frontend/ts/app-toasts.ts
  var hostId = toastOverlayMountDomId;
  var toastMountSelector = `[${toastMountDomAttr}]`;
  var toastCloseSelector = `[${toastCloseDomAttr}]`;
  var initializedToasts = /* @__PURE__ */ new WeakSet();
  function parseToastConfiguration(raw) {
    const config = parseToastConfig(JSON.parse(raw));
    if (config.autoHideMs < 0) {
      throw new Error("ToastConfig autoHideMs must not be negative");
    }
    return config;
  }
  function getHost() {
    return document.getElementById(hostId);
  }
  function dismissToast(toastEl) {
    toastEl.classList.add("app-toast-leaving");
    window.setTimeout(() => {
      if (toastEl.parentNode !== null) {
        toastEl.remove();
      }
    }, 220);
  }
  function initToast(toastEl) {
    if (initializedToasts.has(toastEl)) return;
    initializedToasts.add(toastEl);
    const rawConfig = toastEl.getAttribute(toastConfigDomAttr);
    let config;
    try {
      if (rawConfig === null) throw new Error(`Missing ${toastConfigDomAttr}`);
      config = parseToastConfiguration(rawConfig);
    } catch (error) {
      console.error?.("Invalid generated toast configuration", {
        code: "invalid-toast-config",
        message: error instanceof Error ? error.message : String(error)
      });
      return;
    }
    if (config.autoHideMs > 0) {
      window.setTimeout(() => {
        dismissToast(toastEl);
      }, config.autoHideMs);
    }
  }
  function initHostToasts() {
    const hostEl = getHost();
    if (!(hostEl instanceof HTMLElement)) return;
    hostEl.querySelectorAll(toastMountSelector).forEach(initToast);
  }
  function enableToastOverlayHost() {
    if (typeof window === "undefined") return;
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const closeEl = event.target.closest(toastCloseSelector);
      if (!(closeEl instanceof HTMLElement)) return;
      const toastEl = closeEl.closest(toastMountSelector);
      if (toastEl instanceof HTMLElement) {
        dismissToast(toastEl);
      }
    });
    document.addEventListener(pageReadyEvent, initHostToasts);
  }
  enableToastOverlayHost();

  // frontend/ts/time-picker/configuration.ts
  function parseTimePickerConfiguration(raw) {
    return validateTimePickerConfiguration(parseTimePickerConfig(JSON.parse(raw)));
  }
  function parseTimePickerOptionConfiguration(raw) {
    return validateTimePickerOption(parseTimePickerOption(JSON.parse(raw)));
  }
  function timePickerOptionsForConfiguration(rawConfig, rawOptions) {
    const config = validateTimePickerConfiguration(rawConfig);
    const optionsByValue = /* @__PURE__ */ new Map();
    for (const rawOption of rawOptions) {
      const option = validateTimePickerOption(rawOption);
      if (optionsByValue.has(option.value)) {
        throw new Error(`TimePickerOption value ${option.value} must be unique`);
      }
      optionsByValue.set(option.value, option);
    }
    const startMinute = minuteOfDayFromTimeValue(config.rangeStart);
    const rawEndMinute = minuteOfDayFromTimeValue(config.rangeEnd);
    if (startMinute === null || rawEndMinute === null) {
      throw new Error("TimePickerConfig range values must use HH:MM");
    }
    const endMinute = rawEndMinute < startMinute ? rawEndMinute + 24 * 60 : rawEndMinute;
    const selected = [];
    for (let minute = startMinute; minute <= endMinute; minute += config.stepMinutes) {
      const value = timeValueFromMinuteOfDay(minute);
      const option = optionsByValue.get(value);
      if (option === void 0) {
        throw new Error(`TimePickerConfig missing rendered option ${value}`);
      }
      selected.push(option);
    }
    return selected;
  }
  function validateTimePickerConfiguration(config) {
    if (minuteOfDayFromTimeValue(config.rangeStart) === null || minuteOfDayFromTimeValue(config.rangeEnd) === null) {
      throw new Error("TimePickerConfig range values must use HH:MM");
    }
    if (config.stepMinutes <= 0 || config.stepMinutes > 24 * 60) {
      throw new Error("TimePickerConfig stepMinutes must be between 1 and 1440");
    }
    if (config.emptyLabel.trim().length === 0) {
      throw new Error("TimePickerConfig emptyLabel must not be empty");
    }
    return config;
  }
  function validateTimePickerOption(option) {
    if (minuteOfDayFromTimeValue(option.value) === null) {
      throw new Error("TimePickerOption value must use HH:MM");
    }
    if (option.label.trim().length === 0) {
      throw new Error("TimePickerOption label must not be empty");
    }
    return option;
  }
  function minuteOfDayFromTimeValue(value) {
    if (!/^\d{2}:\d{2}$/.test(value)) return null;
    const [rawHour, rawMinute] = value.split(":");
    const hour = Number(rawHour);
    const minute = Number(rawMinute);
    if (!Number.isInteger(hour) || !Number.isInteger(minute)) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }
  function timeValueFromMinuteOfDay(totalMinutes) {
    const minuteOfDay = totalMinutes % (24 * 60);
    const hour = Math.floor(minuteOfDay / 60);
    const minute = minuteOfDay % 60;
    return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
  }

  // frontend/ts/time-picker/keyboard.ts
  function compactTimePickerValue(digits, stepMinutes, rangeStart, rangeEnd) {
    if (!/^\d{1,4}$/.test(digits) || stepMinutes !== 1 && stepMinutes !== 15) return null;
    if (digits.length <= 2) {
      const hour2 = Number(digits);
      if (!Number.isInteger(hour2) || hour2 < 0 || hour2 > 23) return null;
      const value = `${String(hour2).padStart(2, "0")}:00`;
      return timeIsSelectable(value, stepMinutes, rangeStart, rangeEnd) ? value : null;
    }
    const hour = Number(digits.slice(0, 2));
    if (!Number.isInteger(hour) || hour < 0 || hour > 23) return null;
    const minuteDigits = digits.slice(2);
    const candidates = Array.from({ length: 60 / stepMinutes }, (_, index) => index * stepMinutes).filter((minute) => String(minute).padStart(2, "0").startsWith(minuteDigits));
    for (const minute of candidates) {
      const value = `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
      if (timeIsSelectable(value, stepMinutes, rangeStart, rangeEnd)) return value;
    }
    return null;
  }
  function timeIsSelectable(value, stepMinutes, rangeStart, rangeEnd) {
    const minute = parseMinute(value);
    const start = parseMinute(rangeStart);
    const rawEnd = parseMinute(rangeEnd);
    if (minute === null || start === null || rawEnd === null || minute % stepMinutes !== 0) return false;
    const end = rawEnd < start ? rawEnd + 24 * 60 : rawEnd;
    const normalized = minute < start ? minute + 24 * 60 : minute;
    return normalized >= start && normalized <= end;
  }
  function parseMinute(value) {
    const match = /^(\d{2}):(\d{2})$/.exec(value);
    if (match === null) return null;
    const hour = Number(match[1]);
    const minute = Number(match[2]);
    return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 ? hour * 60 + minute : null;
  }
  function steppedTimePickerOption(options, currentValue, direction) {
    if (options.length === 0) return null;
    const currentIndex = options.findIndex((option) => option.value === currentValue);
    if (currentIndex < 0) {
      return direction === 1 ? options[0] : options[options.length - 1];
    }
    const nextIndex = (currentIndex + direction + options.length) % options.length;
    return options[nextIndex] ?? null;
  }

  // frontend/ts/app-time-picker.ts
  var modalControls = /* @__PURE__ */ new WeakMap();
  var fieldControls = /* @__PURE__ */ new WeakMap();
  var digitBuffers = /* @__PURE__ */ new WeakMap();
  var digitBufferResetMs = 2e3;
  var activeField = null;
  function defaultDiagnosticReporter5(diagnostic11) {
    console.error?.("Invalid generated time picker configuration", diagnostic11);
  }
  function reportError(report, code, fieldName, error) {
    report({
      code,
      fieldName,
      message: error instanceof Error ? error.message : String(error)
    });
  }
  function getModalElement() {
    const modal = document.getElementById(timePickerModalDomId);
    return isHTMLElement(modal) ? modal : null;
  }
  function getBootstrapModal(modal) {
    if (modal === null || window.bootstrap?.Modal === void 0) return null;
    return window.bootstrap.Modal.getOrCreateInstance(modal);
  }
  function roleElements(root, attribute) {
    return Array.from(root.querySelectorAll(`[${attribute}]`));
  }
  function singleRoleElement(root, attribute) {
    const elements = roleElements(root, attribute);
    return elements.length === 1 ? elements[0] : null;
  }
  function readModalControl(report) {
    const modal = getModalElement();
    if (modal === null) {
      reportError(report, "invalid-modal", null, new Error(`Missing #${timePickerModalDomId}`));
      return null;
    }
    const existing = modalControls.get(modal);
    if (existing !== void 0) return existing;
    const grid = singleRoleElement(modal, timePickerOptionsDomAttr);
    const clear = singleRoleElement(modal, timePickerClearDomAttr);
    if (!(grid instanceof HTMLElement) || !(clear instanceof HTMLButtonElement)) {
      reportError(report, "invalid-modal", null, new Error("Time picker modal must contain one generated options grid and clear button"));
      return null;
    }
    const renderedOptions = [];
    const optionByElement = /* @__PURE__ */ new Map();
    try {
      for (const element of roleElements(grid, timePickerOptionDomAttr)) {
        if (!(element instanceof HTMLButtonElement)) {
          throw new Error("Time picker option role must belong to a button");
        }
        const rawConfig = element.getAttribute(timePickerOptionDomAttr);
        if (rawConfig === null) throw new Error(`Missing ${timePickerOptionDomAttr}`);
        const config = parseTimePickerOptionConfiguration(rawConfig);
        if (element.textContent?.trim() !== config.label) {
          throw new Error(`Time picker option ${config.value} label disagrees with rendered copy`);
        }
        const rendered = { element, config };
        renderedOptions.push(rendered);
        optionByElement.set(element, rendered);
      }
      if (renderedOptions.length === 0) {
        throw new Error("Time picker modal must render at least one generated option");
      }
      const optionValues = new Set(renderedOptions.map((option) => option.config.value));
      if (optionValues.size !== renderedOptions.length) {
        throw new Error("Time picker modal option values must be unique");
      }
    } catch (error) {
      reportError(report, "invalid-option", null, error);
      return null;
    }
    const control = { modal, grid, clear, options: renderedOptions, optionByElement };
    modalControls.set(modal, control);
    return control;
  }
  function getOptionalButton(field, attribute) {
    const elements = roleElements(field, attribute);
    if (elements.length === 0) return null;
    if (elements.length === 1 && elements[0] instanceof HTMLButtonElement) return elements[0];
    return void 0;
  }
  function readFieldControl(field, modal, report) {
    const existing = fieldControls.get(field);
    if (existing !== void 0) return existing;
    const rawConfig = field.getAttribute(timePickerConfigDomAttr);
    let config;
    try {
      if (rawConfig === null) throw new Error(`Missing ${timePickerConfigDomAttr}`);
      config = parseTimePickerConfiguration(rawConfig);
    } catch (error) {
      reportError(report, "invalid-field-config", null, error);
      return null;
    }
    const input = singleRoleElement(field, timePickerValueDomAttr);
    const trigger = singleRoleElement(field, timePickerTriggerDomAttr);
    const label = singleRoleElement(field, timePickerLabelDomAttr);
    const stepDown = getOptionalButton(field, timePickerStepDownDomAttr);
    const stepUp = getOptionalButton(field, timePickerStepUpDomAttr);
    const fieldName = input instanceof HTMLInputElement && input.name.length > 0 ? input.name : null;
    if (!(input instanceof HTMLInputElement) || input.type !== "hidden" || input.name.length === 0 || !(trigger instanceof HTMLButtonElement) || !(label instanceof HTMLElement) || !trigger.contains(label) || stepDown === void 0 || stepUp === void 0 || stepDown === null !== (stepUp === null)) {
      reportError(
        report,
        "invalid-field-structure",
        fieldName,
        new Error("Time picker field must contain one named hidden value, trigger/label pair, and either both or neither step buttons")
      );
      return null;
    }
    let selectedConfigs;
    try {
      selectedConfigs = timePickerOptionsForConfiguration(config, modal.options.map((option) => option.config));
    } catch (error) {
      reportError(report, "invalid-field-config", fieldName, error);
      return null;
    }
    const allOptionsByValue = new Map(modal.options.map((option) => [option.config.value, option]));
    const selectedOptions = [];
    for (const option of selectedConfigs) {
      const renderedOption = allOptionsByValue.get(option.value);
      if (renderedOption === void 0) {
        reportError(report, "invalid-field-config", fieldName, new Error("Time picker field resolved an option outside the rendered inventory"));
        return null;
      }
      selectedOptions.push(renderedOption);
    }
    if (input.value !== "" && !allOptionsByValue.has(input.value)) {
      reportError(report, "invalid-field-value", fieldName, new Error(`Time picker value ${input.value} has no Haskell-rendered option`));
      return null;
    }
    const control = {
      field,
      input,
      trigger,
      label,
      stepDown,
      stepUp,
      config,
      options: selectedOptions,
      allOptionsByValue,
      keyboardEnabled: trigger.hasAttribute(timePickerKeyboardDomAttr)
    };
    fieldControls.set(field, control);
    return control;
  }
  function labelForValue(control, value) {
    if (value === "") return control.config.emptyLabel;
    return control.allOptionsByValue.get(value)?.config.label ?? null;
  }
  function synchronizeField(control) {
    const currentValue = control.input.value;
    const label = labelForValue(control, currentValue);
    if (label !== null) {
      control.label.textContent = label;
      control.label.classList.toggle("app-muted", currentValue === "");
    }
    const selectedIndex = control.options.findIndex((option) => option.config.value === currentValue);
    const hasSelection = selectedIndex >= 0;
    control.trigger.disabled = control.input.disabled;
    if (control.stepDown !== null) {
      control.stepDown.disabled = control.input.disabled || !hasSelection || selectedIndex === 0;
    }
    if (control.stepUp !== null) {
      control.stepUp.disabled = control.input.disabled || !hasSelection || selectedIndex === control.options.length - 1;
    }
  }
  function applyTimeValue(control, value, label) {
    if (control.input.disabled) return;
    const previousValue = control.input.value;
    control.label.textContent = label;
    control.label.classList.toggle("app-muted", value === "");
    if (previousValue === value) return;
    control.input.value = value;
    control.input.dispatchEvent(new Event("input", { bubbles: true }));
    if (window.htmx?.trigger !== void 0) {
      window.htmx.trigger(control.input, "change");
    } else {
      control.input.dispatchEvent(new Event("change", { bubbles: true }));
    }
  }
  function renderFieldOptions(modal, field) {
    modal.grid.replaceChildren(...field.options.map((option) => option.element));
  }
  function restoreModalOptions(modal) {
    modal.grid.replaceChildren(...modal.options.map((option) => option.element));
  }
  function highlightSelectedOption(modal, value) {
    for (const option of modal.options) {
      const selected = value !== "" && option.config.value === value;
      option.element.classList.toggle("active", selected);
      option.element.classList.toggle("btn-primary", selected);
      option.element.classList.toggle("btn-outline-secondary", !selected);
    }
  }
  function forceHideModal(modal) {
    modal.modal.classList.remove("show");
    modal.modal.style.display = "none";
    modal.modal.setAttribute("aria-hidden", "true");
    modal.modal.removeAttribute("aria-modal");
    document.body.classList.remove("modal-open");
    document.body.style.removeProperty("padding-right");
    document.querySelectorAll(".modal-backdrop").forEach((backdrop) => backdrop.remove());
    restoreModalOptions(modal);
    activeField = null;
  }
  function hideTimePickerModal(modal) {
    const bootstrapModal = getBootstrapModal(modal.modal);
    if (bootstrapModal === null) {
      forceHideModal(modal);
      modal.modal.dispatchEvent(new CustomEvent("hidden.bs.modal", { bubbles: true }));
      return;
    }
    const hideAfterShown = () => getBootstrapModal(modal.modal)?.hide();
    const removePendingHide = () => modal.modal.removeEventListener("shown.bs.modal", hideAfterShown);
    modal.modal.addEventListener("shown.bs.modal", hideAfterShown, { once: true });
    modal.modal.addEventListener("hidden.bs.modal", removePendingHide, { once: true });
    bootstrapModal.hide();
  }
  function stepFieldValue(control, direction, wrap) {
    if (control.input.disabled) return;
    const option = wrap ? steppedTimePickerOption(control.options.map((candidate) => candidate.config), control.input.value, direction) : (() => {
      const selectedIndex = control.options.findIndex((candidate) => candidate.config.value === control.input.value);
      return selectedIndex < 0 ? null : control.options[selectedIndex + direction]?.config ?? null;
    })();
    if (option === null) {
      synchronizeField(control);
      return;
    }
    applyTimeValue(control, option.value, option.label);
    synchronizeField(control);
  }
  function applyWholeHourDigit(control, digit, now) {
    const previous = digitBuffers.get(control.input);
    const digits = previous === void 0 || now - previous.lastTypedAt > digitBufferResetMs ? digit : previous.digits.length >= 4 ? previous.digits : previous.digits + digit;
    digitBuffers.set(control.input, { digits, lastTypedAt: now });
    const value = compactTimePickerValue(digits, control.config.stepMinutes, control.config.rangeStart, control.config.rangeEnd);
    const option = value === null ? null : control.options.find((candidate) => candidate.config.value === value)?.config ?? null;
    if (option === null) return;
    applyTimeValue(control, option.value, option.label);
    synchronizeField(control);
  }
  function movePickerHighlight(modal, control, direction) {
    const activeValue = control.options.find((option2) => option2.element.classList.contains("active"))?.config.value ?? control.input.value;
    const option = steppedTimePickerOption(control.options.map((candidate) => candidate.config), activeValue, direction);
    if (option === null) return;
    highlightSelectedOption(modal, option.value);
    control.allOptionsByValue.get(option.value)?.element.scrollIntoView({ block: "nearest" });
  }
  function selectHighlightedPickerOption(modal, control) {
    const option = control.options.find((candidate) => candidate.element.classList.contains("active"));
    if (option === void 0) return;
    applyTimeValue(control, option.config.value, option.config.label);
    synchronizeField(control);
    hideTimePickerModal(modal);
  }
  function fieldFromTarget(target, modal, report) {
    const field = closestHTMLElement(target, `[${timePickerFieldDomAttr}]`);
    return field === null ? null : readFieldControl(field, modal, report);
  }
  function timePickerFieldsWithin(target) {
    const root = rootFromTarget(target);
    const fields = Array.from(root.querySelectorAll(`[${timePickerFieldDomAttr}]`)).filter(isHTMLElement);
    if (root instanceof HTMLElement && root.hasAttribute(timePickerFieldDomAttr)) fields.unshift(root);
    return fields;
  }
  function initializeTimePickerFields(target, report = defaultDiagnosticReporter5) {
    const fields = timePickerFieldsWithin(target);
    if (fields.length === 0) return;
    const modal = readModalControl(report);
    if (modal === null) return;
    for (const field of fields) {
      const valueControl = singleRoleElement(field, timePickerValueDomAttr);
      if (valueControl instanceof HTMLInputElement && valueControl.type === "time") continue;
      const control = readFieldControl(field, modal, report);
      if (control !== null) synchronizeField(control);
    }
  }
  function enableQuarterHourTimePicker() {
    if (typeof window === "undefined") return;
    document.addEventListener("keydown", (event) => {
      const modalElement = getModalElement();
      if (modalElement === null || !modalElement.classList.contains("show")) return;
      const modal = readModalControl(defaultDiagnosticReporter5);
      if (modal === null) return;
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopImmediatePropagation();
        hideTimePickerModal(modal);
        return;
      }
      if (activeField === null || !activeField.keyboardEnabled) return;
      const direction = event.key === "ArrowUp" || event.key === "ArrowRight" ? 1 : event.key === "ArrowDown" || event.key === "ArrowLeft" ? -1 : null;
      if (direction !== null) {
        event.preventDefault();
        event.stopImmediatePropagation();
        movePickerHighlight(modal, activeField, direction);
        return;
      }
      if (event.key === "Enter") {
        event.preventDefault();
        event.stopImmediatePropagation();
        selectHighlightedPickerOption(modal, activeField);
      }
    }, true);
    document.addEventListener("keydown", (event) => {
      const nativeInput = closestHTMLElement(event.target, `input[type='time'][${timePickerValueDomAttr}][${timePickerKeyboardDomAttr}]`);
      if (!(nativeInput instanceof HTMLInputElement) || nativeInput.disabled || !/^\d$/.test(event.key)) return;
      const field = nativeInput.closest(`[${timePickerFieldDomAttr}]`);
      if (!(field instanceof HTMLElement)) return;
      const rawConfig = field.getAttribute(timePickerConfigDomAttr);
      if (rawConfig === null) return;
      let config;
      try {
        config = parseTimePickerConfiguration(rawConfig);
      } catch (error) {
        reportError(defaultDiagnosticReporter5, "invalid-field-config", nativeInput.name || null, error);
        return;
      }
      event.preventDefault();
      const now = Date.now();
      const previous = digitBuffers.get(nativeInput);
      const digits = previous === void 0 || now - previous.lastTypedAt > digitBufferResetMs ? event.key : previous.digits.length >= 4 ? previous.digits : previous.digits + event.key;
      digitBuffers.set(nativeInput, { digits, lastTypedAt: now });
      const value = compactTimePickerValue(digits, config.stepMinutes, config.rangeStart, config.rangeEnd);
      if (value === null || value === nativeInput.value) return;
      nativeInput.value = value;
      nativeInput.dispatchEvent(new Event("input", { bubbles: true }));
      nativeInput.dispatchEvent(new Event("change", { bubbles: true }));
    });
    document.addEventListener("keydown", (event) => {
      const trigger = closestHTMLElement(event.target, `[${timePickerTriggerDomAttr}]`);
      if (!(trigger instanceof HTMLButtonElement) || trigger.disabled) return;
      const modal = readModalControl(defaultDiagnosticReporter5);
      if (modal === null) return;
      const field = fieldFromTarget(trigger, modal, defaultDiagnosticReporter5);
      if (field === null || !field.keyboardEnabled || field.input.disabled) return;
      const direction = event.key === "ArrowUp" || event.key === "ArrowRight" ? 1 : event.key === "ArrowDown" || event.key === "ArrowLeft" ? -1 : null;
      if (direction !== null) {
        event.preventDefault();
        digitBuffers.delete(field.input);
        stepFieldValue(field, direction, true);
        return;
      }
      if (/^\d$/.test(event.key)) {
        event.preventDefault();
        applyWholeHourDigit(field, event.key, Date.now());
      }
    });
    document.addEventListener("click", (event) => {
      const trigger = closestHTMLElement(event.target, `[${timePickerTriggerDomAttr}]`);
      if (!(trigger instanceof HTMLButtonElement) || trigger.disabled) return;
      const modal = readModalControl(defaultDiagnosticReporter5);
      if (modal === null) return;
      const field = fieldFromTarget(trigger, modal, defaultDiagnosticReporter5);
      const bootstrapModal = getBootstrapModal(modal.modal);
      if (field === null || field.input.disabled || bootstrapModal === null) return;
      activeField = field;
      renderFieldOptions(modal, field);
      highlightSelectedOption(modal, field.input.value);
      bootstrapModal.show();
    });
    document.addEventListener("click", (event) => {
      const stepDown = closestHTMLElement(event.target, `[${timePickerStepDownDomAttr}]`);
      if (!(stepDown instanceof HTMLButtonElement) || stepDown.disabled) return;
      const modal = readModalControl(defaultDiagnosticReporter5);
      if (modal === null) return;
      const field = fieldFromTarget(stepDown, modal, defaultDiagnosticReporter5);
      if (field !== null) stepFieldValue(field, -1, false);
    });
    document.addEventListener("click", (event) => {
      const stepUp = closestHTMLElement(event.target, `[${timePickerStepUpDomAttr}]`);
      if (!(stepUp instanceof HTMLButtonElement) || stepUp.disabled) return;
      const modal = readModalControl(defaultDiagnosticReporter5);
      if (modal === null) return;
      const field = fieldFromTarget(stepUp, modal, defaultDiagnosticReporter5);
      if (field !== null) stepFieldValue(field, 1, false);
    });
    document.addEventListener("click", (event) => {
      const optionElement = closestHTMLElement(event.target, `[${timePickerOptionDomAttr}]`);
      if (!(optionElement instanceof HTMLButtonElement) || activeField === null) return;
      const modal = readModalControl(defaultDiagnosticReporter5);
      if (modal === null) return;
      const renderedOption = modal.optionByElement.get(optionElement);
      if (renderedOption === void 0 || !modal.grid.contains(optionElement)) return;
      try {
        const rawConfig = optionElement.getAttribute(timePickerOptionDomAttr);
        if (rawConfig === null) throw new Error(`Missing ${timePickerOptionDomAttr}`);
        const currentConfig = parseTimePickerOptionConfiguration(rawConfig);
        if (currentConfig.value !== renderedOption.config.value || currentConfig.label !== renderedOption.config.label) {
          throw new Error("Time picker option payload changed after initialization");
        }
      } catch (error) {
        reportError(defaultDiagnosticReporter5, "invalid-option", activeField.input.name, error);
        return;
      }
      applyTimeValue(activeField, renderedOption.config.value, renderedOption.config.label);
      highlightSelectedOption(modal, renderedOption.config.value);
      synchronizeField(activeField);
      hideTimePickerModal(modal);
    });
    document.addEventListener("click", (event) => {
      const clear = closestHTMLElement(event.target, `[${timePickerClearDomAttr}]`);
      if (!(clear instanceof HTMLButtonElement) || activeField === null) return;
      const modal = readModalControl(defaultDiagnosticReporter5);
      if (modal === null || clear !== modal.clear) return;
      applyTimeValue(activeField, "", activeField.config.emptyLabel);
      highlightSelectedOption(modal, "");
      synchronizeField(activeField);
      hideTimePickerModal(modal);
    });
    document.addEventListener("hidden.bs.modal", (event) => {
      if (!(event.target instanceof HTMLElement) || event.target.id !== timePickerModalDomId) return;
      const modal = modalControls.get(event.target);
      if (modal !== void 0) restoreModalOptions(modal);
      activeField = null;
    });
    onAppPageReady((event) => {
      initializeTimePickerFields(detailTarget(event, "target"));
    });
    onHtmxLoad((event) => {
      initializeTimePickerFields(detailTarget(event, "elt"));
    });
    if (document.readyState !== "loading") {
      initializeTimePickerFields(document.body);
    }
  }
  enableQuarterHourTimePicker();

  // frontend/ts/horizontal-scroll/configuration.ts
  function parseHorizontalSnapConfiguration(raw) {
    const config = parseHorizontalSnapConfig(JSON.parse(raw));
    if (config.snapMode === "nearest-item") {
      if (config.itemSelector === null || config.itemSelector.trim() === "") {
        throw new Error("nearest-item snap requires itemSelector");
      }
      if (config.groupCount !== null || config.groupProperty !== null || config.groupScopeSelector !== null) {
        throw new Error("nearest-item snap must not declare equal-group configuration");
      }
      return config;
    }
    if (config.itemSelector !== null) {
      throw new Error("equal-groups snap must not declare itemSelector");
    }
    const hasCount = config.groupCount !== null;
    const hasProperty = config.groupProperty !== null || config.groupScopeSelector !== null;
    if (hasCount === hasProperty) {
      throw new Error("equal-groups snap requires exactly one group source");
    }
    if (config.groupCount !== null && config.groupCount <= 0) {
      throw new Error("equal-groups groupCount must be positive");
    }
    if (hasProperty && (config.groupProperty === null || config.groupProperty.trim() === "" || config.groupScopeSelector === null || config.groupScopeSelector.trim() === "")) {
      throw new Error("equal-groups CSS source must include property and scope selector");
    }
    return config;
  }
  function parseHorizontalDragConfiguration(raw) {
    const config = parseHorizontalDragConfig(JSON.parse(raw));
    if (config.ignoreSelector !== null && config.ignoreSelector.trim() === "") {
      throw new Error("horizontal drag ignoreSelector must not be empty");
    }
    return config;
  }

  // frontend/ts/horizontal-scroll/math.ts
  function parsePositiveIntegerForHorizontalScroll(value) {
    const parsed = Number.parseInt(value || "", 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
  }
  function clampHorizontalScrollLeft(scrollLeft, scrollWidth, clientWidth) {
    const maxScrollLeft = Math.max(0, scrollWidth - clientWidth);
    return Math.min(Math.max(0, scrollLeft), maxScrollLeft);
  }

  // frontend/ts/app-horizontal-scroll.ts
  var snapSelector = `[${horizontalScrollSnapDomAttr}]`;
  var dragSelector = `[${horizontalScrollDragDomAttr}]`;
  var capabilitySelector = `${snapSelector}, ${dragSelector}`;
  var phoneMediaQuery = "(max-width: 575.98px)";
  var interactiveIgnoreSelector = [
    "a",
    "button",
    "input",
    "select",
    "textarea",
    "label",
    '[role="button"]',
    '[role="link"]'
  ].join(", ");
  var snapDraggingClass = "is-horizontal-snap-dragging";
  var dragDraggingClass = "is-horizontal-dragging";
  var snapDebounceMs = 120;
  var snapTolerancePx = 1;
  var dragThresholdPx = 6;
  var clickSuppressionMs = 250;
  function defaultDiagnosticReporter6(diagnostic11) {
    console.error?.("Invalid generated horizontal-scroll configuration", diagnostic11);
  }
  function readConfig(element, attribute, parse) {
    const raw = element.getAttribute(attribute);
    if (raw === null) throw new Error(`Missing ${attribute}`);
    return parse(raw);
  }
  function validateLocalSelectors(element, snapConfig, dragConfig) {
    if (snapConfig?.itemSelector !== null && snapConfig?.itemSelector !== void 0) {
      element.querySelector(snapConfig.itemSelector);
    }
    if (snapConfig?.groupScopeSelector !== null && snapConfig?.groupScopeSelector !== void 0) {
      element.closest(snapConfig.groupScopeSelector);
    }
    if (dragConfig?.ignoreSelector !== null && dragConfig?.ignoreSelector !== void 0) {
      element.matches(dragConfig.ignoreSelector);
    }
  }
  var HorizontalScrollControl = class {
    constructor(element, snapConfig, dragConfig) {
      this.abortController = new AbortController();
      this.pointerAbortController = null;
      this.timerId = null;
      this.generation = 0;
      this.pointerIds = /* @__PURE__ */ new Set();
      this.touchIds = /* @__PURE__ */ new Set();
      this.activeDrag = null;
      this.suppressClickUntil = 0;
      this.onPointerDown = (event) => {
        if (this.snappingIsEnabled()) {
          this.bumpGeneration();
          this.pointerIds.add(event.pointerId);
          this.element.classList.add(snapDraggingClass);
          this.startPointerTracking();
        }
        if (this.dragConfig === null || event.pointerType !== "mouse" || event.button !== 0 || this.targetIsIgnored(event.target) || this.element.scrollWidth <= this.element.clientWidth) return;
        this.activeDrag = {
          pointerId: event.pointerId,
          startX: event.clientX,
          startScrollLeft: this.element.scrollLeft,
          isDragging: false,
          didDrag: false
        };
        this.startPointerTracking();
        try {
          this.element.setPointerCapture(event.pointerId);
        } catch (_error) {
        }
      };
      this.onPointerMove = (event) => {
        const drag = this.activeDrag;
        if (drag === null || event.pointerId !== drag.pointerId) return;
        const deltaX = event.clientX - drag.startX;
        if (!drag.isDragging && Math.abs(deltaX) < dragThresholdPx) return;
        if (!drag.isDragging) {
          drag.isDragging = true;
          drag.didDrag = true;
          this.element.classList.add(dragDraggingClass);
          if (this.snappingIsEnabled()) this.element.classList.add(snapDraggingClass);
          window.getSelection?.()?.removeAllRanges();
        }
        this.element.scrollLeft = drag.startScrollLeft - deltaX;
        event.preventDefault();
      };
      this.onPointerUp = (event) => this.finishPointer(event, true);
      this.onPointerCancel = (event) => this.finishPointer(event, false);
      this.onTouchStart = (event) => {
        if (!this.snappingIsEnabled()) return;
        this.bumpGeneration();
        for (const touch of Array.from(event.changedTouches)) this.touchIds.add(touch.identifier);
        this.element.classList.add(snapDraggingClass);
      };
      this.onTouchEnd = (event) => {
        for (const touch of Array.from(event.changedTouches)) this.touchIds.delete(touch.identifier);
        this.releaseSnapInput();
      };
      this.onWheel = () => {
        if (this.snappingIsEnabled()) this.bumpGeneration();
      };
      this.onScroll = () => this.scheduleSnap();
      this.onClick = (event) => {
        if (Date.now() <= this.suppressClickUntil) {
          event.preventDefault();
          event.stopPropagation();
        }
      };
      this.element = element;
      this.snapConfig = snapConfig;
      this.dragConfig = dragConfig;
      this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
      const options = { capture: true, signal: this.abortController.signal };
      element.addEventListener("pointerdown", this.onPointerDown, options);
      element.addEventListener("touchstart", this.onTouchStart, options);
      element.addEventListener("touchend", this.onTouchEnd, options);
      element.addEventListener("touchcancel", this.onTouchEnd, options);
      element.addEventListener("wheel", this.onWheel, options);
      element.addEventListener("scroll", this.onScroll, options);
      element.addEventListener("click", this.onClick, options);
    }
    dispose() {
      this.abortController.abort();
      this.stopPointerTracking();
      this.clearTimer();
      this.pointerIds.clear();
      this.touchIds.clear();
      this.activeDrag = null;
      this.element.classList.remove(snapDraggingClass, dragDraggingClass);
    }
    snappingIsEnabled() {
      return this.snapConfig !== null && window.matchMedia(phoneMediaQuery).matches;
    }
    clearTimer() {
      if (this.timerId !== null) {
        window.clearTimeout(this.timerId);
        this.timerId = null;
      }
    }
    bumpGeneration() {
      this.generation += 1;
      this.clearTimer();
    }
    inputIsActive() {
      return this.pointerIds.size > 0 || this.touchIds.size > 0 || this.activeDrag?.isDragging === true;
    }
    scheduleSnap() {
      if (!this.snappingIsEnabled() || this.inputIsActive()) return;
      this.clearTimer();
      const scheduledGeneration = this.generation;
      this.timerId = window.setTimeout(() => {
        this.timerId = null;
        if (this.generation !== scheduledGeneration || this.inputIsActive()) return;
        this.snap();
      }, snapDebounceMs);
    }
    releaseSnapInput() {
      if (this.inputIsActive()) return;
      this.element.classList.remove(snapDraggingClass);
      this.scheduleSnap();
    }
    smoothScrollTo(scrollLeft) {
      const targetLeft = clampHorizontalScrollLeft(
        scrollLeft,
        this.element.scrollWidth,
        this.element.clientWidth
      );
      if (Math.abs(this.element.scrollLeft - targetLeft) <= snapTolerancePx) return;
      this.element.scrollTo({
        left: targetLeft,
        behavior: this.reducedMotion.matches ? "auto" : "smooth"
      });
    }
    groupCount() {
      if (this.snapConfig === null || this.snapConfig.snapMode !== "equal-groups") return 1;
      if (this.snapConfig.groupCount !== null) return this.snapConfig.groupCount;
      if (this.snapConfig.groupProperty === null || this.snapConfig.groupScopeSelector === null) return 1;
      const styleSource = this.element.closest(this.snapConfig.groupScopeSelector);
      if (!(styleSource instanceof Element)) return 1;
      return parsePositiveIntegerForHorizontalScroll(
        window.getComputedStyle(styleSource).getPropertyValue(this.snapConfig.groupProperty)
      ) ?? 1;
    }
    snap() {
      if (this.snapConfig === null) return;
      if (this.snapConfig.snapMode === "equal-groups") {
        const groupWidth = this.element.scrollWidth / this.groupCount();
        if (Number.isFinite(groupWidth) && groupWidth > 0) {
          this.smoothScrollTo(Math.round(this.element.scrollLeft / groupWidth) * groupWidth);
        }
        return;
      }
      if (this.snapConfig.itemSelector === null) return;
      const items = Array.from(this.element.querySelectorAll(this.snapConfig.itemSelector)).filter((item) => item instanceof HTMLElement);
      const containerRect = this.element.getBoundingClientRect();
      const center = containerRect.left + containerRect.width / 2;
      let nearest = null;
      for (const item of items) {
        const rect2 = item.getBoundingClientRect();
        const distance = Math.abs(rect2.left + rect2.width / 2 - center);
        if (nearest === null || distance < nearest.distance) nearest = { element: item, distance };
      }
      if (nearest === null) return;
      const rect = nearest.element.getBoundingClientRect();
      this.smoothScrollTo(this.element.scrollLeft + rect.left + rect.width / 2 - center);
    }
    targetIsIgnored(target) {
      if (!(target instanceof Element)) return false;
      const custom = this.dragConfig?.ignoreSelector;
      const selector = custom === null || custom === void 0 ? interactiveIgnoreSelector : `${interactiveIgnoreSelector}, ${custom}`;
      return target.closest(selector) !== null;
    }
    startPointerTracking() {
      if (this.pointerAbortController !== null) return;
      this.pointerAbortController = new AbortController();
      const options = { capture: true, signal: this.pointerAbortController.signal };
      document.addEventListener("pointermove", this.onPointerMove, options);
      document.addEventListener("pointerup", this.onPointerUp, options);
      document.addEventListener("pointercancel", this.onPointerCancel, options);
    }
    stopPointerTracking() {
      this.pointerAbortController?.abort();
      this.pointerAbortController = null;
    }
    finishPointer(event, scheduleAfterRelease) {
      const drag = this.activeDrag;
      const ownsDrag = drag !== null && event.pointerId === drag.pointerId;
      if (!ownsDrag && !this.pointerIds.has(event.pointerId)) return;
      if (drag !== null && ownsDrag) {
        this.activeDrag = null;
        this.element.classList.remove(dragDraggingClass);
        try {
          this.element.releasePointerCapture(drag.pointerId);
        } catch (_error) {
        }
        if (drag.didDrag) {
          this.suppressClickUntil = Date.now() + clickSuppressionMs;
          window.setTimeout(() => {
            if (Date.now() >= this.suppressClickUntil) this.suppressClickUntil = 0;
          }, clickSuppressionMs);
        }
      }
      this.pointerIds.delete(event.pointerId);
      if (this.pointerIds.size === 0 && this.activeDrag === null) {
        this.stopPointerTracking();
      }
      if (scheduleAfterRelease || !ownsDrag) this.releaseSnapInput();
      else if (!this.inputIsActive()) this.element.classList.remove(snapDraggingClass);
    }
  };
  var controls = /* @__PURE__ */ new Map();
  function controlFor(element, report) {
    const existing = controls.get(element);
    if (existing !== void 0) return existing;
    let snapConfig = null;
    if (element.hasAttribute(horizontalScrollSnapDomAttr)) {
      try {
        snapConfig = readConfig(element, horizontalSnapConfigDomAttr, parseHorizontalSnapConfiguration);
      } catch (error) {
        report({
          code: "invalid-snap-config",
          elementId: element.id,
          message: error instanceof Error ? error.message : String(error)
        });
        return null;
      }
    }
    let dragConfig = null;
    if (element.hasAttribute(horizontalScrollDragDomAttr)) {
      try {
        dragConfig = readConfig(element, horizontalDragConfigDomAttr, parseHorizontalDragConfiguration);
      } catch (error) {
        report({
          code: "invalid-drag-config",
          elementId: element.id,
          message: error instanceof Error ? error.message : String(error)
        });
        return null;
      }
    }
    try {
      validateLocalSelectors(element, snapConfig, null);
    } catch (error) {
      report({
        code: "invalid-snap-config",
        elementId: element.id,
        message: error instanceof Error ? error.message : String(error)
      });
      return null;
    }
    try {
      validateLocalSelectors(element, null, dragConfig);
    } catch (error) {
      report({
        code: "invalid-drag-config",
        elementId: element.id,
        message: error instanceof Error ? error.message : String(error)
      });
      return null;
    }
    const control = new HorizontalScrollControl(element, snapConfig, dragConfig);
    controls.set(element, control);
    return control;
  }
  function capabilityElementsWithin(target) {
    const root = rootFromTarget(target);
    const elements = Array.from(root.querySelectorAll(capabilitySelector)).filter((element) => element instanceof HTMLElement);
    if (root instanceof HTMLElement && root.matches(capabilitySelector)) elements.unshift(root);
    return elements;
  }
  function initializeHorizontalScroll(target, report = defaultDiagnosticReporter6) {
    for (const element of capabilityElementsWithin(target)) controlFor(element, report);
  }
  function disposeHorizontalScroll(target) {
    const root = rootFromTarget(target);
    for (const [element, control] of controls) {
      if (element === root || root instanceof Node && root.contains(element)) {
        control.dispose();
        controls.delete(element);
      }
    }
  }
  function enableHorizontalScroll() {
    if (typeof window === "undefined") return;
    const pendingSwapScrollPositions = /* @__PURE__ */ new WeakMap();
    document.addEventListener("htmx:beforeSwap", (event) => {
      const request = detailTarget(event, "xhr");
      if (request === null || typeof request !== "object") return;
      const positions = capabilityElementsWithin(detailRoot(event, "target")).map((element) => element.scrollLeft);
      if (positions.length > 0) pendingSwapScrollPositions.set(request, positions);
    });
    document.addEventListener("htmx:afterSwap", (event) => {
      const request = detailTarget(event, "xhr");
      if (request === null || typeof request !== "object") return;
      const positions = pendingSwapScrollPositions.get(request);
      if (positions === void 0) return;
      capabilityElementsWithin(detailRoot(event, "target")).forEach((element, index) => {
        const position = positions[index];
        if (position !== void 0) {
          element.scrollLeft = clampHorizontalScrollLeft(position, element.scrollWidth, element.clientWidth);
        }
      });
      pendingSwapScrollPositions.delete(request);
    });
    onAppPageReady((event) => initializeHorizontalScroll(detailTarget(event, "target")));
    onHtmxLoad((event) => initializeHorizontalScroll(detailTarget(event, "elt")));
    document.addEventListener("htmx:beforeCleanupElement", (event) => {
      const cleanupRoot = detailTarget(event, "elt");
      if (cleanupRoot instanceof Element) disposeHorizontalScroll(cleanupRoot);
    });
    if (document.readyState !== "loading") initializeHorizontalScroll(document.body);
  }
  enableHorizontalScroll();

  // frontend/ts/roster/column-edit.ts
  var editorSelector = `[${rosterColumnEditorDomAttr}]`;
  var startSelector = `[${rosterColumnEditStartDomAttr}]`;
  var doneSelector = `[${rosterColumnEditDoneDomAttr}]`;
  var finishDelayMs = 350;
  function defaultDiagnosticReporter7(diagnostic11) {
    console.error?.("Invalid generated roster column-edit boundary", diagnostic11);
  }
  function defaultScheduler() {
    return {
      setTimeout: (handler, delayMs) => window.setTimeout(handler, delayMs),
      clearTimeout: (timerId) => window.clearTimeout(timerId)
    };
  }
  function diagnostic5(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function closestEditor(target) {
    return target.closest(editorSelector);
  }
  function ownedControls(editor, selector) {
    return Array.from(editor.querySelectorAll(selector)).filter((control) => closestEditor(control) === editor);
  }
  function stateFor2(editor, report) {
    if (editor.getAttribute(rosterColumnEditorDomAttr) !== "true") {
      report(diagnostic5(editor, "invalid-editor-role", "Roster column editor role must equal true"));
      return null;
    }
    const state = editor.getAttribute(rosterColumnEditingDomAttr);
    if (!isRosterColumnEditingState(state)) {
      report(diagnostic5(editor, "invalid-state", "Roster column-editing state is not declared by the Surface contract"));
      return null;
    }
    return state;
  }
  function createRosterColumnEditController(report = defaultDiagnosticReporter7, scheduler = defaultScheduler()) {
    const pendingFinishTimers = /* @__PURE__ */ new Map();
    function clearPendingFinish(editor) {
      const timerId = pendingFinishTimers.get(editor);
      if (timerId === void 0) return;
      scheduler.clearTimeout(timerId);
      pendingFinishTimers.delete(editor);
    }
    function reconcile(editor) {
      const state = stateFor2(editor, report);
      if (!state) return false;
      const active = state === rosterColumnEditingStates.active;
      const starts = ownedControls(editor, startSelector);
      const doneControls = ownedControls(editor, doneSelector);
      const invalidStarts = starts.filter((start2) => start2.getAttribute(rosterColumnEditStartDomAttr) !== "true");
      const invalidDoneControls = doneControls.filter((done) => done.getAttribute(rosterColumnEditDoneDomAttr) !== "true");
      invalidStarts.forEach((start2) => {
        report(diagnostic5(start2, "invalid-control-role", "Roster column-edit start role must equal true"));
      });
      invalidDoneControls.forEach((done) => {
        report(diagnostic5(done, "invalid-control-role", "Roster column-edit done role must equal true"));
      });
      if (invalidStarts.length > 0 || invalidDoneControls.length > 0) return false;
      starts.forEach((start2) => start2.setAttribute("aria-pressed", active ? "true" : "false"));
      return true;
    }
    function setState(editor, state) {
      if (!stateFor2(editor, report)) return false;
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
      if (!editor || !stateFor2(editor, report)) return false;
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
  function createLinkedHighlightController(options = {}) {
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
      options.onPinChange?.({
        mount: context.mount,
        pinRoleAttribute: context.definition.pinRoleAttribute ?? "",
        pinnedKey: state.pinnedKey
      });
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
      const mounts = Array.from(queryRoot.querySelectorAll(`[${surfaceDomAttr}]`)).filter(isElementLike5);
      if (isElementLike5(root) && root.getAttribute(surfaceDomAttr) !== null) mounts.unshift(root);
      for (const mount of mounts) {
        for (const definition of definitionsForMount3(mount)) {
          const state = stateFor3(mount, definition);
          if (state.pinnedKey && !sourceExists(mount, definition, state.pinnedKey)) {
            state.pinnedKey = null;
            if (definition.pinRoleAttribute) {
              options.onPinChange?.({
                mount,
                pinRoleAttribute: definition.pinRoleAttribute,
                pinnedKey: null
              });
            }
          }
          if (state.hoverKey && !sourceExists(mount, definition, state.hoverKey)) state.hoverKey = null;
          if (state.focusKey && !sourceExists(mount, definition, state.focusKey)) state.focusKey = null;
        }
        refreshMount(mount);
      }
    }
    function refreshMount(mount) {
      const definitions = definitionsForMount3(mount);
      clearEffectClasses(mount);
      for (const definition of definitions) {
        const state = stateFor3(mount, definition);
        const activeKey = state.pinnedKey ?? state.focusKey ?? state.hoverKey ?? defaultKeyFor(mount, definition);
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
    if (!isElementLike5(target)) return null;
    const mount = closestSurfaceMount2(target);
    if (!mount) return null;
    for (const definition of definitionsForMount3(mount)) {
      const source = closestOwnedRole(target, mount, definition.sourceRoleAttribute);
      const membershipKey = source?.getAttribute(definition.sourceRoleAttribute) ?? "";
      if (source && membershipKey !== "") return { mount, definition, source, membershipKey };
    }
    return null;
  }
  function pinContext(target) {
    if (!isElementLike5(target)) return null;
    const mount = closestSurfaceMount2(target);
    if (!mount) return null;
    for (const definition of definitionsForMount3(mount)) {
      if (!definition.pinRoleAttribute) continue;
      const pin = closestOwnedRole(target, mount, definition.pinRoleAttribute);
      const membershipKey = pin?.getAttribute(definition.pinRoleAttribute) ?? "";
      if (pin && membershipKey !== "") return { mount, definition, pin, membershipKey };
    }
    return null;
  }
  function relatedSourceMatches(context, relatedTarget) {
    if (!relatedTarget || !isElementLike5(relatedTarget)) return false;
    const relatedSource = closestOwnedRole(relatedTarget, context.mount, context.definition.sourceRoleAttribute);
    return relatedSource?.getAttribute(context.definition.sourceRoleAttribute) === context.membershipKey;
  }
  function closestOwnedRole(target, mount, attribute) {
    const candidate = target.closest(`[${attribute}]`);
    if (!isElementLike5(candidate)) return null;
    return closestSurfaceMount2(candidate) === mount ? candidate : null;
  }
  function closestSurfaceMount2(target) {
    const mount = target.closest(`[${surfaceDomAttr}]`);
    return isElementLike5(mount) ? mount : null;
  }
  function definitionsForMount3(mount) {
    const surface = mount.getAttribute(surfaceDomAttr);
    return isFrontendSurfaceName(surface) ? FrontendSurfaceLinkedHighlightRegistry[surface] : [];
  }
  function defaultKeyFor(mount, definition) {
    if (!definition.defaultRoleAttribute || !definition.activations.includes("default")) return null;
    const defaultOwner = Array.from(mount.querySelectorAll(`[${definition.defaultRoleAttribute}]`)).filter(isElementLike5).find((element) => closestSurfaceMount2(element) === mount);
    const defaultKey = defaultOwner?.getAttribute(definition.defaultRoleAttribute) ?? "";
    return defaultKey === "" ? null : defaultKey;
  }
  function sourceExists(mount, definition, membershipKey) {
    return elementsForKey(mount, definition.sourceRoleAttribute, membershipKey).length > 0;
  }
  function clearEffectClasses(mount) {
    const highlightedElements = /* @__PURE__ */ new Set();
    for (const className of effectClasses) {
      Array.from(mount.querySelectorAll(`.${className}`)).filter(isElementLike5).filter((element) => closestSurfaceMount2(element) === mount).forEach((element) => highlightedElements.add(element));
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
    return Array.from(mount.querySelectorAll(`[${attribute}]`)).filter(isElementLike5).filter((element) => closestSurfaceMount2(element) === mount);
  }
  function isElementLike5(value) {
    if (value === null || typeof value !== "object") return false;
    const candidate = value;
    return Boolean(candidate.classList) && typeof candidate.getAttribute === "function" && typeof candidate.setAttribute === "function" && typeof candidate.closest === "function" && typeof candidate.querySelectorAll === "function";
  }
  var browserRuntimeEnabled4 = false;
  function enableFrontendSurfaceLinkedHighlight(options = {}) {
    if (browserRuntimeEnabled4 || typeof document === "undefined") return;
    browserRuntimeEnabled4 = true;
    const controller = createLinkedHighlightController(options);
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
    return isElementLike5(event.relatedTarget) ? event.relatedTarget : null;
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
  function fitRosterExportText(value, maximumWidth, endEllipsis, measure) {
    if (!endEllipsis || measure(value) <= maximumWidth) return value;
    const ellipsis = "\u2026";
    if (measure(ellipsis) > maximumWidth) return "";
    const characters = Array.from(value);
    let lowerBound = 0;
    let upperBound = characters.length;
    while (lowerBound < upperBound) {
      const candidateLength = Math.ceil((lowerBound + upperBound) / 2);
      const candidate = `${characters.slice(0, candidateLength).join("")}${ellipsis}`;
      if (measure(candidate) <= maximumWidth) {
        lowerBound = candidateLength;
      } else {
        upperBound = candidateLength - 1;
      }
    }
    return `${characters.slice(0, lowerBound).join("")}${ellipsis}`;
  }
  var triggerSelector = `[${rosterImageExportTriggerDomAttr}]`;
  var projectionSelector = `[${rosterImageExportProjectionDomAttr}]`;
  var rowSelector = `[${rosterImageExportRowDomAttr}]`;
  var cellSelector = `[${rosterImageExportCellDomAttr}]`;
  var surfaceSelector = `[${surfaceDomAttr}]`;
  function defaultDiagnosticReporter8(diagnostic11) {
    console.error?.("Invalid generated roster image-export boundary", diagnostic11);
  }
  function diagnostic6(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function ownedElements3(surface, selector) {
    return Array.from(surface.querySelectorAll(selector)).filter((element) => element.closest(surfaceSelector) === surface);
  }
  function readImageExport(button, report) {
    if (button.getAttribute(rosterImageExportTriggerDomAttr) !== "true") {
      report(diagnostic6(button, "invalid-trigger-role", "Roster image-export trigger role must equal true"));
      return null;
    }
    const format = button.getAttribute(rosterImageExportFormatDomAttr);
    if (!isRosterImageExportFormatState(format) || format !== rosterImageExportFormatStates.png) {
      report(diagnostic6(button, "invalid-format", "Roster image-export format is not declared by the Surface contract"));
      return null;
    }
    let config;
    try {
      const rawConfig = button.getAttribute(rosterImageExportConfigDomAttr);
      if (rawConfig === null) throw new Error(`Missing ${rosterImageExportConfigDomAttr}`);
      config = parseRosterImageExportConfiguration(rawConfig);
    } catch (error) {
      report(diagnostic6(
        button,
        "invalid-config",
        error instanceof Error ? error.message : String(error)
      ));
      return null;
    }
    const surface = button.closest(surfaceSelector);
    if (surface === null) {
      report(diagnostic6(button, "missing-surface", "Roster image-export trigger has no generated Surface owner"));
      return null;
    }
    const projections = ownedElements3(surface, projectionSelector);
    if (projections.length !== 1) {
      report(diagnostic6(
        surface,
        "invalid-projection-count",
        "Roster image-export Surface must contain exactly one generated projection"
      ));
      return null;
    }
    const projection = projections[0];
    if (projection.getAttribute(rosterImageExportProjectionDomAttr) !== "true") {
      report(diagnostic6(projection, "invalid-projection-role", "Roster image-export projection role must equal true"));
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
        report(diagnostic6(row, "invalid-row-role", "Roster image-export row role must equal true"));
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
        report(diagnostic6(
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
    const rawCellConfig = cell.getAttribute(rosterImageExportCellDomAttr);
    if (rawCellConfig === null) throw new Error(`Missing ${rosterImageExportCellDomAttr}`);
    const cellConfig = parseRosterImageExportCellConfiguration(rawCellConfig);
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
    const measurementCanvas = document.createElement("canvas");
    const measurementContext = measurementCanvas.getContext("2d");
    if (measurementContext === null) return "";
    measurementContext.font = `${fontWeight} ${fontSize}px ${computedStyle.fontFamily || "sans-serif"}`;
    const measure = (value) => measurementContext.measureText(value).width;
    const availableTextWidth = Math.max(0, width - 16);
    const fittedLines = lines.map((line) => fitRosterExportText(
      line,
      availableTextWidth,
      cellConfig.imageExportEndEllipsis,
      measure
    ));
    let textAnchor = "middle";
    let textX = x + width / 2;
    if (textAlign === "left" || textAlign === "start") {
      textAnchor = "start";
      textX = x + 8;
    } else if (textAlign === "right" || textAlign === "end") {
      textAnchor = "end";
      textX = x + width - 8;
    }
    const tspans = fittedLines.map((line, index) => `<tspan x="${textX}" y="${startY + index * lineHeight}">${escapeXml(line)}</tspan>`).join("");
    return `<text font-family="${fontFamily}" font-size="${fontSize}" font-weight="${fontWeight}" fill="${escapeXml(textColor)}" text-anchor="${textAnchor}">${tspans}</text>`;
  }
  function exportSurfaceClass(exportStyle) {
    switch (exportStyle) {
      case "colour":
        return "roster-export-surface--colour";
      case "print":
        return "roster-export-surface--print";
      default:
        return assertNever(exportStyle);
    }
  }
  function buildExportBackgroundSvg(exportStyle, surface, width, height) {
    switch (exportStyle) {
      case "colour":
        return [
          "<defs>",
          '<linearGradient id="rosterExportBg" x1="0%" y1="0%" x2="0%" y2="100%">',
          '<stop offset="0%" stop-color="#1a2331" />',
          '<stop offset="100%" stop-color="#0f1622" />',
          "</linearGradient>",
          "</defs>",
          `<rect x="0" y="0" width="${width}" height="${height}" fill="url(#rosterExportBg)" />`
        ];
      case "print": {
        const surfaceBackground = window.getComputedStyle(surface).backgroundColor;
        return !isTransparentColor(surfaceBackground) ? [`<rect x="0" y="0" width="${width}" height="${height}" fill="${escapeXml(surfaceBackground)}" />`] : [];
      }
      default:
        return assertNever(exportStyle);
    }
  }
  function buildProjectionSvgMarkup(surface, projection, config) {
    const surfaceRect = surface.getBoundingClientRect();
    const projectionRect = projection.getBoundingClientRect();
    const width = Math.ceil(surfaceRect.width);
    const height = Math.ceil(surfaceRect.height);
    const projectionLeft = projectionRect.left - surfaceRect.left;
    const parts = [
      `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`,
      ...buildExportBackgroundSvg(config.imageExportStyle, surface, width, height)
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
      const leftBorderWidth = parsePixelValue(cellStyle.borderLeftWidth, 0);
      const leftBorderColor = escapeXml(cellStyle.borderLeftColor || "#3a4658");
      parts.push(
        `<rect x="${x}" y="${y}" width="${cellRect.width}" height="${cellRect.height}" fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}" shape-rendering="crispEdges" />`
      );
      if (leftBorderWidth > strokeWidth) {
        parts.push(
          `<line x1="${x}" y1="${y}" x2="${x}" y2="${y + cellRect.height}" stroke="${leftBorderColor}" stroke-width="${leftBorderWidth}" shape-rendering="crispEdges" />`
        );
      }
      parts.push(buildCellTextSvg(cell, x, y, cellRect.width, cellRect.height));
    });
    parts.push("</svg>");
    return { width, height, svgMarkup: parts.join("") };
  }
  async function exportSurfaceToBlob(surface, projection, config) {
    const renderSpec = buildProjectionSvgMarkup(surface, projection, config);
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
    surface.className = `roster-export-surface ${exportSurfaceClass(config.imageExportStyle)}`;
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
    try {
      const blob = await buildRosterExportBlob(projection, config, report);
      triggerBlobDownload(blob, config.imageExportFilename);
    } catch (error) {
      report(diagnostic6(
        button,
        "export-failed",
        error instanceof Error ? error.message : String(error)
      ));
      window.alert(config.imageExportFailureMessage);
    }
  }
  function enableRosterImageExport(report = defaultDiagnosticReporter8) {
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
  function roleSelector3(attribute) {
    return `[${attribute}]`;
  }
  function defaultDiagnosticReporter9(diagnostic11) {
    console.error?.("Invalid generated roster week-overview boundary", diagnostic11);
  }
  function diagnostic7(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function ownedElements4(panel, attribute) {
    return Array.from(panel.querySelectorAll(roleSelector3(attribute))).filter((element) => element.closest(panelSelector) === panel);
  }
  function readPanel(panel, report) {
    try {
      const raw = panel.getAttribute(rosterWeekOverviewPanelDomAttr);
      if (raw === null) throw new Error(`Missing ${rosterWeekOverviewPanelDomAttr}`);
      return parseRosterWeekOverviewPanelConfiguration(raw);
    } catch (error) {
      report(diagnostic7(
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
        report(diagnostic7(day, "invalid-day-state", "Week-overview day states must agree with its exact payload"));
        return null;
      }
      return config;
    } catch (error) {
      report(diagnostic7(
        day,
        "invalid-day-config",
        error instanceof Error ? error.message : String(error)
      ));
      return null;
    }
  }
  function readSingleSlot(panel, attribute, report) {
    const slots = ownedElements4(panel, attribute);
    if (slots.length !== 1) {
      report(diagnostic7(panel, "invalid-slot-count", `Week-overview panel requires exactly one ${attribute} slot`));
      return null;
    }
    const slot = slots[0];
    if (slot.getAttribute(attribute) !== "true") {
      report(diagnostic7(slot, "invalid-slot-role", `Week-overview slot ${attribute} must equal true`));
      return null;
    }
    return slot;
  }
  function readOptionalSlot(panel, attribute, report) {
    const slots = ownedElements4(panel, attribute);
    if (slots.length > 1) {
      report(diagnostic7(panel, "invalid-slot-count", `Week-overview panel permits at most one ${attribute} slot`));
      return false;
    }
    const slot = slots[0] ?? null;
    if (slot !== null && slot.getAttribute(attribute) !== "true") {
      report(diagnostic7(slot, "invalid-slot-role", `Week-overview slot ${attribute} must equal true`));
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
      report(diagnostic7(goLinkElement, "invalid-go-link", "Week-overview go-link slot must be an anchor"));
      return null;
    }
    if (!isRosterWeekOverviewAvailabilityState(details.getAttribute(rosterWeekOverviewAvailabilityDomAttr)) || !isRosterWeekOverviewClosureState(details.getAttribute(rosterWeekOverviewClosureDomAttr))) {
      report(diagnostic7(details, "invalid-details-state", "Week-overview details states must be generated values"));
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
  function updateRosterWeekOverviewSelection(panel, selectedDay, report = defaultDiagnosticReporter9) {
    if (selectedDay.closest(panelSelector) !== panel) {
      report(diagnostic7(selectedDay, "day-outside-panel", "Week-overview day is not owned by this panel"));
      return false;
    }
    if (readPanel(panel, report) === null) return false;
    const selectedConfig = readDay(selectedDay, report);
    if (selectedConfig === null) return false;
    const slots = readSlots(panel, report);
    if (slots === null) return false;
    const validDays = /* @__PURE__ */ new Map();
    for (const day of ownedElements4(panel, rosterWeekOverviewDayDomAttr)) {
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
    for (const day of ownedElements4(panel, rosterWeekOverviewDayDomAttr)) {
      const config = readDay(day, report);
      if (config?.weekOverviewDate === panelConfig.weekOverviewCurrentDate) {
        return updateRosterWeekOverviewSelection(panel, day, report);
      }
    }
    report(diagnostic7(panel, "missing-today-day", "Week-overview panel has no valid day for its Haskell-provided current date"));
    return false;
  }
  function panelForControl(control) {
    const panel = control.closest(panelSelector);
    return panel instanceof HTMLElement ? panel : null;
  }
  function enableRosterWeekOverview(report = defaultDiagnosticReporter9) {
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
          report(diagnostic7(today, "invalid-today-role", "Week-overview today role must equal true"));
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
      const selectedDay = ownedElements4(panel, rosterWeekOverviewDayDomAttr).find((day) => day.getAttribute("aria-pressed") === "true");
      if (selectedDay !== void 0) updateRosterWeekOverviewSelection(panel, selectedDay, report);
    });
  }

  // frontend/ts/roster/wage-filter.ts
  function createRosterWageFilterController(targetDocument) {
    const pinnedKeysByMount = /* @__PURE__ */ new WeakMap();
    function pinChanged(change) {
      if (change.pinRoleAttribute !== rosterStaffHighlightPinDomAttr) return;
      if (!(change.mount instanceof HTMLElement)) return;
      const ownerMount = owningRosterMount(change.mount);
      if (!ownerMount) return;
      pinnedKeysByMount.set(ownerMount, change.pinnedKey);
      const config = readWageFilterConfig(ownerMount);
      if (!config?.wageFilterEnabled) return;
      const mountConfig = readFrontendSurfaceMountElement(ownerMount);
      if (!mountConfig || mountConfig.surface !== "roster" || !mountConfig.subscription) return;
      const targetIds = new Set(config.wageFilterRefreshTargetIds);
      const fragments = mountConfig.fragments.filter((fragment) => targetIds.has(fragment.targetId)).map((fragment) => fragment.fragmentKey);
      if (fragments.length === 0) return;
      targetDocument.dispatchEvent(new CustomEvent(liveFragmentsRefreshEvent, {
        detail: {
          scope: mountConfig.subscription.scope,
          scopeKey: mountConfig.scopeKey,
          fragments
        }
      }));
    }
    function decorateRequest(event) {
      const htmxEvent = event;
      const source = htmxEvent.detail?.elt;
      if (!(source instanceof Element)) return;
      const ownerMount = source.closest(`[${surfaceDomAttr}="roster"][${surfaceConfigDomAttr}]`);
      if (!ownerMount) return;
      const config = readWageFilterConfig(ownerMount);
      const mountConfig = readFrontendSurfaceMountElement(ownerMount);
      if (!config?.wageFilterEnabled || !mountConfig || !htmxEvent.detail?.path) return;
      if (!requestTargetsWageFragment(source, ownerMount, config.wageFilterRequestTargetIds)) return;
      const requestPath = new URL(htmxEvent.detail.path, targetDocument.defaultView?.location.origin ?? "http://localhost").pathname;
      const isMountedFragmentRequest = mountConfig.fragments.some(
        (fragment) => config.wageFilterRequestTargetIds.includes(fragment.targetId) && new URL(fragment.url, targetDocument.defaultView?.location.origin ?? "http://localhost").pathname === requestPath
      );
      if (!isMountedFragmentRequest) return;
      const pinnedStaffKey = pinnedKeysByMount.get(ownerMount) ?? null;
      if (!pinnedStaffKey || !htmxEvent.detail) return;
      const encodedRequest = encodeRosterWageFilterRequest({ pinnedStaffKey });
      if (htmxEvent.detail.parameters) {
        Object.assign(htmxEvent.detail.parameters, encodedRequest);
      } else {
        htmxEvent.detail.parameters = { ...encodedRequest };
      }
    }
    function decorateFragmentUrl(url, _fragment, target) {
      const ownerMount = target.closest(`[${surfaceDomAttr}="roster"][${surfaceConfigDomAttr}]`);
      if (!ownerMount) return url;
      const config = readWageFilterConfig(ownerMount);
      if (!config?.wageFilterEnabled || !config.wageFilterRequestTargetIds.includes(target.id)) return url;
      const pinnedStaffKey = pinnedKeysByMount.get(ownerMount) ?? null;
      if (!pinnedStaffKey) return url;
      const request = encodeRosterWageFilterRequest({ pinnedStaffKey });
      const parsed = new URL(url, targetDocument.defaultView?.location.origin ?? "http://localhost");
      Object.entries(request).forEach(([name, value]) => {
        if (value !== void 0) parsed.searchParams.set(name, value);
      });
      return url.startsWith("/") ? `${parsed.pathname}${parsed.search}${parsed.hash}` : parsed.toString();
    }
    return { pinChanged, decorateRequest, decorateFragmentUrl };
  }
  function enableRosterWageFilter() {
    const controller = createRosterWageFilterController(document);
    document.addEventListener("htmx:configRequest", controller.decorateRequest);
    registerSurfaceFragmentRequestDecorator(controller.decorateFragmentUrl);
    return controller;
  }
  function owningRosterMount(interactionMount) {
    return interactionMount.closest(`[${surfaceDomAttr}="roster"][${surfaceConfigDomAttr}]`);
  }
  function readWageFilterConfig(mount) {
    const element = mount.querySelector(`[${rosterWageFilterConfigDomAttr}]`);
    if (!element) return null;
    const raw = element.getAttribute(rosterWageFilterConfigDomAttr);
    if (!raw) return null;
    try {
      return parseRosterWageFilterConfig(JSON.parse(raw));
    } catch {
      return null;
    }
  }
  function requestTargetsWageFragment(source, mount, targetIds) {
    for (const targetId of targetIds) {
      const target = mount.querySelector(`#${targetId}`);
      if (target && (target === source || target.contains(source))) return true;
    }
    return false;
  }

  // frontend/ts/app-roster.ts
  enableRosterWeekOverview();
  enableRosterColumnEditMode();
  enableRosterImageExport();
  var rosterWageFilter = enableRosterWageFilter();
  enableFrontendSurfaceLinkedHighlight({ onPinChange: rosterWageFilter.pinChanged });

  // frontend/ts/app-timesheets.ts
  var entryLinkSelector = `#${timesheetWeekShellDomToken} .timesheet-entry-card-link`;
  var pointerOpenedEntryLink = null;
  function clearTrackedEntryLink() {
    pointerOpenedEntryLink = null;
  }
  function blurTrackedEntryLinkIfFocused() {
    const linkEl = pointerOpenedEntryLink;
    clearTrackedEntryLink();
    if (!(linkEl instanceof HTMLElement)) return;
    if (!document.contains(linkEl)) return;
    if (document.activeElement === linkEl) {
      linkEl.blur();
    }
  }
  function blurPointerOpenedTimesheetEntryAfterDialogClose() {
    if (typeof window === "undefined") return;
    document.addEventListener("pointerdown", (event) => {
      if (!(event.target instanceof Element)) return;
      const linkEl = event.target.closest(entryLinkSelector);
      if (linkEl instanceof HTMLElement) {
        pointerOpenedEntryLink = linkEl;
      }
    }, true);
    document.addEventListener("keydown", clearTrackedEntryLink, true);
    document.addEventListener(dialogDismissedEvent, (event) => {
      const detail = dialogDismissedDetail(event);
      if (detail === null || detail.replacement !== null || pointerOpenedEntryLink === null) return;
      window.requestAnimationFrame(blurTrackedEntryLinkIfFocused);
    });
  }
  blurPointerOpenedTimesheetEntryAfterDialogClose();

  // frontend/ts/xero-candidate-filter/configuration.ts
  function parseXeroCandidateFilterConfiguration(raw) {
    const config = parseXeroCandidateFilterConfig(JSON.parse(raw));
    if (config.searchProjection.trim().length === 0) {
      throw new Error("XeroCandidateFilterConfig searchProjection must not be empty");
    }
    return config;
  }

  // frontend/ts/app-xero.ts
  function roleSelector4(attribute) {
    return `[${attribute}]`;
  }
  function defaultDiagnosticReporter10(diagnostic11) {
    console.error?.("Invalid generated Xero candidate filter configuration", diagnostic11);
  }
  function diagnostic8(element, code, message) {
    return {
      code,
      elementId: element.id || null,
      message
    };
  }
  function normalizeCandidateFilterQuery(value) {
    return value.trim().toLowerCase().replace(/\s+/g, " ");
  }
  function fuzzyIncludes(haystack, query) {
    if (!query) return true;
    if (haystack.includes(query)) return true;
    let haystackIndex = 0;
    for (let queryIndex = 0; queryIndex < query.length; queryIndex += 1) {
      const character = query.charAt(queryIndex);
      haystackIndex = haystack.indexOf(character, haystackIndex);
      if (haystackIndex === -1) return false;
      haystackIndex += 1;
    }
    return true;
  }
  function ownedElements5(root, attribute) {
    const rootSelector = roleSelector4(xeroCandidateFilterRootDomAttr);
    return Array.from(root.querySelectorAll(roleSelector4(attribute))).filter((element) => element.closest(rootSelector) === root);
  }
  function readXeroCandidateFilterControl(input, report) {
    const root = input.closest(roleSelector4(xeroCandidateFilterRootDomAttr));
    if (root === null) {
      report(diagnostic8(input, "missing-root", "Search input has no generated candidate-filter root"));
      return null;
    }
    if (root.getAttribute(xeroCandidateFilterRootDomAttr) !== "true") {
      report(diagnostic8(root, "invalid-root-role", "Candidate-filter root role must equal true"));
      return null;
    }
    const searches = ownedElements5(root, xeroCandidateFilterSearchDomAttr);
    if (searches.length !== 1 || searches[0] !== input) {
      report(diagnostic8(
        root,
        "invalid-search-count",
        "Candidate-filter root must contain exactly one generated search input"
      ));
      return null;
    }
    if (input.getAttribute(xeroCandidateFilterSearchDomAttr) !== "true") {
      report(diagnostic8(input, "invalid-search-role", "Candidate-filter search role must equal true"));
      return null;
    }
    const candidates = [];
    for (const element of ownedElements5(root, xeroCandidateFilterCandidateDomAttr)) {
      if (element.getAttribute(xeroCandidateFilterCandidateDomAttr) !== "true") {
        report(diagnostic8(element, "invalid-candidate-role", "Candidate role must equal true"));
        return null;
      }
      const rawConfig = element.getAttribute(xeroCandidateFilterConfigDomAttr);
      try {
        if (rawConfig === null) throw new Error(`Missing ${xeroCandidateFilterConfigDomAttr}`);
        candidates.push({
          element,
          config: parseXeroCandidateFilterConfiguration(rawConfig)
        });
      } catch (error) {
        report(diagnostic8(
          element,
          "invalid-candidate-config",
          error instanceof Error ? error.message : String(error)
        ));
        return null;
      }
    }
    const emptyStates = ownedElements5(root, xeroCandidateFilterEmptyDomAttr);
    for (const emptyState of emptyStates) {
      if (emptyState.getAttribute(xeroCandidateFilterEmptyDomAttr) !== "true") {
        report(diagnostic8(emptyState, "invalid-empty-role", "Candidate-filter empty role must equal true"));
        return null;
      }
    }
    const expectedEmptyCount = candidates.length === 0 ? 0 : 1;
    if (emptyStates.length !== expectedEmptyCount) {
      report(diagnostic8(
        root,
        "invalid-empty-count",
        `Candidate-filter root requires ${expectedEmptyCount} filtered-empty element(s)`
      ));
      return null;
    }
    return {
      candidates,
      emptyState: emptyStates[0] ?? null
    };
  }
  function updateXeroCandidateFilter(input, report = defaultDiagnosticReporter10) {
    const control = readXeroCandidateFilterControl(input, report);
    if (control === null) return;
    const query = normalizeCandidateFilterQuery(input.value || "");
    let visibleCount = 0;
    for (const candidate of control.candidates) {
      const matches = fuzzyIncludes(candidate.config.searchProjection, query);
      candidate.element.hidden = !matches;
      if (matches) visibleCount += 1;
    }
    if (control.emptyState !== null) {
      control.emptyState.hidden = visibleCount > 0;
    }
  }
  function enableXeroCandidateFilter() {
    if (typeof window === "undefined" || typeof document === "undefined") return;
    document.addEventListener("input", (event) => {
      if (!(event.target instanceof Element)) return;
      const search = event.target.closest(roleSelector4(xeroCandidateFilterSearchDomAttr));
      if (!(search instanceof HTMLInputElement)) return;
      updateXeroCandidateFilter(search);
    });
    document.addEventListener("htmx:afterSwap", (event) => {
      const target = event.target;
      if (!(target instanceof Element || target instanceof Document)) return;
      for (const search of target.querySelectorAll(roleSelector4(xeroCandidateFilterSearchDomAttr))) {
        if (search instanceof HTMLInputElement) updateXeroCandidateFilter(search);
      }
    });
  }
  enableXeroCandidateFilter();

  // frontend/ts/app-toggle-buttons.ts
  var initializedControls = /* @__PURE__ */ new WeakMap();
  var checkedClass = "is-toggle-checked";
  function targetsEqual(left, right) {
    if (left.tag !== right.tag) return false;
    if (left.tag === "omitted" || right.tag === "omitted") return true;
    return left.value === right.value;
  }
  function parseToggleConfiguration(raw) {
    const config = parseToggleConfig(JSON.parse(raw));
    if (config.transportKey.length === 0) {
      throw new Error("Toggle transportKey must not be empty");
    }
    if (config.breakRegionKey !== null && config.breakRegionKey.length === 0) {
      throw new Error("Toggle breakRegionKey must be null or non-empty");
    }
    if (targetsEqual(config.checkedTarget, config.uncheckedTarget)) {
      throw new Error("Toggle checkedTarget and uncheckedTarget must differ");
    }
    return config;
  }
  function toggleTargetForChecked(config, checked) {
    return checked ? config.checkedTarget : config.uncheckedTarget;
  }
  function toggleTransportState(target) {
    switch (target.tag) {
      case "value":
        return { value: target.value, disabled: false };
      case "omitted":
        return { value: "", disabled: true };
      default:
        return assertNever(target);
    }
  }
  function presentationStateForChecked(checked) {
    return checked ? "checked" : "unchecked";
  }
  function defaultDiagnosticReporter11(diagnostic11) {
    console.error?.("Invalid generated toggle configuration", diagnostic11);
  }
  function diagnostic9(input, code, message) {
    return { code, inputId: input.id, message };
  }
  function elementsWithRelationship(root, attribute, key) {
    return Array.from(root.querySelectorAll(`[${attribute}]`)).filter((element) => element.getAttribute(attribute) === key);
  }
  function readToggleControl(input, report) {
    const rawConfig = input.getAttribute(toggleConfigDomAttr);
    let config;
    try {
      if (rawConfig === null) throw new Error(`Missing ${toggleConfigDomAttr}`);
      config = parseToggleConfiguration(rawConfig);
    } catch (error) {
      report(diagnostic9(input, "invalid-config", error instanceof Error ? error.message : String(error)));
      return null;
    }
    if (input.getAttribute(toggleInputDomAttr) !== config.transportKey) {
      report(diagnostic9(input, "invalid-input-key", "Toggle input relationship does not match transportKey"));
      return null;
    }
    const root = input.closest(`[${toggleRootDomAttr}]`);
    if (!(root instanceof HTMLElement)) {
      report(diagnostic9(input, "missing-root", "Toggle input has no generated root"));
      return null;
    }
    if (root.getAttribute(toggleRootDomAttr) !== config.transportKey) {
      report(diagnostic9(input, "invalid-root-key", "Toggle root relationship does not match transportKey"));
      return null;
    }
    const form = input.form;
    if (!(form instanceof HTMLFormElement)) {
      report(diagnostic9(input, "missing-form", "Toggle input must belong to a form"));
      return null;
    }
    const transports = elementsWithRelationship(form, toggleTransportDomAttr, config.transportKey);
    if (transports.length !== 1 || !(transports[0] instanceof HTMLInputElement) || transports[0].type !== "hidden" || transports[0].name.length === 0) {
      report(diagnostic9(input, "invalid-transport", "Toggle must resolve exactly one named hidden transport within input.form"));
      return null;
    }
    const transport = transports[0];
    const expectedPresentation = presentationStateForChecked(input.checked);
    if (config.presentationState !== expectedPresentation) {
      report(diagnostic9(input, "invalid-presentation-state", "Rendered checkbox state disagrees with ToggleConfig presentationState"));
      return null;
    }
    const expectedTransport = toggleTransportState(toggleTargetForChecked(config, input.checked));
    if (transport.value !== expectedTransport.value || transport.disabled !== expectedTransport.disabled) {
      report(diagnostic9(input, "invalid-transport", "Rendered transport state disagrees with ToggleConfig"));
      return null;
    }
    const labels = [];
    const seenStates = /* @__PURE__ */ new Set();
    for (const label of root.querySelectorAll(`[${toggleLabelStateDomAttr}]`)) {
      const state = label.getAttribute(toggleLabelStateDomAttr);
      if (!(label instanceof HTMLElement) || !isTogglePresentationState(state) || seenStates.has(state)) {
        report(diagnostic9(input, "invalid-label-state", "Toggle labels must use unique generated presentation states"));
        return null;
      }
      seenStates.add(state);
      labels.push({ element: label, state });
    }
    if (labels.length !== 0 && labels.length !== 2) {
      report(diagnostic9(input, "invalid-label-state", "State-labelled toggles must render checked and unchecked labels"));
      return null;
    }
    let breakRegion = null;
    if (config.breakRegionKey !== null) {
      const regions = elementsWithRelationship(form, toggleBreakRegionDomAttr, config.breakRegionKey);
      if (regions.length !== 1 || !(regions[0] instanceof HTMLFieldSetElement) || regions[0].id.length === 0 || input.getAttribute("aria-controls") !== regions[0].id) {
        report(diagnostic9(input, "invalid-break-region", "Toggle must resolve one aria-related break fieldset within input.form"));
        return null;
      }
      breakRegion = regions[0];
    }
    return { input, root, form, transport, breakRegion, labels, config };
  }
  function synchronizeToggle(control) {
    const { input, root, transport, breakRegion, labels, config } = control;
    const checked = input.checked;
    const transportState = toggleTransportState(toggleTargetForChecked(config, checked));
    transport.value = transportState.value;
    transport.disabled = transportState.disabled;
    root.classList.toggle(checkedClass, checked);
    root.setAttribute("aria-pressed", String(checked));
    if (input.getAttribute("role") === "switch") {
      input.setAttribute("aria-checked", String(checked));
    }
    for (const label of labels) {
      label.element.hidden = label.state !== presentationStateForChecked(checked);
    }
    if (breakRegion !== null) {
      breakRegion.disabled = !checked;
      breakRegion.setAttribute("aria-disabled", String(!checked));
    }
  }
  function initializeToggle(input, report) {
    const existing = initializedControls.get(input);
    if (existing !== void 0) return existing;
    const control = readToggleControl(input, report);
    if (control === null) return null;
    initializedControls.set(input, control);
    synchronizeToggle(control);
    return control;
  }
  function toggleInputsWithin(target) {
    const root = rootFromTarget(target);
    const inputs = Array.from(root.querySelectorAll(`[${toggleInputDomAttr}]`)).filter((element) => element instanceof HTMLInputElement);
    if (root instanceof HTMLInputElement && root.hasAttribute(toggleInputDomAttr)) {
      inputs.unshift(root);
    }
    return inputs;
  }
  function initializeToggleButtons(target, report = defaultDiagnosticReporter11) {
    for (const input of toggleInputsWithin(target)) {
      initializeToggle(input, report);
    }
  }
  function handleToggleChange(event) {
    if (!(event.target instanceof HTMLInputElement) || !event.target.hasAttribute(toggleInputDomAttr)) return;
    const control = initializeToggle(event.target, defaultDiagnosticReporter11);
    if (control === null) return;
    synchronizeToggle(control);
    if (control.config.submissionPolicy === "immediate") {
      control.form.requestSubmit();
    }
  }
  function enableAppToggleButtons() {
    if (typeof window === "undefined") return;
    document.addEventListener("change", handleToggleChange, true);
    onAppPageReady((event) => {
      initializeToggleButtons(detailTarget(event, "target"));
    });
    onHtmxLoad((event) => {
      initializeToggleButtons(detailTarget(event, "elt"));
    });
    if (document.readyState !== "loading") {
      initializeToggleButtons(document.body);
    }
  }
  enableAppToggleButtons();

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

  // frontend/ts/app-preferences.ts
  var initializedControls2 = /* @__PURE__ */ new WeakMap();
  function defaultDiagnosticReporter12(diagnostic11) {
    console.error?.("Invalid generated ordered-range configuration", diagnostic11);
  }
  function diagnostic10(root, code, message) {
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
      report(diagnostic10(root, "invalid-config", error instanceof Error ? error.message : String(error)));
      return null;
    }
    let state;
    const rawState = root.getAttribute(orderedRangeStateDomAttr);
    try {
      if (rawState === null) throw new Error(`Missing ${orderedRangeStateDomAttr}`);
      state = parseOrderedRangeStateConfiguration(config, rawState);
    } catch (error) {
      report(diagnostic10(root, "invalid-state", error instanceof Error ? error.message : String(error)));
      return null;
    }
    const isRangeInput = (element) => element instanceof HTMLInputElement && element.type === "range" && element.name.length > 0 && element.id.length > 0;
    const startInput = exactlyOneWithin(root, `[${orderedRangeStartDomAttr}]`, isRangeInput);
    if (startInput === null) {
      report(diagnostic10(root, "invalid-start", "Ordered range must contain exactly one named start range input"));
      return null;
    }
    const endInput = exactlyOneWithin(root, `[${orderedRangeEndDomAttr}]`, isRangeInput);
    if (endInput === null || endInput === startInput) {
      report(diagnostic10(root, "invalid-end", "Ordered range must contain exactly one distinct named end range input"));
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
      report(diagnostic10(root, "invalid-availability", "Ordered range availability role must contain exactly one native checkbox"));
      return null;
    }
    const startOutput = outputForInput(root, startInput);
    const endOutput = outputForInput(root, endInput);
    if (startOutput === null || endOutput === null || startOutput === endOutput) {
      report(diagnostic10(root, "invalid-output", "Ordered range endpoints must each have one native output relationship"));
      return null;
    }
    const expectedMinimum = String(config.minimumValue);
    const expectedMaximum = String(config.maximumValue);
    const expectedStep = String(config.stepValue);
    const renderedStateMatches = startInput.min === expectedMinimum && startInput.max === expectedMaximum && startInput.step === expectedStep && endInput.min === expectedMinimum && endInput.max === expectedMaximum && endInput.step === expectedStep && startInput.value === String(state.startValue) && endInput.value === String(state.endValue) && availabilityInput.checked === state.available && startInput.disabled === !state.available && endInput.disabled === !state.available && startOutput.textContent?.trim() === orderedRangeLabelForValue(config, state.startValue) && endOutput.textContent?.trim() === orderedRangeLabelForValue(config, state.endValue);
    if (!renderedStateMatches) {
      report(diagnostic10(root, "rendered-state-mismatch", "Rendered ordered range disagrees with its exact configuration or state"));
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
      control.report(diagnostic10(
        control.root,
        "invalid-input-value",
        error instanceof Error ? error.message : String(error)
      ));
    }
  }
  function initializeOrderedRange(root, report) {
    const existing = initializedControls2.get(root);
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
    initializedControls2.set(root, control);
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
  function initializeOrderedRanges(target, report = defaultDiagnosticReporter12) {
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
