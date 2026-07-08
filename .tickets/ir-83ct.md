---
id: ir-83ct
status: closed
deps: [ir-e0g8]
links: []
created: 2026-07-08T04:59:57Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-5146
tags: [frontend-contracts, app-shell]
---
# Add AppShellAction primitive

Add AppShellContract/AppShellAction as the generated request primitive for app shell, chrome, dialog/toast/global, and non-feature-surface request initiators.

## Design

Add AppShellContract, AppShellAction DSL/IR/reflection/generation, generated TypeScript manifests, and Haskell runtime helpers for marker lookup, links, forms, and HTMX attr pairs. AppShell actions reference existing AppContract DOM ids for dialog/toast targets rather than redeclaring them.

## Acceptance Criteria

Generated TypeScript exposes AppShell action manifests; Haskell helpers render generated attrs; tests cover action declaration, generation, marker lookup, and rendering.


## Notes

**2026-07-08T05:13:49Z**

Implemented AppShellContract/AppShellAction primitive with DSL, IR, reflection, TypeScript manifest generation, registry registration, and Haskell runtime helpers for lookup/rendering/attr pairs. Added initial PartialNavigate AppShell action targeting AppContract AppContentMount. Verified with: bash ./bin/in-env typecheck; bash ./bin/in-env hspec-test --match "AppShell action"; bash ./bin/in-env frontend-check.
