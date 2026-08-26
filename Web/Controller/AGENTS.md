# Controller Guidelines

Read the IHP controller, validation, and QueryBuilder guides referenced by root
`AGENTS.md` before controller work.

## Wiring And Boundaries

A new controller needs all four owners:

1. action type in `Web/Types.hs`
2. `AutoRoute` in `Web/Routes.hs`
3. import and `parseRoute` in `Web/FrontController.hs`
4. implementation under `Web/Controller/`

Import `Web.Controller.Prelude`. Keep IHP as the lifecycle/router boundary;
Bepis action semantics enter through `runBepis` in normal `beforeAction` and
`action` definitions.

Use QueryBuilder, not raw SQL. Parse request IDs with total helpers, then query
through the current venue/tenant before mutation. Malformed or cross-scope input
must produce controlled validation/4xx/redirect behavior, never a 500.

`fill` records parse errors but ignores missing parameters. Pair it with
`requireParam` for required values, normalize user text, enforce schema-aligned
lengths, and rerender through `ifValid`. Browser `required`, hidden fields, and
select options are not server validation. Build URLs with `appendQueryParams`.

Wrap state changes and required side effects in one transaction. Emit audit,
live-update, response, and other architecture facts from the helpers performing
the real effects; do not add descriptive metadata beside helper calls or hide
business effects in broad typeclass instances.

## HTMX And Live Surfaces

Read `Application/Helper/Interaction.SPEC.md`,
`Application/Helper/LiveUpdate.SPEC.md`, and
`Application/Helper/FrontendContract/Surface/README.md` before interaction or
live-surface work.

Validation failures return the submitted form/dialog fragment directly. For a
migrated `FrontendSurface`, successful actor responses emit semantic actor
refresh plus requester-only extras; passive viewers receive listener-delivered
durable resource invalidation and refetch the same authorized plain fragment
GETs. The mutation/domain/audit writes and typed outbox event use one atomic
mutation boundary. Do not publish after commit, return authoritative business
OOB fragments, or broadcast scopes directly from feature controllers.

Keep scopes authorized logical data slices, fragment mappings in `SurfaceImpl`,
and fan-out expansion bounded to active scopes. Fragment actions require the
same authorization as full pages. Use generated AppShell/Surface action and
intent helpers rather than ad hoc JSON/fetch endpoints or handwritten HTMX
contracts.

Workflow dialogs use dedicated fragment actions and the shared dialog mount;
pickers and toasts are separate lanes. Preserve URL context through ISO
`anchorDate`; `RosterWeeksAction` remains the canonical current-window reset.

## Verification

Run `bash ./bin/in-env typecheck` and focused Hspec for changed actions,
including missing/malformed/cross-venue inputs and authorization. Run focused
E2E when browser navigation, HTMX, websocket, dialog, or interaction behavior
changes.
