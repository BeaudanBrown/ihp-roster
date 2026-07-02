# Performance Profiling Tooling

This repo has deterministic profiling tooling for agents to measure app performance before and after changes. Run all commands through the project wrapper:

```bash
bash ./bin/in-env <command>
```

The profiling commands use isolated `app_profile*` databases and dedicated app servers, so they can run alongside normal dev and test servers. Generated artifacts are written under `output/profile*` and are ignored by git.

## Request Instrumentation

Profiling is enabled only when the profiling server sets:

```bash
IHP_ROSTER_PROFILING=1
```

When enabled, response middleware emits `Server-Timing` and `X-Request-Id` headers for normal app responses, including HTML, JSON, redirects, and downloads. Controllers should not add render wrappers just to emit profiling headers. The app does not keep an unbounded in-memory profile store; the runners collect timings from response headers.

The shared `renderProfiled` and `respondHtmlProfiled` helpers add coarse `render.ihp_view` and `render.respond_html` spans when profiling is enabled. `respondHtmlProfiled` also emits `X-Profile-Response-Bytes` for rendered HTML payload size. Use these helpers for profiled routes and add narrower manual spans only when a route-level render span still leaves a large attribution gap.

Profiling counters are available for high-volume render paths via `profileCounter` in IO code and `profileRenderCounter` in pure view code. Counters are emitted in `X-Profile-Counters` and summarized alongside timings. Use counters sparingly for repeated structures such as roster rows, slot blocks, grid cells, launchers, hidden inputs, picker options, and panel entries.

Manual spans are added with helpers from `Application.Helper.Profiling`, for example:

```haskell
profileActionSpan "roster.build_month_overview" do
    buildRosterMonthOverviewDays venueConfig rosterGroupId focusDate
```

Use span names that identify the app area and operation. Prefer category-style prefixes such as `read_model.*`, `projection.*`, `domain.*`, `render.*`, `external.*`, and `live_update.*` for new spans. Existing legacy spans are still accepted and are grouped heuristically by the load reports. The emitted `Server-Timing` token sanitizes dots to underscores, so `roster.build_month_overview` appears as `roster_build_month_overview` in reports.

When `IHP_ROSTER_PROFILING` is unset, profiling is default-off. Span helpers first check for an active request profile and avoid monotonic clock reads or cache-stat snapshots when no profile exists. Production deployments must leave profiling disabled unless an operator intentionally starts an isolated profiling run or enables it briefly for a controlled diagnostic window.

`Server-Timing` exposes internal span names. Do not enable profiling headers for ordinary public traffic. Prefer the isolated `profile-app`, `profile-load`, and `profile-load-suite` commands, which set `IHP_ROSTER_PROFILING=1` only for dedicated profile servers backed by `app_profile*` databases.

## Profile Seed Database

Use `seed-profile` to create a large deterministic database:

```bash
bash ./bin/in-env seed-profile app_profile
```

The default profile seed currently creates:

- 12 venues
- 480 staff
- 3,936 roster weeks
- 27,552 roster days
- 330,624 roster slots
- 24,960 timesheet entries
- 1,440 leave requests

The seed writes CSVs, `load.sql`, `manifest.json`, and a database dump. The manifest gives runners stable login accounts and route paths.

## Browser Journey Profiling

Use `profile-app` for low-volume browser-realistic profiling with Playwright:

```bash
bash ./bin/in-env profile-app --scenario=full --runs=5
```

Outputs:

```text
output/profile/<run-id>/profile.json
output/profile/<run-id>/profile.md
```

Scenarios:

- `full`
- `roster`
- `timesheets`
- `leave`
- `xero`
- `admin`
- `profile`
- `writes`

This is the right tool when checking browser navigation, HTMX follow-up requests, and route-level app spans for realistic user journeys.

Use `xero` when checking the Xero staff mapping autosave path. It loads the admin Xero section, changes a staff mapping select, captures the `SaveXeroStaffMapping` `Server-Timing` header, and records scroll delta in `profile.json`.

Use `writes` for deterministic mutation profiling. It currently exercises export generation against the isolated profile database and records the POST timing separately from read-only journeys.

## Request Volume Profiling

Use `profile-load` for k6 HTTP request-volume profiling:

```bash
bash ./bin/in-env profile-load --scenario=roster-hot --rate=10 --duration=30s --vus=10
```

Outputs:

```text
output/profile-load/<run-id>/k6-metrics.ndjson
output/profile-load/<run-id>/k6.stdout
output/profile-load/<run-id>/load-profile.json
output/profile-load/<run-id>/load-profile.md
output/profile-load/<run-id>/server.log
output/profile-load/<run-id>/seed/manifest.json
```

Add `--otel` to start a Nix-provided local OpenTelemetry Collector and export
agent-readable trace artifacts beside the k6 report:

```bash
bash ./bin/in-env profile-load --scenario=roster-wide --rate=2 --duration=15s --vus=2 --otel
```

Additional OTel outputs:

```text
output/profile-load/<run-id>/otel-collector.log
output/profile-load/<run-id>/otel-traces.json
output/profile-load/<run-id>/otel-summary.json
output/profile-load/<run-id>/otel-summary.md
```

## Live Dev Trace Frontend

For interactive local debugging, start the dev-only Tempo/Grafana/collector
stack and then start the app with OTel enabled:

