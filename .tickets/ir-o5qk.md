---
id: ir-o5qk
status: closed
deps: []
links: [ir-jsyd, ir-vpmd]
created: 2026-06-26T04:23:02Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, frontend, contracts, haskell, typescript, codec, nix]
---
# Codec-first generated frontend contracts

Replace all handwritten TypeScript contract emission with a codec/schema-first generator so shared Haskell/frontend concepts produce JSON encoding, TypeScript declarations, runtime validators, and typed constants deterministically from Haskell.

## Design

Choose between autodocodec-based and custom FrontendCodec implementations, with a strong preference for a single codec/schema source of truth rather than parallel Aeson/schema definitions. Any added library/tool must be introduced through project Nix/devenv configuration. Wire shapes may change to favor regular tagged unions and fully generated output. Registry/manifest content should be derived from runtime surface descriptors, not manually mirrored.

## Acceptance Criteria

No production frontend contract generator modules contain handwritten TypeScript declarations or validators; shared concepts including live updates, interaction contracts, overlay lanes, DOM/event constants, and live surface manifests are generated from codec/schema definitions; runtime validators are generated from the same source; canonical TypeScript types have no string escape hatches; manifest content is derived from registered surface descriptors; Nix owns all new generator dependencies; frontend-contracts-check, frontend-check, typecheck, focused Hspec, and final zero-allowlist guard tests pass.


## Notes

**2026-06-26T07:17:09Z**

Epic complete. Implemented project-owned FrontendCodec generation and migrated live-update contracts, OverlayLane, interaction DTOs/constants/static schemas, and live-surface manifest constants/types to codec-first TypeScript declarations, runtime guards, and typed constants. Removed manual TypeScript helpers and the unused aeson-typescript dependency. Final guardrails pass with zero allowlist for production contract modules outside the codec renderer and no generated | string escape hatches. Final verification passed: typecheck, frontend-contracts-check, frontend-check, and hspec-test --match 'Frontend contract'.
