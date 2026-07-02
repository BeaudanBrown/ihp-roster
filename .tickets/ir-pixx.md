---
id: ir-pixx
status: closed
deps: []
links: []
created: 2026-07-02T11:10:38Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-ypt5
tags: [frontend, surfaces, roster, cleanup]
---
# Replace Roster legacy interaction adapter with native FrontendSurface renderer

Remove the temporary Roster FrontendSurface -> Application.Helper.Interaction compatibility adapter once native FrontendSurface interaction render helpers exist.

## Acceptance Criteria

Roster renders interaction mount shell, disposable layers, conflict policies, and intent forms through native FrontendSurface helpers; Web.RosterWeeks.LiveSurface no longer projects FrontendSurface IR into InteractionStaticSchema/InteractionCapability for Roster; temporary adapter comments are removed; behavior remains covered by Roster/Interaction/frontend tests.


## Notes

**2026-07-02T11:59:39Z**

Completed native Roster FrontendSurface interaction render path: roster shell now renders mount/layers/policies/forms from Web.RosterWeeks.FrontendSurface, Web.RosterWeeks.LiveSurface was removed, and roster no longer projects FrontendSurface IR through Application.Helper.Interaction. Verified with typecheck, frontend-check, focused Roster/Interaction/LiveSurface tests, and focused E2E.
