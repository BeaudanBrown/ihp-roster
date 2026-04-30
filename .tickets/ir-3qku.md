---
id: ir-3qku
status: open
deps: []
links: []
created: 2026-04-30T06:57:06Z
type: task
priority: 2
assignee: beaudan
parent: ir-hw2v
tags: [area:docs, area:payroll]
---
# Update payroll reproducibility specs and agent docs for versioned config

Update product specs, implementation specs, plans, and AGENTS guidance to describe append-only relational pay config versions instead of JSON snapshots.

## Design

After implementation direction is accepted, update specs/02-domain-model.md, specs/06-pay-engine.md, specs/10 compliance docs where relevant, Application/AGENTS.md, Test/AGENTS.md, and annotate older snapshot-plan text as superseded rather than rewriting history.

## Acceptance Criteria

Active docs consistently describe immutable relational version ids and locking gates; old JSON snapshot guidance is marked superseded; tracker links point to ir-hw2v work.

