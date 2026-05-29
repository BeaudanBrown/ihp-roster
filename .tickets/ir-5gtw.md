---
id: ir-5gtw
status: open
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

