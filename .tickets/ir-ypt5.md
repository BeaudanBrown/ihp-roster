---
id: ir-ypt5
status: open
deps: [ir-aleo]
links: []
created: 2026-07-02T02:47:03Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces, roster]
---
# Migrate Roster to FrontendSurface spec

Migrate the complex roster surface after Timesheets, proving the new architecture on live fragments, lazy loading, interactions, drag/drop helper expansion, disposable layers, effects, conflict policies, and duplicate mounts.

## Design

- Model roster scope as reusable shared scope included by the Roster surface:

  ```haskell
  Scope RosterWeek '[ Field VenueId WireUUID, Field RosterGroupId WireUUID, Field WeekOffset WireInt ]
  ```

- Represent roster fragments in type-level specs, including parameterized fragment shapes without sample IDs:
  - `RosterContent`
  - `RosterGridToolbar`
  - `RosterGridFrame`
  - `RosterDayColumns`
  - `RosterDayRail`
  - `RosterWageRail`
  - `RosterSlotsGrid`
  - `RosterStaffPanel`
  - `RosterDaySection '[ Field RosterDayId WireUUID ]`
  - `RosterRow '[ Field RosterDayId WireUUID, Field RowIndex WireInt ]`
- Represent containment with typed fragment relationships instead of raw target-id paths, e.g. content contains grid frame, grid frame contains day sections/rows, day section contains rows. Runtime maps concrete params to concrete target ids.
- Declare lazy staff panel as a fragment option with typed lazy policy. Preserve useful semantics (lazy trigger, placeholder kind, transition, accessible label) but old internal protocol shape may change.
- Use drag/drop helper sugar after lab proves helper expansion. Helper must normalize into primitives: session, disposable layer, effects, intent/action fields, and conflict policies.
- Solve fragment-specific conflict policies before closing Roster. V1 policies should support `AnyFragment`, fragment kind selectors, and fragment subtree selectors; concrete param predicates may wait unless Roster proves they are necessary.
- Role-dependent visibility, authorization, direct DB/read-model fetching, version/freshness, and rendering live in `SurfaceImpl`.
- Do not use `Application.Helper.SurfaceProjection`; local read-model helpers are allowed as ordinary feature code.
- Duplicate mounts must be safe. Mount key is required; all generated ids/forms/layers/fragments are mount-local and TypeScript resolves from closest surface mount. Stable semantic classes/data/test attrs should replace CSS or tests that depend on exact global ids.

## Acceptance Criteria

- Roster generated contracts and runtime mount come from the new `FrontendSurface` architecture.
- Roster direct `SurfaceImpl` handlers cover fragments, URLs, targets, renders, authorization, version, live-resource dependencies, HTMX actions, layout/move intents, drag session, drag-preview layer, clone-shadow/dropzone-highlight effects, lazy staff panel, and conflict policies.
- Successful Roster actor mutations emit touched resources/surface invalidations; actor HTTP responses carry extras such as toasts/dialog cleanup or validation-local errors. Fragment GET routes use new surface helpers and direct rendering.
- No Roster path uses old `TypedLiveSurfaceDefinition`, `Web.LiveSurfaceRegistry` registration, `FrontendCodec` surface DTO/schema authoring, or `Application.Helper.SurfaceProjection`.
- Tests cover typed containment normalization, parameterized fragments without sample IDs, lazy staff panel, live invalidation, drag/drop intent, fragment-specific conflict policy, and duplicate mounts.
