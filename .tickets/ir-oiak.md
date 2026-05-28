---
id: ir-oiak
status: closed
deps: [ir-hdpq]
links: []
created: 2026-05-28T05:42:05Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-j3eq
tags: [area:leave, area:ui, agent-loop]
---
# Render unavailability archive without actions and keep Pending open

Polish manager unavailability sections.

## Design

Keep the Unavailability page's Pending accordion section open by default. Render the Archive section without an Actions header/column/cell. Add a concise tk note or child follow-up for archive pagination because archived unavailability records will grow indefinitely.

## Acceptance Criteria

Pending remains the only default-open unavailability section; Archive rows have no Actions column; no layout gap remains; tests/e2e for leave manager sections are updated; archive pagination follow-up is recorded.


## Notes

**2026-05-28T06:29:06Z**

Archive pagination follow-up is tracked by child ticket ir-aqy1.
