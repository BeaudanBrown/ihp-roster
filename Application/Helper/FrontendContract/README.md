# FrontendContract

`Application.Helper.FrontendContract` is the source of truth for browser-visible
contracts. Contracts are declared in the project DSL, evaluated through explicit
typeclass reflection, checked as contract IR, and rendered to
`frontend/ts/generated/contracts.ts`. Global roots come from
`RegisteredFrontendContracts`; Surface roots come from
`RegisteredFrontendSurfaces` through the single checked reflected
`SurfaceContractIR`. The unified `FrontendContractIR` embeds those checked
`SurfaceIR` values directly. `Application.Helper.FrontendContract.Core` owns the
shared field, wire, schema, diagnostic, and HTMX model, while
`Application.Helper.FrontendContract.Naming` owns naming for both roots.
Generation, server runtime metadata, validation, and semantic Surface
architecture facts consume that model directly; there is no shallow Surface
copy or conversion layer. Test-only Surface fixtures are reflected explicitly
from `Test/` and never enter `RegisteredFrontendSurfaces` or generated production
browser output. Haskell feature code consumes Surface declarations
through marker-indexed accessors and exact `SurfaceFields` in
`Surface.Values`, rather than registry scans or phantom JSON. Those APIs keep
the declared field list as their inference context and expose compact,
marker-named ownership and field-shape diagnostics; the diagnostic contract is
documented in `Surface/README.md`. Live scopes and
fragment keys use the declaration-complete constructors and typed matchers in
`Surface.Live`; raw transport constructors remain internal and feature-owned
identity values live in the corresponding `Surface.<Feature>.Live` module.
Surface resources follow the same shape: `Surface.Resource` owns the opaque
marker-indexed constructor/matcher seam, and concrete values plus domain
matchers live in `Surface.<Feature>.Resource`. No feature-facing free-name/JSON
resource constructor exists. Common Surface
HTMX selectors, triggers, swaps, and sync recipes are typed and render their own
deterministic punctuation; raw syntax requires a non-empty recorded reason.

Every browser root declares explicit reachability: unreachable/server-only,
type-only, guard-only, inbound (type/guard/parser), outbound (type/encoder), or
bidirectional. Exceptional aggregate projections are likewise explicit checked
IR declarations such as `ProjectInteractionDom`; the generator never selects
behavior from a reflected root or Surface name. The TypeScript renderer emits
only the operations justified by that direction. `ServerSchema`, `ServerEvent`,
`ServerDomId`, and `ServerDomAttr` keep Haskell runtime vocabulary in the
reflected IR without creating browser exports. A Haskell-only schema or Surface
declaration remains
available to validation, rendering, and architecture facts without
automatically becoming browser output. Wire primitive aliases are likewise
emitted only when a reachable browser shape uses them.

Roots are split by meaning:

- **Global**: app-wide browser/runtime vocabulary such as DOM ids, event names,
  closed enums, UI-region data, generic interaction runtime shapes,
  live-update wire schemas, and app-shell/dialog request contracts.
- **Surface**: mounted feature UI semantics: scopes, fragments, actions,
  intents, server-side mount state, resources, and interaction metadata.

`AppShellAction` is the server-rendered lane for app-owned shell request initiators
that are not owned by a mounted `FrontendSurface`, including dialog/overlay
workflows targeting the shared dialog overlay mount (initially
`#dialog-overlay-mount`). The DSL owns browser-visible HTMX metadata and
submitted fields; Haskell still owns IHP route/path construction through
`Application.Helper.FrontendContract.AppShell.Runtime`. Successful final dialog
workflow mutations should close/clear overlays and refresh business surfaces
through actor-local/passive invalidation rather than returning authoritative
business fragments OOB.

`InteractionContract` is intentionally generic runtime vocabulary: activation
triggers, field presence, conflict/effect shapes, DOM attrs, values, and pointer
field names. Browser code consumes those names through the generated
`InteractionDom` object. Interaction effects lower to closed semantic IR
carrying typed lifecycle, layer, source, option, and CSS-class choices; browser
spellings are derived from typed markers and never recovered from effect text.
Feature-specific interaction runtime data is derived from registered
`FrontendSurface` declarations into the minimal
`FrontendSurfaceInteractionRegistry`; action metadata, DTO aliases, full static
schemas, and other server-only Surface data are not emitted. Do not add
compatibility shim aliases that resurrect global `Interaction*` roster enums.

