---
id: ir-7wsy
status: closed
deps: []
links: [ir-jsyd, ir-qbm4]
created: 2026-07-09T05:05:28Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, frontend, interaction, roster, drag-drop]
---
# Reusable typed drag/drop interactions and roster staff drop

Refine the typed interaction backbone so app surfaces can declare multiple source/dropzone drag behaviors safely and ergonomically, then prove the pattern by dragging roster staff onto shifts or create targets.

## Design

Extend the Haskell-owned FrontendSurface interaction manifest so source refs can be compatible with specific dropzone refs instead of relying only on shared session kind. Add ergonomic DSL/helper patterns for multi-source/multi-target drag/drop. Update generic TypeScript pointer hit-testing/highlighting/commit to use generated source/dropzone compatibility, without roster-specific JavaScript. Then add roster staff drag as the proof: staff rows become sources; existing shift cards become staff-assignment dropzones; empty row-grid create cells and day-column + Add shift cards become staff-create dropzones. Existing shift-to-day drag keeps the whole-day-column move target, while staff drag day-column whitespace/gaps are neutral.

## Acceptance Criteria

Generated interaction manifest exposes source/dropzone compatibility. Generic pointer runtime highlights/submits only compatible dropzones for the active source. Surface DSL/helper API supports multiple drag source/dropzone refs cleanly. Existing roster shift move/copy behavior remains unchanged. Staff row mouse drag works: dropping onto an existing shift replaces assigned staff immediately with a toast; dropping onto a row-grid empty slot opens the new shift modal with staff preselected; dropping onto the day-column bottom + Add shift card opens the new shift modal with staff preselected; dropping in day-column whitespace/gaps does nothing. Server validates venue, roster group, week, draft/editability, open day, active staff, and roster-group eligibility. No frontend JS constructs mutation URLs or mutates business DOM. Living docs/specs describe the reusable multi-source/multi-dropzone pattern. Focused Haskell/frontend tests pass.

