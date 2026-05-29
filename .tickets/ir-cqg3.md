---
id: ir-cqg3
status: open
deps: []
links: []
created: 2026-05-29T00:51:30Z
type: epic
priority: 2
assignee: beaudan
tags: [agent-loop, css, styling, refactor, frontend]
---
# CSS architecture overhaul and roster stylesheet decomposition

Overhaul app-owned CSS organisation so future styling work is easier to find, safer to change, and less prone to duplicated one-off selectors. The immediate driver is static/css/features/roster.css exceeding 2000 lines, but the work also covers shared component CSS, token/palette ownership, style-audit guardrails, and agent-facing documentation.

## Design

Keep the existing no-bundler/no-@import asset model: stylesheets are linked directly from Web/View/Layout.hs through assetPath and mirrored in Makefile CSS_FILES. Work in small, reviewable, independently testable slices. Start with docs and pure file splits that preserve selector text and cascade order, then introduce shared modules/primitives and cleanup. Preserve Bootstrap 5.3.8 and dark-token behavior. Do not hand-edit static/prod.css or vendor files.

## Acceptance Criteria

The roster CSS is decomposed into focused modules under static/css/features/roster/ with no single app-owned CSS source file left above the agreed size budget except generated/vendor files. Shared component CSS is split by concern. Shift-type palette/tone tokens are centralized. Reusable horizontal-strip, dense-cell, and action-button styling is documented and used where appropriate. Stale CSS is pruned after verification. static/css/README.md and AGENTS instructions explain where future CSS belongs. bin/style-audit (or a companion inventory script) reports/enforces architecture guardrails. Relevant e2e/style/mobile checks pass after each implementation slice and a final verification sweep is recorded.


## Notes

**2026-05-29T00:51:45Z**

Initial CSS scan before implementation: app-owned CSS source is about 4,369 lines excluding vendor/prod.css. Largest files: static/css/features/roster.css 2,138 lines, static/css/components.css 796, static/css/features/timesheets.css 399, static/css/layout.css 286. bin/style-audit currently passes hard checks (undefined vars and Layout/Makefile asset sync) but reports raw palette colors outside tokens, one banned light utility in Web/View/Billing/Index.hs, and inline style attributes for review. Preserve direct assetPath links in Web/View/Layout.hs and Makefile CSS_FILES; do not use app-owned @import or edit static/prod.css/vendor files.
