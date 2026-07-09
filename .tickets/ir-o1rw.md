---
id: ir-o1rw
status: closed
deps: []
links: []
created: 2026-07-09T03:12:56Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-sli3
tags: [agent-loop, page-help, chunk]
---
# Build shared page-help infrastructure

Add reusable page-help data, dialog rendering, route/controller wiring, AppShell action support, and shared title-adjacent help trigger support.

## Design

Create a focused page-help model/helper for topic ids, titles, role/audience-gated sections and items. Add a help dialog action that validates topic keys, filters sections for the current request roles/capabilities, and renders with renderDialogOverlay into the shared dialog mount. Add OpenPageHelpDialog to the AppShell contract so help triggers use generated HTMX attributes. Extend renderAppPage/AppPageConfig so pages can opt into a help topic rendered immediately beside the h1 while appPageActions remains for right-aligned actions. Provide a safe non-HTMX fallback.

## Acceptance Criteria

A page can opt into help with a topic id and renders Title [?]. The HTMX trigger targets #dialog-overlay-mount and swaps innerHTML. Unknown topics fail safely. At least one fixture/help topic has Hspec coverage for registry lookup and non-empty filtered content. Typecheck passes.

