---
id: ir-p4zw
status: closed
deps: []
links: []
created: 2026-06-29T14:19:13Z
type: task
priority: 2
assignee: Beaudan Brown
tags: [frontend, contracts, architecture]
---
# Unify frontend contract codec registry

Consolidate Haskell-owned frontend contract generation with codec typeclass/contract groups, shared schema builders, guardrails, and simple schema adoption.

## Acceptance Criteria

Frontend contract modules use a common contract group renderer and HasFrontendCodec where appropriate; shared field/variant helpers reduce boilerplate; tests guard group registration and raw UI region strings; typecheck, frontend-contracts-check, frontend-check, and focused Hspec pass.


## Notes

**2026-06-29T14:40:30Z**

Implemented frontend contract codec consolidation: added HasFrontendCodec/someFrontendCodec, FrontendContractGroup/typedConstant renderer, schema field/variant builders and parseFrontendField; migrated simple schemas plus live update and interaction declarations to shared rendering; centralized UI region attr rendering through Haskell vocabulary; added contract registry/raw-string guardrails and frontend contract generation README. Verification: typecheck, frontend-contracts-check, frontend-check, hspec-test --match 'Frontend contract', doc-drift-check.
