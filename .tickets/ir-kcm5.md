---
id: ir-kcm5
status: open
deps: [ir-yoho, ir-7dqy, ir-9mz7, ir-cgee]
links: []
created: 2026-06-15T23:44:59Z
type: chore
priority: 1
assignee: beaudan
parent: ir-brfx
tags: [agent-loop, area:staff, area:roster, area:timesheets, area:xero, launch]
---
# Document and verify trial staff roster placeholders

Update living docs/specs and run final verification for the trial staff placeholder epic.

## Design

Update Web/RosterWeeks/SPEC.md to document trial placeholders as rosterable, TRIAL role display, and publish behavior. Update Web/Timesheets/SPEC.md to document exclusion from manual and automated timesheets. Refine cross-cutting specs only if needed; existing product scope already keeps conversion/adoption out of V1. Run final verification and add closeout notes before closing the epic.

## Acceptance Criteria

Living specs document implemented V1 behavior and non-goals. Verification includes bash ./bin/in-env typecheck plus focused Hspec for trial staff helpers, roster panel/assignment behavior, timesheets, roster timesheet automation, and Xero/payroll eligibility if touched. Broader hspec-test is run if implementation breadth warrants it. Epic acceptance criteria are checked and a closeout note is added.

