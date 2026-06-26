# ir-b797 Frontend Codec Generator Spike

Date: 2026-06-26

## Scope

This spike compared two ways to replace hard-coded TypeScript contract output
while keeping the public entrypoints unchanged:

- `bash ./bin/in-env frontend-contracts`
- `bash ./bin/in-env frontend-contracts-check`

Representative contracts considered:

- `LiveUpdateScope`
- `LiveFragmentProtection`
- `LiveSurfaceConfig`
- `InteractionDom`
- `IntentFormContract`
- `LiveSurfaceManifestEntry`

The spike did not migrate production contracts. The examples below are design
prototypes for the implementation ticket.

## Option A: `autodocodec` / schema-tooling path

### Prototype shape

A library-backed prototype would add Haskell packages similar to:

```nix
haskellPackages = p: with p; [
    autodocodec
    autodocodec-schema
]
```

`autodocodec` and `autodocodec-schema` are present in the pinned nixpkgs set
used by this repo (`0.5.0.0` and `0.2.0.1` respectively), so the Haskell side is
feasible through Nix rather than global installation.

Representative authoring model:

```haskell
instance HasCodec LiveSurfaceConfig where
    codec = object "LiveSurfaceConfig" $
        LiveSurfaceConfig
            <$> requiredField "feature" "surface family" .= (.feature)
            <*> requiredField "socketPath" "websocket path" .= (.socketPath)
            <*> requiredField "scope" "live update scope" .= (.scope)
            <*> requiredField "scopeKey" "scope key" .= (.scopeKey)
            <*> requiredField "resyncFragments" "initial fragments" .= (.resyncFragments)
            <*> requiredField "decorateRequestsWithin" "request decoration selectors" .= (.decorateRequestsWithin)
```

A regular tagged-union `LiveUpdateScope` would need to be encoded as explicit
objects, for example:

```json
{ "kind": "roster_week", "venueId": "...", "rosterGroupId": "...", "weekOffset": 0 }
{ "kind": "support_platform" }
```

`LiveFragmentProtection` can be represented as a nullable codec over a closed
sum:

```json
null
{ "kind": "focused_field", "activeSelector": "...", "fieldKeyAttr": "...", "fieldNameFallback": true, "containerSelector": null }
```

### Output path

The library path still needs at least one downstream renderer/tool:

1. Haskell codec -> JSON encode/decode via `autodocodec`.
2. Haskell codec -> JSON Schema/OpenAPI via `autodocodec-schema`.
3. JSON Schema/OpenAPI -> TypeScript declarations.
4. JSON Schema/OpenAPI -> runtime validators/type guards.
5. Separate Haskell serialization path for typed constants such as
   `InteractionDom` and `LiveSurfaceManifest`.

The pinned nixpkgs set contains `quicktype` as a top-level package, but the
obvious Node packages checked during the spike (`json-schema-to-typescript`,
`ajv-cli`, `typescript-json-schema`) are not available as historical
`nodePackages.*` attributes in this nixpkgs revision. They could still be added
through npm lockfile/Nix packaging or replaced with a Haskell renderer, but that
is extra build-system work for the foundation ticket.

### Example generated TypeScript target

A schema-tooling path should produce declarations equivalent to:

```ts
export type LiveUpdateScope =
    | { kind: "roster_week"; venueId: string; rosterGroupId: string; weekOffset: number }
    | { kind: "admin_venue_config"; venueId: string }
    | { kind: "support_platform" };

export type LiveFragmentProtection =
    | null
    | { kind: "focused_field"; activeSelector: string; fieldKeyAttr: string; fieldNameFallback: boolean; containerSelector: string | null };

export type LiveSurfaceConfig = {
    feature: string;
    socketPath: string;
    scope: LiveUpdateScope;
    scopeKey: string;
    resyncFragments: LiveUpdateWireFragment[];
    decorateRequestsWithin: string[];
};
```

Runtime validators are the weak point. JSON Schema can describe these shapes,
but producing small checked-in `isLiveSurfaceConfig(value): value is
LiveSurfaceConfig` guards requires another deterministic renderer or packaged
validator generator. Generated generic JSON-schema validators are likely larger
and less readable than the current hand-written guards.

### Findings

Strengths:

