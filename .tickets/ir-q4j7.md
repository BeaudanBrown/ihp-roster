---
id: ir-q4j7
status: closed
deps: [ir-sffk]
links: []
created: 2026-05-22T06:52:44Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-h2xi
tags: [area:live-fragments]
---
# Harden typed live fragment serving pathway

Add a canonical live-fragment endpoint helper and contract tests so endpoints authorize and serve through the typed surface definition.

## Acceptance Criteria

Representative fragment endpoints use the golden helper and tests cover authorization/target contract behavior.


## Notes

**2026-05-22T07:19:48Z**

Implemented: added AuthorizedLiveFragment and serveTypedLiveFragment, then migrated all live-fragment controller endpoints to name their typed fragment through that helper. Added a guard-test ban on feature/controller use of ensureTypedLiveSurfaceAuthorized so future endpoints stay on the golden pathway. Verification: bash ./bin/in-env typecheck; focused controller/live-surface Hspec (255 examples).
