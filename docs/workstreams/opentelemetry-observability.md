# OpenTelemetry Observability Workstream

Status: active

Epic: `ir-p008` - Replace roster profiling spine with OpenTelemetry

Architecture note: `docs/architecture/observability.md`

## Goal

Replace the custom profiling spine as the primary observability path with
OpenTelemetry traces, agent-readable local profile artifacts, and a tailnet-only
human frontend for production traces/logs.

## Scope

This stream covers:

- app OpenTelemetry runtime wiring and WAI request traces
- IHP action route annotation
- bridging existing profiling spans/counters into OTel without making production
  tracing heavy
- local Nix-managed collector/profile artifacts for coding agents
- project-local Pi tools for querying/comparing profile runs
- production observability module options
- production Collector/Alloy, Tempo, and Loki behind the tailnet
- NAS/personal-host Grafana frontend over the tailnet
- eventual deprecation of `X-Profile-Counters` as a primary reporting path

Metrics are intentionally secondary. They should follow once useful traces and
artifact summaries exist.

## Implementation Plan

### 1. Contract and package decision

Ticket: `ir-at28`

Document the package stack, env gates, attribute policy, backend topology, and
NixOS option direction. Use `hs-opentelemetry-*` with a project `doJailbreak`
override for `hs-opentelemetry-instrumentation-wai`'s stale API upper bound.

### 2. App OpenTelemetry runtime spine

Ticket: `ir-myon`

Add the Haskell dependencies and Nix override. Introduce a telemetry helper
module, initialize the tracer provider only when `IHP_ROSTER_OTEL=1`, wire WAI
request tracing, and add controller action annotation using the action ADT
constructor name.

### 3. Bridge existing profiling helpers

Ticket: `ir-st8a`

Bridge `profileActionSpan` and `profileActionSpanWithDetail` to cheap OTel
child spans. Keep byte-measuring HTML helpers and render counters diagnostic by
requiring `IHP_ROSTER_PROFILING=1` or an equally explicit future diagnostic gate.

### 4. Counters and metrics

Ticket: `ir-6io4`

Move roster render counters to trace attributes/events for diagnostic runs.
Promote only stable low-cardinality signals to metrics later.

### 5. Agent-first collector artifacts

Ticket: `ir-0c2u`

Extend profile scripts with a Nix-managed local OTLP collector that exports
bounded trace files and OTel-derived JSON/Markdown summaries next to existing
profile outputs. Implemented entrypoints are `profile-load --otel` and
`profile-load-suite --otel`, producing `otel-traces.json`, `otel-summary.json`,
and `otel-summary.md` artifacts.

### 6. Pi/agent tools

Ticket: `ir-7hzq`

Add project-local tools for running low-rate profile scenarios, summarizing
profile artifacts, finding slow traces/spans, inspecting representative traces,
and comparing before/after runs. Project-local Pi tools live in
`.pi/extensions/observability.ts`:

- `roster_profile_run` - safe low-rate local profile run with OTel artifacts.
- `roster_profile_summary` - bounded Markdown summary reader.
- `otel_trace_search` - compact slow-span/component/counter rows.
- `otel_trace_get` - bounded trace inspection from `otel-traces.json`.
- `otel_compare_runs` - before/after artifact comparison scaffold.

These tools are artifact-backed and do not require a live dashboard. Once
Grafana/Tempo exists, Grafana MCP is the preferred richer query path for humans
and agents that need dashboard/backend exploration; keep it tailnet-only and do
not expose OTLP ingestion publicly.

### 7. Production NixOS options

Ticket: `ir-3dbl`

Expose app OTel, profiling, collector, Tempo, and Loki runtime controls through
the `services.ihpRoster.observability` NixOS module option tree.

### 8. Production capture/storage

Ticket: `ir-jroj`

Run the production collector/Alloy, Tempo, and Loki on the actual production
host. Keep app OTLP ingestion localhost-only and expose query APIs over
`tailscale0` only.

### 9. Human Grafana frontend

Ticket: `ir-8fit`

In `~/documents/nix-dotfiles`, add a tailnet-only Grafana hosted service on the
personal/NAS host. Provision datasources for production Tempo and Loki tailnet
endpoints.

### 10. Dashboards and trace/log correlation

Ticket: `ir-39r1`

Provision Bepis dashboards and conventions so operators can navigate from a slow
or failed request trace to related Loki logs.

### 11. Runbook and security model

Ticket: `ir-ljeo`

Document safe enable/disable procedures, endpoint exposure, retention, where data
lives, and PII/cardinality rules.

### 12. Compatibility cleanup

Ticket: `ir-62zx`

After traces, artifacts, and tools cover the existing workflows, mark
`X-Profile-Counters` legacy and keep/remove `Server-Timing` based on remaining
browser-devtools value.

## Target Topologies

### Local agent/profile runs

```text
profile-load-suite --otel
  -> app with IHP_ROSTER_OTEL=1 and optionally IHP_ROSTER_PROFILING=1
  -> local Nix-managed OTel collector
  -> local collector export files
  -> otel-summary.json / otel-summary.md
  -> Pi tools
```

### Production and human viewing

```text
Bepis app
  -> localhost OTLP
  -> production Alloy/OTel Collector
  -> production Tempo + Loki
  -> tailnet query APIs
  -> NAS Grafana frontend
```

## Living Docs To Update As Work Lands

- `docs/architecture/observability.md`
- `specs/12-performance-profiling.md`
- `Application/Helper/Profiling.hs` module comments or adjacent docs if added
- `Application/Helper/Telemetry.hs` docs once created
- `Config/nix/modules/ihp-roster.nix` option documentation
- relevant profile script help text under `Config/nix/scripts/profile/`
- nix-dotfiles hosted-service docs if Grafana is added there

## Exit Criteria

- OpenTelemetry traces exist for app requests and useful child spans.
- Agent profile runs generate OTel-derived summary artifacts.
- Pi tools can run, inspect, and compare profile runs without a live UI.
- Production can capture traces/logs locally and expose query APIs only over the
  tailnet.
- NAS/personal Grafana can view production traces/logs over the tailnet.
- Current profiling headers are compatibility-only or intentionally retained for
  browser devtools.
