# Generic Frontend Contract Codecs

Status: superseded by `ir-pkmv` unified `FrontendContract` DSL migration

Tickets:

- Epic: `ir-6kzl` - Solidify generic Haskell-to-TypeScript frontend contracts
- `ir-x7qf` - Add generic frontend codec derivation foundation
- `ir-oxk6` - Migrate simple app, UI region, and roster contracts to generic DTO codecs
- `ir-u3o4` - Migrate live-update wire contracts to generic DTO codecs
- `ir-cn30` - Migrate interaction contracts to generic frontend DTOs
- `ir-yabk` - Migrate live-surface manifest contracts and generic registry containers
- `ir-ws5t` - Enforce exhaustive TypeScript handling for generated closed unions
- `ir-w9dw` - Delete legacy/manual frontend contract generation paths and add final lockdown guards
- `ir-sxxn` - Document final generic frontend contract architecture

## Intent

The current frontend contract system already keeps TypeScript generated from
Haskell-owned schemas, but too much per-contract maintenance still lives in
hand-written `FrontendSchema`, field-name strings, tagged-union variants,
`SchemaRef` names, encoders, parsers, and value-shaped registry declarations.
This stream moves the browser seam to a generic DTO-codec architecture.

The final contract should be:

```text
narrow Haskell frontend DTO type + frontend codec options
  -> Haskell JSON encoder
  -> Haskell JSON parser
  -> FrontendSchema IR
  -> TypeScript type
  -> TypeScript guard
  -> TypeScript parse helper
  -> TypeScript encode helper
```

Wire JSON shape is not stable product API. It may change to whichever regular
shape makes generated Haskell and TypeScript simplest, as long as both sides
consume the generated contracts and tests cover the boundary.

## Scope

In scope:

- `Application/Helper/Frontend/*` contract generation and DTO layout.
- `frontend/ts/generated/contracts.ts` output shape.
- Browser/frontend seam contracts: JSON script/data payloads, live-update config
  and websocket messages, live-surface manifest, interaction schemas and intent
  contracts, UI-region/app/overlay/roster frontend constants and vocabularies.
- TypeScript runtime imports and validation at these boundaries.
- Guardrails against handwritten backend-owned TypeScript contracts.

Out of scope for this stream:

- Broad database model generation for TypeScript.
- Xero, public holiday, Fair Work, passkey/WebAuthn, or other non-browser JSON
  DTOs. They may reuse the same ideas later, but are not part of this epic.
- GHC API or HIE implementation. The DTO/schema IR should leave a clean future
  path for compiler-backed verification.

## Supersession

The generic DTO-codec architecture has been replaced by the unified
`Application.Helper.FrontendContract` DSL/registry. There is no remaining
`Application.Helper.Frontend` codec/DTO/schema-group contract authority.

Current implemented design:

```text
FrontendContract DSL declarations
  -> RegisteredFrontendContracts
  -> FrontendContract.IR
  -> TypeScript renderer
  -> frontend/ts/generated/contracts.ts
```

Haskell runtime wire carriers, currently including live updates, live under
`Application.Helper.FrontendContract.Wire.*`. Their Aeson parse/render path
validates against `FrontendContract.IR` through
`Application.Helper.FrontendContract.Wire.Json`; carrier types are not contract
authority.

Generated TypeScript for each codec should include:

```ts
export type X = ...;
export function isX(value: unknown): value is X { ... }
export function parseX(value: unknown): X { ... }
export function encodeX(value: X): X { return value; }
```

The DTO output should stay JSON-shaped. `encodeX` is identity for current and
expected DTOs, but it is generated uniformly so outbound serialization remains a
contract-owned path and future non-identity encoders cannot be hand-written in
application TypeScript.

Constants and registries remain value-level, but they must be encoded through
DTO codecs. Closed vocabularies should be generated as literal unions; registry
container types should prefer generic structures such as
`Partial<Record<LiveSurfaceFamily, LiveSurfaceManifestEntry>>` over schemas whose
fields are the current registered values.

## Extension Workflow

Adding a frontend-visible concept should normally mean:

1. Add or extend a `FrontendContract` DSL declaration under the appropriate
   `Global` or `Surface` root.
2. Ensure it is reachable from `RegisteredFrontendContracts` or the registered
   surface registry.
3. For Haskell runtime wire use, add typed carriers only under
   `Application.Helper.FrontendContract.Wire.*` and delegate JSON validation to
   `Wire.Json`.
4. Run `bash ./bin/in-env frontend-contracts`.
5. Run `bash ./bin/in-env frontend-check`.
6. Fix TypeScript exhaustiveness failures where app-owned TS branches on a
   generated closed union.

Adding a live surface should not require hand-editing TypeScript. The Haskell
surface/registry path should update generated surface-family, scope-kind,
fragment-kind, manifest value, and interaction linkage contracts.

Adding an interaction intent should update generated intent-name and field-schema
contracts. TypeScript-specific handling must be exhaustive where it switches on
closed generated intent unions; generic data-driven runtime paths need no change.

## Guardrails

The final state has no legacy/manual/spike contract generation leftovers:

- no raw TypeScript declaration blocks in production generator modules outside
  renderer internals;
- no manual TypeScript validators/parsers/encoders for generated contracts;
- no `| string` escape hatches for backend-owned closed vocabularies;
- no shrinking migration allowlists;
- no unregistered DTO contract modules;
- no stale compatibility aliases that exist only for migration.

## Durable Docs Updated

Implemented behavior is now documented in:

- `Application/Helper/FrontendContract/README.md` - unified DSL/wire authoring workflow.
- `Application/Helper/Interaction.SPEC.md` - interaction DTO and exhaustive TypeScript handling contract.
- `Application/Helper/LiveUpdate.SPEC.md` - generated parse/encode and live-update wire boundary rules.
- `Application/Helper/LiveSurface.COOKBOOK.md` - adding surfaces under the manifest/contract generation path.
- `frontend/AGENTS.md` and `static/AGENTS.md` - generated-contract and no-handwritten-contract rules.

## Verification

Expected gates across the epic:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-check
bash ./bin/in-env hspec-test --match "Frontend contract"
bash ./bin/in-env hspec-test --match "FrontendSurface"
bash ./bin/in-env hspec-test --match "Interaction"
bash ./bin/in-env hspec-test --match "LiveUpdate"
bash ./bin/in-env ./bin/doc-drift-check
```

Use focused subsets per child ticket, then the full relevant set before closing
the epic.
