# Architecture Map

This is a lightweight map of the app's main code-owned subsystems. Detailed
behavior belongs in subsystem-local docs.

## Deterministic Architecture Tooling

Project-local architecture commands are declared in `.pi/architecture.json` for
Pi agents and are exposed through the devenv scripts. Generated outputs are
initially gitignored under `output/architecture/`; focused query diagrams are
written under `.pi/tmp/architecture-query/` or `.pi/tmp/architecture-trace/`.

```bash
bash ./bin/in-env architecture-contracts
bash ./bin/in-env architecture-facts
bash ./bin/in-env architecture-schema
bash ./bin/in-env architecture-web-map
bash ./bin/in-env architecture-module-graph
bash ./bin/in-env architecture-check-fresh
```

Focused agent queries use Pi's `architecture_queries` and `architecture_query`
tools. The current project queries are:

- `component`: generic focused controller/action/table/module diagrams.
- `controller`: grouped controller/action surface reports with action kind and
  reference counts.
- `request-flow`: static action request-flow reports from handler source,
  references, response/realtime heuristics, and provenance.
- `realtime-usage`: live freshness usage metrics and diagrams independent of
  the current websocket/fragment mechanism.
- `generated-contracts`: Haskell contract/codecs to generated TypeScript and
  frontend consumer reports.
- `table`: classified schema neighborhoods with audit edge filtering.
- `module`: filtered module dependency neighborhoods.
- `trace`: focused OpenTelemetry trace timing diagrams from profile artifacts.

Do not treat generated diagrams as durable source until a future change promotes
a specific output set into version control.

### Flexibility Contract

Architecture tooling must report observed facts and derived relationships, not
hard-code today's implementation shape as permanent architecture. Keep the
pipeline layered:

```text
source scanners -> versioned facts -> semantic classifiers -> query views -> diagrams/reports
```

Rules for future changes:

- Facts should be source/provenance oriented: entity kind, relationship kind,
  source file/line when known, scanner name, and confidence where practical.
- Query names should describe durable intent, e.g. `request-flow`,
  `realtime-usage`, `generated-contracts`, `controller`, and `table`, rather
  than temporary mechanics such as a specific websocket/fragment implementation.
- Current mechanisms such as websocket invalidation, HTMX fragment refetch,
  Haskell-owned generated TypeScript, and `data-bepis-*` surfaces should appear
  as attributes/classifications on facts, not as assumptions in the harness.
- Diagrams are views over facts. If the live-update mechanism changes, replace
  the relevant scanner/classifier/query view and regenerate diagrams.
- Prefer metrics/tables/sections in query results when a diagram would be a
  hairball.

### Query Roadmap

Implemented project-local query families now include:

- `controller`: grouped action inventory with handler source locations and
  inbound action reference counts.
- `request-flow`: action -> controller -> handler -> auth/scope heuristics ->
  data/response/realtime heuristics.
- `realtime-usage`: coverage for surfaces that use live freshness, regardless of
  whether the current mechanism is websocket invalidation, polling, SSE, or
  something else.
- `generated-contracts`: Haskell contract/codecs -> generated TypeScript ->
  frontend consumers and `data-bepis-*` attributes.
- `table`: schema neighborhoods with audit/user-tracking edges classified and
  hidden by default.
- `module`: import neighborhoods with common imports hidden by default.

These queries intentionally report warnings/confidence when relationships are
heuristic. They should be refined with more precise parsers over time rather than
be treated as complete compiler-grade call graphs.

## Bepis-IHP Boundary

IHP remains the outer framework boundary. `Web/Types.hs`, `Web/Routes.hs`,
`Web/FrontController.hs`, `Controller` instances, `beforeAction`, request
context, route parsing, HSX rendering, QueryBuilder, generated model types, and
framework middleware should stay IHP-native. Bepis should not introduce a custom
router or parallel controller lifecycle unless a future ticket proves the typed
prototype is simpler and safer than the IHP default.

Bepis-owned invariants live inside that IHP shell:

- controller policies such as public, authenticated, venue-scoped, admin, and
  support-only access;
- action kind and response kind, e.g. page, fragment, dialog, mutation,
  redirect, JSON, or file response;
- venue/support scope, request-derived id validation expectations, mutation
  scope, audit policy, and realtime/live freshness policy;
- generated frontend contract and live-surface semantics used by architecture
  facts and convention checks.

