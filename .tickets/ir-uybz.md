---
id: ir-uybz
status: closed
deps: [ir-kxch]
links: []
created: 2026-05-21T07:43:26Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-xyzw
tags: [agent-loop, area:roster, area:performance]
---
# Implement SQL/direct assignment and conflict facts

Replace the projection path's expensive set-derived roster facts with fresh SQL/direct equivalents in the trial path.

## Design

Implement assignment option state rows and slot conflict rows using SQL-friendly set operations where practical. Assignment option states should cover ideal shift thresholds, unavailable days, approved leave, and already-assigned-today flags. Conflicts should cover duplicate assignment, approved leave, late-to-early, shift preference day unavailable, shift preference start-window mismatch, and ideal shift threshold. Preserve existing Haskell-facing conflict types and messages.

## Acceptance Criteria

The trial path produces assignment option states and conflict rows equivalent to existing behavior for representative fixtures. Tests cover each assignment hidden reason and each conflict type.


## Notes

**2026-05-21T08:18:49Z**

HANDOFF: Added SQL/direct assignment option-state and slot-conflict fact builders in Web.RosterWeeks.DirectReadModel, routed roster render data through them, and covered all hidden reasons/conflict types in DirectReadModelSpec; tests run: bash ./bin/in-env typecheck, bash ./bin/in-env hspec-test --match "Roster direct read model"; remaining risk: broader projection-vs-direct parity still belongs to ir-1jsi.
