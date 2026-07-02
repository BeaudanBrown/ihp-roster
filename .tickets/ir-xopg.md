---
id: ir-xopg
status: closed
deps: [ir-ennr, ir-p3c3]
links: []
created: 2026-07-02T02:47:03Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces, ghc-api]
---
# Generate surface TypeScript and DTO contracts from GHC API

Implement the GHC API extraction path from `RegisteredFrontendSurfaces` to normalized `SurfaceContractIR` and generated TypeScript/runtime metadata.

## Design

- Input is the single explicit root list of surfaces, planned in `Application.Helper.FrontendSurface.Registry`:

  ```haskell
  type RegisteredFrontendSurfaces = '[ ... ]
  ```

- Load the registry module with Nix-owned GHC options. The generator command may expose `-package ghc`, but this is owned by Nix/devenv scripts rather than ad hoc developer setup.
- Inspect types only. Do not infer contracts from arbitrary Haskell values.
- Normalize type synonyms, approved helper aliases, and needed closed type families/list flattening into flat primitive normal form. Detect and reject helper expansion cycles. This must cover all lab, Timesheets, and Roster functionality without feature-specific extractor shims.
- Build a raw extracted representation, derive protocol names, merge identical shared declarations, and lower to a checked `SurfaceContractIR` containing surfaces, shared scopes, DTOs, fields, fragments, actions, intents, sessions, layers, effects, policies, events, DOM tokens, mount state, overlay lanes, and closed declaration/reference kind metadata for exhaustive cross-reference validation.
- Validate:
  - duplicate/conflicting shared declarations;
  - unsupported wire types;
  - duplicate field names;
  - action/intent/fragment/session/layer/effect/policy references;
  - one normalized scope per surface;
  - exact-name escape hatch allowlist;
  - surface/global namespace collisions.
- Replace old `FrontendSchema` as the final surface-contract IR for migrated surface/live/interaction contracts. Renderer-internal TS data structures are allowed if fed only by `SurfaceContractIR`.
- Generate TypeScript types, branded aliases for meaningful IDs, guards, parsers, encoders, constants, manifests, shared scope DTOs, surface-local fragment keys, mount-state DTOs, and mount-resolved live-update transport envelopes. Output shape may improve over current generated contracts and need not maintain old internal protocol compatibility.
- Provide reusable Haskell wire-type/field-list reflection or metadata over a closed browser-boundary universe: `WireText`, `WireInt`, `WireBool`, `WireUUID`, `WireDay`, list, optional, nullable, and declared DTO refs. Do not generate Haskell ADTs in V1. Do not serialize arbitrary domain/database models.

## Acceptance Criteria

- Generated contracts include every lab primitive and are consumed by focused frontend checks/tests.
- No lab DTO/schema is authored through `FrontendCodec` or old DTO schema groups.
- Type synonyms, helper expansion, list flattening, nested option lists, parameterized fragment shapes, shared declaration merge, branded ID aliases, and mount-state shapes are covered.
- Generator diagnostics clearly report malformed specs, duplicate names, conflicting shared declarations, invalid cross references, unsupported exact names, and helper expansion cycles, with stable substrings for tests.
- The implementation is general for Timesheets and Roster; no extractor special cases for those features are accepted.

## Notes

**2026-07-02T06:40:29Z**

Added the first generator slice: type-level registry reflection from RegisteredFrontendSurfaces into checked SurfaceContractIR, validation diagnostics for duplicate fields, invalid references and conflicting shared declarations, TypeScript rendering, frontend-contracts integration, and frontend tests consuming generated lab types/manifests. This slice uses typeclass reflection over the normalized DSL (including aliases/Concat) inside the app generator; it does not yet add a script-only GHC API loader. Next decision point: whether to keep extending this reflection extractor or introduce the GHC API loader/normalizer now for source-span diagnostics and explicit synonym/type-family expansion reporting.

**2026-07-02T06:50:29Z**

Reflection/IR hardening chunk: lab DTOs now cover WireList, WireDay, WireOptional, WireNullable, and WireRef; ContractIR validates nested WireRef DTO references with stable invalid-wire-ref diagnostics; generated TS and frontend tests consume the expanded DTO shapes.

**2026-07-02T06:54:58Z**

