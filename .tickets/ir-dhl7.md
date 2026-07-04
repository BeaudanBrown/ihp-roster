---
id: ir-dhl7
status: closed
deps: [ir-fh80]
links: []
created: 2026-07-04T02:44:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-888o
tags: [agent-loop, surfaces, docs, naming]
---
# Polish surface naming in tests and living docs

Rename remaining stale LiveSurface/old-interaction-era test and living-doc vocabulary that now describes current `FrontendSurface`/`Surface` architecture.

## Design

Focus on non-archive files and test module names first. Candidate cleanups include `LiveSurfaceDependencySpec`, `LiveSurfaceGuardSpec`, `Test.Support.LiveSurfaceContract`, and active docs/workstreams that still describe old marker or LiveSurface architecture as current. Archive docs may remain historical unless they confuse active guardrails.

## Acceptance Criteria

- Non-archive tests/docs use current `FrontendSurface`, `Surface`, and generated interaction terminology.
- Stale terms remain only in archives or explicitly historical notes.
- Module/file names and cabal/test references are updated.
- Verification passes.
