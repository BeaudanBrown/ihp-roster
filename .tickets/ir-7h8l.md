---
id: ir-7h8l
status: closed
deps: []
links: []
created: 2026-06-21T06:40:39Z
type: task
priority: 2
assignee: beaudan
parent: ir-bmc0
tags: [agent-loop, frontend, typescript, refactor]
---
# Type roster runtime

Remove ts-nocheck from app-roster.ts after helper extraction.

## Design

Add local DOM/event/data types to the remaining roster entrypoint while keeping behavior unchanged. Prefer explicit narrow DOM checks and existing helper modules; avoid broad feature rewrites in this slice.

## Acceptance Criteria

app-roster.ts no longer uses ts-nocheck; generated static JS is rebuilt; frontend-check and doc-drift-check pass; LSP diagnostics are clean.


## Notes

**2026-06-21T06:41:55Z**

Initial probe of removing ts-nocheck from app-roster.ts produced roughly 98 strict TypeScript errors concentrated in the remaining large DOM/event/export/staff-highlight sections. Reverted the probe to keep the tree green. Next safe step is to split the remaining roster runtime by concern (overview/fullscreen already extracted; next column-edit/export/staff-highlight modules), then remove ts-nocheck after the entrypoint is thin.

**2026-06-21T08:04:59Z**

Staged roster typing slice: extracted column edit DOM behavior to typed frontend/ts/roster/column-edit.ts and replaced the inline app-roster.ts IIFE with enableRosterColumnEditMode(). Rebuilt static/app-roster.js. Verified frontend-check, doc-drift-check, and clean LSP diagnostics.

**2026-06-21T08:06:21Z**

Staged roster typing slice: extracted compact staff panel sorting DOM wiring to typed frontend/ts/roster/staff-panel-sorting.ts. The module reuses compareRosterStaffData from staff-sort.ts and app-roster.ts now invokes enableRosterStaffPanelSorting(). Rebuilt static/app-roster.js. Verified frontend-check, doc-drift-check, and clean LSP diagnostics.

**2026-06-21T08:08:09Z**

Staged roster typing slice: extracted staff/shift hover, focus, keyboard, and pinned highlight behavior to typed frontend/ts/roster/staff-highlight.ts. app-roster.ts now invokes enableRosterStaffShiftHighlight(). Rebuilt static/app-roster.js. Verified frontend-check, doc-drift-check, and clean LSP diagnostics.

**2026-06-21T23:43:13Z**

Staged roster typing slice: extracted roster image export/SVG/canvas behavior to typed frontend/ts/roster/image-export.ts and replaced the inline app-roster.ts IIFE with enableRosterImageExport(). Rebuilt static/app-roster.js. Verified frontend-build, frontend-check, doc-drift-check; syntax diagnostics clean for new module.

**2026-06-21T23:44:21Z**

Final roster typing slice: extracted week overview and fullscreen DOM wiring to typed roster/week-overview.ts and roster/fullscreen-runtime.ts, leaving app-roster.ts as a thin typed entrypoint. Removed the final frontend/ts @ts-nocheck. Rebuilt static/app-roster.js. Verified frontend-build, frontend-check, doc-drift-check, rg @ts-nocheck found no matches, and LSP diagnostics clean for app-roster/week-overview/fullscreen-runtime.
