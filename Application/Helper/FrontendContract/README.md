# FrontendContract

`Application.Helper.FrontendContract` is the source of truth for browser-visible
contracts. Contracts are declared in the project DSL, collected by
`RegisteredFrontendContracts`, lowered to `FrontendContract.IR`, and rendered to
`frontend/ts/generated/contracts.ts`.

Roots are split by meaning:

- **Global**: app-wide browser/runtime vocabulary such as DOM ids, event names,
  closed enums, UI-region data, interaction vocabulary, and live-update wire
  schemas.
- **Surface**: mounted feature UI semantics: scopes, fragments, actions,
  intents, mount state, resources, and interaction metadata.

Haskell wire code must not re-declare browser shapes. Typed carrier modules may
exist for ergonomic runtime APIs, but JSON validation/parsing/rendering delegates
to `Application.Helper.FrontendContract.Wire.Json` over the registered IR. The
live-update carrier module is
`Application.Helper.FrontendContract.Wire.LiveUpdate`.

Generated TypeScript comes through
`Application.Helper.FrontendContract.Contracts`. `FrontendSurface*` TypeScript
names that remain in generated output are runtime/mount metadata adapters for
server-rendered UI, not a parallel contract authority; websocket/browser wire
shapes remain the generated `Surface*` and live-update contract types.

The old `Application.Helper.Frontend` codec/DTO/schema-group tree has been
removed. Guardrails fail if production Haskell modules or imports under that
namespace return.
