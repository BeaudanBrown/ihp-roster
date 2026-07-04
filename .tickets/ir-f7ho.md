---
id: ir-f7ho
status: closed
deps: [ir-4ub1]
links: []
created: 2026-07-04T03:20:00Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-888o
tags: [agent-loop, surfaces, interaction, generator]
---
# Generate interaction refs and manifest metadata from FrontendSurface

Extend `FrontendSurface` extraction/contracts with generated interaction ref and manifest metadata.

## Design

Extend the `FrontendSurface` IR/lowering/type generation as needed so registered surfaces can expose generated/static browser contracts for role refs, sessions, intents, fields, layers, effects, compatibility, and conflict policies. Generate TypeScript types/guards/constants and keep generated names kebab-case and stable. Add compile/contract tests for unknown refs, duplicate refs, invalid source/dropzone/session/intent mappings, and missing intent/session/layer references.

## Acceptance Criteria

- `frontend/ts/generated/contracts.ts` exposes the new manifest/ref contract.
- Haskell tests verify generated metadata for roster and at least one simple activation-only shape.
- `frontend-check` catches exhaustiveness/type drift for generated closed unions.
- No mutation transport URLs are moved into browser-owned config.
