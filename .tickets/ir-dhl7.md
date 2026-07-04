---
id: ir-dhl7
status: open
deps: [ir-gaxt]
links: []
created: 2026-07-04T02:44:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-888o
tags: [agent-loop, surfaces, docs, naming]
---
# Polish surface naming in tests and living docs

Rename remaining stale LiveSurface-era test/doc vocabulary that now describes FrontendSurface/Surface architecture.

## Design

Focus on non-archive files and test module names first. Candidate cleanups include LiveSurfaceDependencySpec, LiveSurfaceGuardSpec, Test.Support.LiveSurfaceContract, and living docs/workstreams that still use LiveSurface for current architecture. Archive docs may keep historical wording unless they confuse active guardrails.

## Acceptance Criteria

Non-archive tests/docs use current FrontendSurface/Surface naming; stale terms remain only in archives or explicitly historical notes; module/file names and cabal/test references are updated; verification passes.

