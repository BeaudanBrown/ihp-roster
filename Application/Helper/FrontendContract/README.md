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
copy or conversion layer. Haskell feature code consumes Surface declarations
through marker-indexed accessors and exact `SurfaceFields` in
`Surface.Values`, rather than registry scans or phantom JSON. Common Surface
HTMX selectors, triggers, swaps, and sync recipes are typed and render their own
deterministic punctuation; raw syntax requires a non-empty recorded reason.

Roots are split by meaning:

- **Global**: app-wide browser/runtime vocabulary such as DOM ids, event names,
  closed enums, UI-region data, generic interaction runtime shapes,
  live-update wire schemas, and app-shell/dialog request contracts.
- **Surface**: mounted feature UI semantics: scopes, fragments, actions,
  intents, server-side mount state, resources, and interaction metadata.

`AppShellAction` is the generated lane for app-owned shell request initiators
that are not owned by a mounted `FrontendSurface`, including dialog/overlay
workflows targeting the shared dialog overlay mount (initially
`#dialog-overlay-mount`). The DSL owns browser-visible HTMX metadata and
submitted fields; Haskell still owns IHP route/path construction through
`Application.Helper.FrontendContract.AppShell.Runtime`. Successful final dialog
workflow mutations should close/clear overlays and refresh business surfaces
through actor-local/passive invalidation rather than returning authoritative
business fragments OOB.

`InteractionContract` is intentionally generic runtime vocabulary: activation
triggers, field presence, conflict/effect shapes, DOM attrs, and generic
capability/static-schema records. Feature-specific interaction vocabulary such
as roster intent names, roster field names, sessions, disposable layers, and
surface-family keys is derived from registered `FrontendSurface` declarations
and rendered as `FrontendSurfaceInteraction*` TypeScript unions. Do not add
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
compatibility aliases are forbidden. Subscriptions, websocket invalidations,
and actor details use the generated `SurfaceScope` and semantic
`SurfaceFragmentKey` contract types only. Server-only `MountState` declarations
are deliberately absent from browser output.

The old `Application.Helper.Frontend` codec/DTO/schema-group tree has been
removed. Guardrails fail if production Haskell modules or imports under that
namespace return.
