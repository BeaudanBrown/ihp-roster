---
id: ir-r3wv
status: closed
deps: []
links: []
created: 2026-06-28T12:23:42Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, live-surfaces, frontend]
---
# Simplify live surface contract pipeline

Improve contract hot reload, remove duplicated registry stages, and strengthen guardrails around the Haskell-owned live surface/fragment/interaction pipeline.

## Design

Implement in small commits: contract watcher integrated with dev lifecycle; single-source registry catalog; move wire kind helpers near wire codecs; guard tests for stale/manual bypasses and dead code.

## Acceptance Criteria

frontend-contracts-watch is integrated with dev-start/status/stop; live surface registry duplication is reduced; stale/manual protocol paths are guarded or removed; frontend/type/Hspec checks pass.


## Notes

**2026-06-28T12:45:33Z**

Implemented contract hot reload, registry catalog unification, kind-helper relocation, guard tests, and docs updates. Verified with frontend-check, focused hspec LiveSurface match, typecheck, doc drift, script syntax, and frontend TS/drift checks.
