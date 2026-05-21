---
id: ir-f16h
status: open
deps: [ir-uybz]
links: []
created: 2026-05-21T07:43:26Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-xyzw
tags: [agent-loop, area:roster, area:live-fragments, area:architecture]
---
# Integrate no-projection roster trial path

Route roster page and fragment reads through the SQL/direct trial path while preserving projection rollback.

## Design

Switch the roster read seam to use the SQL/direct path on the branch. Keep existing HSX/render functions and RosterRenderData consumers stable where possible. Leave self-service panel and wage prediction in Haskell unless earlier measurements show they dominate. Do not delete projection code.

## Acceptance Criteria

Full roster page, content fragment, day section fragment, row fragment, and staff panel flows render correctly without calling loadLiveSurfaceProjection on the trial path. The projection path remains available by reverting the seam. Focused roster and live-fragment tests pass.

