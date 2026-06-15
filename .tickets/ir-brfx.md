---
id: ir-brfx
status: open
deps: []
links: []
created: 2026-06-15T23:44:59Z
type: epic
priority: 1
assignee: beaudan
tags: [agent-loop, area:staff, area:roster, area:timesheets, area:xero, launch]
---
# Trial staff roster placeholders

Allow managers and above to create active trial staff placeholders, roster them like ordinary rosterable staff, show TRIAL in the staff-panel role column, and exclude them from timesheets, Xero/payroll readiness, automation, and exports.

## Design

Use the existing staff.user_id IS NULL model for trial placeholders. Avoid schema changes and defer adoption/conversion invites. Trial staff are active venue-scoped staff rows with no login or venue membership. Define clear eligibility language: rosterable staff = active, not archived, includes linked and trial; linked active staff = active, not archived, user_id IS NOT NULL, eligible for timesheets/payroll/Xero; trial staff = user_id IS NULL. Roster code should use rosterable staff; pay/timesheet/Xero code should use linked active staff unless resolving historical records from existing timesheet entries.

## Acceptance Criteria

Managers/admins/owners/support-equivalent can create current-venue trial staff placeholders. Create form uses the full staff details shape with obvious placeholder contact/emergency defaults. Created trial staff are active, have user_id NULL, are assigned to selected roster groups, appear in roster assignment options, and show TRIAL in the existing staff-panel role column. Trial staff can be rostered and do not block publishing. Roster-to-timesheet automation ignores trial-staff slots without creating timesheet entries or blocking publish. Manual timesheet create/update cannot assign trial staff, and trial staff are not offered in timesheet staff selectors/filters. Xero/payroll readiness/mapping/export paths use active linked staff for eligibility. Focused Hspec coverage and typecheck pass. Living specs document V1 behavior and non-goals.

