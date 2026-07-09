---
id: ir-momf
status: open
deps: [ir-z1tz, ir-2ur7]
links: []
created: 2026-07-09T01:32:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-qbm4
tags: [agent-loop, test, frontend, roster]
---
# Cover modifier drag variants and roster day-drop regressions

Add focused regression coverage for generic modifier selection and roster day-column move/copy behavior.

## Design

Add frontend tests for modifier variant selection, fallback, and shadow class changes. Add Hspec coverage for semantic day token validation, target row growth, same-day move no-op, copy duplicate behavior, and closed/wrong-scope rejection. Add focused Playwright only if unit/Hspec coverage cannot exercise browser drag behavior adequately.

## Acceptance Criteria

Focused tests fail without the new behavior and pass with it. Verification commands are recorded in ticket notes or closeout. RosterWeeks and FrontendSurface focused suites cover the new contract.

