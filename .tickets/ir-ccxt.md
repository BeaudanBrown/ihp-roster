---
id: ir-ccxt
status: open
deps: [ir-udbq]
links: []
created: 2026-06-26T04:23:33Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-o5qk
tags: [agent-loop, frontend, contracts, cleanup, docs]
---
# Remove manual TypeScript generator escape hatches

Delete the remaining manual TypeScript emission APIs and reduce guard allowlists to zero after migrations land.

## Design

Remove stringUnionDeclaration/smallCompositionDeclaration or make them unavailable for shared contracts; remove arbitrary TypeScriptDeclaration.source escape hatches if possible; ban TSRawDeclaration and raw export strings in production frontend contract modules; update docs and agent notes with the codec-first rules.

## Acceptance Criteria

Zero-allowlist guard tests pass; no production Haskell frontend contract generator module contains handwritten TS declarations/validators/constants for shared concepts; docs describe the codec-first workflow and Nix-owned dependency rule; frontend-contracts-check, frontend-check, typecheck, and focused Hspec pass.

