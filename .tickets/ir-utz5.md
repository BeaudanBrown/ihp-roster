---
id: ir-utz5
status: closed
deps: []
links: []
created: 2026-07-03T02:45:01Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-rjfp
tags: [agent-loop, docs, surfaces]
---
# Clean stale surface docs before composition work

Update surface/live-update docs now that production surfaces have migrated and before documenting composition.

## Design

Revise FrontendSurface, LiveUpdate, LiveSurface cookbook, Web/View AGENTS, Web/Controller AGENTS, and frontend docs as needed. Introduce terminology: surface, fragment/region, contained child surface, runtime reconciliation. Remove guidance that new production work should use TypedLiveSurfaceDefinition.

## Acceptance Criteria

Docs describe FrontendSurface as the production authoring path; composition terminology is introduced; no new-production docs recommend TypedLiveSurfaceDefinition/data-live-update-surface authoring.

