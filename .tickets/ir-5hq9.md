---
id: ir-5hq9
status: closed
deps: []
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-sky7
tags: [area:admin, area:ui, area:shift-types, agent-loop]
---
# Convert shift type active status to shared toggle

Replace Shift Type active/inactive dropdowns with unified toggle buttons.

## Design

In Web.View.Admin.ShiftTypes, replace create/edit status selects with renderAppToggleButton-compatible controls while preserving submitted isActive values, HTMX update behavior, inactive filtering, and at-least-one-active behavior if applicable.

## Acceptance Criteria

Shift type create/edit rows use the shared toggle button pattern for active/inactive; existing mutation semantics and inactive filters keep working; focused admin config tests pass.

