---
id: ir-mwma
status: closed
deps: []
links: []
created: 2026-06-30T11:03:28Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-z0j1
tags: [architecture, bepis-actions, agent-loop]
---
# Define single Bepis operation and fact root

Create the final root type that owns action kind, controller policy, runtime facts, telemetry labels, and architecture contracts for pages, fragments, dialogs, mutations, integrations, exports, and JSON endpoints.

## Design

Introduce a central Application.Bepis.Fact/Operation model with BepisFact, BepisFactSet, BepisOperationKind, BepisOperationContext, and emitBepisFact. emitBepisFact appends to the request-local collector and emits safe OTel attributes/events. Keep IHP as the runner boundary; do not build a custom router. The model replaces, not wraps around, BepisMutationSpec-style metadata.

## Acceptance Criteria

The root model compiles, generated contracts include operation/fact vocabularies, request-local fact collection works in tests, telemetry emission is centralized through emitBepisFact, and docs define BepisFact as the single semantic source.
