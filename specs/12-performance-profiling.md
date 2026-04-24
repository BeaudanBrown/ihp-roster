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

When enabled, profiled controllers emit `Server-Timing` and `X-Request-Id` response headers. The app does not keep an unbounded in-memory profile store; the runners collect timings from response headers.

Manual spans are added with helpers from `Application.Helper.Profiling`, for example:

```haskell
profileActionSpan "roster.build_month_overview" do
    buildRosterMonthOverviewDays venueConfig rosterGroupId focusDate
```

Use span names that identify the app area and operation. The emitted `Server-Timing` token sanitizes dots to underscores, so `roster.build_month_overview` appears as `roster_build_month_overview` in reports.

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

This is the right tool when checking browser navigation, HTMX follow-up requests, and route-level app spans for realistic user journeys.

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

Available scenarios:

- `roster-hot`: current full roster, content fragment, overview fragment.
- `roster-wide`: current, historical, future, staff panel, content, overview.
- `roster-overview`: overview-heavy pressure plus historical/future full roster pages.
- `roster-projections`: full roster plus content and staff panel projection paths.
- `fragments`: HTMX-style roster/timesheet fragments.
- `timesheets`: timesheet full page and day fragment.
- `leave`: manager leave and profile leave pages.
- `mixed-app`: broad read-only mix across roster, timesheets, and leave.

`profile-load` uses k6's constant-arrival-rate model. `--rate=10 --duration=30s` means it tries to start 10 iterations per second for 30 seconds. Dropped iterations mean the test could not keep the requested arrival schedule; they are useful regression signal even when requests still pass.

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
- Span p95/p99: specific code paths worth optimizing.
- Dropped iterations: arrival-rate pressure, often useful as regression signal.
- Status counts and failed checks: correctness under load.

Current baseline from the first full suite run showed:

- timesheets and leave are inexpensive under the current read-only profile.
- projection cache lookup is cheap.
- roster overview is the dominant hot path.
- `roster_build_month_overview` is the main span to watch.

## Before And After Workflow

For a code change intended to improve performance:

```bash
bash ./bin/in-env profile-load-suite
# make the code change
bash ./bin/in-env profile-load-suite
```

Compare the two `suite-summary.md` files manually for now. The next planned progression is a dedicated suite comparison command that ranks p95/p99 deltas and status changes.
