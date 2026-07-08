# FrontendContract

`Application.Helper.FrontendContract` is the source of truth for browser-visible
contracts. Contracts are declared in the project DSL, collected by
`RegisteredFrontendContracts`, lowered to `FrontendContract.IR`, and rendered to
`frontend/ts/generated/contracts.ts`.

Roots are split by meaning:

- **Global**: app-wide browser/runtime vocabulary such as DOM ids, event names,
  closed enums, UI-region data, generic interaction runtime shapes,
  live-update wire schemas, and app-shell/dialog request contracts.
- **Surface**: mounted feature UI semantics: scopes, fragments, actions,
  intents, mount state, resources, and interaction metadata.

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
runtime/mount metadata adapters for server-rendered UI, not a parallel contract
authority; websocket/browser wire shapes remain the generated `Surface*` and
live-update contract types.

The old `Application.Helper.Frontend` codec/DTO/schema-group tree has been
removed. Guardrails fail if production Haskell modules or imports under that
namespace return.
