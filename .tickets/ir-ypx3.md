---
id: ir-ypx3
status: closed
deps: [ir-w395]
links: []
created: 2026-05-21T07:00:19Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-umv7
tags: [agent-loop, area:roster, area:ui, area:preferences]
---
# Wire roster menu toggle and highlight rendering

Expose the persisted preference in the roster ... menu and make roster rendering obey it.

## Design

Add a route/action/path helper parallel to UpdateRosterLayoutPreferenceAction and rosterLayoutPreferenceUrl. Add a form-switch section to Web.View.RosterWeeks.Header, likely labelled 'Show shift type colours', with onchange requestSubmit and HTMX targeting #roster-content. Thread the preference into ShowView/RosterGridRenderModel and relevant response/render paths. Render data-roster-shift-type-highlights=true|false on .roster-grid-frame. Keep data-roster-shift-colour on cells/cards regardless of preference so row/day live fragments do not need preference-specific markup. Update roster CSS selectors so assigned shift-type outlines render only when the parent attribute is true; empty/unset cells remain quiet and required warning indicators remain visible.

## Acceptance Criteria

The menu toggle reflects the current persisted preference. Toggling swaps/updates roster content without pushing a new URL. data-roster-shift-type-highlights changes immediately. Assigned shift-type outlines hide/show in both day-row and day-column layouts. Row/day fragment markup remains compatible with live swaps. Required warning indicators and conflict styling remain legible.


## Notes

**2026-05-21T07:13:20Z**

HANDOFF: Wired roster shift-type highlight preference UI/rendering: added UpdateRosterShiftTypeHighlightsPreferenceAction/path, menu form-switch, ShowView/RosterGridRenderModel field, data-roster-shift-type-highlights on roster-grid-frame, and CSS gates for decorative outlines while retaining row/day shift colour metadata; verification: bash ./bin/in-env typecheck and bash ./bin/in-env hspec-test --match "RosterWeeks" passed; remaining risk/next touchpoint: ir-7w9p can add dedicated behavior assertions/e2e coverage.
