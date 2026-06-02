---
id: ir-mwco
status: open
deps: [ir-3pa0]
links: []
created: 2026-06-02T07:20:14Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:myob, area:providers, readiness]
---
# Implement MYOB employee wage-category readiness and assignment

Ensure MYOB employees can use the wage categories required by Bepis timesheet lines.

## Design

Use EmployeePayrollDetails and related payroll details to determine whether required wage categories are linked to each mapped employee. Implement readiness blockers and, if supported and approved by the user, update employee payroll details to assign required wage categories without disturbing calculated categories or unrelated payroll settings.

## Acceptance Criteria

MYOB readiness identifies missing employee wage-category assignments. Approved assignment updates are audited and preserve RowVersion/concurrency requirements. Process avoids storing TFN/bank/super data and does not mutate unrelated employee payroll settings.

