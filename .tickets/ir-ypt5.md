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

Migrate the complex roster surface after Timesheets, proving live fragments, lazy loading, interactions, drag/drop helper expansion, disposable layers, effects, and conflict policies.

## Design

Represent roster fragments, roster_week scope, move/layout intents, drag session, drag-preview layer, clone-shadow/dropzone-highlight effects, lazy staff panel, refresh/conflict policies, and HTMX actions in the type-level spec.

## Acceptance Criteria

Roster generated contracts and runtime mount come from the new surface architecture, enabling removal of replaced old FrontendCodec/schema registry paths.

