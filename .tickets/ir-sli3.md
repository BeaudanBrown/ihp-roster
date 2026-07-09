---
id: ir-sli3
status: closed
deps: []
links: []
created: 2026-07-09T03:12:27Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, page-help, ux]
---
# Contextual page help for main authenticated pages

Add a consistent title-adjacent help button to scoped authenticated pages. The button opens concise role-aware modal help for the page, using existing overlay patterns and maintainable feature-owned help content.

## Design

Use a reusable page-help model/helper and a dedicated help dialog route/controller. Add an OpenPageHelpDialog AppShell action so triggers use generated HTMX/AppShell dialog metadata and target the shared dialog overlay mount. Extend shared page chrome so pages can opt into title-adjacent help beside the h1 while preserving right-aligned appPageActions. Help content is curated static Haskell data with topic ids, sections/items, and audience/capability gates based on existing current-user/current-venue role helpers. Scoped topics: roster, profile, timesheets, unavailability/leave requests, admin, xero, billing. Start with roster as the first vertical slice, then wire the remaining scoped pages. Keep public/auth/legal/internal lab pages out of scope.

## Acceptance Criteria

All scoped pages render a consistent title-adjacent help trigger when the user can access the page. Help dialogs open through the shared overlay mount without full-page navigation under HTMX. Help content is role-aware and omits irrelevant sections/items. Roster help documents current drag/drop and modifier-copy behavior succinctly. Tests or guardrails prove scoped topics are registered, non-empty after role filtering for intended audiences, and wired to page config. Local docs/agent guidance tells future agents to update page help when user-facing page behavior changes.

