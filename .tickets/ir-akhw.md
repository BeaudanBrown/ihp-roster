---
id: ir-akhw
status: open
deps: [ir-a6do]
links: []
created: 2026-06-26T04:23:33Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-o5qk
tags: [agent-loop, frontend, live-updates, contracts]
---
# Migrate live-update contracts to codec-first generation

Replace live-update aeson-typescript/raw-validator mix with codec/schema-first generated wire contracts and validators.

## Design

Migrate LiveUpdateScope, LiveFragmentKey, LiveFragmentProtection, LiveUpdateWireFragment, LiveUpdateCommand, LiveUpdateMessage, and LiveSurfaceConfig. Change wire shapes freely toward regular tagged unions. Remove handwritten LiveFragmentProtection TypeScript and liveUpdateValidatorDeclaration. Keep runtime bridge tests proving Haskell JSON and frontend contracts agree.

## Acceptance Criteria

Live-update TS types and isLiveUpdate* validators are generated from the codec/schema source; no raw TS declarations remain in LiveUpdateSchema; frontend live-update runtime consumes the regenerated contracts; malformed-boundary tests pass; Haskell round-trip and focused live-update specs pass.

