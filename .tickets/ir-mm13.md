---
id: ir-mm13
status: open
deps: []
links: []
created: 2026-05-27T23:58:34Z
type: task
priority: 1
assignee: beaudan
parent: ir-gz9k
tags: [area:static, area:mobile]
---
# Extract reusable horizontal snap component

Move the roster-specific snap logic into a reusable static component with a clear markup contract.

## Design

Add a shared script such as static/app-horizontal-scroll.js or equivalent. Support modes like equal-groups and nearest-item via data attributes, plus active-drag data attrs for CSS. Register it in Layout and Makefile if a new asset is added.

## Acceptance Criteria

Component can snap roster day rows and day columns using declarative attributes; source no longer duplicates generic snap scheduling/pointer-release logic in feature scripts; style-audit/typecheck relevant to asset links passes if links change.

