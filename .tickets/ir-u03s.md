---
id: ir-u03s
status: closed
deps: [ir-2w5m]
links: []
created: 2026-07-07T04:09:19Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-cfcr
tags: [agent-loop, research, live-fragments, frontend-surface]
---
# Inventory FrontendSurface actor response paths

Classify all current actor mutation responses and exceptions before migration.

## Design

Search registered FrontendSurface surfaces and related controllers/helpers for hx-swap-oob, respondHtml/respondHtmlProfiled, HX-Trigger, liveFragmentsRefreshEvent, invalidateTouchedResources, broadcastLiveInvalidation, and feature response helpers. Categorize each path as already actor-local invalidation, authoritative business OOB/HTML success response, validation-local direct response, non-authoritative extras only, pure view-state/refetch GET, or intentional non-FrontendSurface/legacy exception.

## Acceptance Criteria

Ticket notes list Admin simple, Admin Xero, Timesheets, Roster, Leave Requests, Profile, Billing, Support/lab paths with intended action: migrate now, exception, or follow-up. No production behavior changes.


## Notes

**2026-07-07T04:18:35Z**

Inventory complete (no production changes). Registered surfaces: lab, timesheets, roster, leave requests, billing, support, profile, admin page/xero page/simple admin sections/admin xero. Current actor/refetch shapes and action:

- Admin simple (venue settings/invites/exports/roster groups/shift types): venue settings and invites/roster groups use HX-Reswap=none plus WithSwap outerHTML business fragments; shift types currently direct-renders the section and may append renderCurrentVenueXeroSectionFragmentOob when Xero pay items need refresh; exports are covered by admin export resources/mutations. Action: migrate under ir-5v0t/ir-hsnv to shared actor-local invalidation plus extras; keep local validation/form rerenders.
- Admin Xero: some nested paths already use precursor setAdminXeroActorRefresh (staff mapping controls, timesheet mutations) plus toast/dialog extras; shell/pay-items/mapping success/error helpers still render business fragments directly or OOB (respondWithXeroSectionFragmentAndToast, respondWithXeroPayItemsFragmentAndToast*, renderCurrentVenueXeroSectionFragmentOob). Action: ir-myjr/ir-oxnj and children should keep the extras-only paths, replace feature-specific actor-refresh header with shared helper, and migrate shell/pay-items/mapping business HTML to actor-local invalidation.
- Timesheets: fragment GETs are plain (respondWithTimesheetFragment), but success helpers respondWithTimesheetFragments/respondWithTimesheetWeekFragmentsUpdate/respondWithTimesheetDaySectionUpdate/respondWithTimesheetDateMoveUpdate render TimesheetFragmentOob business fragments plus dialog/toast extras. Mutations already emit touched resources. Action: ir-wmdh migrates successes to actor-local invalidation; dialog clear/toast stay extras; validation dialogs stay direct.
- Roster: fragment GET/refetch endpoints are plain for content/rows/day/staff panel; success helpers respondWithRosterFragments/respondWithRosterContentUpdate/respondWithRosterActorRefresh/respondWithRosterPatches render business OOB or patch HTML plus extras. Some failures/toasts are extras-only; remove-row confirmation is dialog-local. Mutations already call invalidateTouchedResources. Action: ir-kuyy children classify navigation GETs as direct view-state and migrate mutation successes to semantic actor-local invalidation, preserving row/day precision through fragment selection/planning.
- Leave Requests: manager/profile/roster self-service leave helpers currently use OOB business fragments (respondWithProfileLeaveFragments, respondWithRosterStaffSelfServiceLeaveFragments, leave request read-model OOB); archive pagination has a documented local swapOob exception. Action: classify manager/profile leave as already migrated legacy OOB from previous epic but include in ir-7j0h/final cleanup as follow-up/exception unless broader current epic chooses to migrate it; validation/no-staff form rerenders stay direct; archive pagination stays pure local view-state exception.
- Profile: profile content updates in Web.Controller.Profiles currently direct-render active section HTML plus toast OOB on success; validation/preference errors direct-render the active local section. Profile leave nested content uses OOB helper. Action: ir-3y9k/ir-blxm/ir-54w9 confirm scope, then migrate successful profile content to actor-local invalidation; keep validation and security/RSA/resync-only direct exceptions explicit.
- Billing: BillingSurface appears to be mostly passive/refetch/read-side; Web.Controller.Billing ShowBillingStatusFragmentAction returns a plain billing status fragment and Billing.Mutations emits resources from customer/control/webhook changes. No authoritative actor success business OOB found in current controller. Action: treat as exception/no-op unless ir-7j0h finds a missed success path.
- Support/lab: SurfaceLab and Support fragments are diagnostics/admin surfaces; Support controller fragment actions respondHtml plain sections/panels, job enqueue paths emit touched resources, and lab action metadata returns direct demo fragments. No migrated business actor success OOB requiring current migration. Action: intentional support/lab exception/no-op, keep plain refetch endpoints and diagnostic behavior.

Cross-cutting: allowed response categories are validation-local direct fragments, extras-only OOB (toast/dialog clear), pure view-state/refetch GETs returning plain target HTML, and documented non-FrontendSurface/legacy exceptions. Prohibited for migrated success paths: authoritative business hx-swap-oob/direct HTML in the actor response.
