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

Extend the profile-load-suite workflow or adjacent scripts to support an ephemeral/local OTLP collector and Tempo/Jaeger-compatible trace store. Export summaries such as slowest traces, largest components, component bytes by route, render span p95s, and counter/attribute comparisons as JSON and markdown. Preserve the current k6 summary shape during transition.

## Acceptance Criteria

A standard low-rate roster-wide profile produces suite-summary.md plus OTel-derived summary artifacts; artifacts include enough data for before/after comparison without a live UI; failures are reported clearly when the collector/backend is unavailable; docs show the exact local command path.

