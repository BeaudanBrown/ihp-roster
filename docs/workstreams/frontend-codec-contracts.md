# Codec-First Frontend Contracts

Status: active

Decision note (ir-b797, 2026-06-26): choose a small project-owned
`FrontendCodec` foundation over an `autodocodec`/external schema-tooling chain
for the initial implementation. `autodocodec` is feasible through the pinned
Nix Haskell package set, but TypeScript declarations, runtime guards, typed
constants, and registry-derived closed enums would still require additional
schema-to-TypeScript/validator tooling or custom rendering. The custom codec
keeps the existing Haskell generator entrypoints, adds no initial Nix
dependencies, and can produce JSON encode/decode, declarations, guards, and
typed constants from one narrow app-specific source of truth. See
`frontend-codec-contracts-ir-b797-spike.md` for the comparison and prototype
shapes.

Wire-shape note (ir-akhw, 2026-06-26): for app-owned domain alternatives,
prefer closed tagged unions over `null` sentinel states. `null` remains
available in `FrontendCodec` for external/legacy JSON boundaries, but contracts
such as `SurfaceFragmentProtection` should encode absence explicitly, e.g.
`{ kind: "none" }`, so future variants remain regular and validator generation
stays deterministic.

Closeout rule (ir-ccxt, 2026-06-26): production frontend contract modules must
not hand-write TypeScript declarations, validators, constants, or `| string`
escape hatches. Add or extend a `FrontendCodec` schema instead, render typed
constants with `renderTypedConstant`, and keep any dependency/tooling changes in
Nix/devenv/package configuration.

Tickets:

- `ir-o5qk` - parent epic, codec-first generated frontend contracts
- `ir-b797` - spike codec-first frontend contract generator options
- `ir-gwsv` - add hard-coded TypeScript contract lockdown guardrails
- `ir-a6do` - implement chosen codec/schema generator foundation
- `ir-akhw` - migrate live-update contracts to codec-first generation
- `ir-5467` - migrate shared frontend constants and overlay lanes
- `ir-dlks` - migrate interaction contracts to codec-first generation
- `ir-udbq` - derive live surface registry and manifest from descriptors
- `ir-ccxt` - remove manual TypeScript generator escape hatches

Linked predecessor work:

- `ir-vpmd` - generated frontend wire contracts from Haskell schemas
- `ir-jsyd` - typed disposable interaction surfaces and intent bridge

## Goal

Replace the current mixed frontend-contract generator with a codec/schema-first
system where each Haskell/frontend shared concept has one Haskell source of
truth. That source must deterministically produce:

- JSON encoding;
- JSON decoding;
- TypeScript declarations;
- TypeScript runtime validators/type guards; and
- typed TypeScript constants for canonical static values.

The end state must not contain handwritten TypeScript declarations, validators,
or canonical string unions in production Haskell generator modules. Wire shapes
may change to make contracts regular and fully generated.

## Why This Stream Exists

The completed `ir-vpmd` stream moved ownership of live-update and interaction
contracts into Haskell and removed large legacy manual TypeScript blocks. A
follow-up review found that some output is still only "generated" in the sense
that Haskell concatenates TypeScript strings. Current examples include:

- `Application/Helper/Frontend/LiveUpdateSchema.hs`
  - handwritten `SurfaceFragmentProtection` TypeScript declaration;
  - handwritten `isLiveUpdate*` validator block.
- `Application/Helper/Frontend/InteractionSchema.hs`
  - handwritten interaction DTO TypeScript declarations;
  - handwritten `InteractionDom` TypeScript constant;
  - generated unions with string-building helpers;
  - open `| string` escape hatches for canonical names.
- `Application/Helper/Frontend/SurfaceManifestSchema.hs`
  - handwritten manifest TypeScript scaffolding;
  - manifest content mirrored manually from live-surface registration.
- `Application/Helper/Frontend/Contracts.hs`
  - `OverlayLane` still emitted through a small manual union helper.

These are improvements over frontend-owned duplicate types, but they are not the
final model. The final model should make frontend contracts deterministic
artifacts of Haskell codec/schema definitions and registered runtime descriptors.

