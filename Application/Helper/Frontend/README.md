# Frontend Contract Generation

This directory owns the Haskell-to-TypeScript browser boundary for Bepis.

## Contract Rule

If TypeScript reads a value from generated constants, JSON script payloads,
websocket messages, event detail, `data-*` attributes, or static surface
manifests, Haskell exposes it through a `FrontendCodec` and a registered
contract group. Do not add hand-written TypeScript unions, validators, parsers,
encoders, or canonical browser strings for backend-owned concepts.

Generated TypeScript lives in `frontend/ts/generated/contracts.ts` and is not
hand-edited. Every named codec emits the same public shape:

```ts
export type X = ...;
export function isX(value: unknown): value is X { ... }
export function parseX(value: unknown): X { ... }
export function encodeX(value: X): X { return value; }
```

DTOs are JSON-shaped. Current generated `encodeX` helpers are identity, but they
are emitted uniformly so outbound browser payloads use the same contract-owned
path as inbound parsing.

## Layout

- `Codec.hs` is the small schema IR and TypeScript renderer.
- `Generic.hs` derives codecs for narrow DTO records, enums, tagged unions,
  arrays, refs, optional fields, nullable fields, and partial record containers.
- `Options.hs` owns naming/tag options such as snake/kebab-case conversion.
- `Dto/*.hs` modules contain browser-facing DTOs/enums only:
  - `App`, `UiRegion`, `Roster`
  - `LiveUpdate`
  - `Interaction`
  - `LiveSurface`
- `*Schema.hs` modules are thin contract-group registration roots. They should
  not contain large hand-authored field lists or raw TypeScript snippets.
- `Contracts.hs` is the composition root that concatenates registered groups.

Use explicit frontend DTOs instead of arbitrary internal server/domain types.
Internal polymorphic or feature-local types should convert to a narrow DTO at
the browser seam.

## Adding Or Changing A Contract

1. Define or extend the narrow Haskell DTO/enum in `Application/Helper/Frontend/Dto/`.
2. Prefer `Generic` plus `genericFrontendCodecWith`; use `FrontendRef`,
   `FrontendOptional`, and `FrontendNullable` for nested refs and field shape.
3. Use a small manual `FrontendCodec` only for justified renderer-level shapes
   such as closed text vocabularies or partial-record registries.
4. Register codecs/constants in exactly one `FrontendContractGroup` via the
   matching `*Schema.hs` module.
5. Add the declaration to `frontendContractDeclarations` in `Contracts.hs` only
   when creating a new group.
6. Regenerate contracts and fix TypeScript call sites to use generated
   constants, `isX`, `parseX`, and `encodeX` helpers.
7. Add focused tests for important seams: Haskell JSON round-trips,
   generated-source guardrails, and frontend parser/runtime behavior.

Commands:

```bash
bash ./bin/in-env frontend-contracts
bash ./bin/in-env typecheck
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-check
bash ./bin/in-env hspec-test --match "Frontend contract"
```

## Live Surfaces And Interactions

Adding a registered live surface should update generated `LiveSurfaceFamily`,
registered scope/fragment kind unions, `LiveSurfaceManifest`, and optional
interaction-schema linkage through `Web.LiveSurfaceRegistry`; do not hand-edit
TypeScript manifests.

Adding an interaction intent should update the Haskell static interaction schema
and generated `InteractionIntentName`/field contracts. Generic TypeScript should
remain data-driven. If TypeScript branches on a generated closed union, use
`assertNever` in the `default` branch so union growth fails `frontend-check`
until handled.

## Guardrails

`Test/FrontendContractsSpec.hs` and frontend checks enforce the final state:

- raw TypeScript declaration snippets are confined to renderer internals;
- no handwritten `isX`/`parseX`/`encodeX` helpers for generated contract names;
- no `| string` escape hatches for backend-owned closed vocabularies;
- every DTO module is registered by a schema group;
- legacy/manual/spike contract modules stay deleted;
- app/runtime TypeScript imports generated contracts instead of duplicating
  canonical `data-bepis-*`, event, fragment, surface, layer, intent, or field
  strings.

## Scope

Generate browser-boundary DTOs only. Avoid exporting broad database/domain
models unless there is a deliberately narrow frontend payload. Xero, passkeys,
external APIs, and database model generation are outside this contract system
unless a future ticket explicitly opts them in. A future GHC API/HIE verifier may
inspect the DTO/schema IR, but the current source of truth is the checked Haskell
DTO codec registry plus tests.
