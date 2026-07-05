---
id: ir-5kxy
status: closed
deps: [ir-97dr]
links: []
created: 2026-07-04T07:18:23Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-pkmv
tags: [agent-loop, frontend-contracts, surface]
---
# Port FrontendSurface roots into FrontendContract Surface

Move existing FrontendSurface contracts onto the new FrontendContract Surface root while preserving mounted surface behavior.

## Design

Re-home or re-export current Surface primitives through FrontendContract. Surface keeps Scope, Fragment, Action, Intent, MountState, Resource/DependsOn, SourceRef, DropzoneRef, ActivationRef, Session, ConflictPolicy, auth, and live invalidation semantics. Existing SurfaceImpl completeness checks and runtime metadata should read the new IR or an adapter that is removed by the epic closeout.

## Acceptance Criteria

Registered production surfaces are present under RegisteredFrontendContracts as Surface roots. Current surface TypeScript, live invalidation, SurfaceImpl handler completeness, and focused surface tests pass against the new pipeline.

