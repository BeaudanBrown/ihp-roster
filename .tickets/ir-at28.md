---
id: ir-at28
status: closed
deps: []
links: []
created: 2026-06-25T13:30:47Z
type: task
priority: 2
assignee: beaudan
parent: ir-p008
tags: [agent-loop, observability, design]
---
# Design the Bepis OpenTelemetry observability contract

Define the concrete OpenTelemetry contract before wiring code: package choices, backend topology, env gates, span/metric naming, sampling defaults, and PII/cardinality rules.

## Design

Record the observability contract before wiring code. Package decision: use `hs-opentelemetry-api`, `hs-opentelemetry-sdk`, `hs-opentelemetry-exporter-otlp`, `hs-opentelemetry-propagator-w3c`, and `hs-opentelemetry-instrumentation-wai` with a project Nix `doJailbreak` override for the stale `hs-opentelemetry-api ==0.2.*` upper bound. Note that the override has been build-tested against the available `hs-opentelemetry-api-0.3.0.0`; do not switch to the separate `opentelemetry-wai` stack unless that stops being true.

Document the initial local backend as app -> Nix-managed OpenTelemetry Collector -> local file/export artifacts for agent summaries. Tempo/Grafana and Prometheus-compatible metrics remain optional later backends, not blockers for first tracing. Metrics are secondary for the first implementation; prioritize root/child traces and useful attributes.

Define env gates and modes: default off; `IHP_ROSTER_OTEL=1` enables lightweight sampled tracing via standard `OTEL_*` variables; `IHP_ROSTER_PROFILING=1` keeps enabling diagnostic profiling headers, forced HTML byte measurement, render counters, and heavier local profile runs.

Decide trace attributes for action route, layout, week status, editability, and low-cardinality roster shape counts. WAI alone cannot infer IHP action constructor names; document the controller `beforeAction` annotation approach using the action ADT `Data` instance to set `http.route`/span name to low-cardinality constructor names. Explicitly exclude names, emails, raw query strings, staff IDs, slot IDs, user IDs, and venue IDs unless a later ticket records an exception.

Record that observability/profiling deployment configuration belongs in the project NixOS module options: enable flag, service name, OTLP endpoint, sampler/sampler arg, optional local collector/profile configuration, and existing diagnostic profiling behavior.

## Acceptance Criteria

A short living design note exists in the appropriate docs/spec location; package/backend/env decisions are recorded; naming and attribute policy covers current roster profiling spans/counters; follow-on tickets have enough detail to implement without reopening architecture decisions.


## Notes

**2026-06-27T23:58:26Z**

Created docs/architecture/observability.md and docs/workstreams/opentelemetry-observability.md with package decisions, env modes, route/action naming policy, local agent artifact topology, production Tempo/Loki split, NAS Grafana frontend, and NixOS option direction.
