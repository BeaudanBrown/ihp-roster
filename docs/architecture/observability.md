# Observability Architecture

Implemented telemetry behavior is owned by `Application/Helper/Telemetry.hs`,
the profiling helpers, `Config/otel/`, and the Nix scripts/module. Exact local
profiling procedures live in `docs/runbooks/performance-profiling.md`. Unresolved
Grafana and production incident-runbook work lives only in
`docs/workstreams/opentelemetry-observability.md` and its linked GitHub issues.

## Modes

Observability modes are deliberately separate:

- default: no OpenTelemetry provider/exporter and no diagnostic profiling;
- `IHP_ROSTER_OTEL=1`: sampled lightweight request/action telemetry using
  standard `OTEL_*` configuration;
- `IHP_ROSTER_PROFILING=1`: expensive diagnostic timing, response-byte, and
  render-counter evidence for isolated profile runs or controlled diagnosis.

Ordinary production traffic must not receive profiling headers or expensive
render diagnostics. `Server-Timing` remains a profile-gated browser-devtools
compatibility surface. `X-Profile-Counters` and `X-Profile-Response-Bytes` are
retired; diagnostic counters and sizes live only in bounded OpenTelemetry
attributes/events and the common artifact model. Production configuration belongs in the
`services.ihpRoster.observability` NixOS module rather than ad hoc environment
files.

## Runtime Contract

`withTelemetryRuntime` owns provider initialization, bounded flush, and bounded
shutdown for the app, worker, and generated operational-script entrypoints.
Middleware only creates request spans; it is not a lifecycle owner. The disabled
path is a cached boolean branch and creates no provider, exporter, thread, or
timer. Initialization, flush, shutdown, exporter, and Collector failures report
a bounded operational message and fail open without replacing application work.

Enabled deployments use a 512-span queue, 128-span export batches, a one-second
export timeout, 256-character attribute values, 64 attributes/events per span,
and 16 links per span. Process flush and shutdown each have a two-second bound.
These are safety ceilings, not capacity targets. Resource data includes service
name/version and commit, deployment environment/slot, and host/instance; local
workspaces additionally identify their workspace kind and slot.

For a matched low-rate `roster-wide` profile-load run (`rate=2`, `duration=20s`,
`vus=2`), sampled lightweight mode (1%) must remain within all of these budgets
relative to disabled mode: no more than 5% throughput loss, 10% HTTP p95 latency
increase, 10% CPU-time-per-completed-iteration increase, 10% peak-RSS increase
with an absolute 32 MiB allowance, and one percentage point additional dropped
iterations. Compare repeated runs
on the same host and seeded database; a single noisy shared-host sample is not
a release conclusion. Always-on and diagnostic modes are diagnosis/capacity
evidence and are not approved ordinary-production modes.

## Trace And Data Boundary

WAI owns request-root spans; Bepis action helpers add low-cardinality action and
effect facts. OpenTelemetry is a sink for typed runtime facts, not the source of
business truth.

Allowed default attributes include service/environment, HTTP method/status,
low-cardinality action or route names, and bounded aggregate counts already
computed for the request. Exclude raw query strings, names, emails, credentials,
free-form parameters, customer identifiers, and high-cardinality labels. Any
exception requires a ticket with explicit privacy and cardinality justification.

Diagnostic headers used by local browser tooling are trusted-local inputs only
and are not a production contract.

Outside WAI, the application emits these bounded semantic spans:

- one `bepis.job.run` root-capable span per claimed `app_jobs` attempt, carrying
  only registered job kind, bounded attempt/max-attempt facts, retry state, and
  outcome; explicit Xero continuations add retry-scheduled/exhausted events;
- one client span per selected Stripe, Xero, FWC MAPD, or SMTP operation,
  carrying only closed provider/operation/method, status class, and outcome;
- one `bepis.live_update.process` span per decoded subscribe/unsubscribe command;
- one `bepis.export.generate` span per fixed export request.

The wrappers catch failures inside the SDK span, record only `failed`, and
rethrow after closing it. The SDK therefore cannot copy raw exception payloads
into these semantic spans. Unknown job kinds and provider operations collapse to
`unknown`; URLs, ids, payloads, dedupe keys, addresses, and exception text are
never attributes. Span volume is bounded by `job attempts + selected provider
calls + decoded websocket commands + export requests`; FWC MAPD paging is one
logical span with a 1,000-page safety ceiling, and Xero period-timesheet paging
stops before page 101. The retained issue-453 measurement used a 25-iteration
`telemetry-boundary-probe` and exported exactly 100 semantic spans (four per
iteration) with zero prohibited attributes. A matched 20-second `roster-wide`
profile emitted 2,124 existing request/domain spans across 44 requests and zero
new semantic spans, as expected because that scenario performed no jobs,
provider calls, websocket commands, or exports. Trace context is not
persisted in `app_jobs`: worker attempts intentionally start a new root because
persisting request trace state would couple durable retries to customer-request
sampling and retention. In-process child operations still inherit the active
job or request context normally.

