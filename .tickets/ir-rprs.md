---
id: ir-rprs
status: closed
deps: []
links: []
created: 2026-07-09T01:05:25Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-3irv
tags: [agent-loop, frontend-surface, inventory]
---
# Inventory parameterized FrontendSurface migration candidates

Build the exact migration map across registered FrontendSurface surfaces before framework changes.

## Design

Inspect every registered surface: SurfaceLab, Timesheets, Roster, LeaveRequests, Billing, Support, Profile, Staff, and Admin surfaces. Classify each fragment family as already parameterized, duplicated and suitable for parameterization, single/static non-applicable, legacy/OOB special case, or decision point requiring user input. Record the migration table in ticket notes or living docs. Pause and ask before making ambiguous calls.

## Acceptance Criteria

Every registered surface is classified. Every applicable migration target is listed. Non-applicable surfaces/fragments have rationale. Ambiguities are marked as pause/ask-user decisions.


## Notes

**2026-07-09T01:07:17Z**

Inventory result for parameterized FrontendSurface migration candidates:

| Surface | Classification | Migration notes |
| --- | --- | --- |
| LeaveRequests | duplicated section fragments; first adopter | Current pending/approved/denied/archive count/list fragments and resources should become parameterized section count/list fragments backed by leave-requests-section { venueId, section }. Preserve accordion shell and archive pagination response-mode seam. |
| Timesheets | already parameterized | timesheet-day-section { dayOffset } already uses FromFragment. Migrate mounting/render/query/resource construction to new helpers after foundation. Week toolbar/columns stay static. |
| Roster | already parameterized, high risk | roster-day-section { rosterDayId } and roster-row { rosterDayId, rowIndex } already use FromFragment. Migrate to helpers only after leave proves foundation. Pause before changes that affect stable shell DOM ownership, conflict/focus behavior, or generated contract semantics. |
| SurfaceLab | fixture already parameterized | lab-panel { panelId } should migrate as fixture/proof coverage for helper APIs. |
| Profile | duplicated section-style candidate | details/preferences/security/leave/RSA are separate static fragments with shared section semantics. Inventory recommends migration if foundation supports distinct dependencies per section cleanly. Pause if parameterization would obscure differing dependencies or validation-local form targets. |
| Staff | duplicated section-style candidate | staff details/preferences and leave form boundaries are similar to Profile; migrate where it reduces duplication while preserving staff/profile permission distinction. |
| AdminPage/AdminXeroPage containers | non-applicable containers | page content fragments contain nested surfaces and do not themselves represent repeated regions. Leave static. |
| AdminVenueSettings/AdminInvites/AdminExports | mostly non-applicable static fragments | single static fragments per nested surface; no parameterization benefit unless later grouped into an admin-section surface. |
| AdminShiftTypes/AdminRosterGroups | duplicated list-management pattern candidate | separate surfaces/fragments share list-management shape and inactive toggle state. Consider migration only if helpers support section/list families without losing distinct action fields and resources. Pause before merging distinct resources. |
| AdminXero | duplicated tab/section candidate | shell/staff-mappings/pay-items/timesheets are section-style fragments with distinct resources. Candidate for parameterized xero-section fragments if differing resources can remain explicit. Pause if response-mode/OOB seams around preparation mappings or pay-item data are unclear. |
| Billing | non-applicable static | billing-status is single static live fragment. Leave static. |
| Support | duplicated simple pair candidate, low value | award-rates/public-holidays are two section-like fragments with no scope fields. Could parameterize support-section if foundation makes it trivial; acceptable to leave static only with rationale in final sweep. |

Decision/pause points carried forward:
- Need user input before adding closed enum DSL support rather than using WireText/string params.
- Need user input before broad generated TypeScript contract shape changes.
- Need user input before changing roster/timesheet DOM ownership or live conflict/focus semantics.
- Need user input before parameterizing fragments with meaningfully different permissions/resources if the model becomes less clear.
