---
id: ir-7s9u
status: closed
deps: [ir-oxnj]
links: []
created: 2026-05-29T03:16:10Z
type: task
priority: 1
assignee: beaudan
parent: ir-kuyy
tags: [agent-loop, research, confirmation, high-risk, frontend-surface]
---
# Confirm roster semantic invalidation strategy and scroll ownership

Deeply research roster update paths before changing the highest-risk surface.

## Design

Inspect roster live surface, render data, responses, controller actor refresh helpers, grid/header targets, week/group navigation, assignment filters, staff panel, direct/projection backend behavior, interaction conflict policy, and horizontal frame ownership. Decide which semantic fragments each success path should invalidate, how row/day precision is preserved without actor business OOB, and whether week navigation should preserve or reset scroll.

## Acceptance Criteria

Ticket note records migration sequence, scroll owner boundaries, semantic actor-local invalidation replacement strategy, duplicate-mount implications, direct/projection concerns, and any intentionally deferred paths. No production behavior changes are made.

## Notes

**2026-07-07T05:00:35Z**

Roster migration strategy confirmed. Scope remains rosterWeekLiveScope/profile FrontendSurface scope equivalent: venue id + roster group id + weekOffset, and duplicate mounts must be resolved by the browser from RosterWeeks.FrontendSurface mounted fragments. Fragment GET endpoints already exist for content, toolbar, frame, day-columns, rails, slots-grid, staff-panel, day-section, and row; these must remain plain target-node HTML and become the only authoritative business render path. Actor success responses should stop using respondWithRosterFragments/respondWithRosterPatches business OOB and instead set HX-Reswap none plus actor-local semantic invalidation for the selected RosterProjectionFragment list, with extras only (toast, dialog close/confirmation, error toast). Preserve row/day precision by continuing to compute actor fragment candidates from touched resources and impacted row keys: row-level slot edits invalidate matching roster-row fragments plus assignment/staff-panel fragments when staff changed; day structural changes and preference changes invalidate grid structural fragments (toolbar/frame/day-columns/day rail/wage rail/slots grid) as currently selected; full content/navigation success paths invalidate roster-content or grid structural fragments as appropriate. Staff panel refresh should be semantic fragment invalidation, not OOB panel HTML, unless it is a plain ShowRosterWeekStaffPanelFragmentAction GET. Scroll ownership: horizontal grid scroll belongs to the roster grid frame/client runtime; week/group navigation may push URL and replace content/frame through semantic invalidation but should not add server-rendered business OOB that resets scroll outside existing frame ownership. Dialog validation failures and confirmation dialogs remain direct local responses. Roster self-service leave quick-tool form remains tied to the staff/self-service panel and should be folded into staff-panel semantic invalidation when the broader roster content/staff-panel migration lands. Migration sequence: first align helpers so projection fragments can be converted to mounted wire fragments without rendering; then migrate row/day actor patch helpers; then migrate content/staff-panel/navigation and preference success paths; finally run parity and remove obsolete roster actor business-OOB helpers.
