# Subissue body template

## Problem

Describe the concrete maintenance, navigability, duplication, module-depth, test,
or architecture-drift problem. Explain cost without claiming a behavior bug.

## Evidence

- Paths/symbols: `<path:line, module, function>`
- Callers/references: `<representative and total scope>`
- Repetition/churn/coupling evidence: `<measured facts>`
- Current tests/contracts: `<paths>`
- Existing issue overlap: `<none or links and ownership decision>`

## Architecture fit

- Canonical source of truth: `<type/DSL/schema/module/contract>`
- Current manual copies or bypasses: `<paths>`
- Intended module interface/seam: `<direction; validate before locking details>`
- Why this increases depth/locality or improves derivation: `<reason>`

## Scope

1. `<characterize or establish guardrail if needed>`
2. `<deepen/extract/derive the canonical implementation>`
3. `<migrate all in-scope callers>`
4. `<remove replaced path and reconcile local docs/checks>`

## Behavior-preservation contract

The following remain unchanged:

- `<routes/status/redirect/error behavior>`
- `<authorization and venue scope>`
- `<query/persistence/order/transaction behavior>`
- `<rendered/wire/frontend/live behavior>`
- `<other applicable external or operational behavior>`

## Acceptance criteria

- [ ] `<resulting ownership/interface is explicit>`
- [ ] `<manual copies/bypasses in scope are gone>`
- [ ] `<new cases fail loudly or derive automatically where applicable>`
- [ ] `<focused behavior proof passes>`
- [ ] `<broader affected-area proof passes>`
- [ ] `<nearest living docs/checks are updated>`

Avoid acceptance criteria based only on file length, number of modules, or
formatting.

## Verification

- Baseline/characterization: `<test or observation>`
- Focused: `<exact command/test and invariant>`
- Generated/architecture drift: `<exact check if applicable>`
- Broader: `<typecheck/Hspec/E2E/verification aggregate>`

Expected results must remain independent of the implementation under test.

## Non-goals

- No behavior fixes or feature changes.
- No unrelated formatting/renaming/dependency upgrades.
- `<issue-specific exclusions>`

## Dependencies and documentation

- Blocked by: `<issue or none; technical reason>`
- Blocks: `<issue or none>`
- Living docs: `<nearest README/SPEC/AGENTS/workstream>`
- Migration/generated artifacts: `<none or exact ownership>`
