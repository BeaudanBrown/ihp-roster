---
id: ir-pixx
status: open
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

