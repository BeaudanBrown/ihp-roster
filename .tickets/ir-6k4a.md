---
id: ir-6k4a
status: closed
deps: []
links: []
created: 2026-05-28T05:42:05Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-j3eq
tags: [area:timesheets, area:ui, agent-loop]
---
# Prevent timesheet card Break line wrapping

Fix a narrow CSS/layout issue in timesheet cards.

## Design

Adjust the timesheet entry card markup or CSS so the 'Break: <summary>' meta line does not split awkwardly between the label and value. Keep cards responsive and avoid creating page-level horizontal overflow.

## Acceptance Criteria

Timesheet card Break line stays together at supported widths; cards remain responsive without page-level horizontal overflow; focused visual/e2e or CSS-safe assertions are updated if practical.


## Notes

**2026-05-28T06:31:14Z**

Verification: typecheck and hspec Timesheets passed; mobile-experience e2e passed. style-audit still reports pre-existing unrelated CSS audit issues (--app-white, palette colors, existing inline styles).
