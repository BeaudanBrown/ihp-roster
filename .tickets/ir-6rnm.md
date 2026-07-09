---
id: ir-6rnm
status: closed
deps: []
links: []
created: 2026-07-07T03:54:40Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, roster, timeline, surfaces, interaction]
---
# Roster single-day timeline drag-to-move

Add a single-day horizontal roster timeline view where roster shifts can be dragged to 15-minute time targets and slot-definition lanes while preserving duration.

## Design

Create a timeline-oriented roster surface/page scoped to one roster day, roster group, and week offset. Render slot-definition lanes on the vertical axis and the operational day (06:00 through 05:45 next day) on the horizontal axis with server-rendered 15-minute dropzones. Dynamic inner tracks are visual-only overlap packing inside each slot-definition lane. Generic FrontendSurface interaction runtime submits opaque source/dropzone keys through server-rendered HTMX intent forms; the server owns all parsing, authorization, time validation, row-index placement, and authoritative fragment responses. Dragging a whole shift preserves duration; moving across outer lanes updates roster_week_slot_definition_id; row_index is preserved if free in the target slot definition, otherwise the first free row is used. Resize handles, configurable slot-definition titles, coordinate-derived browser timeline semantics, creation/deletion from timeline, staff reassignment, and live-roster editing are out of scope.

## Acceptance Criteria

Managers/admins can open a single-day timeline from existing day-row and day-column roster views and return to the canonical week view. Managers/admins can edit only draft/unpublished weeks; staff can view only live/published weeks and never edit. The timeline renders one day with slot-definition lanes, 15-minute targets, positioned shift cards, and visual overlap tracks. Editable draft shifts can be dragged to change start/end time while preserving duration and optionally move to another slot-definition lane. Server validation rejects invalid targets safely and emits authoritative roster/timeline updates through the existing surface resource/live-update path. Living docs and focused tests describe the implemented behavior and non-goals.

