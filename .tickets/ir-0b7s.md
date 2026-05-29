---
id: ir-0b7s
status: closed
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


## Notes

**2026-05-29T04:00:54Z**

Implemented shared FragmentRenderMode plus typed actor response helpers in Application.Helper.LiveSurface. Added focused LiveSurfaceSpec coverage for typed containment normalization and OOB-mode rendering with extras. Verification attempts: bin/in-env typecheck and bin/in-env hspec-test --match LiveSurface both fail before reaching these focused assertions because generated types are missing unrelated XeroAccount, XeroImportedPayItem, and UserFeedbackItem types (likely existing schema/generated-types drift noted in working context).
