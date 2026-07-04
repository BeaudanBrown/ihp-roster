---
id: ir-4ub1
status: open
deps: []
links: []
created: 2026-07-04T02:44:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-888o
tags: [agent-loop, surfaces, interaction, planning]
---
# Specify generated interaction render helper API

Write the concrete API contract for FrontendSurface-aware interaction render helpers before implementation.

## Design

Inventory current Application.Helper.Interaction marker/form/layer helpers and their call sites. Decide the exported high-level API shape, likely in Application.Helper.FrontendSurface.Interaction or a sibling render module, for activation intents, pointer sessions, dropzones, disposable layers, intent forms, generated target resolution, and conflict-policy metadata. Keep low-level marker helpers available internally but define which modules/views may import them.

## Acceptance Criteria

A living SPEC/README section defines helper names, inputs, expected markup, ownership of data-bepis-* attributes, migration rules, and non-goals; tickets downstream can implement without reopening architecture decisions.

