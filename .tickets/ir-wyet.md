---
id: ir-wyet
status: open
deps: [ir-elbv]
links: []
created: 2026-05-27T23:58:34Z
type: task
priority: 1
assignee: beaudan
parent: ir-bao4
tags: [area:roster, area:mobile, area:ui]
---
# Apply shared week controls to roster mobile header

Update roster week header ordering on mobile while preserving desktop layout.

## Design

Use the shared toolbar with a mobile layout where Live/This week/settings sit on the top row and week navigation sits below, closer to the roster grid. Keep roster overview dropdown and HTMX nav semantics unchanged.

## Acceptance Criteria

Roster desktop header stays one row; phone screenshot/layout test shows requested two-row order; existing roster-mobile navigation tests pass.

