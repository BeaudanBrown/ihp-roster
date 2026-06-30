---
id: ir-glwa
status: open
deps: [ir-mwma]
links: []
created: 2026-06-30T11:03:28Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-z0j1
tags: [architecture, bepis-actions, agent-loop]
---
# Make live invalidation helpers produce realtime evidence

Make touched-resource invalidation return typed live/realtime evidence from the function that expands/plans/broadcasts invalidations.

## Design

Change invalidateTouchedResources and invalidateTouchedResourcesWithoutContext, or add final replacements, so successful invalidation returns evidence including touched resources, expanded resources, selected scopes/fragments where available, and actor client handling. Remove fromLiveMutationResult as final API.

## Acceptance Criteria

Realtime evidence comes from actual invalidation helpers; no fromLiveMutationResult calls remain; live invalidation tests and focused controller tests pass.

