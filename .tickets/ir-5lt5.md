---
id: ir-5lt5
status: open
deps: [ir-momf]
links: []
created: 2026-07-09T01:32:04Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-qbm4
tags: [agent-loop, docs, roster, interaction]
---
# Document final roster modifier drag behavior

Move implemented roster drag/drop and semantic modifier facts into living documentation.

## Design

Update Web/RosterWeeks/SPEC.md for whole-day day-column drag/drop, target growth, move/copy semantics, and silent same-day move no-op. Update Web/RosterWeeks/README.md or local AGENTS only if new reusable navigation or gotchas are discovered. Add an ADR only if the semantic modifier decision needs rationale beyond the interaction spec.

## Acceptance Criteria

Implemented behavior is documented in local living specs, not only tickets/workstream. Reusable gotchas are captured in the nearest local docs. No stale future-only workstream text is left as the sole source of truth.

