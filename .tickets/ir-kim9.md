---
id: ir-kim9
status: closed
deps: []
links: []
created: 2026-05-27T23:58:34Z
type: task
priority: 1
assignee: beaudan
parent: ir-hx3q
tags: [area:ui, area:mobile, area:overlays]
---
# Stop dialogs and overlays from focusing controls on mount

Update shared dialog overlay behavior so HTMX/page overlays do not focus inputs, selects, textareas, buttons, or links automatically when mounted.

## Design

Change static/app-dialog-overlays.js focus management to avoid automatic control focus. If any shell focus is retained for accessibility, it must not trigger mobile keyboards and must not focus form controls.

## Acceptance Criteria

Opening timesheet, leave, and passkey recovery dialogs leaves document focus outside form controls or on a non-input shell only; dialogs still close via Escape/backdrop/close button.

