---
id: ir-6thh
status: open
deps: []
links: [ir-l089, ir-dk24]
created: 2026-05-21T11:56:52Z
type: bug
priority: 1
assignee: Beaudan Brown
parent: ir-xyzw
tags: [agent-loop, area:roster, area:performance, area:architecture, area:live-fragments]
---
# Restore true roster projection rollback and parity baseline

The roster SQL read-model trial currently overwrote the old projection loader path: ProjectionRosterReadModel now caches the direct SQL read model instead of the pre-trial projection/Haskell builders, and full-page direct renders still warm the projection cache. Restore a real reversible backend split before relying on parity/performance results.

## Design

Reintroduce or preserve a projection-backed render-data builder that matches the pre-trial path, keep the direct SQL builder separate, and make ProjectionRosterReadModel use the true projection cache path. Gate keepCurrentRosterWeekProjectionHot so it does not warm the projection cache when DirectRosterReadModel is active. Update parity tests so they compare true projection-cached behavior against direct behavior, not cached-direct against uncached-direct.

## Acceptance Criteria

Switching currentRosterReadModelBackend to ProjectionRosterReadModel restores the old projection-backed behavior. DirectRosterReadModel full-page and fragment reads do not warm or populate the roster projection cache except where explicitly testing projection rollback. Parity coverage compares true projection-cached output with direct output for manager draft, staff hidden draft, published/day-column, and key fragments. Focused roster tests and typecheck pass.

