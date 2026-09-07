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

Wrap each atomic local change and its required side effects in its owning
transaction; preserve explicit provider phases described below. Emit audit,
live-update, response, and other architecture facts from the helpers performing
the real effects; do not add descriptive metadata beside helper calls or hide
business effects in broad typeclass instances.

## Feature Workflow Contract

Use existing feature modules to hide coherent operations, not mandatory layers.
Controllers retain IHP/runBepis, access-policy invocation, staged request
adaptation and response selection. Workflows own operation-specific loading,
validation/application and completion data; mutation owners retain locks,
revalidation, writes and durable publication; response owners retain exact HTTP
and copy. Projections remain with the existing read-model/layout owner.

The delivered interfaces intentionally differ:

- `Web.Exports.WorkbookConfigurations` consumes nominal AppShell requests after
  controller access checks and returns a closed editor outcome with the exact
  fallback/submitted draft. Delete calls its already-deep mutation directly.
- `Web.RosterWeeks.ShiftWorkflow` accepts raw dialog values and the snapshots
  loaded for earlier controller scope/calendar/placement checks. Create owns
  cell reuse; edit derives Published fill and returns post-commit row impact.
  These records promise neither authorization nor freshness by themselves.
- `Web.Billing.Mutations` composes Checkout's existing phase runner and audit
  callback; `Web.Billing.ReadModel` hides owner/support and exact-return
  assembly, while `Web.Billing.Responses` retains hosted completion validation,
  request audits and HTTP. See `Application/Billing/README.md`. Do not wrap the
  whole provider operation in an ordinary-form transaction.

Preserve error and side-effect ordering when adopting this contract:

- Do not eagerly parse all fields before an earlier denial. Omitted, blank,
  malformed and protected-field presence retain their existing distinctions.
  Consume generated operation-local request evidence, not duplicate wire DTOs.
- Scoped lookup and under-lock revalidation stay at their existing points.
  Workbook's absent-row error precedes name validation; roster materialization
  may precede invalid form feedback. Do not add an encompassing transaction.
- Outcomes carry domain errors or exact dialog continuations and committed
  completion data, not callbacks for further controller-side business work.
  A sum type is useful for distinct outcomes; `Either` remains appropriate where
  there are only rejection/success cases. Do not require one universal result.
- IHP terminal responses and unexpected exceptions must keep escaping their
  current boundaries. `withDurableLiveMutationOutcome` selects publication, not
  rollback: returning `Left` after writes can commit them. Preserve existing
  rollback mechanisms and never catch a response exception as a domain error.
- Actual/effective actor and session/support provenance come from initialized
  request context at the real effect. Never substitute submitted IDs, fabricate
  a support venue membership, or add audits to an operation that had none.
- Keep completion HTTP outside committed mutation transactions. Preserve native
  versus HTMX branches, no-toast variants, warning/overlay ordering and passive
  publication ownership. A post-commit projection failure must not repeat writes.

Before movement, characterize precedence, scoped invalid/stale input, rollback,
resource/effect counts and independent HTTP responses. Keep those public seam
assertions after migration. Review depth by reduced caller knowledge, never by
line counts, export counts or a ban on controller IO/framework imports.

For Timesheets, Leave or Billing adoption, extend only demonstrated dependency
roles in `scripts/architecture/workflow-boundaries.mjs` with an accountable
feature owner and positive/negative fixtures. Its import checks are a narrow
regression guard, not proof of transaction behavior or transitive effect purity.
Do not add empty modules, pass-through wrappers or an effects registry to satisfy
it. Feature-specific contracts remain authoritative.

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
