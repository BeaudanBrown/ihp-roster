---
id: ir-ra94
status: open
deps: [ir-0b7s]
links: []
created: 2026-05-29T03:16:07Z
type: task
priority: 1
assignee: beaudan
parent: ir-6q3e
tags: [agent-loop, timesheets, cleanup]
---
# Move timesheets onto the shared fragment helper

Replace the local timesheet-specific actor fragment helper with the shared helper as the first real consumer.

## Design

Keep the timesheet DOM and behavior from the completed refactor; only replace local helper plumbing with the shared pattern and FragmentRenderMode names.

## Acceptance Criteria

Timesheets typecheck; existing timesheet Hspec and scroll-preservation Playwright coverage pass; no TimesheetProjectionPage or shell live fragment is reintroduced.

