---
id: ir-s3a3
status: open
deps: [ir-bzuk]
links: []
created: 2026-07-03T06:55:44Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-aa95
tags: [agent-loop, auth, surfaces, live-updates]
---
# Generate subscription authorization dispatch

Generate websocket subscription authorization dispatch from Scope authorization policies.

## Design

Attach explicit Authorize/NoAuth policies to all current scopes. Generate dispatch from surface-native live scope payloads to existing server-side authorization helpers such as authorizeLiveScopeRequirement. Keep actual membership/platform-role decisions in existing auth code.

## Acceptance Criteria

Web.LiveSurfaceRegistry.authorizeRegisteredLiveSurfaceScope hard-coded cases are removed/replaced. Unknown surface, malformed scope payload, missing fields, wrong field types, and missing policy deny by default. VenueAccess/LiveUpdate Hspec assert generated dispatch behavior for current policies.


## Notes

**2026-07-03T07:16:17Z**

ir-qhzl introduced NoAuth metadata on current scopes only to satisfy mandatory auth validation before generated dispatch exists. Replace these with real per-scope policies before wiring generated subscription authorization; do not treat current NoAuth declarations as final business authorization.
