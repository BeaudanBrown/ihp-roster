---
id: ir-myjr
status: closed
deps: []
links: []
created: 2026-05-29T03:16:09Z
type: task
priority: 1
assignee: beaudan
parent: ir-oxnj
tags: [agent-loop, research, confirmation, frontend-surface]
---
# Confirm Xero semantic invalidation and extras constraints

Research current Admin Xero fragment paths and confirm constraints before implementation.

## Design

Inspect `Web.View.Admin.Xero`, nested Xero view modules, `Web.Controller.Admin.Xero.Responses`, Admin controller fragment endpoints, auto-sync trigger forms, dialog OOB paths, and existing actor refresh headers. Confirm which success paths should emit shell-level versus child-level semantic invalidations, which paths are validation/dialog-local, and which response HTML is extras-only.

## Acceptance Criteria

Ticket note records selected semantic invalidation fragments, auto-sync handling, dialog/toast extras, duplicate-mount implications, and any deferred cases. No production behavior changes are made.

## Notes

**2026-07-07T04:26:22Z**

Xero constraints confirmed. Semantic fragment selection: connection start/callback/disconnect/reference sync and payroll calendar/earnings-rate/account-code changes should invalidate adminXeroShellFragment because connection status, action controls, operational panels, and readiness can appear/disappear. Pay-item sync/import/archive/create-missing paths should invalidate adminXeroPayItemsFragment; if a pay-item result changes shell-level readiness/action availability, include adminXeroShellFragment as well. Staff mapping save/suggest paths should invalidate adminXeroStaffMappingsFragment; existing toast-only path is already extras-only after shared helper. Xero timesheet preparation submission/retry paths should invalidate adminXeroTimesheetsFragment; final submission success may also include pay items/shell if backend readiness changes.

Auto-sync handling: renderXeroAutoSyncTrigger is shell-owned and currently posts SyncXeroPayrollReferenceDataAction on load with hx-target #admin-xero-fragment. Migration should avoid actor business HTML; auto-sync success should emit shell actor-local invalidation plus toast/extras or no extra, and any hx-target/hx-swap values on the load form should become compatible with hx-swap=none/actor-local invalidation when migrated.

Dialog/local exceptions: Open/import pay-item dialogs and timesheet-preparation wizard steps are dialog-local HTMX and should keep direct dialog fragments for validation/progress. Dialog close is extras-only OOB (#dialog-overlay-mount innerHTML). Toasts remain extras-only. Fragment GET actions ShowadminXeroShell/StaffMappings/PayItems/Timesheets must continue returning plain target-node HTML.

Duplicate mounts: all success actor invalidations should pass adminXeroLiveScope currentVenueId to setActorLiveFragmentsRefresh so every mounted Admin Xero surface copy in the tab resolves its own target/url/protection. Deferred cases: legacy renderCurrentVenueXeroSectionFragmentOob from Admin shift type Xero refresh is owned by admin simple/shift-type migration; full removal of renderXero*Oob helpers can wait for ir-1nps/ir-6bqb/ir-78cn after all call sites move.