- Good Haskell authoring model for records and regular tagged unions.
- JSON encode/decode can come from the codec, satisfying the single-source goal
  for ordinary JSON DTOs.
- Haskell packages are available through Nix.

Weaknesses:

- TypeScript declarations and guards require an additional schema-to-TS and
  validator toolchain or a custom renderer anyway.
- Typed constants (`InteractionDom`, `LiveSurfaceManifest`) are not solved by
  JSON schema alone; they still need an app-level declaration/constant emission
  layer.
- Tool output may be less stable/readable, and its Nix integration is more
  complex than the repo's current single Haskell generator command.
- The app needs closed app-specific string enums derived from runtime
  descriptors. General schema tooling does not remove that registry plumbing.

Conclusion: feasible, but not the best fit unless the project also wants a
public JSON Schema/OpenAPI artifact. It adds package/toolchain complexity while
still requiring custom generation for constants and ergonomic validators.

## Option B: project-owned `FrontendCodec`

### Prototype shape

A narrow app-owned codec can make the codec itself the single source of truth:

```haskell
data FrontendCodec a = FrontendCodec
    { codecName     :: Maybe Text
    , codecSchema   :: FrontendSchema
    , encodeValue   :: a -> Aeson.Value
    , parseValue    :: Aeson.Value -> Aeson.Parser a
    }
```

The `FrontendSchema` AST only needs the shapes used by browser contracts:

```haskell
data FrontendSchema
    = FString
    | FInt
    | FBool
    | FNull
    | FNullable FrontendSchema
    | FArray FrontendSchema
    | FRecord Text [FrontendField]
    | FStringEnum Text [Text]
    | FTaggedUnion Text Text [FrontendVariant]
    | FRef Text
```

Renderer functions consume the same schema:

```haskell
renderTypeDeclaration :: FrontendSchema -> Text
renderGuardDeclaration :: Text -> FrontendSchema -> Text
renderTypedConstant :: FrontendCodec a -> Text -> a -> Text
```

The JSON instances can delegate to the codec instead of sitting beside it:

```haskell
instance Aeson.ToJSON LiveSurfaceConfig where
    toJSON = encodeFrontend liveSurfaceConfigCodec

instance Aeson.FromJSON LiveSurfaceConfig where
    parseJSON = parseFrontend liveSurfaceConfigCodec
```

### Representative contract prototypes

```haskell
liveUpdateScopeCodec :: FrontendCodec LiveUpdateScope
liveUpdateScopeCodec = taggedUnion "LiveUpdateScope" "kind"
    [ variant "roster_week" RosterWeek
        |> field "venueId" text (.venueId)
        |> field "rosterGroupId" text (.rosterGroupId)
        |> field "weekOffset" int (.weekOffset)
    , variant "support_platform" SupportPlatform
    ]

liveFragmentProtectionCodec :: FrontendCodec LiveFragmentProtection
liveFragmentProtectionCodec = nullable $ taggedUnion "LiveFragmentProtectionPolicy" "kind"
    [ variant "focused_field" FocusedFieldProtectionConfig
        |> field "activeSelector" text (.activeSelector)
        |> field "fieldKeyAttr" text (.fieldKeyAttr)
        |> field "fieldNameFallback" bool (.fieldNameFallback)
        |> field "containerSelector" (nullable text) (.containerSelector)
    ]

liveSurfaceConfigCodec :: FrontendCodec LiveSurfaceConfig
liveSurfaceConfigCodec = object "LiveSurfaceConfig" LiveSurfaceConfig
    |> field "feature" text (.feature)
    |> field "socketPath" text (.socketPath)
    |> field "scope" liveUpdateScopeCodec (.scope)
    |> field "scopeKey" text (.scopeKey)
    |> field "resyncFragments" (array liveUpdateWireFragmentCodec) (.resyncFragments)
    |> field "decorateRequestsWithin" (array text) (.decorateRequestsWithin)
```

Typed constants use the same codec/renderer rather than raw TypeScript blocks:

