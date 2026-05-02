# Architecture Map

This is a lightweight map of the app's main code-owned subsystems. Detailed
behavior belongs in subsystem-local docs.

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

- `Application/Schema.sql` is the schema source of truth.
- Generated model types live under `build/Generated/`.
- Business authority is venue-scoped through `venue_memberships`.
- Payroll-adjacent history must remain reproducible through immutable version
  references or append-only history.

## Runtime

- The app is an IHP web app with PostgreSQL.
- Actor-local dynamic UI uses HTMX fragments.
- Passive viewer freshness uses websocket invalidation plus authorized fragment
  refetch.
- Static assets are app-owned under `static/` and loaded via `assetPath`.
