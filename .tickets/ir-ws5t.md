---
id: ir-ws5t
status: closed
deps: [ir-yabk]
links: []
created: 2026-07-01T01:40:01Z
type: feature
priority: 2
assignee: beaudan
parent: ir-6kzl
tags: [agent-loop, frontend, typescript, guardrail]
---
# Enforce exhaustive TypeScript handling for generated closed unions

Make generated union growth fail incomplete surface/intent/fragment-specific TypeScript logic while preserving generic runtime paths where no switch is needed.

## Design

Add shared assertNever(value: never): never and use it in surface/intent/fragment-specific switches. Ensure frontend-check/tsconfig guard against broad defaults that swallow generated union variants. Prefer generic data-driven runtime code where possible; only require exhaustive switches where TS actually branches by a closed generated union.

## Acceptance Criteria

At least one generated union has an exhaustive switch test/example. Adding a dummy union variant in a local probe would fail TypeScript until handled. No broad default swallowing generated union variants without assertNever remains in app-owned TS. frontend-check covers the guard.


## Notes

**2026-07-01T02:25:54Z**

Added shared assertNever and wired the generated LiveFragmentProtection switch to default through assertNever, so adding a generated protection variant fails TypeScript until handled. Added frontend no-broad-switch-defaults check to reject switch defaults that do not call assertNever. Verification: frontend-contracts-check; frontend-check.
