---
id: ir-83ct
status: open
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

