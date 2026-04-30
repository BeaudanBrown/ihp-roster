---
id: ir-tqnr
status: closed
deps: []
links: []
created: 2026-04-30T06:31:42Z
type: task
priority: 4
assignee: beaudan
parent: ir-m8hc
tags: [area:docs, area:testing, source:2026-04-30-audit]
---
# Add lightweight documentation drift checks

Reduce recurrence of docs drifting from implementation for protocol names, nav order, key script assets, and schema terminology.

## Design

Add small, cheap checks where appropriate: grep-based script/docs check, Hspec assertions for live scope kinds already present, or a docs checklist section. Keep this lightweight and avoid brittle tests for prose unless they protect high-value invariants.

## Acceptance Criteria

At least one low-maintenance guard exists for a drift-prone invariant, or the plan documents why checks would be too brittle; future changes have a clear place to update docs alongside code.
