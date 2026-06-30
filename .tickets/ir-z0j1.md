---
id: ir-z0j1
status: closed
deps: []
links: []
created: 2026-06-30T11:02:34Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [architecture, bepis-actions, live-surfaces, agent-loop]
---
# Finalize Bepis runtime facts architecture

Replace legacy descriptive Bepis metadata with a single root runtime fact model where helpers emit typed Bepis facts as a side effect of performing real authorization, audit, live invalidation, and response work.

## Design

No legacy coexistence as a final state. Remove BepisMutationSpec, descriptive pipeline/evidence labels, mutation drift guards, and duplicated response/action concepts. Keep IHP as the outer framework boundary, but centralize Bepis semantics under runBepis, BepisFact, emitBepisFact, and Haskell-generated contracts. emitBepisFact is also the telemetry boundary: typed facts are collected per action and summarized to OTel, while OTel remains a sink rather than the source type. Source scans may locate usages or forbid legacy APIs, but must not infer Bepis semantics.

## Acceptance Criteria

There is one root BepisFact model and emitBepisFact boundary; BepisMutationSpec and mutation drift guard code are gone; scope/audit/live/response facts are emitted by the helpers that actually perform those effects; all controllers/actions use the final runBepis API; generated architecture facts no longer parse Bepis semantics from Haskell source regex; strict gates and focused tests pass; docs describe final rules with no legacy fallback.