The migration path is wrapper-first. Existing controller actions should keep the
normal IHP shape but delegate immediately through small Bepis wrappers, for
example `bepisBeforeAction`, `bepisPageAction`, `bepisFragmentAction`,
`bepisDialogAction`, and `bepisMutationAction`. A typed `ControllerSpec`
dispatcher is deferred for now; see `controller-spec-prototype.md` for the
prototype decision and revisit trigger.

Typed behavior is preferred over standalone metadata. Architecture facts should
classify actions and flows in this order:

```text
typed Bepis action values, generated Bepis contracts, and mutation pipeline evidence
  > typed Bepis wrappers/specs
  > app-owned live surface and generated contract registries
  > static source/call scanning
  > naming-convention fallback
```

When a query falls back to a heuristic, it must report confidence/provenance so
agents do not treat inferred request-flow or realtime edges as compiler-perfect
truth.

### Bepis Component Pipelines

Live-surface descriptors are the exemplar component model: create a small typed
core, attach visible capabilities with `|>`, then lower/render/run at the IHP or
browser boundary. The mutation pipeline follows the same rule. A mutation can now
be written as a typed chain that attaches scope, audit, realtime, and response
evidence before `runBepisMutationPipeline` returns the application value.

```haskell
newMutation (approveTimesheetEntryMutation weekOffset timesheetEntry)
    |> scopedToCurrentVenue
    |> auditedAs "timesheet_approved"
    |> fromLiveMutationResult "timesheet.approve"
    |> respondsWithFragments "timesheet-day-section"
    |> respondsWithRedirect "timesheet-week"
    |> runBepisMutationPipeline
```

Use a pipeline component when the capability is meaningful architecture or
product policy and should stay visible at the call site. Use an ordinary helper
function for local mechanics. Use a typeclass only for intrinsic behavior shared
by a family of values; do not hide business decisions such as audit/realtime
requirements in invisible instances.

Generated Bepis architecture contracts come from
`Application.Bepis.Architecture` via `architecture-contracts`. Source scanners may
still locate usage sites, but wrapper/action/response/mutation vocabularies
should prefer generated Haskell-owned contract JSON. During migration,
`BepisMutationSpec` remains a fallback for unmigrated actions and the gate emits
optional mutation drift warnings when required audit/realtime specs lack visible
effect evidence.

IHP Auto Refresh is not a replacement for Bepis live scopes. It tracks table
reads for an action, reruns the action after matching database changes, and
morphs the browser `document.body`. Bepis collaborative surfaces need
domain/surface/viewer authorization scopes and fragment refetch behavior. Future
work may reuse or learn from IHP table-read tracking, but Bepis retains the
scope and authorized-fragment model. See `ihp-auto-refresh-spike.md` for the
current reuse decision.

## Web Surface

- `Web/Controller/` owns request handling, params, redirects, HTMX response
  shape, and permission response choices. New or migrated actions should route
  app-level policy, action kind, mutation policy, response kind, and
  architecture annotations through Bepis wrappers while preserving IHP
  controller conventions.
- `Web/View/` owns HSX rendering and layout structure.
- Feature modules under `Web/RosterWeeks/`, `Web/Timesheets/`, and
  `Web/LeaveRequests/` own projections, response helpers, paths, and local
  domain helpers for those surfaces.

## Application Services

- `Application/Helper/` owns shared helpers, domain services, export helpers,
  pay calculation orchestration, live-update helpers, and view helper modules.
- `Application/Xero/` owns Xero connection, reference data, pay item, and
  timesheet integration logic.
- `Application/FwcMapd/` owns Fair Work MAPD sync, curation, raw storage, and
  projection.
- `Application/PublicHolidays/` owns public holiday sync and jobs.
- `Application/Script/` owns command-line jobs and seed/profile tooling.

## Data

- `Application/Schema.sql` is the canonical full schema source of truth for
  fresh databases and generated model types.
- `Application/Migration/` is the upgrade path for existing deployed databases;
  production runs IHP migrations before starting app and worker services.
- Generated model types live under `build/Generated/`.
- Business authority is venue-scoped through `venue_memberships`.
- Payroll-adjacent history and customer records must remain reproducible and
  data-preserving through immutable version references, append-only history, and
  live-safe migrations.

## Runtime

- The app is an IHP web app with PostgreSQL.
- Actor-local dynamic UI currently uses HTMX fragments.
- Passive viewer freshness currently uses websocket invalidation plus authorized
  fragment refetch.
- Static assets are app-owned under `static/` and loaded via `assetPath`.
- Planned observability topology is described in `observability.md`: lightweight
  OpenTelemetry request tracing, diagnostic profiling, local agent artifacts,
  production Tempo/Loki capture, and tailnet Grafana viewing.
