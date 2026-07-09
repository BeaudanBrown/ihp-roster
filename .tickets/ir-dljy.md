---
id: ir-dljy
status: open
deps: [ir-jxle]
links: []
created: 2026-07-09T10:10:25Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-rlh2
tags: [agent-loop, time-picker, roster, timeline]
---
# Apply venue picker window to roster timeline

Make the roster day timeline selectable range follow the venue picker window.

## Design

Replace the fixed 06:00 plus 24h timeline axis/dropzone generation with the configured venue window. Generate dropzones only within the configured window. Preserve existing shift rendering without data loss and keep drag/drop authorization, draft/live, closed-day, and slot-definition checks server-side.

## Acceptance Criteria

Timeline axis and dropzones match the venue window for same-day and overnight ranges. Existing out-of-window shifts remain safely represented without deletion or hard blocking. Timeline drag/drop tests or focused coverage verify configured window behavior.

