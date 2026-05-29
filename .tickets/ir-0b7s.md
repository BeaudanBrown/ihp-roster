---
id: ir-0b7s
status: open
deps: [ir-2ert]
links: []
created: 2026-05-29T03:16:06Z
type: task
priority: 1
assignee: beaudan
parent: ir-6q3e
tags: [agent-loop, helper, htmx]
---
# Introduce shared fragment render mode and OOB response helper

Add the generic typed-fragment response helper and supporting render-mode types.

## Design

Create a reusable FragmentRenderMode/Oob mode and helper that loads a snapshot once, normalizes typed fragment refs/containment, renders fragments as hx-swap-oob outerHTML, appends extras such as toasts/dialog clears, and responds with profiled HTML.

## Acceptance Criteria

Helper compiles; focused unit/Hspec coverage verifies parent/child containment normalization and extras; no feature behavior changes except tests/examples if needed.

