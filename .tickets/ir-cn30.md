---
id: ir-cn30
status: closed
deps: [ir-u3o4]
links: []
created: 2026-07-01T01:40:01Z
type: feature
priority: 2
assignee: beaudan
parent: ir-6kzl
tags: [agent-loop, frontend, contracts, interaction]
---
# Migrate interaction contracts to generic frontend DTOs

Untangle interaction internal polymorphic/server types from browser DTOs and generate interaction contracts from explicit generic DTO types.

## Design

Create or use Application.Helper.Frontend.Dto.Interaction for browser-facing DTOs: interaction DOM constants, vocabularies, session/layer/intent/field names, selectors, mount metadata, intent field schema, intent form contract, conflict policy, capability/static schema DTOs, and static schema registry container. Internal polymorphic interaction structures convert into narrow DTO values before encoding. Prefer generated DTO codecs over Aeson.Value/valueCodec/manual SchemaRef trees.

## Acceptance Criteria

Interaction generated types come from DTO codecs, not Aeson.Value/manual valueCodec schemas. Static schema constants are encoded through generated DTO codecs. Adding a Haskell intent updates generated InteractionIntentName and TypeScript exhaustive handling/tests fail until handled where appropriate. No duplicated intent/layer/field strings remain in TypeScript. Focused Interaction Hspec, frontend tests, frontend-contracts-check, and frontend-check pass.


## Notes

**2026-07-01T02:17:29Z**

Migrated interaction browser contracts to explicit generic DTO codecs in Application.Helper.Frontend.Dto.Interaction. InteractionSchema is now only group registration and typed constants; static schema constants are encoded through DTO codecs while preserving generated TS shape. Verification: typecheck; frontend-contracts; frontend-contracts-check; frontend-check; hspec-test --match 'interaction surface'; hspec-test --match 'Frontend contract'.
