---
id: ir-ptnv
status: open
deps: [ir-mlle]
links: []
created: 2026-06-16T13:45:58Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, frontend, live-updates, htmx, interaction]
---
# Coordinate interaction runtime with live fragments

Make live fragment swaps and interaction sessions safe when the same surface is being dragged, resized, or otherwise manipulated.

## Design

Define and implement a shared policy for data-interaction-active/data-interaction-pending on surfaces. During active pointer interactions, same-surface passive live swaps should be deferred or the interaction should be canceled predictably. On HTMX afterSwap/responseError/live swap, clear disposable interaction layers and stale sessions. Avoid JS-created DOM becoming part of server-owned fragments.

## Acceptance Criteria

Live runtime and interaction runtime have an explicit boundary; same-surface swaps during active interactions do not leave stale ghost nodes or broken references; actor HTMX responses replace server-owned DOM and clear pending interaction state; behavior is covered by tests or targeted e2e.

