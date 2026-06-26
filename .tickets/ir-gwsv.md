---
id: ir-gwsv
status: closed
deps: [ir-b797]
links: []
created: 2026-06-26T04:23:33Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-o5qk
tags: [agent-loop, frontend, contracts, guardrails]
---
# Add hard-coded TypeScript contract lockdown guardrails

Add source and generated-output guard tests that prevent new handwritten TypeScript contracts while existing offenders are migrated behind a shrinking allowlist.

## Design

Scan production frontend contract generator modules, excluding docs/tests/generated output, for TSRawDeclaration and raw export type/interface/const/function strings. Scan generated contracts for canonical '| string' escape hatches. Start with an explicit allowlist for current offenders and require each migration ticket to shrink it.

## Acceptance Criteria

Guard tests fail on new handwritten TS declaration/validator emitters, new stringUnionDeclaration-style shared unions, and new canonical string escape hatches outside the allowlist; tests are documented as the enforcement point for the codec-first migration.


## Notes

**2026-06-26T04:48:11Z**

Added FrontendContracts guard tests as the codec-first migration enforcement point. Source guard scans Application/Helper/Frontend/*.hs for TSRawDeclaration, raw export type/interface/const/function strings, and stringUnionDeclaration uses behind an explicit shrinking allowlist. Generated-output guard scans frontendContractsTypeScript for canonical '| string' escape hatches behind an explicit shrinking allowlist. Verification passed: hspec-test --match 'Frontend contract', typecheck, frontend-contracts-check.
