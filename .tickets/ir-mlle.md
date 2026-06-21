---
id: ir-mlle
status: open
deps: [ir-ojl5]
links: []
created: 2026-06-16T13:45:52Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, frontend, javascript, mobile, interaction]
---
# Implement pointer and touch gesture primitives

Add reusable pointer-event primitives for drag, resize, draw, hit-testing, autoscroll, cancellation, and mobile/touch behavior.

## Design

Use Pointer Events rather than native HTML drag/drop for custom timeline interactions. Support mouse, pen, and touch through pointer capture, movement thresholds, long-press or handle-based activation on touch, escape/cancel handling, and CSS touch-action guidance. Use elementFromPoint(...).closest(...) for drop/slot hit-testing while interaction overlays use pointer-events:none. Keep previews in data-bepis-interaction-layer and real server DOM unchanged.

## Acceptance Criteria

Runtime supports start/preview/commit/cancel phases for pointer drag/resize with mouse and touch; hit-testing works under overlay ghosts; gestures can be disabled/read-only; interaction state is cleaned up on timeout, cancel, htmx response, and live swap.

