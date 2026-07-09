---
id: ir-qbm4
status: closed
deps: []
links: [ir-jsyd, ir-7wsy]
created: 2026-07-09T01:32:04Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, frontend, interaction, roster, drag-drop]
---
# Finalize modifier-aware typed interaction intents for roster drag/drop

Lock down the reusable architecture for modifier-selected interaction intents, then prove it with roster day-column drag/drop: move by default, copy/duplicate with platform-native copy modifier, whole-day drop highlighting, and target-day row growth.

## Design

Extend the Haskell-owned typed interaction manifest so source/dropzone interactions can declare a default intent plus semantic modifier variants. The generic TypeScript pointer runtime resolves the active semantic modifier from platform-aware key bindings, selects the generated intent/effects, and submits the matching server-rendered HTMX intent form. Roster day-column dropzones become semantic whole-day targets; server-side roster logic chooses/grows backing slot targets and handles move/copy semantics. Default move onto the same day is a silent no-op; copy onto the same day is allowed.

## Acceptance Criteria

Typed interaction docs/spec describe semantic modifier variants, platform bindings, fallback behavior, and variant effects. Generic TS runtime selects declared intent variants without feature-specific roster branching. Generated contracts expose enough metadata for modifier variants and effect selection. Roster day-column drag/drop highlights the whole day column using the expanded + Add shift visual style, moves by default, silently no-ops same-day moves, duplicates with the platform-native copy modifier, grows target day backing rows as needed, and shows a distinct copy drag shadow. Focused Haskell/frontend tests cover contracts, runtime selection, and roster move/copy validation. Relevant living docs are updated.

