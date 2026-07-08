---
id: ir-zvq0
status: open
deps: [ir-65w7]
links: []
created: 2026-07-08T06:53:50Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5146
tags: [frontend-contracts, interaction, roster, surface]
---
# Move roster-specific interaction vocabulary to RosterSurface

Remove roster-specific interaction enum authority from the global InteractionContract and source the names from RosterSurface declarations.

## Design

Move/derive intent names, intent field names, session names, disposable layer names, and the roster surface family key from RosterSurface interaction declarations. Update Haskell/TypeScript consumers directly; do not preserve compatibility shim exports for old global roster-specific names.

## Acceptance Criteria

Global InteractionContract no longer declares Roster-only interaction vocabulary; generated TypeScript exposes the needed roster interaction names through surface-derived contracts; runtime/tests use the new exports directly; no compatibility shim aliases remain; focused roster interaction tests pass.

