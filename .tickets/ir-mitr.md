---
id: ir-mitr
status: closed
deps: [ir-jkt2]
links: []
created: 2026-04-30T05:43:19Z
type: task
priority: 2
assignee: beaudan
parent: ir-y2wh
tags: [area:style, area:view, area:roster, area:timesheets]
---
# Rename shared roster action menu styling

Replace non-roster use of roster-week-more-menu with a generic shared action-menu class while preserving roster and timesheet dropdown behavior.

## Design

Introduce a generic class such as app-action-menu in static/css/components.css or the narrowest shared stylesheet. Keep roster-week-more-menu as a temporary alias only if needed for backwards compatibility during the slice, then remove it once call sites are migrated. Update Web/View/RosterWeeks/Header.hs and Web/View/Timesheets/Index.hs call sites. Keep menu dimensions, padding, dropdown behavior, and HTMX forms visually equivalent.

## Acceptance Criteria

Timesheets no longer references roster-week-more-menu; any remaining roster-week-more-menu selector/use is genuinely roster-specific or removed; shared dropdown action menu CSS lives under app-* naming; bash ./bin/in-env typecheck passes; a lightweight screenshot or existing e2e coverage is run if visual behavior changes.

