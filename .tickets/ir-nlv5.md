---
id: ir-nlv5
status: closed
deps: []
links: []
created: 2026-06-15T23:44:59Z
type: task
priority: 1
assignee: beaudan
parent: ir-brfx
tags: [agent-loop, area:staff, area:roster, area:timesheets, area:xero, launch]
---
# Add staff eligibility helpers for trial placeholders

Introduce explicit helper/query vocabulary for trial, rosterable, and linked-active staff so roster and payroll-adjacent code do not confuse active staff with payroll eligibility.

## Design

Build on Application.Helper.Staff.isTrialStaff. Add or consolidate helpers in focused modules such as Application.Helper.Staff, Application.Helper.VenueScopedQueries, and roster-group helpers. Prefer names that communicate intent, e.g. rosterable active staff includes active non-archived trial rows, while linked active staff requires user_id IS NOT NULL. Replace ambiguous helper usage only where local and low-risk; leave broader cleanup to follow-up if discovered.

## Acceptance Criteria

Named helpers exist for trial staff, rosterable staff, and linked active staff. Existing trial-staff tests are extended for helper/filter behavior. No schema change is introduced. Typecheck passes.


## Notes

**2026-06-15T23:50:27Z**

Added explicit rosterable vs linked-active staff helpers in Application.Helper.Staff and venue-scoped query helper names; kept fetchActiveVenueStaff as rosterable-compatible alias for existing callers. Focused Trial staff Hspec and typecheck pass.
