---
id: ir-4uuy
status: open
deps: []
links: []
created: 2026-06-16T13:45:27Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-jsyd
tags: [agent-loop, docs, frontend, htmx, interaction]
---
# Document interaction layer contract

Write the shared contract for declarative interaction surfaces, intent events, HTMX form submission, server/live ownership boundaries, and mobile pointer/touch behavior.

## Design

Add living docs near the static/runtime subsystem. Capture the three DOM ownership categories: server DOM, JS interaction DOM, and local widget DOM. Specify the data-bepis-* attribute vocabulary, normalized intent event shape, allowed JS DOM mutations, and the rule that backend mutations use server-rendered HTMX intent forms rather than JS-constructed URLs. Include live fragment coordination policy: defer/cancel same-surface swaps during active interactions, and keep JS-created DOM disposable.

## Acceptance Criteria

Docs describe the golden path, attribute naming, event phases, mobile/touch strategy, live-fragment interaction policy, and examples for click, drop, resize, and sortable intents; static/AGENTS.md or a local SPEC points future work to the contract.

