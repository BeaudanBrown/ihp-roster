---
id: ir-a7dt
status: closed
deps: []
links: [ir-y2wh, ir-5mdm]
created: 2026-04-30T06:35:08Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-18tm
tags: [area:style, area:view, area:maintenance]
---
# Normalize shared app surface CSS and feature stylesheet ownership

Move shared toolbar/menu/list primitives out of roster feature CSS, remove leave-list duplication, and fix the extra closing brace in the leave stylesheet without broad visual redesign.

## Design

Promote app-surface-toolbar, app-week-nav, action-menu, and any genuinely shared list primitives to static/css/components.css or another shared CSS module. Keep roster-only grid/staff/sidebar rules in roster.css and leave-only row/list rules in leave.css. Verify timesheet and roster headers still share the intended controls.

## Acceptance Criteria

Roster CSS no longer owns shared app toolbar styles or leave-only rules; leave CSS has valid brace structure; roster, timesheet, and leave pages retain their current layout at desktop and mobile breakpoints; focused screenshots or Playwright checks cover touched views.
