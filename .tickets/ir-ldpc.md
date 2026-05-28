---
id: ir-ldpc
status: open
deps: [ir-skto]
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-pups
tags: [area:auth, area:profile, area:ui, agent-loop]
---
# Render passkey list read-only with relative last-used age

Simplify existing passkey rows.

## Design

Remove rename controls from the passkey list UI and remove the Created column. Show passkey name and relative Last used age only. Implement a small formatter with one displayed unit at a time using hours, days, weeks, then months (e.g. 'less than 2 months ago'), with sensible handling for Never.

## Acceptance Criteria

Passkey list has no rename form and no Created column; Last used displays relative age in one unit; formatter is covered by tests; delete controls remain available only through the verified delete flow.

