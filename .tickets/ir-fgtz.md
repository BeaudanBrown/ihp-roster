---
id: ir-fgtz
status: closed
deps: [ir-ix0n]
links: []
created: 2026-05-15T02:27:18Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-nnfx
tags: [area:live-fragments, area:frontend, javascript]
---
# Shrink live-update JavaScript to declarative transport

Keep the browser runtime generic and small by moving feature decisions into server-produced surface and fragment metadata.

## Design

The client should discover mounted surface configs, maintain one websocket per tab, subscribe and unsubscribe scopes, decorate matching HTMX requests, refetch invalidated mounted fragments, apply reusable protection policies, and swap HTML. Remove legacy or feature-specific paths once server-side typed metadata covers them.

## Acceptance Criteria

No feature-specific adapters are needed for normal live behavior, legacy refresh aliases are removed or quarantined behind tests, focused-field behavior remains policy-driven, and focused live-update Playwright coverage still passes.

