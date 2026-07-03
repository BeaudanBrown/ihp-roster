---
id: ir-j23l
status: closed
deps: [ir-81wq]
links: []
created: 2026-07-03T04:17:38Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-7huc
tags: [agent-loop, surfaces, contracts, live-updates]
---
# Generate FrontendSurface-native live transport contracts

## Design

Extend ContractIR with live fragments derived from Fragment options containing Live. Generate TypeScript types/guards for surface-native live scope, live fragment refs, live wire fragments, and subscription config using deterministic kebab-case names. Composition-only surfaces produce no subscription metadata.

## Acceptance Criteria

Generated topology and live metadata identify all Live fragments. Admin page and Admin Xero page have no subscription without TypeScript special cases. Representative fragment params are generated from Haskell fields and validated in TS/Hspec tests.

