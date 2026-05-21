---
id: ir-7w9p
status: open
deps: [ir-ypx3]
links: []
created: 2026-05-21T07:00:19Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-umv7
tags: [agent-loop, area:roster, test]
---
# Cover roster highlight preference behavior

Add focused regression coverage for the shift-type highlight user preference.

## Design

Add controller/Hspec coverage near the existing roster layout preference tests. Cover default enabled rendering, disabling persistence, re-enabling persistence, and a second user remaining on the default enabled setting. Assert the rendered parent data attribute and persisted UserPreference value. Add a lightweight visual/e2e or screenshot check only if low-friction after implementation.

## Acceptance Criteria

Focused tests prove default enabled, disabled persistence, re-enabled persistence, and user isolation. Tests assert roster content render attributes for the preference. bash ./bin/in-env typecheck and focused RosterWeeks Hspec pass.

