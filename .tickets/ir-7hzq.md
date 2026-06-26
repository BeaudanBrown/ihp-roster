---
id: ir-7hzq
status: open
deps: [ir-0c2u]
links: []
created: 2026-06-25T13:30:47Z
type: feature
priority: 2
assignee: beaudan
parent: ir-p008
tags: [agent-loop, observability, pi-extension, tooling]
---
# Expose observability workflows to coding agents

Give coding agents first-class tools to run profile scenarios and query OpenTelemetry-derived results.

## Design

Implement a project-local Pi extension before relying on external MCP. Candidate tools: `roster_profile_run`, `roster_profile_summary`, `otel_trace_search`, `otel_trace_get`, `otel_compare_runs`, and later `otel_metric_query` once metrics are promoted. Prefer artifact-backed tools first: read the profile run's OTel JSON/Markdown summaries and local collector export files, with bounded output and representative trace drill-downs. Keep commands safe by default: low rate, local/staging only unless explicit, compact summaries, PII redaction. Also document Grafana MCP as the preferred richer integration once Grafana/Tempo is running.

## Acceptance Criteria

An agent can run a low-rate roster profile, retrieve slowest route/span summaries, inspect a representative trace, and compare against a previous profile artifact without manually parsing NDJSON; Grafana MCP setup notes exist for teams that want dashboard/backend querying; tools have bounded output suitable for LLM use.

