---
id: ir-e3o5
status: closed
deps: []
links: []
created: 2026-04-30T06:31:42Z
type: task
priority: 3
assignee: beaudan
parent: ir-m8hc
tags: [area:docs, area:frontend, source:2026-04-30-audit]
---
# Refresh AGENTS navigation and frontend asset guidance

Root and subdirectory AGENTS guidance drifted from the current global nav and split JavaScript/runtime asset layout.

## Design

Update Web/View/AGENTS.md nav order to include xero between leave and admin; update root AGENTS.md JavaScript split list to include app-dialog-overlays.js, app-toasts.js, app-time-picker.js, app-roster.js, and app-timesheets.js. Remove/annotate obsolete CDN concerns now that HTMX and Bootstrap Icons are vendored via assetPath.

## Acceptance Criteria

Agent docs match Web/View/Layout.hs script/nav reality; no active doc suggests CDN-loaded HTMX/Bootstrap Icons; helpers.js migration guidance remains accurate.
