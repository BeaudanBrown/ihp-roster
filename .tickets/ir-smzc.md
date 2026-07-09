---
id: ir-smzc
status: closed
deps: [ir-lzqr]
links: []
created: 2026-07-09T01:32:04Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-qbm4
tags: [agent-loop, frontend, interaction, haskell, contracts]
---
# Extend FrontendSurface contracts for modifier intent variants

Add Haskell-owned interaction contract metadata for default and modifier-selected intent variants.

## Design

Extend the FrontendSurface interaction IR/DSL/static schema so source/dropzone pointer interactions can declare a default intent/effects plus semantic modifier variants with variant intent and effect metadata/class. Update TypeScript contract generation and tests. Preserve behavior for surfaces that declare no variants.

## Acceptance Criteria

Roster surface can declare default move and copy duplicate variants from Haskell. Generated TypeScript manifest contains variant metadata. Existing surfaces without variants behave unchanged. Contract drift and FrontendSurface contract tests pass.

