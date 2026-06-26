---
id: ir-a6do
status: closed
deps: [ir-b797, ir-gwsv]
links: []
created: 2026-06-26T04:23:33Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-o5qk
tags: [agent-loop, frontend, contracts, codec, nix]
---
# Implement chosen codec/schema generator foundation

Build the selected codec/schema-first generator foundation for JSON, TypeScript declarations, validators, and typed constants.

## Design

If custom FrontendCodec wins, add codec/schema modules for primitives, arrays, nullable, records, enums, tagged unions, named references, constants, JSON encode/decode, TS declaration rendering, and TS guard rendering. If autodocodec wins, add the package/tooling through Nix and implement the app adapter layer. Avoid arbitrary raw TypeScript source as a public escape hatch.

## Acceptance Criteria

Representative contracts can generate JSON encoders/decoders, TS declarations, TS validators, and typed constants from one codec/schema definition; generator tests cover record, enum, tagged union, nullable, array, nested references, exact-object validation, constants, deterministic formatting, and duplicate-name failures; new dependencies are declared through Nix/devenv and cabal/package config as applicable.


## Notes

**2026-06-26T04:42:21Z**

Implemented custom FrontendCodec foundation in Application.Helper.Frontend.Codec: schema AST for primitives, nullable, optional, arrays, exact records, closed string enums, tagged unions, refs, JSON encode/parse hooks, TypeScript declarations, runtime guards, typed constants, and duplicate top-level name detection. Added FrontendContractsSpec coverage for representative LiveUpdateScope/LiveFragmentProtection/LiveSurfaceConfig/InteractionDom-like contracts. No Nix dependencies added. Verification passed: typecheck, frontend-contracts-check, hspec-test --match 'Frontend contract'.

**2026-06-26T04:48:11Z**

Blocker ir-gwsv is closed. FrontendCodec foundation plus lockdown guardrails are implemented with no new Nix dependencies. Verification passed: hspec-test --match 'Frontend contract', typecheck, frontend-contracts-check.
