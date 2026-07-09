---
id: ir-mijy
status: open
deps: []
links: []
created: 2026-07-09T02:39:01Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-z20h
tags: [agent-loop, roster, ui]
---
# Allow roster slot-name sections to be minimised

Add collapse/minimise affordances for roster row slot-name sections.

## Design

Implement minimising for roster slot-definition/row sections without changing roster data. Prefer low-risk UI state first; persist preference only if straightforward and aligned with existing user preference patterns. Keep live/read-only and draft/edit behavior coherent.

## Acceptance Criteria

Users can minimise and expand roster slot-name sections. The roster remains usable on desktop/mobile and live fragment refreshes do not corrupt state. No roster data is changed by minimising.

