---
id: ir-5mdm
status: open
deps: [ir-jkt2]
links: []
created: 2026-04-30T05:43:27Z
type: task
priority: 2
assignee: beaudan
parent: ir-y2wh
tags: [area:style, area:view, area:maintenance]
---
# Convert repeated local surfaces to shared app surface helpers

Replace audited repeated border rounded p-* local surfaces with shared app surface/panel helpers where the markup represents an ordinary themed surface.

## Design

Start with Web/View/Admin/Xero/Readiness.hs, Calendars.hs, StaffMappings.hs, Timesheets.hs, Admin Invites/ShiftTypes/RosterGroups, and Web/View/StaffProfileForm.hs. Prefer existing renderAppPanel, simpleAppPanel, appPanelWithActions, and appSurfaceClasses before adding new helpers. If a surface is too small for a panel, add a narrowly scoped renderAppSurface/renderAppSection helper in Application.Helper.View.Chrome only after verifying at least two callers. Preserve headings, form field order, HTMX attributes, validation behavior, and responsive layout.

## Acceptance Criteria

Audited repeated border rounded p-* surfaces are either migrated to app-panel/app-surface helpers or documented as intentionally Bootstrap-native; any new Chrome helper has an explicit export and at least two callers; bash ./bin/in-env typecheck passes; no unrelated visual cleanup or copy changes are included.

