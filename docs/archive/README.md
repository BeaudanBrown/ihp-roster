# Archive

Git history is the default archive for completed plans and implementation
narration. Files remain here only when their evidence supports a current
architecture decision, repeatable comparison, or externally researched
constraint. They are not implementation guidance.

## Retained Evidence

- `hspec-feedback-lane-decision-2026-07-30.md` — measured rationale for keeping
  partial Hspec selections diagnostic; supports ADR 0004.
- `hspec-final-performance-evidence-2026-07-30.md` — repeatable final benchmark
  evidence for the protected Hspec gate and future same-protocol comparisons.
- `hspec-refactor-closeout-2026-07-30.md` — compact reconciliation of the Hspec
  authority boundaries preserved by ADR 0004.
- `playwright-agent-browser-tooling-research-2026-07-23.md` — official-source
  tool comparison retained for future browser-agent/tooling decisions.
- `typed-contract-authority.md` — implemented epic #328 baseline, topology
  counts, and exit evidence retained to support ADR 0002's zero-bypass boundary.
- `xero-payroll-au-v2-openapi-research-2026-07-23.md` — official-source evidence
  that the required Payroll AU contract was unavailable, retained for future
  provider-contract review.

Completed numbered plans, generated inventories, migration narration, and
implemented workstream audits were removed; their history remains in Git.
Current behavior belongs in local `SPEC.md` files, unresolved design in
`docs/workstreams/`, and live status in GitHub Issues.
