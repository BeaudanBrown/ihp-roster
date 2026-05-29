---
id: ir-5gtw
status: closed
deps: [ir-lgt3]
links: []
created: 2026-05-29T00:51:31Z
type: task
priority: 2
assignee: beaudan
parent: ir-cqg3
tags: [agent-loop, css, audit, guardrails, ci]
---
# Make CSS architecture guardrails enforceable after cleanup

Convert the warning-only CSS architecture report into useful hard or semi-hard guardrails once the refactor has reduced known false positives.

## Design

Update bin/style-audit or the companion inventory command so the project can prevent regressions: Layout/Makefile sync and undefined variables remain hard; file size budget for app-owned CSS becomes hard or allowlisted; raw colors outside documented token/palette files become hard or allowlisted; app/global/Bootstrap selectors inside feature modules become hard or allowlisted; app-owned @import remains banned. Keep a small explicit allowlist file or comments if needed. Update docs to describe how to handle intentional exceptions.

## Acceptance Criteria

Running bash ./bin/in-env ./bin/style-audit catches newly added app-owned CSS files missing from Layout/Makefile, undefined vars, oversized files beyond the documented budget, unexpected raw colors, and forbidden global selectors in feature stylesheets. Existing project CSS passes the hard checks. Docs tell future agents how to resolve or justify warnings.


## Notes

**2026-05-29T02:21:37Z**

Hardened bin/style-audit into the CSS architecture gate: it now fails on unlinked/non-mirrored app-owned CSS files, app-owned @import, CSS files over CSS_LINE_BUDGET, raw colour literals outside token/palette/bootstrap-bridge files, and unexpected app/global/Bootstrap selectors in feature CSS, while retaining existing undefined-var and Layout/Makefile checks. Added narrow embedded allowlists for the two compatibility marker CSS files and current feature-scoped Bootstrap/app selector exceptions. Moved preference focus-ring rgba into --app-focus-ring-primary in bootstrap-bridge so current CSS has no raw colour findings. Updated static CSS docs/agent notes to explain hard gates and exception handling. Verification: bash -n bin/style-audit passed; bash ./bin/in-env ./bin/style-audit passed; temporary _guardrail-probe.css correctly made style-audit fail on missing Layout link, missing CSS_FILES, @import, raw color, and unexpected feature global selector, then was removed; bash ./bin/in-env ./bin/css-inventory passed warning-only with raw colours now none; lsp_diagnostics '*' clean except existing e2e/roster-row-controls implicit-any hint; bash ./bin/in-env e2e e2e/styling-regression.spec.ts passed (7/7).
