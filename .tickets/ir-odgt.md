---
id: ir-odgt
status: closed
deps: [ir-23k7, ir-pnj2]
links: []
created: 2026-04-30T01:11:16Z
type: task
priority: 3
assignee: beaudan
parent: ir-6vvh
tags: [area:test, area:maintenance, source:2026-04-30-health-scan]
---
# Split oversized Hspec suites by behavior

Break AdminSpec and RosterWeeksSpec into behavior-focused spec modules while preserving Test/Suite registration and coverage.

## Design

This is a test navigability refactor. It should trail the code-boundary work so
test moves do not conflict with active controller/view extraction.

Initial split candidates:

- `Test/Controller/AdminSpec.hs`
  - invitations
  - roster groups
  - slot names
  - shift types
  - Xero admin fragments/mutations
  - exports/config smoke coverage
- `Test/Controller/RosterWeeksSpec.hs`
  - week navigation and empty week shells
  - publish/copy/create flows
  - roster slot mutations
  - live fragment metadata/responses
  - permissions/venue scoping

Implementation approach:

- Move specs into behavior-focused modules under the existing test tree.
- Keep shared setup helpers either in existing test support or in a local
  `SpecSupport` module for that controller family.
- Update `Test/Suite.hs` registrations without changing test names more than
  necessary.

Guardrails:

- Do not weaken or delete assertions while moving tests.
- Do not combine this with broad fixture rewrites.
- Avoid running multiple focused `hspec-test` processes in parallel because the
  repo notes mention shared build/test database races.

## Acceptance Criteria

- Oversized admin and roster specs are split into modules a future agent can
  scan by behavior.
- `bash ./bin/in-env hspec-test --match "Admin"` and the corresponding roster
  focused match pass, or any remaining failures are documented with exact
  failing tests.
- Full `Test/Suite.hs` registration remains clear and deterministic.
