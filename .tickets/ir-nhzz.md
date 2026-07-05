---
id: ir-nhzz
status: closed
deps: []
links: []
created: 2026-07-04T12:31:43Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-pkmv
tags: [agent-loop, frontend-contracts, constants]
---
# Derive Haskell constant accessors from FrontendContract declarations

Remove remaining drift-prone Haskell constants from Application.Helper.Frontend.AppConstants and RosterConstants.

## Design

Add reflected value accessors under FrontendContract, e.g. eventNameValue, domIdValue, enumLiteralValue or narrow AppValues/RosterValues modules generated from/reflected against the DSL declarations. Replace AppConstants and RosterConstants call sites with FrontendContract-owned accessors. Delete the old constants modules when unused.

## Acceptance Criteria

No imports of Application.Helper.Frontend.AppConstants or RosterConstants remain. Haskell values used in views/helpers are obtained from FrontendContract declarations or mechanically checked values. Frontend tests and typecheck pass.

