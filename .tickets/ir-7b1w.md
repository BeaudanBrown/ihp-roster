---
id: ir-7b1w
status: closed
deps: []
links: [ir-w5a8, ir-xqwe, ir-s8k1, ir-wec9, ir-2324]
created: 2026-07-10T00:19:58Z
type: task
priority: 2
assignee: beaudan
parent: ir-z20h
tags: [agent-loop, roster, ui]
---
# Polish roster staff panel header controls

Move roster staff panel controls into a clearer horizontal header layout.

## Design

Render Add trial staff and Show all staff in the same flex row, wrapping on small screens. Preserve the existing staff-scope toggle behavior and Add trial staff dialog route.

## Acceptance Criteria

Roster staff panel header shows Add trial staff inline horizontally with Show all staff when both are visible. Single-control states still align cleanly. Existing staff-panel HTMX behavior and focused roster tests pass.

