---
id: ir-k3q0
status: closed
deps: [ir-xkxz]
links: []
created: 2026-06-25T11:57:29Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-vpmd
tags: [agent-loop, frontend, contracts, haskell, typescript, live-updates]
---
# Generate live-update wire protocol from Haskell types

Move live-update websocket and fragment wire types onto generated Haskell JSON and TypeScript declarations.

## Design

Use the generator foundation to derive or explicitly share ToJSON/FromJSON and TypeScript declarations for LiveUpdateScope, LiveFragmentKey, LiveFragmentProtection, LiveUpdateWireFragment, LiveUpdateCommand, LiveUpdateMessage, and LiveSurfaceConfig where applicable. Update TypeScript protocol code and tests for any accepted encoding changes. Preserve semantic behavior: subscribe/unsubscribe, subscribed ack, invalidation, resync, focused protection, and source-client handling.

## Acceptance Criteria

Generated contracts.ts contains live-update protocol types emitted from Haskell types rather than handwritten declarations; Haskell JSON instances and TS declarations share one schema/options source; frontend live-update tests pass; focused LiveUpdate/LiveSurface Hspec passes; websocket/runtime behavior remains compatible within a single deployed version.


## Notes

**2026-06-25T12:55:54Z**

Migrated live-update protocol contracts to Haskell-owned schema types in Application.Helper.Frontend.LiveUpdateSchema. Generated contracts.ts now emits LiveUpdateScope, LiveFragmentKey, LiveFragmentProtection, LiveUpdateWireFragment, LiveUpdateCommand, LiveUpdateMessage, and LiveSurfaceConfig through aeson-typescript; old handwritten live-update TypeScript was removed from LegacyManualContracts. Runtime Aeson instances now encode/decode through schema conversion helpers so JSON and TypeScript share the same schema/options. Updated frontend command builder/tests for explicit null lastSeenVersion and added Hspec coverage tying runtime JSON to generated schema wire values plus guard coverage ensuring no stale live-update manual block remains. Verified frontend-check, frontend-contracts-check, typecheck, and focused LiveUpdate/LiveSurface/FrontendContracts Hspec.