```haskell
interactionDomCodec :: FrontendCodec InteractionDom
interactionDomConstant :: TypeScriptDeclaration
interactionDomConstant = typedConstant "InteractionDom" interactionDomCodec interactionDom

liveSurfaceManifestEntryCodec :: FrontendCodec LiveSurfaceManifestEntry
liveSurfaceManifestConstant :: TypeScriptDeclaration
liveSurfaceManifestConstant = typedConstant
    "LiveSurfaceManifest"
    (recordMap liveSurfaceManifestEntryCodec)
    registeredLiveSurfaceManifestByFamily
```

For `IntentFormContract`, the implementation should introduce a concrete wire
DTO for the browser boundary so generic Haskell parameters do not leak into the
renderer:

```haskell
data IntentFormContractWire = IntentFormContractWire
    { intent :: Text
    , name :: Text
    , action :: Text
    , method :: HtmxMethod
    , trigger :: Text
    , target :: InteractionIntentTargetWire
    , swap :: HtmxSwap
    , fields :: [IntentFieldSchema]
    , hiddenFields :: [IntentHiddenField]
    , sync :: Maybe Text
    , disabledElement :: Maybe Text
    }
```

Closed app-specific unions such as `InteractionIntentName` and
`InteractionIntentFieldName` should be generated from registered interaction
schemas, then referenced by the wire codec where appropriate. This removes the
current `| string` escape hatches.

### Example generated TypeScript target

The custom renderer can intentionally emit the small style this repo wants:

```ts
export type LiveSurfaceConfig = {
    feature: string;
    socketPath: string;
    scope: LiveUpdateScope;
    scopeKey: string;
    resyncFragments: LiveUpdateWireFragment[];
    decorateRequestsWithin: string[];
};

export function isLiveSurfaceConfig(value: unknown): value is LiveSurfaceConfig {
    return isRecord(value)
        && typeof value.feature === "string"
        && typeof value.socketPath === "string"
        && isLiveUpdateScope(value.scope)
        && typeof value.scopeKey === "string"
        && isArrayOf(value.resyncFragments, isLiveUpdateWireFragment)
        && isArrayOf(value.decorateRequestsWithin, isString);
}

export const InteractionDom: InteractionDomContract = {
    attributes: {
        surface: "data-bepis-surface",
        surfaceFamily: "data-bepis-surface-family"
    },
    values: {
        enabled: "true",
        activationMarker: "activation"
    },
    pointerFields: {
        sessionKind: "sessionKind",
        pointerId: "pointerId"
    }
};
```

### Findings

Strengths:

- Single source of truth for JSON encode/decode, declarations, guards, and
  constants.
- No new dependency is required for the foundation; Nix impact is minimal.
- Output style can match the repo's existing generated TypeScript and guard
  naming conventions.
- Constants and registry-derived unions are first-class, not bolted on after a
  general schema step.
- The supported shape set is deliberately small and matches the app's browser
  contracts.

Weaknesses:

- The project owns a small codec/schema library and its tests.
- The implementation must be disciplined: production generator modules should
  only render from schema values, and guard tests must prevent raw TypeScript
  escape hatches from returning.
- General-purpose schema artifacts are not produced unless explicitly added
  later.

Conclusion: best fit for this repo. It minimizes tooling complexity, keeps
contract output deterministic under the existing Haskell entrypoints, and covers
app-specific typed constants better than a generic schema toolchain.

## Recommendation

Choose Option B: implement a small project-owned `FrontendCodec` foundation in
`ir-a6do`.

Implementation notes for `ir-a6do`:

1. Add `Application.Helper.Frontend.Codec` with the schema AST, encode/decode
   helpers, TypeScript declaration renderer, guard renderer, and typed-constant
   renderer.
2. Keep `frontend-contracts` and `frontend-contracts-check` as the public
   commands; they should continue calling the Haskell generator composition
   root.
3. Start with the representative contracts from this spike and tests for their
   rendered declarations/guards before migrating all production contracts.
4. Prefer regular tagged unions with explicit `kind` fields; allow wire-shape
   changes where they remove manual special cases.
5. Generate registry-derived closed enums from Haskell descriptors and remove
   `| string` escape hatches as each contract migrates.
6. Add no new Nix dependencies for the initial custom foundation. If future
   JSON Schema/OpenAPI export is desired, add it as a separate ticket rather
   than coupling it to frontend-contract generation.

## Verification

This spike changed documentation/ticket artifacts only. No generated contracts
or production Haskell modules were modified.
