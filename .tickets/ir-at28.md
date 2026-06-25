---
id: ir-at28
status: open
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

Validate hs-opentelemetry-api/sdk/exporter-otlp/instrumentation-wai availability in the project build. Document local backend as app -> OTLP collector -> Tempo/Grafana plus Prometheus-compatible metrics. Decide trace attributes for route/layout/week status/slot counts and explicitly exclude names, emails, raw query strings, staff IDs, slot IDs, user IDs, and venue IDs unless a later ticket records an exception.

## Acceptance Criteria

A short living design note exists in the appropriate docs/spec location; package/backend/env decisions are recorded; naming and attribute policy covers current roster profiling spans/counters; follow-on tickets have enough detail to implement without reopening architecture decisions.

