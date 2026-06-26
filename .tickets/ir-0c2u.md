---
id: ir-0c2u
status: open
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

