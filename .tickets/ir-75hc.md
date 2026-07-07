---
id: ir-75hc
status: open
deps: [ir-gipq]
links: []
created: 2026-07-07T03:54:41Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-6rnm
tags: [agent-loop, roster, timeline, haskell]
---
# Implement roster day timeline drag-to-move mutation

Persist timeline drag-to-move intents with server-side validation and authoritative responses.

## Design

Add the timeline move action/controller path backing the generated intent form. Parse opaque source and target keys, validate current venue, roster group, week offset, roster day, manager role, draft/editable state, source slot ownership, target slot definition, target 15-minute minute, operational window, and preserved-duration start/end. Moving across lanes updates roster_week_slot_definition_id and slot_sort_order. Preserve row_index if the target slot-definition cell is free; otherwise choose the first free row_index. Reject invalid drops with a toast/actor refresh. Emit generated roster resources and authoritative timeline/roster fragments through the existing live-update pipeline.

## Acceptance Criteria

Dragging a staffed draft shift changes start/end by preserving duration. Dragging across slot-definition lanes changes the slot definition. Row index placement follows preserve-if-free then first-free behavior. Invalid/out-of-window/unauthorized drops fail safely with a message and no partial mutation. Passive viewers refresh through the current surface resource/live-update path. Focused RosterWeeks Hspec covers validation and placement.

