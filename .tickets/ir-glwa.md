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
# Make live invalidation helpers emit live facts

Make touched-resource invalidation emit typed live facts from the functions that expand, plan, and broadcast invalidations.

## Design

Change invalidateTouchedResources and invalidateTouchedResourcesWithoutContext, or add final replacements, so successful invalidation calls emitBepisFact with touched/expanded resource counts, planned scope/fragment counts where available, mechanism, and actor-client handling. Remove fromLiveMutationResult as final API.

## Acceptance Criteria

Live facts come from actual invalidation helpers; no fromLiveMutationResult calls remain; live invalidation tests and focused controller tests pass.
