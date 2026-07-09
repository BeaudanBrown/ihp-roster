---
id: ir-zoa9
status: closed
deps: [ir-7ulr]
links: []
created: 2026-07-09T05:06:02Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-7wsy
tags: [agent-loop, roster, views, interaction]
---
# Render roster staff drag sources and precise staff drop targets

Render manager-visible staff rows as drag sources and render precise roster assignment/create dropzones for staff drag.

## Design

In Web.View.RosterWeeks.StaffPanel, render staff rows with generated staff source refs and staff:<staff-id> source keys while preserving click-to-edit behavior. In roster grid/day-column views, render existing editable shifts as staff-assignment dropzones with existing:<slot-id>; row-grid empty create cells as staff-create dropzones; and day-column bottom + Add shift cards as staff-create dropzones. Do not make day-column whitespace/gaps staff-create dropzones. Preserve existing shift drag/drop markup and behavior.

## Acceptance Criteria

Staff rows emit generated source refs. Existing shifts and create targets emit generated compatible dropzone refs. The day-column section itself is not a staff-create dropzone. Click-to-edit staff and click-to-open shift dialogs still work. Current shift drag/drop markup remains functional.

