---
id: ir-tila
status: closed
deps: [ir-1vhl, ir-3316]
links: []
created: 2026-05-27T23:58:34Z
type: task
priority: 2
assignee: beaudan
parent: ir-gz9k
tags: [area:e2e, area:mobile]
---
# Add roster/timesheet snap regression tests

Extend Playwright coverage for the shared snapping component and timesheet snapping.

## Design

Keep existing roster snap coverage, add timesheet nearest-day snap coverage with reduced motion enabled and explicit synthetic scroll events. Assert no initial auto-scroll on timesheet page load.

## Acceptance Criteria

Focused e2e covers roster equal-groups, roster nearest-item, timesheet nearest-item, pointer-release delay, and no initial auto-scroll.

