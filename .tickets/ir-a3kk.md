---
id: ir-a3kk
status: open
deps: []
links: []
created: 2026-07-03T11:15:32Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-3b6m
tags: [agent-loop, surfaces, live-updates, frontend]
---
# Add surface-native live subscription protocol

Extend the live update wire protocol so subscribe/unsubscribe commands carry generated FrontendSurface subscription data, including scope, scopeKey, and mounted live fragments.

## Design

Reuse generated FrontendSurface mount config data. The browser should send the exact live fragments it mounted instead of requiring the server to reconstruct candidates from a closed scope ADT. Keep a temporary compatibility parser only if needed during this ticket, with cleanup explicitly deferred to the final cleanup ticket.

## Acceptance Criteria

TypeScript builds subscribe commands from generated FrontendSurface subscription config including mounted fragments. Haskell DTOs parse/encode the new command shape. Frontend protocol tests cover the new payload. Focused typecheck/frontend checks pass.

