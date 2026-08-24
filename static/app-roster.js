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
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-toolbar" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-day-columns" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-side-panel-content" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "timesheet-day-section" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["operationalDate"], ["operationalDate"]) && typeof value["params"]["operationalDate"] === "string");
  }
  function isRosterSurfaceFragmentKey(value) {
    return isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-layout" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-content" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-grid-toolbar" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-grid-frame" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-columns" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-rail" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-wage-rail" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-slots-grid" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-staff-panel" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-week-overview" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-template-library" && (value["params"] === null || isRecord(value["params"]) && hasExactKeys(value["params"], [], [])) || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-template-record" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["templateId"], ["templateId"]) && typeof value["params"]["templateId"] === "string") || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-template-draft" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["userId"], ["userId"]) && typeof value["params"]["userId"] === "string") || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-day-section" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["rosterDayId"], ["rosterDayId"]) && typeof value["params"]["rosterDayId"] === "string") || isRecord(value) && hasExactKeys(value, ["kind", "params"]) && value.kind === "roster-row" && (isRecord(value["params"]) && hasExactKeys(value["params"], ["rosterDayId", "rowIndex"], ["rosterDayId", "rowIndex"]) && typeof value["params"]["rosterDayId"] === "string" && (typeof value["params"]["rowIndex"] === "number" && Number.isInteger(value["params"]["rowIndex"])));
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
  var pageReadyEvent = "bepis:page-ready";
  var liveFragmentsRefreshEvent = "bepis:live-fragments-refresh";
  function isRosterImageExportStyle(value) {
    return typeof value === "string" && ["colour", "print"].includes(value);
  }
  function isLeaveSectionValue(value) {
    return typeof value === "string" && ["pending", "approved", "denied", "archive"].includes(value);
  }
  var surfaceDomAttr = "data-bepis-surface";
  var surfaceConfigDomAttr = "data-bepis-surface-config";
  function isTimesheetsTimesheetWeekScope(value) {
    return isRecord(value) && hasExactKeys(value, ["venueId", "windowStartDate", "windowEndDate", "rosterCalendarRevision"], ["venueId", "windowStartDate", "windowEndDate", "rosterCalendarRevision"]) && typeof value["venueId"] === "string" && typeof value["windowStartDate"] === "string" && typeof value["windowEndDate"] === "string" && (typeof value["rosterCalendarRevision"] === "number" && Number.isInteger(value["rosterCalendarRevision"]));
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
  var timesheetsTimesheetStaffHighlightSourceDomAttr = "data-bepis-timesheets-timesheet-staff-highlight-source";
  var timesheetsTimesheetStaffHighlightMemberDomAttr = "data-bepis-timesheets-timesheet-staff-highlight-member";
  var timesheetsTimesheetStaffHighlightPinDomAttr = "data-bepis-timesheets-timesheet-staff-highlight-pin";
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
  var rosterColumnEditingDomAttr = "data-bepis-roster-column-editing";
  var rosterImageExportFormatDomAttr = "data-bepis-roster-image-export-format";
  var rosterWeekOverviewAvailabilityDomAttr = "data-bepis-roster-week-overview-availability";
  var rosterWeekOverviewClosureDomAttr = "data-bepis-roster-week-overview-closure";
  var rosterWeekOverviewCalendarDayDomAttr = "data-bepis-roster-week-overview-calendar-day";
  var rosterStaffHighlightOrderDomAttr = "data-bepis-roster-staff-highlight-order";
  var rosterDayTimelineShiftGroupHighlightSourceDomAttr = "data-bepis-roster-day-timeline-shift-group-highlight-source";
  var rosterDayTimelineShiftGroupHighlightMemberDomAttr = "data-bepis-roster-day-timeline-shift-group-highlight-member";
  var leaveRequestsLeaveStaffHighlightSourceDomAttr = "data-bepis-leave-requests-leave-staff-highlight-source";
  var leaveRequestsLeaveStaffHighlightMemberDomAttr = "data-bepis-leave-requests-leave-staff-highlight-member";
  var leaveRequestsLeaveStaffHighlightPinDomAttr = "data-bepis-leave-requests-leave-staff-highlight-pin";
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
  var FrontendSurfaceLinkedHighlightRegistry = { "timesheets": [{ "name": "timesheet-staff-cards-highlight", "sourceRoleAttribute": timesheetsTimesheetStaffHighlightSourceDomAttr, "memberRoleAttribute": timesheetsTimesheetStaffHighlightMemberDomAttr, "pinRoleAttribute": timesheetsTimesheetStaffHighlightPinDomAttr, "defaultRoleAttribute": null, "orderStateAttribute": null, "activations": ["hover", "focus", "keyboard", "pin"], "effects": ["matching-source", "matching-member"] }], "roster": [{ "name": "staff-shifts-highlight", "sourceRoleAttribute": rosterStaffHighlightSourceDomAttr, "memberRoleAttribute": rosterStaffHighlightMemberDomAttr, "pinRoleAttribute": rosterStaffHighlightPinDomAttr, "defaultRoleAttribute": rosterStaffHighlightDefaultDomAttr, "orderStateAttribute": rosterStaffHighlightOrderDomAttr, "activations": ["hover", "focus", "keyboard", "pin", "default"], "effects": ["matching-source", "matching-member", "ordered-member-bounds"] }, { "name": "shift-group-highlight", "sourceRoleAttribute": rosterShiftGroupHighlightSourceDomAttr, "memberRoleAttribute": rosterShiftGroupHighlightMemberDomAttr, "pinRoleAttribute": null, "defaultRoleAttribute": null, "orderStateAttribute": null, "activations": ["hover", "focus", "keyboard"], "effects": ["matching-member"] }], "roster-day-timeline": [{ "name": "shift-group-highlight", "sourceRoleAttribute": rosterDayTimelineShiftGroupHighlightSourceDomAttr, "memberRoleAttribute": rosterDayTimelineShiftGroupHighlightMemberDomAttr, "pinRoleAttribute": null, "defaultRoleAttribute": null, "orderStateAttribute": null, "activations": ["hover", "focus", "keyboard"], "effects": ["matching-member"] }], "roster-template-designer": [], "leave-requests": [{ "name": "leave-staff-periods-highlight", "sourceRoleAttribute": leaveRequestsLeaveStaffHighlightSourceDomAttr, "memberRoleAttribute": leaveRequestsLeaveStaffHighlightMemberDomAttr, "pinRoleAttribute": leaveRequestsLeaveStaffHighlightPinDomAttr, "defaultRoleAttribute": null, "orderStateAttribute": null, "activations": ["hover", "focus", "keyboard", "pin"], "effects": ["matching-source", "matching-member"] }], "self-service-leave": [], "billing": [], "support": [], "profile": [], "staff": [], "admin-page": [], "admin-xero-page": [], "admin-venue-config": [], "admin-invites": [], "admin-exports": [], "admin-shift-types": [], "admin-roster-groups": [], "admin-xero": [] };
  var FrontendSurfaceFragmentRegistry = { "timesheets": ["timesheet-toolbar", "timesheet-day-columns", "timesheet-side-panel-content", "timesheet-day-section"], "roster": ["roster-content", "roster-grid-toolbar", "roster-grid-frame", "roster-day-columns", "roster-day-rail", "roster-wage-rail", "roster-slots-grid", "roster-staff-panel", "roster-template-library", "roster-day-section", "roster-row"], "roster-day-timeline": ["roster-day-timeline-content"], "roster-template-designer": [], "leave-requests": ["unavailability-blackouts", "leave-side-panel-content", "leave-availability-warnings", "leave-section-count", "leave-section-list"], "self-service-leave": ["self-service-leave-form", "visible-unavailability-blackouts", "self-service-leave-history"], "billing": ["billing-status"], "support": ["support-award-rates", "support-public-holidays"], "profile": ["profile-details-section", "profile-preferences-section", "profile-security-section", "profile-leave-section"], "staff": ["staff-details-section", "staff-preferences-section", "staff-visible-unavailability-blackouts", "staff-leave-section"], "admin-page": [], "admin-xero-page": [], "admin-venue-config": ["admin-venue-settings"], "admin-invites": ["admin-invites"], "admin-exports": ["admin-exports"], "admin-shift-types": ["admin-shift-types"], "admin-roster-groups": ["admin-roster-groups"], "admin-xero": ["admin-xero-shell", "admin-xero-reference-sync", "admin-xero-timesheet-preparation-wait", "admin-xero-pay-item-import-wait"] };
  function isFrontendSurfaceName(value) {
    return typeof value === "string" && Object.prototype.hasOwnProperty.call(FrontendSurfaceFragmentRegistry, value);
  }
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
  function defaultDiagnosticReporter(diagnostic4) {
    console.error?.("Invalid generated roster column-edit boundary", diagnostic4);
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
  function createLinkedHighlightController(options = {}) {
    const statesByMount = /* @__PURE__ */ new WeakMap();
    function stateFor2(mount, definition) {
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
      stateFor2(context.mount, context.definition).hoverKey = context.membershipKey;
      refreshMount(context.mount);
    }
    function pointerLeft(target, relatedTarget) {
      const context = sourceContext(target);
      if (!context || !context.definition.activations.includes("hover")) return;
      if (relatedSourceMatches(context, relatedTarget)) return;
      const state = stateFor2(context.mount, context.definition);
      if (state.hoverKey === context.membershipKey) state.hoverKey = null;
      refreshMount(context.mount);
    }
    function focusEntered(target) {
      const context = sourceContext(target);
      if (!context || !context.definition.activations.includes("focus")) return;
      stateFor2(context.mount, context.definition).focusKey = context.membershipKey;
      refreshMount(context.mount);
    }
    function focusLeft(target, relatedTarget) {
      const context = sourceContext(target);
      if (!context || !context.definition.activations.includes("focus")) return;
      if (relatedSourceMatches(context, relatedTarget)) return;
      const state = stateFor2(context.mount, context.definition);
      if (state.focusKey === context.membershipKey) state.focusKey = null;
      refreshMount(context.mount);
    }
    function togglePin(target) {
      const context = pinContext(target);
      if (!context || !context.definition.activations.includes("pin")) return false;
      const state = stateFor2(context.mount, context.definition);
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
      const mounts = Array.from(queryRoot.querySelectorAll(`[${surfaceDomAttr}]`)).filter(isElementLike);
      if (isElementLike(root) && root.getAttribute(surfaceDomAttr) !== null) mounts.unshift(root);
      for (const mount of mounts) {
        for (const definition of definitionsForMount(mount)) {
          const state = stateFor2(mount, definition);
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
      const definitions = definitionsForMount(mount);
      clearEffectClasses(mount);
      for (const definition of definitions) {
        const state = stateFor2(mount, definition);
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
  function defaultKeyFor(mount, definition) {
    if (!definition.defaultRoleAttribute || !definition.activations.includes("default")) return null;
    const defaultOwner = Array.from(mount.querySelectorAll(`[${definition.defaultRoleAttribute}]`)).filter(isElementLike).find((element) => closestSurfaceMount(element) === mount);
    const defaultKey = defaultOwner?.getAttribute(definition.defaultRoleAttribute) ?? "";
    return defaultKey === "" ? null : defaultKey;
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
  function enableFrontendSurfaceLinkedHighlight(options = {}) {
    if (browserRuntimeEnabled || typeof document === "undefined") return;
    browserRuntimeEnabled = true;
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
  function defaultDiagnosticReporter2(diagnostic4) {
    console.error?.("Invalid generated roster image-export boundary", diagnostic4);
  }
  function diagnostic2(element, code, message) {
    return { code, elementId: element.id || null, message };
  }
  function ownedElements(surface, selector) {
    return Array.from(surface.querySelectorAll(selector)).filter((element) => element.closest(surfaceSelector) === surface);
  }
  function readImageExport(button, report) {
    if (button.getAttribute(rosterImageExportTriggerDomAttr) !== "true") {
      report(diagnostic2(button, "invalid-trigger-role", "Roster image-export trigger role must equal true"));
      return null;
    }
    const format = button.getAttribute(rosterImageExportFormatDomAttr);
    if (!isRosterImageExportFormatState(format) || format !== rosterImageExportFormatStates.png) {
      report(diagnostic2(button, "invalid-format", "Roster image-export format is not declared by the Surface contract"));
      return null;
    }
    let config;
    try {
      const rawConfig = button.getAttribute(rosterImageExportConfigDomAttr);
      if (rawConfig === null) throw new Error(`Missing ${rosterImageExportConfigDomAttr}`);
      config = parseRosterImageExportConfiguration(rawConfig);
    } catch (error) {
      report(diagnostic2(
        button,
        "invalid-config",
        error instanceof Error ? error.message : String(error)
      ));
      return null;
    }
    const surface = button.closest(surfaceSelector);
    if (surface === null) {
      report(diagnostic2(button, "missing-surface", "Roster image-export trigger has no generated Surface owner"));
      return null;
    }
    const projections = ownedElements(surface, projectionSelector);
    if (projections.length !== 1) {
      report(diagnostic2(
        surface,
        "invalid-projection-count",
        "Roster image-export Surface must contain exactly one generated projection"
      ));
      return null;
    }
    const projection = projections[0];
    if (projection.getAttribute(rosterImageExportProjectionDomAttr) !== "true") {
      report(diagnostic2(projection, "invalid-projection-role", "Roster image-export projection role must equal true"));
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
        report(diagnostic2(row, "invalid-row-role", "Roster image-export row role must equal true"));
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
        report(diagnostic2(
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
      report(diagnostic2(
        button,
        "export-failed",
        error instanceof Error ? error.message : String(error)
      ));
      window.alert(config.imageExportFailureMessage);
    }
  }
  function enableRosterImageExport(report = defaultDiagnosticReporter2) {
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
  function roleSelector(attribute) {
    return `[${attribute}]`;
  }
  function defaultDiagnosticReporter3(diagnostic4) {
    console.error?.("Invalid generated roster week-overview boundary", diagnostic4);
  }
  function diagnostic3(element, code, message) {
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
      report(diagnostic3(
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
        report(diagnostic3(day, "invalid-day-state", "Week-overview day states must agree with its exact payload"));
        return null;
      }
      return config;
    } catch (error) {
      report(diagnostic3(
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
      report(diagnostic3(panel, "invalid-slot-count", `Week-overview panel requires exactly one ${attribute} slot`));
      return null;
    }
    const slot = slots[0];
    if (slot.getAttribute(attribute) !== "true") {
      report(diagnostic3(slot, "invalid-slot-role", `Week-overview slot ${attribute} must equal true`));
      return null;
    }
    return slot;
  }
  function readOptionalSlot(panel, attribute, report) {
    const slots = ownedElements2(panel, attribute);
    if (slots.length > 1) {
      report(diagnostic3(panel, "invalid-slot-count", `Week-overview panel permits at most one ${attribute} slot`));
      return false;
    }
    const slot = slots[0] ?? null;
    if (slot !== null && slot.getAttribute(attribute) !== "true") {
      report(diagnostic3(slot, "invalid-slot-role", `Week-overview slot ${attribute} must equal true`));
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
      report(diagnostic3(goLinkElement, "invalid-go-link", "Week-overview go-link slot must be an anchor"));
      return null;
    }
    if (!isRosterWeekOverviewAvailabilityState(details.getAttribute(rosterWeekOverviewAvailabilityDomAttr)) || !isRosterWeekOverviewClosureState(details.getAttribute(rosterWeekOverviewClosureDomAttr))) {
      report(diagnostic3(details, "invalid-details-state", "Week-overview details states must be generated values"));
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
  function updateRosterWeekOverviewSelection(panel, selectedDay, report = defaultDiagnosticReporter3) {
    if (selectedDay.closest(panelSelector) !== panel) {
      report(diagnostic3(selectedDay, "day-outside-panel", "Week-overview day is not owned by this panel"));
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
    report(diagnostic3(panel, "missing-today-day", "Week-overview panel has no valid day for its Haskell-provided current date"));
    return false;
  }
  function panelForControl(control) {
    const panel = control.closest(panelSelector);
    return panel instanceof HTMLElement ? panel : null;
  }
  function enableRosterWeekOverview(report = defaultDiagnosticReporter3) {
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
          report(diagnostic3(today, "invalid-today-role", "Week-overview today role must equal true"));
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

  // frontend/ts/live-updates/mount.ts
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
})();
