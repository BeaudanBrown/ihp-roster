---
id: ir-auvz
status: closed
deps: [ir-ypks, ir-56rx]
links: []
created: 2026-05-16T01:25:47Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-3pnb
tags: [area:live-fragments, area:profile, area:leave]
---
# Migrate profile and leave live surfaces to strict typed contracts

Replace profile content, profile leave, and manager leave-request live surfaces with TypedLiveSurfaceDefinition-based contracts.

## Design

Feature-local surface definitions own user/venue scope conversion, focused-field protection, default fragments, fragment refs, and authorization. Profile endpoints and leave-request endpoints use ensureTypedLiveSurfaceAuthorized. Broadcasts and actor responses use typed mutation helpers.

## Acceptance Criteria

Profile and leave live surfaces use mkTypedDefinedLiveSurface only. Websocket and HTTP fragment authorization share the typed rule. Contract tests cover config JSON, refs, targets, mounted metadata, unauthorized fragment access, and authorized rendering. Existing profile/leave controller tests and live multiview coverage pass.


## Notes

**2026-05-16T02:19:41Z**

Migrated profile content, profile leave, and manager leave surfaces to TypedLiveSurfaceDefinition contracts with typed fragment authorization and typed broadcasts.
