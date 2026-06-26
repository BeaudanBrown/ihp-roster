---
id: ir-dlks
status: open
deps: [ir-akhw, ir-5467]
links: []
created: 2026-06-26T04:23:33Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-o5qk
tags: [agent-loop, frontend, interaction, contracts]
---
# Migrate interaction contracts to codec-first generation

Replace manually assembled interaction TypeScript contracts and static schema constants with codec/schema-first generated DTOs, validators where needed, and typed constants.

## Design

Generate InteractionDom, InteractionMountMetadata, ServerLayerContract, DisposableLayerContract, SessionKindContract, IntentFieldSchema, IntentHiddenField, InteractionIntentTarget, IntentFormContract, InteractionConflictPolicy, InteractionCapabilityContract, InteractionStaticSchema, and InteractionStaticSchemas from codec/schema-backed Haskell types/values. Remove all canonical '| string' escape hatches.

## Acceptance Criteria

InteractionSchema no longer emits hand-written TypeScript declarations; generated interaction types are closed over canonical names; InteractionStaticSchemas is a typed generated constant; frontend interaction runtime/tests compile without string escape hatches; focused Interaction and frontend tests pass.

