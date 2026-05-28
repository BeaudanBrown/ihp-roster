---
id: ir-qhhm
status: closed
deps: []
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-sky7
tags: [area:admin, area:ui, agent-loop]
---
# Default Admin accordions closed

Make Admin accordions closed by default.

## Design

Update Admin accordion rendering so no Admin section opens automatically on page load. This implements the global accordion direction except for the Unavailability page's Pending section, which remains open in its own epic.

## Acceptance Criteria

Admin Invites, Venue Settings, Shift Types, Roster Groups, and any visible Admin sections render collapsed by default; tests and screenshots expecting Invites open are updated.

