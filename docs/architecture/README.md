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
bash ./bin/in-env architecture-wiring-registry-test
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

`architecture-check-fresh` regenerates the whole-module DOT evidence but skips
its expensive, unreadable whole-graph SVG layout; run `architecture-module-graph`
explicitly when that SVG is required, or prefer a focused `module` query.
It also enforces closed wiring parity: controller records in `Web/Types.hs` must be routed and mounted exactly once, and every
top-level `frontend/ts/app*.ts` bundle must be loaded exactly once by
`Web/View/Layout.hs`. Each exception's accountable subsystem owner and rationale
live in `scripts/architecture/wiring-policy.mjs`; generated JavaScript byte drift stays
with the existing frontend drift check.

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
- runtime facts emitted by real helpers for venue/support scope,
  request-derived id validation, audit/version writes, live invalidation, and
  actor responses;
- generated frontend contract and live-surface semantics used by architecture
  facts and convention checks.

The current action boundary is `runBepis`. Controller actions keep the normal
IHP shape but delegate immediately through `runBepis currentAction
Bepis...Action do`. A typed `ControllerSpec` dispatcher is deferred for now; see
`controller-spec-prototype.md` for the prototype decision and revisit trigger.

Typed behavior is preferred over standalone metadata. Architecture facts should
classify actions and flows in this order:

```text
typed Bepis action values, generated Bepis contracts, and helper-emitted Bepis facts
  > app-owned live surface and generated contract registries
  > static source/call scanning for usage location only
  > naming-convention fallback
```

When a query falls back to a heuristic, it must report confidence/provenance so
agents do not treat inferred request-flow or realtime edges as compiler-perfect
truth.

### Bepis Runtime Facts

Bepis uses one runtime fact boundary: helpers that perform real effects call
`emitBepisFact`. `runBepis` opens the action-local collector, emits the action
fact, runs the normal IHP action body, and summarizes collected facts to
telemetry. OpenTelemetry is a sink for these typed facts, not the source of
truth.

```haskell
action currentAction@ApproveTimesheetEntryAction { timesheetEntryId } =
    runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        _ <- approveTimesheetEntryMutation weekOffset timesheetEntry
        respondWithTimesheetDaySectionUpdate ...
```

Authorization helpers emit scope facts, audit/version helpers emit audit facts,
live invalidation helpers emit live facts, and response helpers emit response
facts. Do not add parallel descriptive metadata beside a helper call; add fact
emission to the helper that actually performs the effect.

Generated Bepis architecture contracts come from
`Application.Bepis.Architecture` via `architecture-contracts`. Source scanners may
still locate usage sites and enforce no-legacy rules, but Bepis semantic
vocabularies should prefer generated Haskell-owned contract JSON and runtime
fact artifacts.

## Web Surface

- `Web/Controller/` owns request handling, params, redirects, HTMX response
  shape, and permission response choices. New or migrated actions should route
  app-level policy and action kind through `runBepis`; scope/audit/live/response
  semantics come from fact-emitting helpers while preserving IHP controller
  conventions.
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
