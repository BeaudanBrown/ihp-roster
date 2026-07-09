---
id: ir-ij7m
status: closed
deps: [ir-p5qu, ir-o8nm, ir-bfvx]
links: []
created: 2026-07-09T03:12:56Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-sli3
tags: [agent-loop, page-help, chunk, docs]
---
# Add page-help guardrails and docs

Add tests and local agent documentation so future user-visible workflow changes keep page help current.

## Design

Update shared and feature-local AGENTS/SPEC docs with a page-help maintenance rule. Add guardrail tests that the scoped topics stay registered and produce non-empty content for representative roles/audiences. Document the implemented page-help contract in the appropriate local SPEC or view helper notes.

## Acceptance Criteria

Agent docs explicitly require updating matching help topics when changing page controls, workflows, gestures, settings, role-visible behavior, or page copy that affects user guidance. Guardrail fails if a scoped topic is missing or representative role-filtered content is empty. Typecheck and focused Hspec pass.

