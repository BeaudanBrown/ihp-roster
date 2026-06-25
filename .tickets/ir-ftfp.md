---
id: ir-ftfp
status: closed
deps: []
links: []
created: 2026-06-25T11:57:29Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-vpmd
tags: [agent-loop, frontend, contracts, haskell, typescript, spike]
---
# Spike aeson-typescript for frontend wire contracts

Prove aeson-typescript fits this IHP/Nix project and our desired generated wire-contract shapes before broad migration.

## Design

Add aeson-typescript to the project Haskell package set. Build a small representative contract prototype covering a plain enum, a discriminated union with tag/type field, a record with optional/null fields, UUID-as-string/newtype handling, and a nested wire message. Compare generated TypeScript against the current frontend needs and document selected Aeson Options/encoding conventions. Wire protocol changes are acceptable if generated Haskell JSON and TypeScript stay aligned.

## Acceptance Criteria

Project typecheck can import aeson-typescript; frontend-contracts can generate a representative snippet; chosen encoding conventions are documented in the ticket notes or code comments; risks/limitations are recorded before migration tickets depend on it.


## Notes

**2026-06-25T12:09:39Z**

Spike result: aeson-typescript 0.6.4.0 imports and typechecks in the IHP/Nix env. Prototype generator is wired into frontend-contracts under Application.Helper.Frontend.AesonTypeScriptSpike and covers string enum, TaggedObject union with type tag, nullable Maybe (omitNothingFields=False), optional Maybe (omitNothingFields=True), custom string-like id wrapper, and nested message arrays. Intended options for live-update/interaction DTOs: derive Aeson and TypeScript from the same options, use TaggedObject with tagFieldName="type" for unions, use all-nullary string tags for enums, use explicit string-like wrappers for UUID/browser ids, and choose per-record Maybe semantics: nullable key-present fields or optional omitted fields. Limitation/risk: aeson-typescript mirrors Aeson options, so a single Maybe field is either optional or nullable by default, not both optional and null, unless we add a custom TS instance/options wrapper.