## Diagnostic Profiling Evidence

`IHP_ROSTER_PROFILING=1` additionally enables run-boundary evidence; it does not
add query, GC, heap, pool, or fanout work to ordinary traffic. Diagnostic runs
write `diagnostic-profile.json` and `.md` with explicit sample counts and five
separate pressure groups: database, runtime, render, external provider, and
live update.

Database evidence aggregates IHP's parameterized debug-query timings. Reports
retain only operation, count, duration, and a 16-hex SHA-256 fingerprint of a
normalized statement; SQL text, parameters, routes, and customer identifiers
are omitted. The twenty retained slow fingerprints are bounded. Connection-pool
wait evidence is necessarily a run-level proxy because Hasql does not expose
acquisition wait duration: the report samples active/open database connections,
pool saturation, server waiters, and acquisition timeouts and states that
limitation explicitly.

GHC allocation, copied-byte, collection, heap, mutator CPU, and GC CPU deltas
are sampled once per second by the process-owned diagnostic runtime. External
process sampling supplies CPU and peak RSS. Live-load reports aggregate
subscribers, fanout, target fragments, broadcasts, delivery, and drops by closed
surface/label; diagnostic output retains at most 64 labels with weighted overflow
aggregation and never emits evidence per subscriber or message.

Stable regression budgets currently cover evidence presence, request
correctness, clean-run drops, pool acquisition timeouts, and live drops/errors.
Host-sensitive latency requires a matched baseline. The separate sampled-mode
production overhead budget above remains authoritative.

## Topologies

Local repeatable profiling remains agent-first and artifact-based:

```text
isolated profile runner -> app -> localhost OTLP collector
  -> ignored JSON/Markdown trace summaries under output/
```

The optional development frontend remains localhost-only:

```text
dev app -> local collector -> local Tempo -> local Grafana
```

Use the runbook and command `--help` output rather than copying scenario or
option inventories here.

Every Collector file-export and Tempo-materialized run is normalized to
`bepis.otel.profile.v2` in `otel-summary.json`. The common model owns route and
IHP action identity (closed `*Action` names only; all other values are
privacy-hashed), overlap-safe exclusive time, repeated span groups, explicit
sample counts, response/component sizes, render counters, provider/database/
runtime/live categories, load pressure, and separate real-error versus IHP
response-exit counts. Browser and load tooling therefore expose the same schema;
suite files are bounded `bepis.otel.suite.v2` wrappers around those reports.
Architecture trace diagrams consume only the bounded safe `traceViews` in that
summary, not arbitrary raw span attributes. Output-facing trace identifiers are
stable 128-bit SHA-256 references rather than raw exporter trace IDs.

Comparison output is `bepis.otel.comparison.v2`: only matched scenario/route/
action/span groups are compared, with before/after samples, descriptive
confidence, median/P95/exclusive-P95 deltas, dropped iterations, and VU
saturation. Parsers reject malformed input, files above 64 MiB, more than
100,000 spans, unsafe architecture artifact paths, and oversized trace/group
views with bounded messages. Tempo reads additionally cap search results and
apply per-request timeouts.

The production host runs the capture and storage backend locally:

```text
Bepis app/worker -> 127.0.0.1:4318 Collector
systemd app/worker journals -> Collector
Collector -> 127.0.0.1 Tempo/Loki ingest
Tempo :3200 / read-only Loki proxy :3101 -> tailscale0 firewall only
```

OTLP gRPC/HTTP ingestion, Collector health, Collector metrics, Tempo internal
and ingest ports, and Loki HTTP/gRPC remain localhost-only and are never added
to the general or tailnet firewall. Tailnet Loki access uses a separate nginx
proxy that permits only GETs below `/loki/api/v1/`; write and OTLP paths are not
proxied. Query services bind for tailnet access only when configured, and the
firewall opens ports 3101/3200 exclusively on `tailscale0`. Tailscale device
authentication remains an out-of-band host bootstrap step. Grafana is a separate
consumer and its availability does not control local capture.

Collector memory is limited to 320 MiB by systemd and a 256 MiB processor
limit. Each backend exporter has a 2,048-item disk-backed queue and five-minute
bounded retry window. Hard systemd project quotas cap Collector state at 256
MiB and Tempo/Loki state at 4 GiB each; production requires the backing root
filesystem to mount with `prjquota`. Tempo also has a 512 MiB memory limit, 100
MB ingester block ceiling, and seven-day block retention. Loki has a 512 MiB
memory limit, seven-day retention/query window, 4 MiB/s steady and 8 MiB burst
ingestion limits, and bounded query parallelism.

Only `app.service` and `worker.service` journals are accepted. Before export,
the Collector replaces every journal body with `[redacted production journal
event]` and retains only allowlisted systemd unit/priority/syslog attributes.
This deliberately provides occurrence, severity, service, and timing evidence
without making arbitrary application messages searchable. Expanding retained
content or adding nginx request logs requires a separate privacy review.

