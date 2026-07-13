# Observability Architecture

Status: planned

Primary epic: `#90` - Replace roster profiling spine with OpenTelemetry

## Goals

Bepis observability has two audiences:

1. Coding agents need bounded, scriptable trace/profile artifacts for debugging and before/after performance comparisons.
2. Humans need a tailnet-only frontend for production traces, logs, and later metrics.

The system should keep production defaults safe: tracing is off unless enabled,
normal production tracing is lightweight and sampled, and expensive HTML byte and
render-counter diagnostics remain explicitly gated.

## Modes

- **Off**: default. No OpenTelemetry tracer provider/exporter is initialized.
- **Lightweight OTel**: `IHP_ROSTER_OTEL=1`. The app emits sampled WAI request
  traces and cheap child spans/attributes using standard `OTEL_*` variables.
- **Diagnostic profiling**: `IHP_ROSTER_PROFILING=1`. Existing profiling
  headers, forced HTML byte measurement, render counters, and deeper component
  diagnostics are enabled. This mode is for isolated profile runs or controlled
  operator diagnostics, not ordinary public traffic.

`IHP_ROSTER_OTEL` and `IHP_ROSTER_PROFILING` are intentionally separate. A
production deployment may enable lightweight sampled OTel without enabling the
heavier profiling path.

Production should configure these through the NixOS module rather than ad-hoc
environment variables:

```nix
services.ihpRoster.observability = {
  otel = {
    enable = true;
    serviceName = "ihp-roster-prod";
    sampler = "parentbased_traceidratio";
    samplerArg = "0.01";
  };
  collector = {
    enable = true;
    receiverAddress = "127.0.0.1";
  };
};
```

The module keeps OTLP ingestion on localhost by default. Tailnet exposure is
reserved for query APIs such as Tempo/Loki/Grafana, and remains opt-in through
separate `queryAddress` options.

## Haskell Package Choice

Use the `hs-opentelemetry-*` package family:

- `hs-opentelemetry-api`
- `hs-opentelemetry-sdk`
- `hs-opentelemetry-exporter-otlp`
- `hs-opentelemetry-propagator-w3c`
- `hs-opentelemetry-instrumentation-wai`

The nixpkgs `hs-opentelemetry-instrumentation-wai` derivation is marked broken
because the published Cabal file still bounds `hs-opentelemetry-api ==0.2.*`.
A project `doJailbreak` override has been build-tested against the available
`hs-opentelemetry-api-0.3.0.0`, so prefer that override over switching to the
separate `opentelemetry-wai` stack.

## App Trace Shape

WAI middleware owns the root HTTP server span. It may record method, status,
protocol, and a sanitized path-like target, but must not emit raw query strings.

IHP action names are not inferrable from WAI alone. Add a lightweight action
annotation helper called from controller `beforeAction` implementations. The
helper should use each action ADT's `Data` instance to set/update `http.route`
and the root span name to low-cardinality constructor names such as
`ShowRosterWeekAction`.

Existing semantic profiling helpers should bridge into OTel:

- `profileActionSpan` and `profileActionSpanWithDetail` create cheap child spans
  in lightweight OTel mode.
- `respondHtmlProfiled`, `profileHtmlComponent`, `profileCounter`, and
  `profileRenderCounter` add byte/counter details only in diagnostic profiling
  mode, because they can force rendering or add high-volume work.

## Attribute Policy

Allowed by default:

- service name, environment, host
- HTTP method and status
- IHP action constructor name
- low-cardinality route/layout/week/editability state
- low-cardinality component names
- aggregate counts already computed for a render/profile run

Excluded by default:

- names and emails
- raw query strings
- user, staff, venue, slot, passkey, export job, sync run, and similar ids
- free-form request params
- high-cardinality labels in metrics or log streams

Any exception needs a ticket and an explicit PII/cardinality justification.

## Agent-First Local Profile Topology

Local/profile runs should not require Grafana or a live UI:

```text
profile runner -> app with OTel/profiling env -> local OTLP collector -> local export files -> JSON/Markdown summaries -> Pi tools
```

The collector should be Nix-managed and ephemeral for profile runs. Summary
artifacts should live beside existing profile outputs and include slow traces,
representative spans, component bytes, counters, and before/after comparison
inputs.

