---
id: ir-jroj
status: open
deps: [ir-3dbl]
links: []
created: 2026-06-27T23:56:50Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-p008
tags: [agent-loop, observability, tempo, loki, nixos]
---
# Run production collector Tempo and Loki behind tailnet

Add the production-host observability backend for traces and logs so telemetry is captured locally even when the personal Grafana host is offline.

## Design

Run Grafana Alloy or OpenTelemetry Collector on the production host receiving app OTLP on localhost, forwarding/storing traces in Tempo and journald/systemd logs in Loki. Expose only query APIs over tailscale0; do not expose OTLP ingestion publicly.

## Acceptance Criteria

Production app exports to localhost collector; traces are queryable from Tempo over tailnet; app/system logs are queryable from Loki over tailnet; public internet cannot reach telemetry APIs; retention/storage limits are configured.

