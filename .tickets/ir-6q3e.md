---
id: ir-6q3e
status: open
deps: []
links: []
created: 2026-05-29T03:16:06Z
type: epic
priority: 1
assignee: beaudan
parent: ir-cfcr
tags: [agent-loop, live-fragments, foundation]
---
# Build shared typed-fragment actor response foundation

Extract the reusable pieces learned from the timesheets refactor before migrating more pages.

## Design

Introduce shared render-mode/OOB helpers and a typed response helper that feature code can call instead of bespoke renderXxxOob and renderMainFragmentOob branches.

## Acceptance Criteria

There is a documented shared helper/API for rendering typed surface fragments as plain or OOB; timesheets uses it or has a deliberate short-term note; tests cover containment normalization and actor OOB rendering through the helper.

