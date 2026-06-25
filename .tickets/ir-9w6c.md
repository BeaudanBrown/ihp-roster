---
id: ir-9w6c
status: open
deps: [ir-tp1i, ir-2g0b]
links: []
created: 2026-06-25T11:57:30Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-vpmd
tags: [agent-loop, frontend, contracts, docs, cleanup]
---
# Remove manual frontend contract remnants and update docs

Clean up obsolete handwritten contract generation paths and document the new Haskell-schema-owned contract workflow.

## Design

Remove compatibility helpers that embedded large TypeScript declarations in Haskell strings. Update Application/Helper/Interaction.SPEC.md, Application/Helper/LiveSurface.COOKBOOK.md, docs/workstreams/typed-interaction-surfaces.md, frontend/AGENTS.md, and static/AGENTS.md as needed. State that every Haskell/TypeScript shared concept must be generated from Haskell-owned schema, while runtime-specific URLs/ids remain Haskell-rendered metadata.

## Acceptance Criteria

Docs describe generator architecture, static schema versus runtime metadata, and validator/type guard expectations; guardrails prohibit new large handwritten TS declaration blocks for Haskell-owned contracts; frontend-check, typecheck, and focused contract tests pass.

