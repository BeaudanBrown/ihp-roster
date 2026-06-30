---
id: ir-bhbi
status: closed
deps: []
links: []
created: 2026-06-30T09:54:22Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-si7h
tags: [architecture, bepis-actions, agent-loop]
---
# Migrate one representative mutation to pipeline evidence

Prove the mutation pipeline on a high-value real action before broad rollout.

## Design

Migrate a roster or timesheet mutation that already performs authorization, audit/versioning, touched resources, passive invalidation, and actor response. Architecture facts should prefer pipeline/evidence facts for this action over descriptive specs.

## Acceptance Criteria

The migrated action typechecks, focused controller tests pass, trace/architecture facts show scope/audit/realtime/response facts from the pipeline, and legacy BepisMutationSpec remains only as fallback for unmigrated actions.

