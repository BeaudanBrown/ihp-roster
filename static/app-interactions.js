"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  var FrontendSurfaceInteractionDom = { sourceRef: "data-bepis-source-ref", sourceKey: "data-bepis-source-key", dropzoneRef: "data-bepis-dropzone-ref", dropzoneKey: "data-bepis-dropzone-key", activationRef: "data-bepis-activation-ref", activeSourceRef: "data-bepis-active-source-ref" };
  function isFrontendSurfaceInteractionSurfaceName(value) {
    return typeof value === "string" && ["roster", "roster-day-timeline"].includes(value);
  }
  var interactionIntentEvent = "bepis:interaction-intent";
  var interactionSessionStartEvent = "bepis:interaction-session-start";
  var interactionSessionEndEvent = "bepis:interaction-session-end";
  var interactionSessionCancelRequestEvent = "bepis:interaction-session-cancel-request";
  function isInteractionFieldPresence(value) {
    return typeof value === "string" && ["required", "optional"].includes(value);
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
  var InteractionStaticSchemas = { "roster": { "serverLayers": [], "disposableLayers": [{ "name": "drag-preview", "domIdSuffix": "drag-preview" }], "sessionKinds": [{ "kind": "drag", "description": "Roster drag/drop prototype", "effects": { "global": [{ "className": "bepis-pointer-clone-shadow", "kind": "clone-shadow", "layer": "drag-preview", "preserveGrabOffset": true, "source": "pointer-marker" }], "contextual": [{ "className": "bepis-dropzone-highlight", "kind": "dropzone-highlight" }] } }], "intents": [{ "name": "set-roster-layout-mode", "fields": [{ "name": "rosterLayoutMode", "presence": "required", "defaultValue": null }] }, { "name": "move-roster-shift-to-slot", "fields": [{ "name": "sourceItemKey", "presence": "required", "defaultValue": null }, { "name": "targetDropzoneKey", "presence": "required", "defaultValue": null }, { "name": "sessionKind", "presence": "optional", "defaultValue": null }, { "name": "pointerId", "presence": "optional", "defaultValue": null }, { "name": "pointerType", "presence": "optional", "defaultValue": null }, { "name": "startClientX", "presence": "optional", "defaultValue": null }, { "name": "startClientY", "presence": "optional", "defaultValue": null }, { "name": "currentClientX", "presence": "optional", "defaultValue": null }, { "name": "currentClientY", "presence": "optional", "defaultValue": null }, { "name": "deltaX", "presence": "optional", "defaultValue": null }, { "name": "deltaY", "presence": "optional", "defaultValue": null }] }, { "name": "duplicate-roster-shift-to-day", "fields": [{ "name": "sourceItemKey", "presence": "required", "defaultValue": null }, { "name": "targetDropzoneKey", "presence": "required", "defaultValue": null }, { "name": "sessionKind", "presence": "optional", "defaultValue": null }, { "name": "pointerId", "presence": "optional", "defaultValue": null }, { "name": "pointerType", "presence": "optional", "defaultValue": null }, { "name": "startClientX", "presence": "optional", "defaultValue": null }, { "name": "startClientY", "presence": "optional", "defaultValue": null }, { "name": "currentClientX", "presence": "optional", "defaultValue": null }, { "name": "currentClientY", "presence": "optional", "defaultValue": null }, { "name": "deltaX", "presence": "optional", "defaultValue": null }, { "name": "deltaY", "presence": "optional", "defaultValue": null }] }, { "name": "drop-roster-staff", "fields": [{ "name": "sourceItemKey", "presence": "required", "defaultValue": null }, { "name": "targetDropzoneKey", "presence": "required", "defaultValue": null }, { "name": "sessionKind", "presence": "optional", "defaultValue": null }, { "name": "pointerId", "presence": "optional", "defaultValue": null }, { "name": "pointerType", "presence": "optional", "defaultValue": null }, { "name": "startClientX", "presence": "optional", "defaultValue": null }, { "name": "startClientY", "presence": "optional", "defaultValue": null }, { "name": "currentClientX", "presence": "optional", "defaultValue": null }, { "name": "currentClientY", "presence": "optional", "defaultValue": null }, { "name": "deltaX", "presence": "optional", "defaultValue": null }, { "name": "deltaY", "presence": "optional", "defaultValue": null }] }], "conflictPolicies": [] }, "roster-day-timeline": { "serverLayers": [], "disposableLayers": [{ "name": "drag-preview", "domIdSuffix": "drag-preview" }], "sessionKinds": [{ "kind": "drag", "description": "roster-day-timeline drag interaction session", "effects": { "global": [{ "className": "bepis-pointer-clone-shadow", "kind": "clone-shadow", "layer": "drag-preview", "preserveGrabOffset": true, "source": "pointer-marker" }], "contextual": [{ "className": "bepis-dropzone-highlight", "kind": "dropzone-highlight" }] } }], "intents": [{ "name": "move-roster-timeline-shift", "fields": [{ "name": "sourceItemKey", "presence": "required", "defaultValue": null }, { "name": "targetDropzoneKey", "presence": "required", "defaultValue": null }, { "name": "sessionKind", "presence": "optional", "defaultValue": null }, { "name": "pointerId", "presence": "optional", "defaultValue": null }, { "name": "pointerType", "presence": "optional", "defaultValue": null }, { "name": "startClientX", "presence": "optional", "defaultValue": null }, { "name": "startClientY", "presence": "optional", "defaultValue": null }, { "name": "currentClientX", "presence": "optional", "defaultValue": null }, { "name": "currentClientY", "presence": "optional", "defaultValue": null }, { "name": "deltaX", "presence": "optional", "defaultValue": null }, { "name": "deltaY", "presence": "optional", "defaultValue": null }] }], "conflictPolicies": [{ "session": { "kind": "session", "session": "drag" }, "fragment": { "kind": "any" }, "resolution": "defer", "timeoutMs": 5e3 }] } };
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
  var surfaceActivationSelector = `[${FrontendSurfaceInteractionDom.activationRef}]`;
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
    if (!isFrontendSurfaceName(surface)) return null;
    const ref = marker.getAttribute(FrontendSurfaceInteractionDom.activationRef);
    const definition = FrontendSurfaceRegistry[surface].interaction.activationRefs.find((candidate) => candidate.ref === ref);
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

  // frontend/ts/shared/exhaustive.ts
  function assertNever(value, message = "Unexpected generated union variant") {
    throw new Error(`${message}: ${JSON.stringify(value)}`);
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
  var sourceRefSelector = `[${FrontendSurfaceInteractionDom.sourceRef}]`;
  var disposableLayerSelector = `[${attrs4.disposableLayer}]`;
  var pointerFields = InteractionDom.pointerFields;
  var defaultThresholdPx = 4;
  var activeSourceRefAttribute = FrontendSurfaceInteractionDom.activeSourceRef;
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
    const mount = closestInteractionMount3(marker);
    if (!mount) return null;
    const surface = mount.getAttribute(attrs4.surface);
    if (!isFrontendSurfaceName(surface)) return null;
    const sourceRef = marker.getAttribute(FrontendSurfaceInteractionDom.sourceRef);
    const source = FrontendSurfaceRegistry[surface].interaction.sourceRefs.find((candidate) => candidate.ref === sourceRef);
    if (!source) return null;
    const sourceKey = marker.getAttribute(FrontendSurfaceInteractionDom.sourceKey);
    if (!sourceKey) return null;
    const compatibleDropzoneRefs = compatibleDropzoneRefsForSource(surface, source);
    const targetField = FrontendSurfaceRegistry[surface].interaction.dropzoneRefs.find((candidate) => compatibleDropzoneRefs.includes(candidate.ref))?.targetField ?? null;
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
    return InteractionStaticSchemas[family].sessionKinds.find((candidate) => candidate.kind === session.sessionKind) ?? null;
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
    if (compatibleRefs.length === 0) return `[${FrontendSurfaceInteractionDom.dropzoneRef}]`;
    return compatibleRefs.map((ref) => `[${FrontendSurfaceInteractionDom.dropzoneRef}="${cssString(ref)}"]`).join(",");
  }
  function compatibleDropzoneRefsForSource(surface, source) {
    const explicitRefs = source.compatibleDropzones ?? [];
    if (explicitRefs.length > 0) return explicitRefs;
    return FrontendSurfaceRegistry[surface].interaction.dropzoneRefs.filter((candidate) => candidate.session === source.session).map((candidate) => candidate.ref);
  }
  function targetDropzoneFieldForSession(session, target) {
    if (!target) return null;
    const surface = session.mount.getAttribute(attrs4.surface);
    if (!isFrontendSurfaceName(surface)) return null;
    const ref = target.getAttribute(FrontendSurfaceInteractionDom.dropzoneRef);
    if (!ref) return null;
    return FrontendSurfaceRegistry[surface].interaction.dropzoneRefs.find((candidate) => candidate.ref === ref)?.targetField ?? null;
  }
  function targetDropzoneKeyForTarget(target) {
    if (!target) return null;
    return target.getAttribute(FrontendSurfaceInteractionDom.dropzoneKey);
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

  // frontend/ts/app-interactions.ts
  enableGenericInteractionActivations();
  enableGenericPointerSessions();
})();
