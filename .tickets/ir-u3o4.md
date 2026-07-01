---
id: ir-u3o4
status: open
deps: [ir-oxk6]
links: []
created: 2026-07-01T01:40:01Z
type: feature
priority: 2
assignee: beaudan
parent: ir-6kzl
tags: [agent-loop, frontend, contracts, live-update]
---
# Migrate live-update wire contracts to generic DTO codecs

Move live-update protocol and config contracts onto generic DTO codecs with generator-friendly wire JSON.

## Design

Create or use Application.Helper.Frontend.Dto.LiveUpdate for LiveUpdateScope, LiveFragmentKey, LiveFragmentProtection, LiveUpdateWireFragment, LiveSurfaceConfig, LiveUpdateCommand, and LiveUpdateMessage. Wire shapes may change to regular tagged unions. Haskell ToJSON/FromJSON, TS types, guards, parse helpers, and encode helpers all come from the same DTO codec. Update websocket/config TypeScript to parse unknown inbound JSON through generated parse helpers and build outbound commands through generated encode helpers.

## Acceptance Criteria

Haskell JSON for live-update wire boundaries comes from generated DTO codecs. TS websocket/config parsing uses generated parse helpers at unknown JSON boundaries. TS outbound subscribe/unsubscribe uses generated encodeLiveUpdateCommand. Existing hand-written live-update schema/encode/parse field lists are gone. Live-update frontend validation tests, focused Hspec, frontend-contracts-check, and frontend-check pass.

