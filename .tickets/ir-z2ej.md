---
id: ir-z2ej
status: open
deps: [ir-mwrz]
links: []
created: 2026-06-16T13:46:10Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, frontend, htmx, mobile, interaction, timeline]
---
# Prototype timeline edge resize intent

Build a prototype for changing a block duration by dragging a start/end resize handle while keeping server DOM authoritative.

## Design

Resize handles emit pointer resize sessions. The interaction layer draws a translucent preview snapped to server-declared slots; the real shift/block stays unchanged. On pointerup, submit itemId, edge, and slotId through a declared HTMX intent form. Server validates min duration, overlaps, scope, and final timestamps.

## Acceptance Criteria

A timeline block can be resized from start or end with mouse and touch handle interactions; preview is disposable; HTMX submits intent tokens only; server response replaces the authoritative fragment; errors and live updates cleanly cancel or refresh the session.

