---
id: ir-mwma
status: open
deps: []
links: []
created: 2026-06-30T11:03:28Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-z0j1
tags: [architecture, bepis-actions, agent-loop]
---
# Define single Bepis operation and evidence root

Create the final root type that owns action kind, controller policy, effect evidence, telemetry labels, and architecture contracts for pages, fragments, dialogs, mutations, integrations, exports, and JSON endpoints.

## Design

Introduce a central Application.Bepis.Operation model such as BepisOperation/BepisStep/BepisEvidence with typed evidence constructors for scope, audit, live/realtime, and response. Keep IHP as the runner boundary; do not build a custom router. The model must replace, not wrap around, BepisMutationSpec-style metadata.

## Acceptance Criteria

The root model compiles, generated contracts include the root operation/evidence vocabulary, existing legacy metadata types are marked for deletion in the same epic, and docs define the single source of truth.

