---
id: ir-k3q0
status: open
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

