---
id: ir-ptnv
status: closed
deps: [ir-mlle]
links: []
created: 2026-06-16T13:45:58Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, frontend, live-updates, htmx, interaction]
---
# Coordinate disposable interaction sessions with live fragments

Make passive live fragment swaps, actor HTMX responses, and active disposable sessions safe when they share a typed surface.

## Design

Implement the policy documented in the typed interaction contract. Interactive surfaces should prefer a stable mount with server-owned live fragments under the server layer and disposable UI in sibling disposable layers. Live updates may apply behind active disposable UI when the fragment does not conflict with the active session. Conflicting updates should apply, defer, or cancel according to Haskell-owned/generated policy.

The runtime should distinguish:

- actor HTMX responses for the current committed intent: authoritative, not deferred, clear disposable UI and active session state;
- passive live invalidations/refetches from another tab/user/background job: may apply immediately if non-conflicting, or defer/cancel if they touch active anchors, active targets, intent forms, disposable layer mounts, or the whole surface shell.

Deferred passive updates must not block indefinitely. Timeout should cancel stale sessions and apply/refetch server state. HTMX lifecycle events such as `htmx:beforeCleanupElement`, `htmx:afterSwap`, and `htmx:responseError` should clear stale sessions/disposable DOM. The implementation should avoid feature-specific live-update adapters.

## Acceptance Criteria

- Live-update runtime and interaction runtime share an explicit generic boundary for active surface/session state.
- Non-conflicting live fragment swaps can apply behind active disposable UI.
- Conflicting passive swaps defer or cancel according to generated policy.
- Actor HTMX responses clear disposable UI and do not get deferred by their own active session.
- Stale sessions are cleaned up on cancel, timeout, response error, before-cleanup, after-swap, and live swap conflict.
- Tests or targeted E2E cover at least one deferred/cancelled conflict and one non-conflicting behind-the-surface update.
- `bash ./bin/in-env frontend-check` and relevant live-update focused checks pass.

