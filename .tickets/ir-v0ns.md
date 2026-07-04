---
id: ir-v0ns
status: closed
deps: []
links: []
created: 2026-07-04T00:37:02Z
type: chore
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, surfaces, cleanup]
---
# Retire SurfaceResourceValue alias in favor of SurfaceResourceValue

Use one canonical surface resource value type instead of the old SurfaceResourceValue alias/vocabulary.

## Design

Rename SurfaceResourceValue to SurfaceResourceValue, remove the SurfaceResourceValue alias, update invalidation/mutation APIs and docs/guardrails to use surface-resource terminology.

## Acceptance Criteria

No SurfaceResourceValue type alias/public module vocabulary remains for the generated resource value path; verification passes.


## Notes

**2026-07-04T00:46:02Z**

Replaced the old LiveResource/FrontendSurfaceResourceValue naming split with one canonical SurfaceResourceValue type. Renamed Application.Helper.LiveResource to Application.Helper.SurfaceResource and Web.LiveResourceInvalidation to Web.SurfaceInvalidation, updated APIs/tests/docs/guardrails, and verified typecheck, frontend-check, full hspec-test.
