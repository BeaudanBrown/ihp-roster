---
id: ir-amxj
status: open
deps: [ir-39dg]
links: []
created: 2026-06-30T11:03:28Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-z0j1
tags: [architecture, bepis-actions, agent-loop]
---
# Replace architecture facts and gates with generated Bepis fact contracts

Remove fragile regex parsing for Bepis semantics and make architecture facts/gates consume Haskell-generated operation/fact contracts plus simple usage/no-legacy checks.

## Design

Architecture scanners may still locate controller actions and runBepis calls, but semantic facts about kind, scope, audit, live, and response must come from generated contracts or captured runtime fact artifacts. Delete mutation drift guard mode and replace it with strict no-legacy/no-missing-final-runner checks.

## Acceptance Criteria

Strict architecture gate passes; source regex is not used to infer Bepis semantics; generated facts show final BepisFact provenance; contract JSON has golden/unit coverage.
