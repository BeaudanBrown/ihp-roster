---
id: ir-w9dw
status: closed
deps: [ir-ws5t]
links: []
created: 2026-07-01T01:40:01Z
type: feature
priority: 2
assignee: beaudan
parent: ir-6kzl
tags: [agent-loop, frontend, contracts, guardrail]
---
# Delete legacy/manual frontend contract generation paths and add final lockdown guards

Remove all leftovers from older frontend contract generation approaches and make reintroduction fail loudly.

## Design

Delete manual raw schema field lists for migrated DTOs, manual validators/parsers/encoders in TypeScript for generated contracts, stale migration aliases, compatibility helpers, shrinking allowlists, and spike/legacy references. Strengthen Hspec/static guards: no raw export type/interface/const/function snippets in production generator modules except renderer internals; no manual is/parse validators in app TS for generated contracts; no '| string' escape hatches for backend-owned closed vocabularies; no unregistered DTO contract modules.

## Acceptance Criteria

Zero allowlist remains for production frontend contract generator modules except explicit renderer internals. rg/Hspec guards prove no legacy/manual/spike/bridge names remain. Generated output is reproducible and drift-free. Full verification set passes.


## Notes

**2026-07-01T02:28:29Z**

Removed remaining handwritten generated-contract validators in frontend runtime by importing generated guards for InteractionFieldPresence and InteractionConflictResolution. Strengthened FrontendContractsSpec lockdowns: DTO module registry, renderer-only raw TS emitters, no handwritten is/parse/encode helpers for generated contract type names, and legacy/spike names. Verification: typecheck; frontend-check; hspec-test --match 'Frontend contract'.
