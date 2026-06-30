---
id: ir-lhbd
status: open
deps: [ir-95yp, ir-8zip]
links: []
created: 2026-06-30T04:48:17Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-zqp3
tags: [architecture, tests, guardrails]
---
# Add Bepis architecture convention checks

Add test/static checks that make wrapper drift visible before runtime.

## Design

Add an Hspec or deterministic architecture check that scans Web/Controller/*.hs action handlers and reports actions not delegating through approved Bepis wrappers. Add checks for wrapper kind mismatch against naming fallback, mutation wrapper without mutation spec, raw IHP response exits in migrated controllers where app response wrappers are required, unclassified FKs, and generated frontend raw strings where generated constants exist. Start report-only for non-migrated controllers; enforce for controllers explicitly marked migrated.

## Acceptance Criteria

A focused verification command fails if SessionsController regresses to raw IHP action bodies after migration. Non-migrated controllers are reported without blocking until opted in. architecture_query conventions or equivalent reports violations with source paths/lines.