## Bounded Agent Queries

The generic agent query surface defaults to the current development workspace's
localhost Tempo. `just otel-start` starts the dev observability stack and an
OTel-enabled app; `just otel-recent` then materializes recent local timing
evidence. The workspace wrapper supplies its isolated Tempo port and service
name.

Production is an explicit target. Configure the full MagicDNS name or Tailscale
IP; endpoints are never accepted as command-line arguments:

```bash
export BEPIS_PRODUCTION_TEMPO_QUERY_URL=https://bepis-production.example.ts.net:3200
export BEPIS_PRODUCTION_LOKI_QUERY_URL=https://bepis-production.example.ts.net:3101
```

Development accepts loopback only; production accepts tailnet addresses only.
Both reject credentials, paths, fragments, wrong ports, and OTLP ingestion
ports. Commands issue GETs only to fixed Tempo search/trace paths and, when Loki
is configured for the artifact target, its fixed service range query. There is
no arbitrary TraceQL, LogQL, Grafana, write, or URL parameter surface. The dev
stack currently provides Tempo but not Loki, so local related-log lookup fails
closed unless `BEPIS_DEVELOPMENT_LOKI_QUERY_URL` names an approved loopback Loki.

```bash
# Query local dev by default; pass production as the first just argument.
just otel-recent
just otel-recent production --minutes=5 --limit=10

# Use only the safe trace reference and artifact path printed above.
just otel-trace .pi/tmp/observability-query/... SAFE_REF
just otel-logs .pi/tmp/observability-query/... SAFE_REF

# Compare two bounded windows on an explicit target.
just otel-compare production \
  2026-08-30T01:00:00Z 2026-08-30T01:20:00Z

# The underlying commands also accept --target=development|production.
# BEPIS_OTEL_QUERY_TARGET changes the default for command-line use.
```

Queries are limited to the last seven days, three seconds per request and twenty
seconds per window, 8 MiB total response bytes, 2 MiB per response, 4 MiB per
materialized JSON artifact, 2,000 spans, 500 spans per trace, and 200 log rows. Raw traces exist in memory only. Before
materialization, attributes/resources are allowlisted, unknown span names and
values are hashed, status messages/events are removed, and raw trace IDs become
the common model's safe references. Loki output is rejected in full unless every
body is the production redaction marker; retained log evidence is count-only,
grouped by allowlisted metadata. Related logs are a fixed service query over the
trace's bounded time range plus 30 seconds, so they are temporal evidence rather
than a claim of causal trace context.

Private mode-0600 artifacts live only below
`.pi/tmp/observability-query/`, carry target-bound query provenance and a 24-hour expiry,
and are cleaned on subsequent command use. They remain
`bepis.otel.profile.v2`/`bepis.otel.comparison.v2`, so `otel_trace_search`,
`otel_trace_get`, `otel_compare_runs`, and the architecture `trace` query consume
them unchanged. Authorization, timeout, malformed-response, and outage failures
return bounded diagnostics and never touch production capture.

The app and worker want, but do not require, the Collector. Backend failure or
disablement therefore remains fail-open. Rollback is declarative: disable
`observability.otel`, `collector`, `tempo`, and `loki`, rebuild the host, and
leave `/var/lib/ihp-roster/{tempo,loki}` intact for recovery. Retention/access
operations and final incident procedures remain owned by the production
observability runbook issue.

## Verification And Navigation

- `docs/runbooks/performance-profiling.md`: exact local commands, artifacts,
  comparison, and diagnosis.
- `bash ./bin/in-env telemetry-boundary-probe`: exporter-backed semantic job,
  provider, websocket, export, outcome, and prohibited-attribute contract.
- `bash ./bin/in-env observability-production-check`: production Collector,
  Tempo, Loki, retention, resource, firewall, and unsafe-option validation.
- `bash ./bin/in-env observability-backend-smoke`: bounded local OTLP trace/log
  export through the production-shaped Collector into queryable Tempo/Loki.
- `otel-recent`, `otel-trace`, `otel-logs`, and `otel-compare`: fixed, bounded,
  target-aware development/production diagnosis surfaces.
- `docs/workstreams/opentelemetry-observability.md`: unresolved production
  intent and issue links.
- `Application/Helper/Telemetry.hs`: app telemetry implementation.
- `Config/nix/modules/ihp-roster.nix`: production configuration boundary.
- `Config/otel/` and `Config/nix/scripts/profile/`: collector and runner
  implementation.

Use `otel_recent`, `otel_trace`, `otel_logs`, and `otel_compare` for target-aware
materialization and focused inspection; use
`otel_trace_search`, `otel_trace_get`, and `otel_compare_runs` for bounded local
artifact inspection. Run canonical architecture and profile checks after
changing these boundaries.
