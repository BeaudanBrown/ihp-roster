# Performance Profiling Runbook

Use this runbook to collect comparable browser and request-load profiles. The
scripts and `--help` output own current options and scenario inventories. Run
commands through the project wrapper:

```bash
bash ./bin/in-env <command>
```

The profiling commands use isolated `app_profile*` databases and dedicated app servers, so they can run alongside normal dev and test servers. Generated artifacts are written under `output/profile*` and are ignored by git.

## Verification Pipeline Profiling

Verification timing is meaningful only when revision, inputs, cache state, host
pressure, and selected test tier match. Before runtime E2E, confirm the checkout
and slot:

```bash
bash ./bin/in-env dev-workspace-info --json
git rev-parse HEAD
git diff --binary HEAD | sha256sum
git ls-files -o --exclude-standard -z | sha256sum
```

Run one command at a time through that checkout's `bin/in-env`; concurrent
wrapper entries can race on generated devenv files. Record the exact argument
vector, UTC start, monotonic wall time, exit status, tool versions, logical CPU
and memory totals. Collect metadata before starting the command timer; stop it
at process exit, before sampler teardown. Use per-command child CPU deltas and
per-process memory evidence, not inherited/cumulative child counters from a
multi-command shell. Timestamp stdout/stderr so the existing `verify-fast:` and
`verify-full:` markers define stage boundaries. Retain test/example counts,
shards, projects/devices, retries, flakes and skips.

Sample command descendants and host `/proc/stat`, `/proc/loadavg`, and
`/proc/pressure/{cpu,io,memory}` at a low rate. Report descendant user/system
CPU and peak RSS separately from host pressure. Descendant accounting excludes
Nix-daemon and pre-existing database/application services; host samples include
unrelated work. Record cache-lock, Nix evaluation/substitution/build, network,
remote-builder, database setup/reset, linking, startup, test, and teardown waits
when their owners expose them. Never infer idle time from low child CPU while a
daemon performs the build.

Use these cache-state names:

- **retained-cache observation**: all useful workspace, user, Nix and OS caches
  remain; document command order.
- **immediate warm repeat**: unchanged revision and inputs, same command-owned
  outputs, run immediately after the producer.
- **output-cold**: point a supported command-owned build/output variable at a
  new empty directory; retain package, Nix and OS caches. For example:

  ```bash
  TYPECHECK_BUILD_DIR="$PWD/.pi/tmp/verification-profile/typecheck-cold" \
    bash ./bin/in-env typecheck
  ```

- **machine-cold**: package/Nix/OS cache eviction. Do not use this on a shared
  development host without explicit approval; it is not required for routine
  comparisons.

Capture `verify-fast` and `verify-full` from process entry to exit. A canonical
failure remains an end-to-end failed observation: retain its stopping stage and
do not invoke later stages and call the result a pipeline pass. Then measure
representative focused Haskell, frontend, and E2E commands, environment entry,
and immediate warm repeats. Focused results are additive diagnostics and never
inherit full-gate authority. `verify-fast` does not replace complete Hspec,
complete Playwright, production, schema/migration, package, or deployment
authority.

Only a successful producer may publish a handoff. Static proof reuse requires
an identity covering source, generated and dependency inputs, compiler/package
environment, flags, inventories, and policy. Runtime results are not reusable
merely because source hashes match. A failed or interrupted `verify-full` run
supplies neither complete-gate evidence nor its later generated-tooling,
architecture, production-closure, and browser handoffs.

For a before/after conclusion, use the same revision class, cache definition,
command order, host, toolchain, shard/device selection, and network/builder
policy. Prefer at least three successful quiet-host runs per state; report
median, tail, peak memory and every failure rather than selecting the fastest
run. Preserve raw local logs and bounded machine-readable summaries under
`.pi/tmp/`; retain only reviewed comparison evidence with continuing value in
`docs/archive/`.

### Command recorder

The Linux command-recorder interface is opt-in and tested by `verify-tooling`:

