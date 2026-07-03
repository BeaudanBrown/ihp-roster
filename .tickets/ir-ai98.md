---
id: ir-ai98
status: closed
deps: [ir-s3a3]
links: []
created: 2026-07-03T06:55:44Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-aa95
tags: [agent-loop, live-updates, codegen]
---
# Introduce generated resource values with temporary bridge

Generate resource value codecs/helpers from resources discovered in registered surface dependencies and add a temporary bridge from existing LiveResource constructors.

## Design

Generated resource values are the target representation for planner input. Existing mutations may temporarily emit the current LiveResource ADT and cross an isolated, clearly marked bridge to generated resource values while surfaces/resources migrate.

## Acceptance Criteria

Existing invalidation tests pass through generated resource values. Temporary bridge code is isolated and explicitly marked for removal. A later cleanup ticket depends on all migration work and must delete the bridge before epic close.

