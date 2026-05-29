---
id: ir-re0y
status: closed
deps: []
links: []
created: 2026-05-29T00:51:30Z
type: task
priority: 2
assignee: beaudan
parent: ir-cqg3
tags: [agent-loop, css, docs, guardrails]
---
# Document stylesheet ownership and CSS refactor guardrails

Create the durable guidance needed before moving files: a CSS ownership map, decision tree for where styles belong, size/cascade expectations, and agent instructions that prevent future duplication.

## Design

Add static/css/README.md. Update static/AGENTS.md and Web/View/AGENTS.md. Keep root AGENTS concise. Document the direct assetPath + Makefile CSS_FILES contract, the no app-owned @import rule, static/prod.css/vendor as generated/read-only, and the expected module map (tokens, bootstrap bridge, layout, components/*, features/*). Add a 'before adding CSS' checklist: search existing modules/selectors, prefer shared component classes, add semantic tokens before raw colors, scope feature CSS by feature root/prefix, and avoid global Bootstrap/app overrides in feature stylesheets unless explicitly allowed. Fix the outdated Web/View/AGENTS.md wording that says tokens live in static/app.css; point to static/css/tokens.css and the new CSS README.

## Acceptance Criteria

static/css/README.md exists and gives a clear ownership map plus examples for roster, timesheets, overlays, forms, buttons, tables, palettes, and feature-only CSS. static/AGENTS.md tells agents how to choose a module, how to add stylesheet links, and what not to duplicate. Web/View/AGENTS.md references static/css/tokens.css and the CSS README. No runtime CSS behavior changes are made. bash ./bin/in-env ./bin/style-audit still passes its failing checks.


## Notes

**2026-05-29T01:09:17Z**

Implemented static/css/README.md ownership map and updated static/Web view agent guidance. Verification: bash ./bin/in-env ./bin/style-audit (passed; existing warning-only hardcoded palette/light utility/inline-style findings remain reported).
