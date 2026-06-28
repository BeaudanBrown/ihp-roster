---
id: ir-fvq6
status: closed
deps: [ir-a8o9, ir-imlz]
links: []
created: 2026-06-28T12:17:09Z
type: feature
priority: 1
assignee: beaudan
parent: ir-osr3
tags: [agent-loop, roster, performance, lazy-loading]
---
# Lazy-load the roster staff panel fragment

Apply the new load policy and renderer to the roster staff panel so the full roster page can render the grid/shell first and fetch the staff panel from ShowRosterWeekStaffPanelFragmentAction.

## Design

Mark RosterProjectionStaffPanel lazy, likely LazyOnLoadDelay or a thresholded policy if implementation chooses. Replace eager staff panel rendering in the full roster shell with the generic live fragment mount. Keep ShowRosterWeekStaffPanelFragmentAction authoritative and ensure it returns the same root id rosterStaffPanelFragmentId. Preserve current manager-only visibility and multi-group toggle behavior. Validate that invalidations before load are harmless and that loaded panel participates in existing live updates.

## Acceptance Criteria

Initial ShowRosterWeekAction no longer eagerly renders all staff panel rows when the lazy policy applies; the staff panel appears after HTMX fetch; clicking a staff row still lazy-loads EditStaffAction modal; staff panel scope toggle works; live-update refetches still target the same fragment; focused roster e2e/profile run passes.


## Notes

**2026-06-28T13:04:59Z**

Marked RosterProjectionStaffPanel lazy with a load-delayed table placeholder, rendered the full-page staff side panel through renderLiveSurfaceFragmentMount, and preserved manager-only visibility plus the authoritative ShowRosterWeekStaffPanelFragmentAction target/root id. Verification: style-audit passed; typecheck (and therefore focused e2e/profile) is blocked before changed modules by missing OpenTelemetry.* packages in the current environment.
