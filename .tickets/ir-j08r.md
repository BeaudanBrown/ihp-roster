---
id: ir-j08r
status: closed
deps: [ir-zcue]
links: []
created: 2026-07-09T05:06:02Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-7wsy
tags: [agent-loop, frontend, typescript, interaction]
---
# Use compatible dropzone refs in generic pointer runtime

Update the generic TypeScript pointer runtime to hit-test, highlight, and submit only dropzones compatible with the active source ref.

## Design

Update frontend/ts/interaction/pointer-session.ts so active sessions retain source-ref identity and build dropzone selectors from generated compatibility metadata. Keep target-field selection generic. Add frontend tests for multiple source refs sharing a session but seeing different valid dropzones, and keep modifier/copy behavior covered.

## Acceptance Criteria

Incompatible dropzones do not highlight and are not submitted. Existing roster shift move/copy behavior still works. No roster-specific branching is added to the TypeScript runtime. frontend-test/frontend-check pass for interaction coverage.

