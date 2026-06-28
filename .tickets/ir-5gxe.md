---
id: ir-5gxe
status: closed
deps: [ir-a8o9]
links: []
created: 2026-06-28T12:17:09Z
type: task
priority: 2
assignee: beaudan
parent: ir-osr3
tags: [agent-loop, frontend, htmx, lazy-loading]
---
# Add lazy fragment client error and retry handling

Add minimal client-side behavior, if needed, to make failed lazy fragment loads visible and retryable without duplicating code per surface.

## Design

Prefer declarative HTMX. Add a tiny TypeScript module only if standard HTMX events are needed for aria-busy, error classes, or retry buttons. Reuse frontend/ts conventions and generated static app split. Ensure production behavior does not depend on diagnostic trace headers.

## Acceptance Criteria

Failed lazy fragment requests show a reusable error/retry state; successful loads clear busy/error states; node/type checks pass; no large client framework or duplicated per-surface JS is introduced.


## Notes

**2026-06-28T13:08:24Z**

Added generic HTMX lazy-surface error handling in app-live-updates: failed response/send/timeout events render a shared app-lazy-surface-error state with retry HTMX markup; successful retry goes back through the authoritative fragment URL. Verification: frontend-build passed, frontend-test passed (42 tests), style-audit passed; frontend-check/typecheck are blocked by missing OpenTelemetry.* Haskell packages before frontend drift/typecheck completes.
