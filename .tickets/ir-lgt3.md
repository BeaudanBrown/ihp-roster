---
id: ir-lgt3
status: open
deps: [ir-lp03, ir-ecqz]
links: []
created: 2026-05-29T00:51:31Z
type: task
priority: 2
assignee: beaudan
parent: ir-cqg3
tags: [agent-loop, css, cleanup, e2e]
---
# Prune verified stale CSS and stale styling-regression assumptions

After file splits and shared primitive extraction, remove unused/stale selectors and update tests that encode obsolete structure.

## Design

Use rg plus runtime coverage before deleting. Candidate selectors from the initial scan include: .roster-grid-header-center, .roster-grid-header-side-left/right, .slot-time-step, .day-label-empty, .leave-requests-toolbar, .leave-request-accordion-count, .app-surface-toolbar*, .admin-setting-row-select, .app-page-narrow/.app-page-wide if not used, .app-auth-card-profile if not used, and global .breadcrumb/.nav-tabs rules currently inside roster CSS. For each candidate, either remove it, move it to a correct shared module, or document why it is intentionally kept. Update e2e/styling-regression.spec.ts so it checks durable contracts instead of removed legacy class names. Do not remove feature classes used by JS/e2e without updating callers and tests.

## Acceptance Criteria

Verified dead selectors are removed or justified in code comments/ticket notes. Any global Bootstrap overrides are moved out of feature stylesheets or removed if unused. Styling regression tests no longer depend on removed stale class names. style-audit/css-inventory warnings are materially reduced. Focused e2e/style/mobile checks pass or attempted failures are recorded.

