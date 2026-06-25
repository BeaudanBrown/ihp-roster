---
id: ir-tp1i
status: closed
deps: [ir-k3q0]
links: []
created: 2026-06-25T11:57:29Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-vpmd
tags: [agent-loop, frontend, contracts, typescript, validation, live-updates]
---
# Generate runtime validators for frontend wire JSON

Add generated or schema-driven TypeScript validators/type guards for JSON received by the browser from Haskell wire boundaries.

## Design

Build on the Haskell schema/generator so incoming untrusted JSON can be checked before generic runtimes branch on it. Start with live-update websocket messages and live surface config JSON. Prefer generated type guards such as isLiveUpdateMessage/isLiveSurfaceConfig, or schema-derived validators if aeson-typescript alone only emits static types. Replace ad hoc frontend validation where the generated guard can own the boundary.

## Acceptance Criteria

Browser-received live-update JSON is validated by generated/schema-driven guards before use; invalid payload tests cover malformed kind/type, missing required fields, and wrong field primitive types; existing live-update validation tests are updated rather than duplicated; frontend-test and frontend-check pass.


## Notes

**2026-06-25T13:03:02Z**

Added Haskell-generated/schema-owned TypeScript runtime guards for live-update wire JSON: isLiveUpdateScope, isLiveFragmentKey, isLiveFragmentProtection, isLiveUpdateWireFragment, isLiveSurfaceConfig, isLiveUpdateCommand, and isLiveUpdateMessage now emit from Application.Helper.Frontend.LiveUpdateSchema into generated contracts.ts. Replaced ad hoc surface config validation with generated isLiveSurfaceConfig and wired websocket onmessage parsing through generated isLiveUpdateMessage before branching. Updated frontend validation tests to cover malformed discriminants, missing required fields, and wrong primitive types for surface configs, wire fragments, and websocket messages. Verified frontend-check, frontend-contracts-check, typecheck, and focused FrontendContracts/LiveUpdate Hspec.
