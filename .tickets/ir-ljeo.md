---
id: ir-ljeo
status: open
deps: [ir-39r1, ir-7hzq]
links: []
created: 2026-06-27T23:56:50Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-p008
tags: [agent-loop, observability, docs, runbook]
---
# Document production observability runbook and security model

Document how to operate the production observability stack and what must remain private/tailnet-only.

## Design

Describe app OTel modes, production collector/Tempo/Loki, NAS Grafana, tailnet exposure, retention, PII/cardinality rules, and emergency disable steps.

## Acceptance Criteria

Runbook explains safe enable/disable, where data lives, which endpoints are exposed, how agents and humans query data, and how to avoid PII/high-cardinality telemetry.

