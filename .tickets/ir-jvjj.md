---
id: ir-jvjj
status: open
deps: []
links: []
created: 2026-07-08T07:20:33Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [frontend-contracts, typescript, architecture]
---
# Derive generated TypeScript scaffolding from Haskell contract types

Remove hardcoded contract-looking TypeScript declarations from Application.Helper.FrontendContract.TypeScript so generated TypeScript shapes are derived from Haskell DSL/IR/carrier types rather than ad-hoc string blocks.

## Design

Generated contracts may still be rendered as TypeScript text, but exported types, names, manifests, and validators must come from Haskell contract declarations, IR, or reflected carrier schemas. Runtime helper implementations that are not contract authority should move to handwritten frontend TypeScript modules importing generated contracts. Avoid compatibility shim aliases unless explicitly approved.

## Acceptance Criteria

Audit classifies all hardcoded TypeScript blocks; generated contract-looking types such as FrontendSurfaceUUID/Day, HtmxActionOptions, mount config, live subscription adapters, interaction static registry, and registry helper shapes are either derived from Haskell declarations/IR or moved out of generated output; guardrails prevent new raw exported type/function string blocks outside approved renderer combinators; typecheck, frontend-check, and focused frontend contract tests pass.