```bash
bash ./bin/in-env python3 scripts/profiling/verification-measure.py run \
  --output .pi/tmp/verification-command-01 --owner typecheck \
  --cache-state retained -- typecheck
bash ./bin/in-env python3 scripts/profiling/verification-measure.py inspect \
  .pi/tmp/verification-command-01
```

Choose a new output directory per attempt; existing or symlinked paths are
rejected. Artifacts are bounded private JSON, not command logs. Only a digest of
argv is stored; command stdout/stderr pass through to the terminal unchanged.
Owner labels must be public, non-sensitive identifiers. Revision and input
provenance are collected before command timing. `provenance.json` fingerprints
tracked changes, untracked files and generated Haskell/TypeScript sources,
without storing input paths or contents. Keep inputs quiescent: this is a
bounded, best-effort diagnostic snapshot, not atomic proof or cache identity.
Missing Git context, unsupported/symlinked inputs and exceeded capture bounds
remain unavailable. Ignored files outside the two generated-source owners,
external dependencies and compiler configuration are not covered; record these
separately under the protocol above. Original metadata-v1 artifacts remain
inspectable without provenance; metadata-v2 requires validated provenance.

`inspect` validates the completion schema and returns the recorded exit status;
missing, corrupt or incomplete evidence returns 2. Completion is diagnostic,
never gate or cache authority. SIGINT/SIGTERM are forwarded to the command's new
process group, with a ten-second grace before kill escalation (configurable
from 1–60 using `--termination-grace-seconds`). An interrupted
command cannot become successful because its signal handler returns zero. A
hard-killed recorder leaves no completed result. Detached services remain their
existing owner's cleanup responsibility; do not use this recorder to manage
production processes.

CPU is the kernel accounting for this waited command and descendants it waited
for, excluding recorder metadata and pre-existing services/daemons. Memory is
sampled simultaneous descendant RSS, not summed historical maxima or unique
physical memory: shared pages can be double-counted, and short-lived/reparented
processes can be missed. No samples means unavailable, not zero. The timer has
up to a polling interval plus sampling latency; collection overhead is included
in the observation. This command-level recorder does not yet attribute linker,
service-readiness, database or suite phases; #599 owns that integration.

## Request Instrumentation

Profiling is enabled only when the profiling server sets:

```bash
IHP_ROSTER_PROFILING=1
```

When enabled, response middleware retains `Server-Timing` and `X-Request-Id`
for compatibility diagnostics in browser developer tools and older local reports.
They are not the primary profiling artifact. `otel-summary.json` and the bounded
agent tools own span, size, counter, and comparison evidence. Controllers should
not add render wrappers only to emit headers.

The shared `renderProfiled` and `respondHtmlProfiled` helpers add coarse
`render.ihp_view` and `render.respond_html` OpenTelemetry spans when profiling is
enabled. Rendered byte sizes are recorded as diagnostic-only `html.bytes` span
attributes. The retired `X-Profile-Response-Bytes` header is no longer emitted;
compatibility reports may use ordinary `Content-Length` when available.

Local trace-run and trace-step request headers accept at most 96 UTF-8 bytes and
only ASCII letters, digits, `-`, `_`, `.`, `:`, and `/`. Invalid values are
discarded. They remain trusted-local correlation inputs, not customer-facing or
production metadata.

Profiling counters remain available for high-volume render paths via
`profileRenderCounter`. They are attached to the enclosing diagnostic render
span and `bepis.render.counters` event. The legacy `X-Profile-Counters` header
and its request-global accumulation are retired. Use counters sparingly for
repeated structures such as roster rows, slot blocks, grid cells, launchers,
hidden inputs, picker options, and panel entries.

Manual spans are added with helpers from `Application.Helper.Profiling`, for example:

```haskell
profileActionSpan "roster.build_month_overview" do
    buildRosterMonthOverviewDays venueConfig rosterGroupId focusDate
```

Use span names that identify the app area and operation. Prefer category-style prefixes such as `read_model.*`, `projection.*`, `domain.*`, `render.*`, `external.*`, and `live_update.*` for new spans. The common OpenTelemetry model owns primary grouping. For compatibility only, emitted `Server-Timing` tokens sanitize dots to underscores, so `roster.build_month_overview` appears as `roster_build_month_overview` in older reports.

