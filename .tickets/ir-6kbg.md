---
id: ir-6kbg
status: open
deps: [ir-zel6, ir-59zh, ir-v1w2, ir-qbmu, ir-jlm2, ir-v3wa]
links: []
created: 2026-07-10T05:32:28Z
type: chore
priority: 2
assignee: beaudan
parent: ir-zpyz
tags: [agent-loop, lint, maintenance]
---
# Clear HLint gate after functional fixes settle

Address the HLint hints causing bash ./bin/in-env lint to fail after functional churn has settled.

## Design

Prioritize low-risk mechanical changes such as unused extensions, redundant $, redundant brackets, eta reductions, and simple lambda simplifications. Treat broad semantic suggestions in contract lowering code carefully.

## Acceptance Criteria

bash ./bin/in-env lint passes. typecheck passes after lint cleanup. No unrelated behavior changes are introduced.

