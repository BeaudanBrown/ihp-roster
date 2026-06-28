---
id: ir-imlz
status: open
deps: [ir-grmo]
links: []
created: 2026-06-28T12:17:09Z
type: feature
priority: 2
assignee: beaudan
parent: ir-osr3
tags: [agent-loop, ui, lazy-loading]
---
# Add shared lazy surface placeholders and styles

Provide reusable loading skeletons, compact spinners, table placeholders, error/retry markup, and CSS for lazy live fragments.

## Design

Add a small placeholder renderer and CSS component, likely under Application.Helper.View and static/css/components. Placeholder variants should cover panel skeletons, table/list skeletons, compact spinner, and custom Html. Use accessible labels, aria-busy, and stable classes like app-lazy-surface, app-lazy-surface-skeleton, app-lazy-surface-row, app-lazy-surface-error, app-lazy-surface-retry. Mirror any new stylesheet in Layout and Makefile CSS_FILES per project conventions.

## Acceptance Criteria

All lazy placeholders use shared styles; no feature-specific loading animation is required for roster staff panel; CSS audit/Layout sync conventions are satisfied; placeholder markup is accessible and Bootstrap-compatible.

