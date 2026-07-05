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
`Application.Helper.FrontendContract.Contracts`. The old
`Application.Helper.Frontend` codec/DTO/schema-group tree has been removed.
