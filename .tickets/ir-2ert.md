---
id: ir-2ert
status: closed
deps: []
links: []
created: 2026-05-29T03:16:06Z
type: task
priority: 1
assignee: beaudan
parent: ir-6q3e
tags: [agent-loop, research, confirmation]
---
# Confirm unified fragment helper API against current code

Research the current post-timesheets code, inspect existing OOB helpers, and ask/confirm any API-shape questions before implementing the shared helper.

## Design

Review Application.Helper.LiveSurface, Application.Helper.View.Oob, Web.Timesheets.Responses, roster/leave/admin/Xero response paths, and the latest ticket state. Confirm whether the helper should render immediate OOB HTML only, whether actor-refresh headers remain supported for roster during transition, and where the helper module should live.

## Acceptance Criteria

A note is added to this ticket summarizing confirmed decisions, changed assumptions since the planning scan, and the exact helper API to implement; no production behavior changes are made in this ticket.


## Notes

**2026-05-29T03:55:31Z**

Confirmed API after inspecting current post-timesheets code: keep immediate HTMX/OOB HTML as the actor-success response model for this phase; do not replace successful actor responses with browser-side refetch instructions. Fragment GET endpoints stay plain target-node responses via existing renderLiveSurfaceProjectionFragment/serveTypedLiveFragment paths. Add shared API in Application.Helper.LiveSurface because it already owns TypedLiveSurfaceDefinition, containment normalization, projection loading/rendering, profiling-adjacent response helpers, and actor-refresh headers. API shape to implement: a reusable FragmentRenderMode (FragmentPlain | FragmentOob OobSwapAttr) plus a typed actor response helper over ProjectionLiveSurfaceDefinition that accepts a typed definition/projection definition, surface key, requested fragments, and extra Html; normalizes requested fragments through typedLiveSurfaceFragmentRefs/normalizeSurfaceFragmentRefs, loads the snapshot once, renders normalized fragments in FragmentOob outerHTML mode, appends extras (toast/dialog-clear HTML), and respondHtmlProfiled. The render callback should be mode-aware so timesheets can replace its local Bool renderOob branch. Keep validation failures as direct form/dialog rerenders. Roster and Admin Xero still have transition-only HX-Trigger actor-refresh paths; leave those alone unless a scoped follow-up migrates them.
