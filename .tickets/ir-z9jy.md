---
id: ir-z9jy
status: open
deps: [ir-rl1u]
links: []
created: 2026-05-01T00:58:16Z
type: task
priority: 2
assignee: beaudan
parent: ir-afos
tags: [area:xero, area:payroll, ui]
---
# Show actionable Xero payroll-calendar mismatch messages in admin timesheet panel

Ensure employee payroll-calendar readiness blockers are visible and understandable in the existing Xero admin timesheet panel.

## Design

Reuse existing readiness blocker rendering. Prefer improving blocker message text in helper code over adding new UI structure. Message should tell the operator to assign the employee to the selected Xero payroll calendar or exclude/fix that employee before submission.

## Acceptance Criteria

Admin Xero page surfaces the new blocker messages in the readiness panel. Existing Xero page tests remain stable; add a view/controller assertion only if existing rendering tests do not cover blocker output.

