---
id: ir-iute
status: closed
deps: [ir-7f00, ir-rc3l, ir-y0mn]
links: []
created: 2026-07-04T07:18:23Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-pkmv
tags: [agent-loop, frontend-contracts, docs, guardrails]
---
# Document and guard the unified FrontendContract architecture

Update living docs and guardrails for the final model.

## Design

Document Global vs Surface: Global is app-wide shared browser/runtime/skeleton vocabulary; Surface is mounted feature UI ownership. Document type-level constants, naming conventions, no DeriveDto v1, refs, live transport unions, and surface-local-to-global promotion. Add guardrails/tests that reject Application.Helper.Frontend.Dto, FrontendCodec, old schema groups, handwritten TS contracts for registry-owned names, and non-registry contract generation paths.

## Acceptance Criteria

Docs reflect the new authoring workflow. Guardrails fail on reintroducing deleted DTO/codec/schema paths or manual frontend contract sources. Important reference/collision/closed-union behavior is covered by type errors or validation tests.

