---
id: ir-mxsn
status: closed
deps: [ir-wqa4, ir-r27i]
links: []
created: 2026-05-16T03:27:18Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-y166
tags: [area:live-fragments, area:protocol, area:frontend]
---
# Decide compact live-update wire protocol

Decide whether to shrink websocket/actor-refresh payloads now that each mounted surface has typed config metadata.

## Design

Compare current self-describing invalidations (target/url/protection in every payload) with a compact fragment-key protocol that resolves details from mounted surface config. If changing JSON, update static/app-live-updates.js and add migration tests for multiple mounted surfaces, reconnect resync, stale configs, actor refresh, and focused protection. If not changing JSON, record the decision and close with no code change.

## Acceptance Criteria

An ADR or workstream decision states whether the browser JSON protocol changes. If implemented, Playwright and Hspec compatibility/migration tests pass; if deferred, protocol simplification is explicitly parked with rationale.


## Notes

**2026-05-16T03:43:36Z**

Decision recorded in the workstream: compact browser payloads are deferred. The self-describing JSON protocol is retained to avoid stale-config/multi-surface/actor-refresh migration risk.