Started the GHC API path with a script-owned probe. Config/nix/scripts/frontend/surface-ghc-probe compiles Application.Script.FrontendSurfaceGhcProbe with project GHC opts plus -package ghc, loads Application.Helper.FrontendSurface.Registry through the GHC API with Opt_ForceRecomp for source spans, locates RegisteredFrontendSurfaces, and prints its source span, kind and synonym RHS. Verification: surface-ghc-probe prints RHS Just '[SurfaceLabSurface] with Registry.hs source span. Next pause point: choose whether to make this probe lower GHC Type values into SurfaceContractIR directly, or first add a raw GHC-extracted AST/Type JSON layer for diffable diagnostics.

**2026-07-02T07:08:56Z**

GHC API probe now has a raw extraction layer: RawRegistry/RawSurface/RawType captures registry source/kind/RHS, surface refs, source spans, and one-step synonym-expanded surface type trees. The probe supports human and --json output, giving a diffable raw artifact before lowering to SurfaceContractIR. Current JSON shows SurfaceLabSurface expands to Surface SurfaceLab (Concat ...); next pause point is type-family/list normalization: choose whether to evaluate approved families (Concat/Append/Lazy option lists) inside the GHC extractor now or hand off normalized reflection output for one more slice.

**2026-07-02T07:14:02Z**

Started approved normalization inside the GHC raw extractor. The --json output now includes normalized surface trees where type synonyms are expanded and approved list helpers Concat/Append plus promoted lists are represented as PromotedList nodes. Current lab normalized tree contains primitive nodes such as Scope/Fragment/Dto under a flattened Surface capability list while preserving source spans on marker/constructor refs. Next pause point: lowering this normalized RawType tree into SurfaceContractIR versus first adding explicit diagnostics for unsupported type families/cycles.

**2026-07-02T07:24:25Z**

Lowered normalized GHC RawType trees into checked SurfaceContractIR inside the probe. The lowerer covers the lab primitive set, fields, wire types, options, selectors, conflict resolutions, DTO refs, naming, and existing ContractIR validation. --json now includes lowered.status=ok and lowered surface summaries (surface-lab, lab scope, lab-shell/lab-panel, refresh-panel, move-lab-card, DTOs). Next pause point: replacing frontend-contracts generation with the GHC lowerer versus first moving raw/lowerer code out of the probe into reusable modules and adding deterministic tests.

**2026-07-02T07:37:18Z**

Refactored the GHC raw contract path out of the probe into Application.Helper.FrontendSurface.Ghc.Raw and .Lower. Added deterministic raw-lowering tests that compare a hand-built normalized lab RawRegistry to registeredFrontendSurfaceContractIR and assert unsupported primitive plus ContractIR validation diagnostics. Verified typecheck, probe JSON lowering, focused Hspec binary tests, frontend-contracts-check, and frontend-test. hspec-test wrapper still compiles but cannot run without the local postgres socket.

**2026-07-02T08:24:56Z**

Moved the GHC extraction/normalization code out of the probe into Application.Helper.FrontendSurface.Ghc.Extract and added a dedicated GenerateFrontendContractsGhc script. The repo frontend/contracts and contracts-check scripts now compile that GHC generator with -package ghc and pass ghc --print-libdir, while the legacy GenerateFrontendContracts reflection path remains import-clean for current shell PATH wrappers. Added progress lines because the GHC generator compile/extraction is otherwise silent for ~30s and can look hung. GHC-generated contracts match the checked-in contracts.

**2026-07-02T08:37:32Z**

Added stable GHC raw-lowering diagnostics/tests for unsupported normalized type-family nodes, malformed non-PromotedList field lists, unsupported wire types, and unsupported options. Verified refreshed PATH canonical frontend-contracts/frontend-contracts-check, typecheck, probe lowering JSON, focused GHC lowering Hspec binary, frontend-contracts-check, frontend-test, and one frontend-contracts-watch regeneration cycle.

**2026-07-02T09:26:59Z**

Final review after guardrails: GHC API extraction/normalization/lowering is in reusable Ghc.Raw/Ghc.Extract/Ghc.Lower modules; frontend-contracts and frontend-contracts-check use GenerateFrontendContractsGhc; generated contracts include lab primitives/DTOs/mount state and pass frontend consumption tests; diagnostics cover unsupported type-family nodes, malformed lists, unsupported wire/options, duplicate names, conflicting/shared declarations, invalid refs, and DTO refs; frontend-surface-guardrails blocks old contract/live/projection authoring for migrated lab paths. Verified frontend-surface-guardrails and frontend/check path after PATH reload.
