---
id: ir-aosk
status: open
deps: [ir-a3kk]
links: []
created: 2026-07-03T11:15:32Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-3b6m
tags: [agent-loop, surfaces, codegen]
---
# Derive live subscription auth and validation from FrontendSurface metadata

Replace remaining hard-coded scope/fragment parsing for live subscriptions with reflected/generated RegisteredFrontendSurfaces validation and authorization helpers.

## Design

Use the existing GHC/reflection ContractIR path to validate known surface names, scope payload field shape, live fragment names, and fragment params. Authorize subscriptions through Scope Authorize/NoAuth metadata. Unknown or malformed surface/scope/fragment data denies or is rejected by default.

## Acceptance Criteria

Subscription authorization accepts valid generated scopes, rejects unknown/malformed scopes, and validates mounted fragments as declared live fragments for the same surface. No feature-specific authorization fallback is introduced. Focused LiveUpdate/FrontendSurface tests pass.

