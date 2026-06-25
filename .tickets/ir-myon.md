---
id: ir-myon
status: open
deps: [ir-at28]
links: []
created: 2026-06-25T13:30:47Z
type: feature
priority: 2
assignee: beaudan
parent: ir-p008
tags: [agent-loop, observability, opentelemetry]
---
# Wire OpenTelemetry WAI request tracing and OTLP export

Add the OpenTelemetry runtime spine: WAI root HTTP server spans, tracer provider/exporter setup, and environment-gated OTLP export.

## Design

Use hs-opentelemetry instrumentation for WAI where practical. Gate app initialization with IHP_ROSTER_OTEL=1 and standard OTEL_* environment variables such as OTEL_SERVICE_NAME, OTEL_EXPORTER_OTLP_ENDPOINT, and sampler configuration. Keep current IHP_ROSTER_PROFILING behavior untouched.

## Acceptance Criteria

With IHP_ROSTER_OTEL=1 and a local collector, a roster request appears as an HTTP server trace with method/path/status/route-ish attributes; with the flag unset there is no meaningful runtime/export overhead; existing typecheck and focused roster tests pass; setup docs include a minimal local collector command/config.

