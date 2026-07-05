---
id: ir-kzr1
status: closed
deps: [ir-5kxy, ir-53sm]
links: []
created: 2026-07-04T07:18:23Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-pkmv
tags: [agent-loop, frontend-contracts, live-update]
---
# Generate live transport contracts from DSL-owned surface unions

Replace live-update DTO envelopes with FrontendContract-generated records/tagged unions and derived surface scope/fragment payload unions.

## Design

Model live transport under a LiveTransport Global root using Record and TaggedUnion declarations. Avoid long-term WireUnknown/Aeson.Value contracts by deriving SurfaceScopePayload and SurfaceFragmentKey unions from registered Surface scopes/fragments. Use WireSurfaceScope/WireSurfaceFragmentKey or equivalent semantic wire refs in LiveUpdateMessage/Command shapes.

## Acceptance Criteria

Websocket subscribe/unsubscribe/invalidate/resync flows use generated FrontendContract TypeScript parsers and Haskell render/parse helpers. Existing live update behavior is preserved, but SurfaceScope/SurfaceFragmentKey no longer expose arbitrary unknown payloads in the frontend contract.


## Notes

**2026-07-04T09:33:56Z**

Decision: keep existing Haskell LiveUpdate DTOs temporarily as runtime JSON plumbing only. The frontend-visible live transport contract is now FrontendContract-owned with closed derived surface unions. Eventual DSL-backed Haskell parse/render is tracked by ir-13nx and blocks final legacy deletion via ir-y0mn.
