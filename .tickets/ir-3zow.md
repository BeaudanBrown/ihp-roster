---
id: ir-3zow
status: closed
deps: [ir-1zup, ir-kzr1]
links: []
created: 2026-07-04T07:18:23Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-pkmv
tags: [agent-loop, frontend-contracts, interaction]
---
# Migrate complex interaction capability schemas to the DSL

Replace remaining complex Interaction DTOs with explicit FrontendContract Record/Enum/TaggedUnion declarations.

## Design

Cover nested records and unions such as interaction session effects, selectors, intent targets/forms, conflict policies, capability contracts, static schemas, and generated surface interaction manifests. Prefer simpler new shapes over old DTO conventions. Tagged unions use fixed tag discriminator and derived case names.

## Acceptance Criteria

No complex Interaction DTO definitions remain as frontend contract authorities. Generated TypeScript validates the same runtime data needed by the interaction shell, and frontend-check passes after call-site migration.