When `IHP_ROSTER_PROFILING` is unset, profiling is default-off. Span helpers first check for an active request profile and avoid monotonic clock reads or cache-stat snapshots when no profile exists. Production deployments must leave profiling disabled unless an operator intentionally starts an isolated profiling run or enables it briefly for a controlled diagnostic window.

`Server-Timing` exposes internal span names. Do not enable profiling headers for ordinary public traffic. Prefer isolated profile commands backed by `app_profile*` databases. For new diagnosis use `--otel`, `otel-browser`, `otel-summary`, `otel_trace_search`, `otel_trace_get`, and `otel_compare_runs`; treat header-derived timing sections as compatibility context only.

## Profile Seed Database

Use `seed-profile` to create a large deterministic database:

```bash
bash ./bin/in-env seed-profile app_profile
```

The default creates a multi-venue, multi-year roster/timesheet dataset. Use `seed-profile --help` for bounded venue, staff, history, roster-density, seed, and Xero sizing overrides instead of relying on implementation-specific row totals.

The seed writes CSVs, `load.sql`, `manifest.json`, and a database dump. `Application.Script.SeedProfile.profileTableDescriptors` is the single typed owner of CSV file names, table names, columns, rows, and load order; generation rejects missing/duplicate descriptors and row-width mismatches. The manifest gives runners stable login accounts and typed application route paths. Approved synthetic timesheets retain their CSV representation while the load plan stages them through schema-valid sealed pay-ledger rows.

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
- `staff`
- `support`
- `billing`
- `auth`
- `writes`

This is the right tool when checking browser navigation, HTMX follow-up requests, and route-level app spans for realistic user journeys.

Use `xero` when checking the owner-only Xero connection shell and its server-rendered shell fragment. Guided timesheet preparation and pay-item import remain focused browser flows rather than synthetic autosave profiling targets.

Use `staff` for an ordinary worker account, `support` for the platform support
shell plus bounded FWC MAPD job enqueue, `billing` for the venue billing shell,
and `auth` for measured password-login and virtual-passkey registration flows.
Use `writes` for deterministic export-generation mutation profiling. All use
isolated profile seed data; profile passkey credentials are synthetic.

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
agent-readable trace artifacts beside the k6 report. Use `--no-profiling` for a
lightweight OTel run and `--otel-sampler`/`--otel-sampler-arg` to select the
runtime sampler:

```bash
bash ./bin/in-env profile-load --scenario=roster-wide --rate=2 --duration=15s --vus=2 --otel
```

Diagnostic mode also writes:

```text
output/profile-load/<run-id>/diagnostic-profile.json
output/profile-load/<run-id>/diagnostic-profile.md
output/profile-load/<run-id>/runtime-resources.json
output/profile-load/<run-id>/runtime-resources.tsv
```

The diagnostic report separates database, runtime, render, external-provider,
and live-update pressure. It includes sample counts, aggregate query timing,
bounded normalized query fingerprints, pool saturation/wait proxies, GHC
allocation/GC/heap/CPU, and process CPU/RSS. It never includes SQL text,
parameters, or customer identifiers. `server.log` is a local diagnostic input
and can contain framework debug SQL structure; do not publish it.

Additional OTel outputs:

```text
output/profile-load/<run-id>/otel-collector.log
output/profile-load/<run-id>/otel-traces.json
output/profile-load/<run-id>/otel-summary.json
output/profile-load/<run-id>/otel-summary.md
```

## Runtime Mode Benchmark

Use the four-mode runner to compare disabled, 1% sampled, always-on lightweight,
and always-on diagnostic behavior against one seeded database:

```bash
bash ./bin/in-env otel-runtime-benchmark \
  --scenario=roster-wide --rate=2 --duration=20s --vus=2
```

