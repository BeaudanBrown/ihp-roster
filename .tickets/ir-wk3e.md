---
id: ir-wk3e
status: open
deps: [ir-re0y]
links: []
created: 2026-05-29T00:51:30Z
type: task
priority: 2
assignee: beaudan
parent: ir-cqg3
tags: [agent-loop, css, audit, tooling]
---
# Add non-destructive CSS inventory and architecture audit reporting

Make the current CSS debt visible without blocking the first split: file sizes, raw colors outside token/palette files, feature-file global selectors, stale selector candidates, and Layout/Makefile asset sync.

## Design

Extend bin/style-audit only where checks are already intended to be hard (undefined variables and missing assets), or add a companion script such as bin/css-inventory for warning-only architecture reporting. Report app-owned CSS line counts excluding vendor/prod.css, files over the documented budget, raw hex/rgb/hsl colors outside token/palette modules, app/global/Bootstrap selectors inside feature stylesheets, and simple selector candidates with no HS/JS mention. Keep false positives warning-only until the cleanup tickets land. Mention how to run the tool from static/AGENTS.md/static/css/README.md.

## Acceptance Criteria

A repo-local command produces a concise CSS architecture report. Existing hard style-audit gates still pass. The report identifies static/css/features/roster.css as over budget before the split and gives actionable warnings without failing CI-style verification. Documentation names the command and explains warning-only vs hard-fail output.

