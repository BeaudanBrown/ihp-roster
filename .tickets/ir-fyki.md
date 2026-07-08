---
id: ir-fyki
status: open
deps: [ir-zi2e]
links: []
created: 2026-07-08T07:20:33Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jvjj
tags: [frontend-contracts, typescript, wire]
---
# Derive frontend wire primitive aliases from Haskell IR

Replace hardcoded FrontendContractUuid/Day and FrontendSurfaceUUID/Day aliases with names derived from the Haskell wire primitive model or remove redundant aliases.

## Design

Make WireIR primitive TypeScript names a single Haskell value-level source used by renderWire, tests, and any branded aliases. Prefer removing FrontendSurfaceUUID/Day if they are only redundant adapter aliases; otherwise derive their names from explicit Haskell declarations.

## Acceptance Criteria

No raw header strings define wire primitive exported aliases; generated UUID/Day references still compile; tests prove renaming/changing primitive aliases happens through Haskell source only.

