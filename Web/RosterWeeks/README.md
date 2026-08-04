# Roster Weeks

## Ownership

`Web/RosterWeeks/` owns roster-week read models, domain workflows, typed Surface
metadata, invalidation planning, and response construction. The root
`Web/Controller/RosterWeeks.hs` retains authorization, request adaptation,
mutation invocation, and response selection; HSX lives in
`Web/View/RosterWeeks/`.

## Start Here

- `DirectReadModel.hs` and `RenderData.hs` — authoritative page/fragment data.
- `FrontendSurface.hs` and `SurfaceInvalidation.hs` — typed fragments,
  resources, interactions, and live fanout.
- `Mutations.hs` and `Service.hs` — roster writes and shared domain policy.
- `ShiftWorkflow.hs` and `DropWorkflow.hs` — dialog and drag/drop request
  resolution before mutation.
- `TemplateDesigner.hs` and `TemplateApplication.hs` — immutable template
  authoring and locked application.
- `Responses.hs`, `Paths.hs`, and `Dom.hs` — response shape, canonical URLs, and
  stable DOM identity.
- `Capabilities.hs`, `Filters.hs`, `WageFilter.hs`, and `Overview.hs` —
  authorization/presentation projections.
- `Application/RosterNotification/` — immutable notification snapshots and
  durable per-recipient delivery.

Follow imports from these seams rather than maintaining a module or feature
inventory here.

## Boundaries

- The URL's `weekOffset` is week-navigation authority.
- Server-rendered HTML and registered Surface contracts are browser authority.
- Views consume generated interaction roles and payloads; generic browser
  behavior belongs in the shared interaction runtime.
- Roster writes validate venue/group scope and current Staff/Open/pay state at
  the server boundary, regardless of rendered controls.
- The shared SidePanel owns only visibility and responsive mechanics. Roster
  owns Staff/Templates/Settings content, permissions, and linked highlighting.
- Emailing a live roster is an explicit editor action. One immutable run
  snapshots its audience and roster; each recipient sees only their own assigned
  shifts and the snapshot's Open shifts. Durable jobs continue if the roster
  later changes or returns to draft.

## Related Docs

- `SPEC.md` — durable scheduling, publication, template, notification, and
  Timesheet contracts.
- `AGENTS.md` — local editing rules and hazards.
- `Application/RosterNotification/README.md` — notification persistence and
  worker contract.
- `Application/Helper/Interaction.SPEC.md` and
  `Application/Helper/LiveUpdate.SPEC.md` — shared frontend/runtime contracts.
- `docs/workstreams/roster-operations-and-support-ux.md` — unresolved shared
  SidePanel closeout.
