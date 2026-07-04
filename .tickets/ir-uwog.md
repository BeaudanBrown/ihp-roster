---
id: ir-uwog
status: open
deps: [ir-vexe]
links: []
created: 2026-07-04T04:34:06Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-lnxp
tags: [agent-loop, surfaces, guardrails, cleanup]
---
# Tighten final FrontendSurface cleanup guardrails and close epic

Add final no-regression checks for the removed Billing override, semantic InteractionDom attrs, and feature-local interaction renderer seams, then verify and close the epic.

## Design

Extend Hspec and frontend surface guardrail scripts to forbid production data-live-update-url, deleted semantic interaction attrs in generated contracts/runtime, and roster-style feature-local shell/form/layer rendering once generic helpers exist. Run the epic verification suite and close the epic only when all child acceptance criteria are satisfied.

## Acceptance Criteria

Guardrails cover every removed seam. Full verification passes: frontend-contracts, frontend-check, typecheck, hspec-test, doc-drift-check, and focused e2e where needed. Epic is closed with a clean worktree.

