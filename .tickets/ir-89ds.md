---
id: ir-89ds
status: open
deps: [ir-hc2u]
links: []
created: 2026-07-01T02:44:57Z
type: task
priority: 2
assignee: beaudan
parent: ir-ao41
tags: [agent-loop, frontend, typescript, interaction]
---
# Refactor pointer sessions around generated effect runner

Introduce a generic TypeScript effect runner for pointer sessions that reads generated session effect config.

## Design

Refactor frontend/ts/interaction/pointer-session.ts, extracting effect-runner types/modules as useful. On session start/activation, resolve the mount surface family from generated InteractionDom attrs, look up the surface schema in generated InteractionStaticSchemas, find the matching session kind, and instantiate global/contextual effect handlers from generated effect configs. Missing schema/effects must be safe and preserve current intent submission. Provide lifecycle hooks for activate/update/target-change/commit/cancel/cleanup. Do not branch on roster or hardcoded drag layer names.

## Acceptance Criteria

Existing pointer session tests pass. New frontend unit/DOM tests cover generated schema lookup, empty/missing effects, lifecycle ordering, and cleanup invocation. Runtime imports generated contract types/constants and uses exhaustive handling for generated effect unions. No roster-specific TypeScript is added.