A minimal local smoke-test collector can be run from Nix without installing
anything globally:

```bash
nix shell nixpkgs#opentelemetry-collector-contrib -c otelcol-contrib \
  --config ./Config/otel/local-file-collector.yaml
```

The app side of that smoke test should use:

```bash
IHP_ROSTER_OTEL=1 \
OTEL_SERVICE_NAME=ihp-roster-dev \
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318 \
OTEL_TRACES_SAMPLER=always_on
```

The checked-in profile-run collector configuration owns this smoke-test path and
its bounded summary artifacts.

## Dev Live Frontend Topology

For interactive local debugging, the repo provides a disposable localhost-only
Tempo/Grafana/collector stack:

```text
just dev -> dev app with IHP_ROSTER_OTEL=1 -> localhost OTel Collector -> localhost Tempo -> localhost Grafana Explore
```

Use `just dev` for the default foreground path: it starts the dev app with
`IHP_ROSTER_OTEL=1` and the matching `OTEL_*` defaults, plus the localhost-only
collector, Tempo, and Grafana stack. Local dev also enables
`IHP_ROSTER_OTEL_DIAGNOSTIC_HEADERS=1`, which lets trusted local tools attach
low-cardinality `bepis.trace.run` and `bepis.trace.step` attributes from
`X-Bepis-Trace-Run` / `X-Bepis-Trace-Step` request headers. These headers are for
local/agent diagnostics and are not part of the normal production contract.

Make requests against the dev app, then open `http://127.0.0.1:3300/explore` and
search the Tempo datasource for service `ihp-roster-dev`. The detached
compatibility entrypoint `bash ./bin/in-env dev-start-otel` remains available.
This flow is for live inspection; profile artifact flows remain the repeatable
before/after comparison path.

Agent-facing browser trace runs are available through:

```bash
# Exercise the shared scenario catalog with Playwright, tag each request, then
# write journey + Tempo summaries under output/otel-browser/.
bash ./bin/in-env otel-browser --scenario full --role owner

# Summarize an existing tagged run or recent service traces.
bash ./bin/in-env otel-summary --run-id <uuid>
bash ./bin/in-env otel-summary --limit 200
```

The summary artifacts include slow spans, largest exclusive-time gaps, repeated
span names, and error-status classification. This is the preferred AI-agent
entrypoint before changing performance-sensitive code because it preserves a
bounded browser journey and a machine-readable trace summary beside the Markdown
report.

## Production Topology

Production should keep critical capture/storage near the app:

```text
Bepis app -> localhost OTLP -> production Alloy/OTel Collector -> production Tempo + Loki
```

- OTLP ingestion is localhost-only by default.
- Tempo and Loki query APIs may be exposed on `tailscale0` only.
- Production should continue capturing traces/logs if the personal/NAS frontend
  is offline.
- Retention and storage limits must be configured.

Journald/systemd logs should be collected with Grafana Alloy or equivalent and
stored in Loki. Log labels must remain low-cardinality, e.g. service, unit,
host, environment.

## Human Frontend Topology

The human frontend should run on the personal/NAS host through the existing
nix-dotfiles hosted-service pattern:

```text
NAS Grafana -> production Tempo/Loki tailnet query endpoints
```

Grafana should be tailnet-only and authenticated. It should provision Tempo and
Loki datasources first, with Prometheus added later when stable metrics are
promoted.

## NixOS Configuration Direction

The ihp-roster NixOS module should expose observability options instead of
requiring ad-hoc environment files. Expected option groups:

- app OTel enable/service name/OTLP endpoint/sampler/sampler arg
- diagnostic profiling enable
- local collector receiver settings
- production Tempo/Loki enablement and tailnet exposure
- retention/storage limits

The nix-dotfiles NAS side should add a tailnet-only Grafana hosted service and
provision datasources pointing at production tailnet endpoints.

## Related Tickets

- `#73` - Run production collector Tempo and Loki behind tailnet
- `#40` - Add NAS Grafana tailnet frontend for production observability
- `#13` - Provision Bepis observability dashboards and trace log correlation
- `#79` - Document production observability runbook and security model
- `#28` - Deprecate the custom profiling header spine after OTel parity
