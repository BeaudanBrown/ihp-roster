---
id: ir-gaxt
status: open
deps: [ir-729e]
links: []
created: 2026-07-04T02:44:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-888o
tags: [agent-loop, surfaces, interaction, guardrails]
---
# Migrate remaining interaction helper call sites and restrict low-level marker imports

Move non-roster feature views/tests to generated helpers and make low-level data-bepis-* primitives internal by convention or guardrail.

## Design

Audit all imports of Application.Helper.Interaction and direct data-bepis-* literals in production views. Keep genuinely generic shared primitives, but route feature markup through FrontendSurface-aware helpers. Add a guardrail or documented allowlist if practical.

## Acceptance Criteria

Production feature views no longer hand-wire interaction markers where a generated helper exists; remaining low-level usage is documented/allowlisted; tests cover the guardrail.

