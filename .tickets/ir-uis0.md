---
id: ir-uis0
status: open
deps: []
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-sky7
tags: [area:admin, area:ui, agent-loop]
---
# Hide Admin exports section behind disabled-for-now comment

Remove the Admin exports accordion from the rendered page while keeping export code available.

## Design

Update Web.View.Admin.Index so the Exports section is not rendered on the Admin page for now. Keep Web.View.Admin.Exports and controller/fragment code in place unless tests require narrowing access. Add a code comment explaining that the section is temporarily hidden/disabled, not deleted.

## Acceptance Criteria

Admin page no longer displays the Exports accordion/section; export implementation files remain; an explanatory code comment exists near the omission; admin tests/e2e expectations are updated.

