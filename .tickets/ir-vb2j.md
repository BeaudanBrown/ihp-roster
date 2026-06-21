---
id: ir-vb2j
status: open
deps: [ir-0ec8]
links: []
created: 2026-06-21T03:37:17Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-l5gk
tags: [agent-loop, frontend, typescript, roster, conversion]
---
# Convert roster runtime to TypeScript

Convert app-roster.js to TypeScript while preserving roster behavior.

## Design

Move app-roster.js source to frontend/ts/app-roster.ts and compile back to static/app-roster.js. Preserve roster week navigation, snapping, staff highlighting, mobile controls, and feature-local behavior. Extract testable roster calculations/state decisions into importable modules where practical and cover them with unit/DOM tests, while retaining focused Playwright coverage for browser layout, scrolling, highlighting, and mobile behavior. Coordinate with live-update conversion if shared assumptions appear.

## Acceptance Criteria

app-roster.ts compiles to the existing static asset. frontend-check passes with meaningful unit/DOM coverage for converted roster behavior. Roster week navigation, snapping, staff highlighting, mobile controls, and feature-local behavior remain unchanged. Focused roster/mobile e2e coverage passes.

