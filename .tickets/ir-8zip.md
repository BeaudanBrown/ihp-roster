---
id: ir-8zip
status: open
deps: [ir-63go]
links: []
created: 2026-06-30T04:48:17Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-zqp3
tags: [architecture, tooling, bepis-actions]
---
# Detect Bepis wrappers in architecture facts

Teach deterministic architecture facts to prefer typed Bepis wrappers over naming heuristics.

## Design

Extend scripts/architecture/facts.mjs to detect bepisPageAction, bepisFragmentAction, bepisDialogAction, bepisMutationAction, controller policy wrappers, response wrappers, and mutation specs. Add confidence/source fields such as typed-wrapper, app-registry, heuristic-static-scan, naming-fallback. Preserve existing heuristics as fallback.

## Acceptance Criteria

output/architecture/facts.json records wrapper-derived action kind/response kind/policy where wrappers exist, with provenance and confidence. controller and request-flow queries display typed-wrapper facts for migrated actions and warnings for heuristic fallback actions.

