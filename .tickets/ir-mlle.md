---
id: ir-mlle
status: open
deps: [ir-ojl5, ir-95e7]
links: []
created: 2026-06-16T13:45:52Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, frontend, typescript, mobile, interaction]
---
# Implement pointer and touch disposable session primitives

Add reusable TypeScript primitives for pointer/touch disposable sessions such as drag, resize, draw-range, hit-testing, autoscroll, cancellation, and cleanup.

## Design

Use Pointer Events rather than native HTML drag/drop for custom timeline interactions. Primitives should consume Haskell-generated surface/layer/handle/slot metadata and keep previews in declared disposable layers. The real server-owned DOM remains unchanged until an authoritative HTMX response.

Support mouse, pen, and touch through pointer capture, movement thresholds, handle-based activation where possible, optional long-press fallback for touch, Escape/cancel handling, disabled/read-only states, and CSS `touch-action` guidance. Use `elementFromPoint(...).closest(...)` for hit-testing while disposable overlay nodes use `pointer-events:none` when appropriate.

Keep this generic: drag/drop and resize are initial users, but the session model should also support future selection rectangles, drawing previews, context menus, and keyboard-driven disposable UI.

## Acceptance Criteria

- Runtime supports disposable session start/preview/commit/cancel/error phases for pointer interactions.
- Mouse, pen, and touch are supported with safe activation thresholds/handles.
- Hit-testing works under disposable overlay/ghost nodes.
- Sessions can be disabled or read-only from generated markup/policy.
- Disposable UI is cleaned up on cancel, timeout, HTMX lifecycle cleanup, and explicit session end.
- Unit/DOM tests cover session state transitions and hit-testing decisions where practical.
- `bash ./bin/in-env frontend-check` passes.

