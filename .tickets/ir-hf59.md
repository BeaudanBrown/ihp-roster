---
id: ir-hf59
status: closed
deps: [ir-8zip, ir-nl8k]
links: []
created: 2026-06-30T04:48:17Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-zqp3
tags: [architecture, realtime, live-updates]
---
# Refine realtime architecture into coverage and flow queries

Make realtime/live diagrams answer separate coverage and mechanism-flow questions.

## Design

Split or refine realtime-usage into realtime-coverage and realtime-flow. Coverage should group server files/actions/frontend consumers/tests and distinguish unique live surfaces from references. Flow should explain current mechanism: mutation action -> mutation/service -> LiveResource/LiveSurface -> invalidation registry/bus -> websocket message -> generated LiveUpdateMessage -> frontend app-live-updates.ts -> fragment refetch/UI region transition. Keep names mechanism-agnostic so polling/SSE/etc can be represented later.

## Acceptance Criteria

Realtime coverage no longer reports misleading 'typed surfaces: 311' as distinct surfaces. Diagrams group by subsystem and distinguish tests from runtime consumers. A flow diagram exists for at least one migrated or representative action/surface.

