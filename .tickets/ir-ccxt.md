---
id: ir-ccxt
status: closed
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


## Notes

**2026-06-26T07:16:43Z**

Removed the remaining manual TypeScript emission helpers from Application.Helper.Frontend.TypeScript and dropped the no-longer-used aeson-typescript dependency from Cabal/Nix config. Guardrails now use a zero allowlist for production frontend contract modules outside the codec renderer and generated output has no | string escape hatches. Documented the codec-first closeout rule. Verification passed: typecheck, frontend-contracts-check, frontend-check, and hspec-test --match 'Frontend contract'.
