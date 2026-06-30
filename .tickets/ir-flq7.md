---
id: ir-flq7
status: closed
deps: []
links: []
created: 2026-06-30T07:48:23Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [architecture, bepis-actions, agent-loop]
---
# Harden typed Bepis boundary after whole-app migration

Reduce remaining convention ambiguity, derive architecture metadata from typed Bepis contracts, and add checks/tests for strict golden-path enforcement.

## Design

Keep IHP as outer boundary. Prefer Haskell typed registries/constructors as the metadata source, with Node tooling reading those contracts instead of duplicating maps. Add feature-specific mutation specs where useful and strict architecture checks where compile-time enforcement is not feasible.

## Acceptance Criteria

Architecture tooling derives Bepis wrapper metadata from Application.Bepis types/definitions; strict conventions pass with no blocking and no raw-response info noise; architecture gate is covered by a test/script check; high-risk mutation specs are named per feature; focused typecheck/checks pass.


## Notes

**2026-06-30T07:59:10Z**

Hardening complete: wrapper metadata and mutation policy labels are derived from Haskell Bepis type/contract definitions, strict conventions have zero rows/errors, high-risk controllers use feature-level mutation specs, and architecture-check-fresh includes a deterministic Bepis architecture gate.
