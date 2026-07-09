---
id: ir-3irv
status: closed
deps: []
links: []
created: 2026-07-09T01:05:25Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, frontend-surface, live-fragments, refactor]
---
# Generalize parameterized FrontendSurface fragments and migrate surfaces

Make parameterized fragments/resources a first-class, ergonomic FrontendSurface pattern and migrate every applicable registered surface, starting with leave requests as the proving ground.

## Design

Model repeated UI regions as fragment kind + typed params + target id + URL, with resources that can depend on scope fields and fragment params. Add reusable FrontendSurface foundation for parameterized fragments/resources, resource-driven actor refresh, and explicit fragment response modes. Prove the pattern on leave requests, then inventory and migrate all applicable registered surfaces. Implementation agents must pause and ask before expanding the epic when they hit unforeseen DSL, generated-contract, authorization, DOM-ownership, or legacy-OOB decision points.

## Acceptance Criteria

Parameterized fragments/resources are documented and tested as the preferred FrontendSurface pattern for repeated regions. Actor refresh can be driven by touched resources and matches passive invalidation planning. Fragment response mode is standardized for plain vs OOB delivery. Leave requests, roster, timesheets, SurfaceLab, profile/staff, and applicable admin/support/billing surfaces are migrated or explicitly marked non-applicable with rationale. No successful migrated FrontendSurface business refresh relies on authoritative actor OOB HTML. Final inventory confirms no applicable surface remains unmigrated. Required verification passes.


## Notes

**2026-07-09T01:55:32Z**

Epic complete. Parameterized FrontendSurface helpers, resource-driven actor refresh, shared fragment response mode, leave-section parameterization, existing parameterized surface helper migrations, applicability classification, docs, final sweep, and final verification are complete. Final verification: typecheck, full hspec-test, frontend-check, and doc-drift-check passed.
