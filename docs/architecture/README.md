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
- Actor-local dynamic UI uses HTMX fragments.
- Passive viewer freshness uses websocket invalidation plus authorized fragment
  refetch.
- Static assets are app-owned under `static/` and loaded via `assetPath`.
- Planned observability topology is described in `observability.md`: lightweight
  OpenTelemetry request tracing, diagnostic profiling, local agent artifacts,
  production Tempo/Loki capture, and tailnet Grafana viewing.