Artifacts are retained under `output/otel-runtime-benchmark/<run-id>/`, with one
subdirectory per mode, sampled server CPU/RSS evidence in
`runtime-resources.json`, and an aggregate `benchmark.json`. Repeat the matrix on
the same idle host before drawing a release conclusion. The sampled-mode budget
and queue/memory ceilings are defined in `docs/architecture/observability.md`.
Exporter/Collector outage checks should point the app at a closed localhost
port and confirm application checks complete while export failures remain
bounded by the one-second exporter timeout.

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
- `staff`: ordinary-worker roster, timesheet, and profile paths.
- `support`: platform-support shell.
- `billing`: venue billing shell.
- `auth`: login route plus the per-VU measured login setup.
- `mixed-app`: broad read-only mix across roster, timesheets, leave, admin, and profile.

The shared scenario catalog lives at `e2e/profile-scenarios.json`; update it when adding or retiring profile coverage so Playwright and k6 stay aligned.
Representative export mutations run through browser scenario `writes`; roster,
timesheet, leave, admin, and support job mutations plus websocket fanout run
through `profile-live-load --scenario=mixed-live` and `--scenario=support`.

Stable evidence/correctness budgets live in
`e2e/profile-regression-budgets.json`. Diagnostic runners write the report and
fail when required query, GHC, process, or pool samples are absent, or when a
stable correctness budget fails. Compare latency only against a matched seed,
scenario, rate, and host baseline. External `profile-live-load --base-url` runs
must also pass `--server-pgid` for bounded process-group sampling and
`--server-log` so the runner can retain only query/GHC evidence appended during
the run.

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

Prefer matched `otel-summary.json` route/span groups and exclusive-time evidence for code optimization. `Server-Timing` is compatibility context only; HTTP latency also includes transfer, local scheduling, and login setup.

Useful fields:

- HTTP p95/p99 by route: user-visible request latency.
- App total p95/p99 by route: server-side request work.
- Attribution gaps: `app_total - named spans`; large gaps mean add spans around rendering/serialization or another uninstrumented boundary before guessing at a refactor.
- Largest responses: OpenTelemetry `html.bytes`/response-size attributes are authoritative; compatibility HTTP reports use `Content-Length` when available.
- Render counters: diagnostic OpenTelemetry span attributes/events expose high-volume render counts useful for finding multiplicative markup such as slot cells, grid cells, launchers, forms, and panel entries.
- Span category p95/p99: grouped costs such as `read_model`, `projection`, `domain`, `render`, `external`, and `live_update`.
- Diagnostic pressure groups: DB query count/duration, safe slow fingerprints,
  pool pressure, GHC allocation/GC/heap, CPU/RSS, render, external, and
  live-update aggregate evidence with explicit sample counts.
- Span p95/p99: specific code paths worth optimizing.
- Dropped iterations: arrival-rate pressure, often useful as regression signal.
- VU saturation: whether k6 had to use most of the configured virtual-user ceiling.
- Status counts and failed checks: correctness under load.
- `otel-summary.json`: the versioned `bepis.otel.profile.v2` model shared by
  load and browser runs. It includes matched route/action/span groups, sample
  counts, overlap-safe exclusive time, repeated spans, categories, sizes,
  counters, safe trace views, load pressure when available, and separate real
  failures from IHP response exits.

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
  output/profile-load-suite/<before>/otel-summary.json \
  output/profile-load-suite/<after>/otel-summary.json \
  output/profile-load-suite/<after>/comparison.md
```

Each scenario report uses `bepis.otel.profile.v2`; the suite is a
`bepis.otel.suite.v2` wrapper. The comparison writes both Markdown and
`comparison.json` (`bepis.otel.comparison.v2`). It reports only matched
scenario/route/action/span deltas, before/after sample counts, descriptive
confidence, median/P95/exclusive-P95 changes, dropped iterations, VU saturation,
and failure classification. Low sample confidence is context, not a statistical
significance claim.

Artifact readers reject malformed JSON, unsafe architecture paths, files above
64 MiB, more than 100,000 spans, and oversized trace/group views. Tempo queries
are limited to 500 traces and 30-second per-request timeouts; defaults are lower.
