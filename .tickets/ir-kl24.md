---
id: ir-kl24
status: closed
deps: [ir-89ds]
links: []
created: 2026-07-01T02:44:57Z
type: feature
priority: 2
assignee: beaudan
parent: ir-ao41
tags: [agent-loop, frontend, typescript, css, interaction]
---
# Implement clone-shadow global pointer effect

Add the generic clone-shadow effect handler for pointer sessions.

## Design

Implement clone-shadow as a session-global effect. It clones the configured source (v1: pointer marker), sanitizes id, hx-*, live-update, interaction, focus, and form-submission attributes as appropriate, appends it to the configured disposable layer in the same mount, sizes it from getBoundingClientRect, and moves it with transform while preserving the original pointer grab offset. Use a generic CSS class configured by the Haskell schema, with pointer-events none and suitable fixed positioning. Keep all DOM changes disposable and cleanup-owned.

## Acceptance Criteria

Frontend unit/DOM tests prove shadow appears only after threshold activation, preserves grab offset, updates on pointer move, uses the configured layer/class, has pointer-events disabled, is sanitized, and cleans on commit/cancel/Escape/pointercancel/HTMX cleanup. No business/server DOM is persistently mutated. frontend-test/frontend-check pass.


## Notes

**2026-07-01T03:07:37Z**

Implemented clone-shadow global effect with sanitized pointer-marker clone, declared disposable layer, grab offset preservation, pointer-events none, and cleanup. Verification: style-audit; frontend-test; frontend-check.
