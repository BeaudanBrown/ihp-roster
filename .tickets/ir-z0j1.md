---
id: ir-z0j1
status: open
deps: []
links: []
created: 2026-06-30T11:02:34Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [architecture, bepis-actions, live-surfaces, agent-loop]
---
# Finalize Bepis effect-evidence architecture

Replace legacy descriptive Bepis metadata with a single root Bepis operation/evidence model where scope, audit, realtime, and response evidence is produced by the helpers that perform those effects.

## Design

No legacy coexistence as a final state. Remove BepisMutationSpec, descriptive mutation evidence labels, mutation drift guards, and duplicated response/action concepts. Keep IHP as the outer framework boundary, but centralize Bepis semantics under one root operation/evidence type and Haskell-generated contracts. Every architecture fact about Bepis semantics must come from typed operation/evidence values or effect-producing helpers; source scans are only allowed for locating usages or forbidding legacy APIs.

## Acceptance Criteria

There is one root Bepis operation/evidence model; BepisMutationSpec and mutation drift guard code are gone; scope/audit/live/response evidence is produced by authorization, audit, invalidation, and response helpers; all controllers/actions use the final API; generated architecture facts no longer parse Bepis semantics from Haskell source regex; strict gates and focused tests pass; docs describe final rules with no legacy fallback.

