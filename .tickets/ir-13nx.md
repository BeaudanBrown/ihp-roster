---
id: ir-13nx
status: closed
deps: []
links: []
created: 2026-07-04T09:33:53Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-pkmv
tags: [agent-loop, frontend-contracts, haskell-runtime]
---
# Derive Haskell frontend wire parse/render from FrontendContract DSL

Replace the remaining non-authoritative FrontendCodec/DTO runtime JSON plumbing with a FrontendContract-derived Haskell wire parse/render path, or an equivalent mechanically checked DSL-backed interpreter, so Haskell and TypeScript are both derived from one contract authority.

## Design

Use a hybrid transition: derive/check complex live/surface Haskell runtime parse/render against the FrontendContract IR now, while allowing temporary runtime DTO records as implementation details only. This ticket must not create a second permanent path: before the epic is complete, final cleanup must either delete the temporary DTO wrappers or move them fully under a single FrontendContract-owned Haskell wire interpreter. No FrontendCodec/schema-group path may remain as a contract authority.

## Acceptance Criteria

Live-update and remaining frontend browser wire parse/render no longer depend on FrontendCodec as contract authority. Haskell wire JSON parsing/rendering for frontend-visible contracts is DSL-backed or mechanically checked against the DSL. The temporary hybrid state is explicitly bounded: ir-y0mn must eliminate the duplicate DTO/schema path before the epic is complete, leaving one FrontendContract-owned Haskell wire path.