Haskell wire code must not re-declare browser shapes. Ergonomic carrier ADTs use
the declaration-indexed builders and exact parsers in
`Application.Helper.FrontendContract.Wire.Carrier`. `recordValue`, `eventValue`,
and `taggedUnionValue` select their complete field/case shape from
`RegisteredFrontendContracts`; their matching parsers validate the unknown
`Aeson.Value` against reflected IR, then expose declaration-ordered typed values
directly to the carrier constructor. No validated value is encoded and decoded
again, and ordinary feature code does not import parser classes or field
constructors.

Outer field presence remains separate from recursive wire nullability. An absent
`OptionalField` is omitted, a present optional nullable value can be explicit
`null`, every `NullableField` must be present, and list/optional/nullable source
containers remain recursive (`WireList WireUUID` maps to `[UUID]`, not `UUID`).
`haskellWireSource` is the canonical checked-IR projection for deterministic
Haskell source generation. Exact marker-indexed IR validation lives in
`Application.Helper.FrontendContract.Wire.Json`; its old name-indexed public
entrypoint is intentionally absent. The migrated live-update carrier module is
`Application.Helper.FrontendContract.Wire.LiveUpdate`, which contains no wire
field, discriminator, or case literals.

Mechanical Haskell Surface adapters use the separate foundation under
`Application.Helper.FrontendContract.Surface.HaskellAdapter`. Nominal adapter
families are associated with existing Surface aliases through
`AdapterFamilySurface`; a `SurfaceResourceAdapterHome family resource` registers
only ownership and never repeats fields, presence, or wires. The normal Haskell
generator combines that typed registry with the checked `SurfaceContractIR`,
Typeable source-module metadata, and `haskellWireSource`. It emits private
feature-adjacent `.Generated.Resource` modules that call only the public
marker-indexed resource builders and matchers. Unsupported source carriers fail
with the owning resource and field in the diagnostic. Production family
associations live in feature-local `Surface.<Feature>.HaskellAdapter` modules,
and the checked aggregate registry assigns exactly one canonical home to every
unique production resource identity. Curated `Surface.<Feature>.Resource`
facades are the generated modules' only consumers and retain only domain aliases,
domain matchers, and meaningful public exports.

Use `frontend-surface-adapters` to write generated Haskell modules and
`frontend-surface-adapters-check` to reject missing, extra, unformatted, or stale
output. Generation does not inspect compiler syntax trees, parse source modules,
or choose behavior from feature-name text.

Generated TypeScript comes through
`Application.Helper.FrontendContract.Contracts`. Exported TypeScript contract
shapes must be rendered from Haskell DSL declarations, `FrontendContract.IR`, or
explicit Haskell support schemas consumed by the same renderer as ordinary
contracts. Raw TypeScript strings are allowed as renderer syntax templates and
for generated runtime data constants, but not as independent `export type` /
`export function` contract authorities. Helper implementations that normalize or
query generated data should live in handwritten `frontend/ts` runtime modules and
import generated types/data.

`FrontendSurface*` TypeScript names that remain in generated output are
runtime/mount metadata for server-rendered UI, not a parallel contract
authority. Reflection generates one exact per-surface mount type/guard and their
`FrontendSurfaceMountConfig` union; handwritten aggregate mount parsers and
compatibility aliases are forbidden. The live bundle consumes only
`FrontendSurfaceFragmentRegistry`; the interaction bundle consumes only
`FrontendSurfaceInteractionRegistry`. They remain separate and minimal; action
metadata and contained-surface topology stay server-only. Subscriptions, websocket invalidations, and actor details use the
generated `SurfaceScope` and semantic `SurfaceFragmentKey` contract types only.
Shared server/browser DOM ids and semantic tokens come from reflected global or
Surface declarations, rather than copied string literals. Every fragment owns
one typed `MountTarget`; descriptor and view IDs are rendered through
`surfaceFragmentTargetId` from declaration-ordered typed fields. Server-only
`MountState` declarations are deliberately absent from browser output.
