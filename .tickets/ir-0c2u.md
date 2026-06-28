---
id: ir-0c2u
status: closed
deps: [ir-6io4]
links: []
created: 2026-06-25T13:30:47Z
type: feature
priority: 2
assignee: beaudan
parent: ir-p008
tags: [agent-loop, observability, profiling, tooling]
---
# Add local collector and profile-run OTel summary artifacts

Make low-rate profile runs start/use an OpenTelemetry backend and emit compact agent-readable summaries alongside existing suite artifacts.

## Design

Extend the profile-load-suite workflow or adjacent scripts to support a Nix-managed ephemeral/local OTLP collector. The first-class local backend should be collector file/export artifacts in the profile run directory so AI agents can inspect bounded data without a live UI. Tempo/Jaeger/Grafana can be supported as optional richer backends later, but should not be required for the initial agent workflow.

Export summaries such as slowest traces, representative slow spans, largest components, component bytes by route/action, render span p95s, and counter/attribute comparisons as JSON and markdown. Preserve the current k6 summary shape during transition, and add OTel-derived `otel-summary.json`/`otel-summary.md` style artifacts beside existing suite outputs.

## Acceptance Criteria

A standard low-rate roster-wide profile produces `suite-summary.md` plus OTel-derived JSON/Markdown summary artifacts from local collector export files; artifacts include enough data for before/after comparison and representative trace inspection without a live UI; failures are reported clearly when the collector/backend is unavailable; docs show the exact Nix-managed local command path.


## Notes

**2026-06-28T02:20:33Z**

Added --otel support to profile-load/profile-load-suite. profile-load starts a Nix-shell otelcol-contrib collector, exports per-run otel-traces.json, and generates otel-summary.json/md. profile-load-suite passes --otel to scenarios and aggregates root otel-summary.json/md. Added summary parsers plus profile collector config. Verified with bash -n/node --check/otelcol validate and a live 1s profile-load --otel smoke run.