## Design Principles

1. **One source of truth.** Do not define Haskell JSON instances, TypeScript
   declarations, and validators separately for the same contract.
2. **Codec/schema first.** The canonical frontend contract is a Haskell
   codec/schema value or library-backed codec from which JSON, TS declarations,
   validators, and constants are derived.
3. **No handwritten TypeScript for shared concepts.** Production generator
   modules must not embed TypeScript declarations or validators as raw strings.
4. **No canonical string escape hatches.** Shared frontend contracts should not
   use `| string` for known app concepts such as surface families, fragments,
   layers, sessions, intents, or intent fields.
5. **Generated constants are allowed.** Static canonical values such as DOM
   attribute names, event names, surface manifests, and interaction schemas may
   be emitted as TypeScript constants when they are serialized from Haskell
   values and annotated with generated types.
6. **Runtime metadata stays runtime.** Request-specific URLs, DOM ids, scope
   keys, mount ids, hidden values, and HTMX action/target details remain
   Haskell-rendered page metadata/forms, not global static constants.
7. **Nix owns tooling.** Any new Haskell package, Node/TypeScript tool, schema
   generator, validator generator, or executable used by this stream must be
   introduced through project Nix/devenv/package configuration. Do not require
   global installs or ad hoc npm/npx workflows.

## Generator Options To Spike

The first ticket compares two realistic approaches using the same representative
contracts: `SurfaceScope`, `SurfaceFragmentProtection`, `LiveSurfaceConfig`,
`InteractionDom`, `IntentFormContract`, and `LiveSurfaceManifestEntry`.

### Option A: Library-backed codec/schema first

Prototype `autodocodec` or a similar Haskell codec/schema library.

The source would look conceptually like:

```haskell
instance HasCodec LiveSurfaceConfig where
    codec =
        object "LiveSurfaceConfig" $
            LiveSurfaceConfig
                <$> requiredField "feature" "surface family" .= (.feature)
                <*> requiredField "socketPath" "socket path" .= (.socketPath)
                <*> requiredField "scope" "scope" .= (.scope)
                <*> requiredField "scopeKey" "scope key" .= (.scopeKey)
```

Evaluation questions:

- Can it express the desired tagged-union wire shapes cleanly?
- Can JSON encoding/decoding be derived from the codec?
- Can schema/OpenAPI/JSON Schema output drive readable TypeScript declarations?
- Can runtime validators be generated without handwritten TypeScript?
- What Nix dependencies and build steps are required?

Potential downstream tools include OpenAPI/JSON Schema to TypeScript generators
and standalone validator generation. These tools are acceptable only when they
are wired through Nix/devenv and produce deterministic checked-in output.

### Option B: Project-owned `FrontendCodec`

Build a narrow app-specific codec/schema layer for the shapes this app needs:

- primitives: string, int, bool;
- nullable/optional values;
- arrays;
- exact records;
- closed string enums;
- regular tagged unions;
- named references;
- typed constants.

The source would look conceptually like:

```haskell
liveSurfaceConfigCodec :: FrontendCodec LiveSurfaceConfig
liveSurfaceConfigCodec =
    object "LiveSurfaceConfig" LiveSurfaceConfig
        |> field "feature" text (.feature)
        |> field "socketPath" text (.socketPath)
        |> field "scope" liveUpdateScopeCodec (.scope)
        |> field "scopeKey" text (.scopeKey)
        |> field "resyncFragments" (array liveUpdateWireFragmentCodec) (.resyncFragments)
        |> field "decorateRequestsWithin" (array text) (.decorateRequestsWithin)
```

The same codec must provide JSON encode/decode, TypeScript declarations,
TypeScript guards, and typed constants. This option avoids external generator
complexity but means the project owns a small schema/codec library.

## Decision Criteria

Choose the option that best satisfies, in order:

1. single source of truth;
2. no handwritten TypeScript declarations or validators;
3. generated runtime validators;
4. readable generated TypeScript;
5. low ongoing maintenance;
6. good Haskell authoring ergonomics;
7. simple deterministic Nix/devenv integration.

