---
id: ir-cfzc
status: closed
deps: []
links: []
created: 2026-07-09T02:34:45Z
type: bug
priority: 2
assignee: Beaudan Brown
parent: ir-qbm4
tags: [agent-loop, frontend, interaction, roster, drag-drop]
---
# Disable touch drag and show copy drag shadow

Follow-up: prevent touch scroll gestures from briefly starting drag sessions, and make copy modifier drag shadow visibly distinct as the modifier is pressed before drop.

## Acceptance Criteria

Touch pointer events do not start generic drag/drop sessions. Copy modifier changes the active drag shadow styling before commit and remains platform-aware. Focused frontend tests and checks pass.

