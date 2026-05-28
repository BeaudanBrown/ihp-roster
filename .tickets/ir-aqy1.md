---
id: ir-aqy1
status: open
deps: [ir-oiak]
links: []
created: 2026-05-28T05:42:18Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-j3eq
tags: [area:leave, area:ui, area:performance, agent-loop]
---
# Paginate unavailability archive

Prevent the unavailability Archive section from growing without bounds.

## Design

The delete-removal decision means old unavailable periods remain in history. Add pagination or another bounded loading pattern for the Archive section after the immediate action-column cleanup lands. Preserve Pending/Approved/Denied behavior and keep archive navigation accessible and HTMX/live-surface compatible.

## Acceptance Criteria

Archive rendering is bounded by page/limit or an equivalent incremental loading mechanism; users can navigate older archive entries; live-fragment behavior remains correct; controller/view tests cover archive pagination boundaries.

