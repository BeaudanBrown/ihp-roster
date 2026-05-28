---
id: ir-hx3q
status: closed
deps: []
links: []
created: 2026-05-27T23:58:33Z
type: epic
priority: 1
assignee: beaudan
parent: ir-63z2
tags: [area:ui, area:mobile, area:accessibility, agent-loop]
---
# Remove automatic focus across pages and overlays

Eliminate all app-owned automatic focus behavior, including page autofocus attributes and dialog/overlay focus-to-input behavior that opens mobile keyboards.

## Design

Audit app-owned Haskell views and static JS for autofocus and programmatic focus on load/open. Preserve explicit user-initiated focus behavior such as clicking a field or picker, but opening a page or overlay must not focus form controls automatically.

## Acceptance Criteria

App-owned source search for autofocus is clean outside documentation/tests/vendor/generated bundles; dialog overlays open without focusing inputs/buttons/links; mobile smoke coverage proves opening common forms/dialogs does not place focus in a text/select control automatically.