The decision should be documented in this workstream before implementation
continues past the foundation ticket.

## Target Architecture

The final contract generator should make contract output explicit by category:

- declarations: named TypeScript types/interfaces/unions generated from codecs;
- guards: generated `isX(value: unknown): value is X` functions;
- constants: `export const X: GeneratedType = <Haskell JSON value>`;
- registry output: generated from runtime descriptors, not hand-maintained
  mirror lists.

Production code should not expose a broad `Text` source escape hatch for shared
contracts. If an internal renderer must produce TypeScript text, it should do so
from codec/schema values and be covered by generator tests.

## Migration Scope

### Live updates

Migrate these concepts first because they are unknown browser JSON boundaries:

- `SurfaceScope`;
- `SurfaceFragmentKey`;
- `SurfaceFragmentProtection`;
- `SurfaceWireFragment`;
- `LiveUpdateCommand`;
- `LiveUpdateMessage`;
- `LiveSurfaceConfig`.

Remove the handwritten live-update validator block and any custom raw
TypeScript declaration for protection policies. Wire shape may change to a
regular generated tagged union.

### Shared constants

Generate all shared static constants and small unions from codec/schema values,
including:

- `OverlayLane`;
- interaction DOM attribute names;
- interaction event names if shared by Haskell/frontend;
- HTMX method/swap enums where they cross the Haskell/frontend boundary.

### Interaction contracts

Migrate interaction DTOs/constants from `InteractionSchema.hs` to codec/schema
contracts:

- `InteractionDom`;
- `InteractionMountMetadata`;
- `ServerLayerContract`;
- `DisposableLayerContract`;
- `SessionKindContract`;
- `IntentFieldSchema`;
- `IntentHiddenField`;
- `InteractionIntentTarget`;
- `IntentFormContract`;
- `InteractionConflictPolicy`;
- `InteractionCapabilityContract`;
- `InteractionStaticSchema`;
- `InteractionStaticSchemas`.

Remove canonical `| string` escape hatches.

### Surface registry and manifest

Replace manual manifest mirroring with registered surface descriptors. The same
descriptor source should feed:

- websocket scope authorization;
- invalidation planning;
- context-free/current-venue scope matching;
- generated live surface manifest;
- generated interaction schema registry.

The descriptor model must support context-sensitive definitions such as current
venue surfaces and context-free specialized definitions such as `...ForVenue`.

## Guardrails

Add guard tests early and shrink the allowlist as migrations land. The final
state should ban, in production frontend contract generator modules:

- `TSRawDeclaration`;
- raw `export type`, `export interface`, `export const`, or `export function`
  TypeScript strings for shared contracts;
- `stringUnionDeclaration`-style manual unions;
- `| string` escape hatches for canonical names;
- manually mirrored manifest or interaction schema lists.

Docs, tests, fixtures, and generated output may contain examples or literals,
but production runtime code should prefer generated constants/types where easy.

## Verification

Use focused checks during the stream:

```bash
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-check
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Frontend contract"
bash ./bin/in-env hspec-test --match "LiveUpdate"
bash ./bin/in-env hspec-test --match "Typed interaction surface capabilities"
bash ./bin/in-env hspec-test --match "FrontendSurface"
```

If the chosen option adds packages or tools, also verify the Nix/devenv entry
points that use them and document the exact commands in the relevant ticket
notes.

## Exit Criteria

- The generator choice has been spiked and documented.
- All new dependencies/tools are wired through Nix/devenv/package config.
- Live-update contracts and validators are codec/schema-generated.
- Interaction contracts and constants are codec/schema-generated.
- Shared constants such as overlay lanes are codec/schema-generated.
- Live surface manifest and interaction schema registry are derived from runtime
  descriptors.
- Guard tests have no production-code allowlist for hard-coded TypeScript
  contract output.
- The frontend generated contract entrypoints remain unchanged for callers:
  `frontend-contracts` and `frontend-contracts-check`.
