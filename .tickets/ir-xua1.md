---
id: ir-xua1
status: open
deps: []
links: []
created: 2026-07-10T05:30:27Z
type: bug
priority: 1
assignee: beaudan
parent: ir-zyk3
tags: [agent-loop, area:frontend-contracts, area:htmx]
---
# Fix generated HTMX swap value serialization

Generated surface action attrs currently lower OuterHTML to hx-swap=outer-html, which is not HTMX's canonical outerHTML value and can cause broken swaps.

## Design

Update surface contract lowering/reflection so HTMX swap markers render canonical HTMX values such as outerHTML, innerHTML, and none. Audit generated production forms for invalid swap casing and add focused contract coverage around staff/profile/roster action swap values.

## Acceptance Criteria

No production generated form emits hx-swap="outer-html". Staff/profile/roster surface action contract tests expect valid HTMX swap strings. Focused surface/frontend-contract checks pass.

