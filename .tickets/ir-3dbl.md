---
id: ir-3dbl
status: open
deps: [ir-myon]
links: []
created: 2026-06-27T23:56:50Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-p008
tags: [agent-loop, observability, nixos, opentelemetry]
---
# Add production observability NixOS module options

Expose ihp-roster OpenTelemetry, diagnostic profiling, collector, Tempo, and Loki runtime controls through the project NixOS module instead of ad-hoc env setup.

## Design

Add services.ihpRoster.observability options for otel enable/serviceName/endpoint/sampler, profiling enable, collector local receiver, and optional Tempo/Loki tailnet exposure. Emit app OTEL_* and IHP_ROSTER_* env vars from module options while keeping OTLP ingestion localhost by default.

## Acceptance Criteria

Production can enable lightweight OTel tracing with module options; diagnostic profiling remains explicit; collector ingestion defaults to localhost; tailnet exposure is opt-in; module option docs describe safe defaults.

