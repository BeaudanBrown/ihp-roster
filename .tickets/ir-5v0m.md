---
id: ir-5v0m
status: open
deps: []
links: []
created: 2026-07-09T02:39:01Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-z20h
tags: [agent-loop, ui, performance]
---
# Investigate and fix accordion UI lag

Investigate accordion lag seen during the demo and apply a targeted fix if app-side.

## Design

Inspect admin/profile accordion markup, Bootstrap behavior, live fragments, and heavy content. Prefer removing avoidable expensive reflows/renders. If no clear app-side fix is found, document findings and create a narrower follow-up.

## Acceptance Criteria

Accordion lag is either fixed with a targeted change and verified, or the investigation records reproduction steps, likely cause, and a follow-up ticket. No broad UI rewrite is introduced.

