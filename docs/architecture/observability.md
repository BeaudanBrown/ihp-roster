# Observability Architecture

Implemented telemetry behavior is owned by `Application/Helper/Telemetry.hs`,
the profiling helpers, `Config/otel/`, and the Nix scripts/module. Exact local
profiling procedures live in `docs/runbooks/performance-profiling.md`. Unresolved
production capture, storage, retention, and Grafana work lives only in
`docs/workstreams/opentelemetry-observability.md` and its linked GitHub issues.

## Modes

Observability modes are deliberately separate:

- default: no OpenTelemetry provider/exporter and no diagnostic profiling;
- `IHP_ROSTER_OTEL=1`: sampled lightweight request/action telemetry using
  standard `OTEL_*` configuration;
- `IHP_ROSTER_PROFILING=1`: expensive diagnostic timing, response-byte, and
  render-counter evidence for isolated profile runs or controlled diagnosis.

Ordinary production traffic must not receive profiling headers or expensive
render diagnostics. Production configuration belongs in the
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

The unresolved production target is intentionally documented only at the
workstream level:

```text
Bepis -> localhost OTLP -> production Collector/Alloy -> Tempo/Loki
  -> tailnet-only query APIs -> authenticated tailnet Grafana
```

Production enablement requires reviewed retention/storage limits, access and
PII policy, low-cardinality conventions, rollback/disable procedures, and
continued local capture when a remote frontend is unavailable. OTLP ingestion
must not be publicly exposed.

## Verification And Navigation

- `docs/runbooks/performance-profiling.md`: exact local commands, artifacts,
  comparison, and diagnosis.
- `docs/workstreams/opentelemetry-observability.md`: unresolved production
  intent and issue links.
- `Application/Helper/Telemetry.hs`: app telemetry implementation.
- `Config/nix/modules/ihp-roster.nix`: production configuration boundary.
- `Config/otel/` and `Config/nix/scripts/profile/`: collector and runner
  implementation.

Use `otel_trace_search`, `otel_trace_get`, and `otel_compare_runs` for bounded
agent inspection of generated artifacts. Run canonical architecture and profile
checks after changing these boundaries.
