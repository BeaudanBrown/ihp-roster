---
id: ir-pu6u
status: closed
deps: [ir-96d8, ir-hm3w]
links: []
created: 2026-04-30T23:32:41Z
type: task
priority: 2
assignee: beaudan
parent: ir-sryt
tags: [area:performance, area:profiling, area:docs]
---
# Document production profiling policy and operator workflow

Define how profiling code may be included and enabled outside local profiling servers without surprising overhead or exposing internal implementation detail.

## Design

Document default-off behavior, allowed environments, sampling/detail modes, expected overhead, header exposure policy, artifact retention, and how to run isolated profile-app/profile-load/profile-load-suite checks. Include guidance for adding spans and scenarios to new endpoints.

## Acceptance Criteria

specs/12-performance-profiling.md and AGENTS guidance explain safe production defaults, sampling/detail controls, span/scenario conventions, and operator commands; future endpoint work has a clear profiling checklist.


## Notes

**2026-04-30T23:59:05Z**

Updated specs/12-performance-profiling.md and AGENTS.md with default-off production policy, middleware header behavior, shared scenario catalog, write scenario, and before/after comparison workflow.
