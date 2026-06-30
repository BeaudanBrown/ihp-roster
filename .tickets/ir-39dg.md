---
id: ir-39dg
status: closed
deps: [ir-23gs]
links: []
created: 2026-06-30T11:03:28Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-z0j1
tags: [architecture, bepis-actions, agent-loop]
---
# Big-bang migrate all controllers off legacy Bepis metadata

Apply the final runBepis/fact-emitting helper API across all controller actions without leaving legacy spec-backed mutations behind.

## Design

Migrate every controller/action to the final API, replacing descriptive scope/audit/live/response labels with helpers that emit facts while doing real work. Remove BepisMutationSpec values and feature-specific mutation specs in the same change set.

## Acceptance Criteria

All 175 handlers use final API; rg finds no BepisMutationSpec, auditedAs, scopedTo*, fromLiveMutationResult, respondsWith*, or mutation drift fallback symbols in runtime code; typecheck and focused controller tests pass.
