# Architecture Map

This is a lightweight map of the app's main code-owned subsystems. Detailed
behavior belongs in subsystem-local docs.

## Deterministic Architecture Tooling

Project-local architecture commands are declared in `.pi/architecture.json` for
Pi agents and are exposed through the devenv scripts. Generated outputs are
initially gitignored under `output/architecture/`; focused query diagrams are
written under `.pi/tmp/architecture-query/` or `.pi/tmp/architecture-trace/`.

```bash
bash ./bin/in-env architecture-facts
bash ./bin/in-env architecture-schema
bash ./bin/in-env architecture-web-map
bash ./bin/in-env architecture-module-graph
bash ./bin/in-env architecture-check-fresh
```

Focused agent queries use Pi's `architecture_queries` and `architecture_query`
tools. The current project queries are:

- `component`: focused controller/action/table/module diagrams.
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

The next useful project-local query families are:

- `controller`: grouped action inventory with handler module, source locations,
  route references, and optional inbound links/forms.
- `request-flow`: action -> handler -> auth/scope checks -> reads/writes ->
  rendered view/fragment/redirect -> realtime/frontend effects.
- `realtime-usage`: coverage and flow for surfaces that use live freshness,
  regardless of whether the current mechanism is websocket invalidation,
  polling, SSE, or something else.
- `generated-contracts`: Haskell contract/codecs -> generated TypeScript ->
  frontend consumers/backend emitters.
- `table`: schema neighborhoods with audit/user-tracking edges classified and
  optionally hidden.
- `module`: import neighborhoods with common imports hidden and subsystem
  clusters/summaries by default.

## Web Surface

- `Web/Controller/` owns request handling, params, redirects, HTMX response
  shape, and permission response choices.
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
