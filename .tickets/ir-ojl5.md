---
id: ir-ojl5
status: open
deps: [ir-4uuy, ir-95e7]
links: []
created: 2026-06-16T13:45:33Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, frontend, typescript, htmx, interaction]
---
# Implement generic intent bus and HTMX form bridge

Add a TypeScript runtime that normalizes interaction intents and submits matching Haskell-rendered HTMX forms for committed intents.

## Design

Author the runtime under `frontend/ts/` and compile through the existing esbuild/Nix pipeline. Consume generated interaction contracts from `frontend/ts/generated/contracts.ts`; do not define canonical surface, layer, or intent strings by hand. The runtime should remain generic and feature-agnostic.

Implement an intent bus with cancelable events and phases such as start, preview, commit, cancel, and error. Commit is the default persistence boundary. Start/preview are local/disposable unless a later typed form explicitly opts in.

The HTMX bridge should, on a committed intent:

1. resolve the concrete surface mount;
2. find the matching generated intent form within that mount;
3. strictly validate that emitted string fields match the generated field schema and hidden inputs;
4. copy fields into inputs;
5. dispatch the generated custom trigger so HTMX submits the server-rendered form.

The bridge must not construct domain URLs, call `fetch` for persistence, infer HTMX targets/swaps, or mutate server-owned business DOM. Missing/unknown fields and malformed forms fail safely with debug-visible warnings. Use standard HTMX custom event triggers rather than an HTMX extension for this first runtime.

## Acceptance Criteria

- Runtime can emit and observe normalized intent events with start/preview/commit/cancel/error phases.
- Committed intents fill matching Haskell-rendered forms and trigger HTMX submission.
- Unknown/missing fields and missing forms fail safely with warnings and no partial mutation.
- Runtime consumes generated contracts for intent/surface/layer field names where available.
- Runtime does not construct URLs or mutate business DOM.
- Frontend unit/DOM tests cover event dispatch, cancellation, strict field validation, form filling, and trigger dispatch.
- `bash ./bin/in-env frontend-check` passes.

