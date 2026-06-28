---
id: ir-vliw
status: in_progress
deps: [ir-hw6a]
links: []
created: 2026-06-28T12:23:42Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-r3wv
tags: [agent-loop, live-surfaces, cleanup]
---
# Tighten live surface contract guardrails and cleanup

Move kind helpers nearer wire codecs where useful and add tests/docs for stale bypasses.

## Acceptance Criteria

Guard tests cover contract watcher scripts and registry/generator assumptions; stale spike/dead paths are audited; checks pass.


## Notes

**2026-06-28T12:39:32Z**

Moved live update scope/fragment kind helpers into Application.Helper.LiveUpdate.Internal/Runtime, added registry and frontend-contract watcher guard tests, and updated README/frontend docs. Haskell tests remain blocked by pre-existing missing OpenTelemetry modules; frontend unit/ts/drift, script syntax, format, and doc drift checks pass.

**2026-06-28T12:45:12Z**

After forcing direnv to reload the updated flake, frontend-check, focused hspec LiveSurface match, and typecheck pass.
