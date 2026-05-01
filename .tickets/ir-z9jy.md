---
id: ir-z9jy
status: closed
deps: [ir-rl1u]
links: []
created: 2026-05-01T00:58:16Z
type: task
priority: 2
assignee: beaudan
parent: ir-afos
tags: [area:xero, area:payroll, ui]
---
# Show Xero payroll-calendar exclusion warnings in admin timesheet panel

Ensure employee payroll-calendar readiness warnings are visible and understandable in the existing Xero admin timesheet panel when employees are excluded because they belong to a different selected-calendar lane.

## Design

Reuse existing readiness warning rendering. Prefer improving message text in helper code over adding new UI structure. Message should tell the operator that employees on other Xero payroll calendars were skipped from this selected-calendar submission.

## Acceptance Criteria

Admin Xero page surfaces the exclusion warning in the readiness panel. Existing Xero page tests remain stable; add a view/controller assertion only if existing rendering tests do not cover warning output.

## Notes

**2026-05-01T02:34:53Z**

2026-05-01: Admin timesheet readiness now surfaces different-calendar employees as warnings via existing readiness warning rendering instead of blockers. The warning explains that the mapped Xero employee was skipped from the selected-calendar submission. Verified with focused Xero readiness/preview/submission Hspec.
