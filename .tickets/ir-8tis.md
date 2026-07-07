---
id: ir-8tis
status: open
deps: [ir-oxwq, ir-w1x3]
links: []
created: 2026-07-07T03:24:31Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-vw5m
tags: [agent-loop, lazy-loading, docs, tests]
---
# Add lazy fragment guardrails docs and verification

Lock in the unified lazy fragment contract with guardrails, living docs, and focused verification.

## Design

Add Hspec/guardrail coverage for no stale data-bepis-surface-lazy* attrs, canonical UI-region attrs on lazy fragment roots, absence of the stale Application.Helper.View.LazySurface helper, and lazy renderer application of root slot classes. Update Application/Helper/FrontendContract/Surface/README.md and Application/Helper/LiveUpdate.SPEC.md, and Web/View/AGENTS.md only if a reusable gotcha needs documenting. Run focused checks and record unrelated blockers in ticket notes.

## Acceptance Criteria

Docs describe the single lazy-fragment path. Guardrails fail on old attrs/helper reintroduction. Focused typecheck, frontend-contracts-check, frontend-test, FrontendSurface/lazy Hspec, frontend-check, surface-guardrails, and surface-compile-fail-check pass or unrelated failures are documented.

