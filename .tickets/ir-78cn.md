---
id: ir-78cn
status: open
deps: [ir-kuyy]
links: []
created: 2026-05-29T03:16:11Z
type: epic
priority: 3
assignee: beaudan
parent: ir-cfcr
tags: [agent-loop, cleanup, verification, docs]
---
# Finalize app-wide unified fragment pattern

Remove obsolete compatibility paths, add guardrails, and verify the unified fragment system app-wide after feature migrations.

## Design

This closeout phase should inventory remaining OOB/direct hx-target paths, update docs/tests, and run broad verification.

## Acceptance Criteria

No obsolete renderMainFragmentOob/page-live-fragment/direct successful actor swap paths remain in migrated surfaces; guardrails catch regressions; canonical verification passes or unrelated failures are documented.

