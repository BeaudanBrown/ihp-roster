---
id: ir-lf8v
status: closed
deps: [ir-pbsx, ir-kim9]
links: []
created: 2026-05-27T23:58:34Z
type: task
priority: 2
assignee: beaudan
parent: ir-hx3q
tags: [area:e2e, area:mobile]
---
# Add no-autofocus regression coverage

Add focused regression checks for no automatic focus on representative pages and overlays.

## Design

Prefer Playwright checks that assert document.activeElement is not an input/select/textarea immediately after load/open. Include a lightweight source grep assertion if practical.

## Acceptance Criteria

E2E coverage fails if sign-in/profile/passkey/timesheet/leave dialog open flows auto-focus a control; mobile smoke remains green.