```bash
bash ./bin/in-env dev-start-otel
```

This starts local-only services:

- Grafana frontend: `http://127.0.0.1:3300/explore`
- Tempo health/API: `http://127.0.0.1:3200/ready`
- OTel Collector health: `http://127.0.0.1:13133/`
- App OTLP/HTTP ingestion endpoint: `http://127.0.0.1:4318`

Tempo and the OTLP ingestion endpoint are APIs, not browser frontends; `404`
from `/` on ports `3200` or `4318` is normal. After making requests against the
dev app, open Grafana Explore and search the Tempo datasource for service
`ihp-roster-dev`. Trace search can lag a few seconds behind requests while the
batch processor exports spans.

Useful controls:

```bash
bash ./bin/in-env dev-observability-status
bash ./bin/in-env dev-observability-stop
```

Use `IHP_ROSTER_PROFILING=1 bash ./bin/in-env dev-start-otel` only when you
need the heavier diagnostic render counters/HTML byte spans in the live trace
view.

Available scenarios:

- `roster-hot`: current full roster, content fragment, overview fragment.
- `roster-wide`: current, historical, future, staff panel, content, overview.
- `roster-overview`: overview-heavy pressure plus historical/future full roster pages.
- `roster-projections`: full roster plus content and staff panel projection paths.
- `fragments`: HTMX-style roster/timesheet fragments.
- `timesheets`: timesheet full page and day fragment.
- `leave`: manager leave and profile leave pages.
- `admin`: admin landing and exports section.
- `profile`: profile and security sections.
- `mixed-app`: broad read-only mix across roster, timesheets, leave, admin, and profile.

The shared scenario catalog lives at `e2e/profile-scenarios.json`; update it when adding or retiring profile coverage so Playwright and k6 stay aligned.

`profile-load` uses k6's constant-arrival-rate model. `--rate=10 --duration=30s` means it tries to start 10 iterations per second for 30 seconds. Dropped iterations mean the test could not keep the requested arrival schedule; they are useful regression signal even when requests still pass. Reports classify runs as `clean` (<1% dropped), `strained` (1–10%), or `overloaded` (>10%). Use clean/strained runs for latency comparisons and overloaded runs for stress/capacity comparisons.

## Load Suite

Use `profile-load-suite` for the standard matrix:

```bash
bash ./bin/in-env profile-load-suite
```

The suite seeds once, reuses the same DB, runs all standard scenarios, and writes:

```text
output/profile-load-suite/<run-id>/<scenario>/load-profile.json
output/profile-load-suite/<run-id>/<scenario>/load-profile.md
output/profile-load-suite/<run-id>/suite-summary.json
output/profile-load-suite/<run-id>/suite-summary.md
```

With `--otel`, each scenario also writes `otel-traces.json`,
`otel-summary.json`, and `otel-summary.md`, and the suite root writes
`otel-summary.json` plus `otel-summary.md` aggregating slow spans, large HTML
components, and render counters:

```bash
bash ./bin/in-env profile-load-suite --scenario=roster-wide --rate=2 --duration=15s --vus=2 --otel
```

Default rates:

- `20/sec`: `roster-overview`, `roster-projections`, `fragments`
- `10/sec`: all other scenarios

To run a smaller targeted suite:

```bash
bash ./bin/in-env profile-load-suite \
  --scenario=roster-hot \
  --scenario=timesheets \
  --rate=10 \
  --duration=30s
```

## Interpreting Reports

Prefer app-side `Server-Timing` numbers for code optimization. HTTP latency includes transfer, local scheduling, and login setup.

Useful fields:

- HTTP p95/p99 by route: user-visible request latency.
- App total p95/p99 by route: server-side request work.
- Attribution gaps: `app_total - named spans`; large gaps mean add spans around rendering/serialization or another uninstrumented boundary before guessing at a refactor.
- Largest responses: response byte sizes when the server provides `Content-Length` or `X-Profile-Response-Bytes`; missing byte records usually mean chunked/streamed responses and are reported separately.
- Profile counters: high-volume render counts per route/request, useful for finding multiplicative markup such as slot cells, grid cells, launchers, forms, and panel entries.
- Span category p95/p99: grouped costs such as `read_model`, `projection`, `domain`, `render`, `external`, and `live_update`.
- Span p95/p99: specific code paths worth optimizing.
- Dropped iterations: arrival-rate pressure, often useful as regression signal.
- VU saturation: whether k6 had to use most of the configured virtual-user ceiling.
- Status counts and failed checks: correctness under load.

Current baseline from the first full suite run showed:

- timesheets and leave are inexpensive under the current read-only profile.
- roster overview is the dominant hot path.
- `roster_build_month_overview` is the main span to watch.

## Before And After Workflow

For a code change intended to improve performance:

```bash
bash ./bin/in-env profile-load-suite
# make the code change
bash ./bin/in-env profile-load-suite
```

Compare the two suite artifacts with:

```bash
bash ./bin/in-env profile-compare \
  output/profile-load-suite/<before>/suite-summary.json \
  output/profile-load-suite/<after>/suite-summary.json \
  output/profile-load-suite/<after>/comparison.md
```

The comparison report ranks request/span latency deltas plus dropped-iteration and VU-saturation changes.
