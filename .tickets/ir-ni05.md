---
id: ir-ni05
status: open
deps: []
links: []
created: 2026-07-07T03:24:11Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-elys
tags: [frontend-contracts, frontend-surface, htmx, design]
---
# Design FrontendSurface action metadata IR and DSL extension

Add contract-level action metadata sufficient for generated HTMX action manifests.

## Design

Extend the current SurfaceAction representation so each action can carry method, target fragment, swap behavior, and future-extensible options without moving IHP route construction into the type-level DSL. Keep route construction for a later Haskell typeclass/instance layer. Update IR validation so action target fragments must exist on the same surface, action names are collision-checked, and option names remain closed.

## Acceptance Criteria

Surface contract IR can represent method, target fragment, swap, and extensible action options. Invalid target fragments fail validation. Existing surfaces compile unchanged or migrate through a clear default constructor where necessary.

