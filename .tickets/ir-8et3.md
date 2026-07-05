---
id: ir-8et3
status: closed
deps: [ir-94fn]
links: []
created: 2026-07-04T12:31:43Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-pkmv
tags: [agent-loop, frontend-contracts, live-update, wire]
---
# Move live-update wire carriers under FrontendContract.Wire

Replace Application.Helper.Frontend.Dto.LiveUpdate with a FrontendContract-owned live-update wire module.

## Design

Create Application.Helper.FrontendContract.Wire.LiveUpdate containing the typed runtime carrier types and Aeson instances for SurfaceScope, SurfaceFragmentKey, LiveUpdateCommand, LiveUpdateMessage, invalidations, and active-scope payloads. Instances must delegate shape validation to FrontendContract.Wire.Json/registeredFrontendContractIR. Update all imports and delete Application.Helper.Frontend.Dto.LiveUpdate.

## Acceptance Criteria

No Application.Helper.Frontend.Dto imports remain. LiveUpdate runtime Hspec still passes. The live-update wire module documents that carrier types are implementation API over DSL-owned wire contracts, not contract authority.

