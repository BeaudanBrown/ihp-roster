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
`Surface.Values`, rather than registry scans or phantom JSON. Common Surface
HTMX selectors, triggers, swaps, and sync recipes are typed and render their own
deterministic punctuation; raw syntax requires a non-empty recorded reason.

Every browser root declares explicit reachability: unreachable/server-only,
type-only, guard-only, inbound (type/guard/parser), outbound (type/encoder), or
bidirectional. The TypeScript renderer emits only the operations justified by
that direction. `ServerSchema`, `ServerEvent`, `ServerDomId`, and
`ServerDomAttr` keep Haskell runtime vocabulary in the reflected IR without
creating browser exports. A Haskell-only schema or Surface declaration remains
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
`InteractionDom` object. Feature-specific interaction runtime data is derived
from registered `FrontendSurface` declarations into the minimal
`FrontendSurfaceInteractionRegistry`; action metadata, DTO aliases, full static
schemas, and other server-only Surface data are not emitted. Do not add
compatibility shim aliases that resurrect global `Interaction*` roster enums.

Haskell wire code must not re-declare browser shapes. Typed carrier modules may
exist for ergonomic runtime APIs, but JSON validation/parsing/rendering delegates
to `Application.Helper.FrontendContract.Wire.Json` over the registered IR. The
live-update carrier module is
`Application.Helper.FrontendContract.Wire.LiveUpdate`.

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
