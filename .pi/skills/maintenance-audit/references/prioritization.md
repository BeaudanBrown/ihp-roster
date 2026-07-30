# Prioritization, Clustering, and Issue Slicing

The audit should produce a small set of high-leverage issues, not an exhaustive
catalog of aesthetic preferences.

## Score evidence, not enthusiasm

For each validated finding, record 0–3 for:

### Benefit

- **Recurrence:** isolated (0) to repeated across many call sites (3).
- **Change frequency:** stable (0) to repeatedly touched/shotgun-edited (3).
- **Agent friction:** obvious/local (0) to routinely difficult to locate/reason
  about (3).
- **Drift risk:** compiler/check already protects it (0) to silent cross-layer or
  policy divergence (3).
- **Locality gain:** mostly cosmetic (0) to one fix would replace knowledge in
  many callers/tests (3).

### Delivery risk

- **Behavior sensitivity:** pure/internal (0) to auth, money, time, migration,
  wire, or customer-visible output (3).
- **Scope/blast radius:** focused (0) to cross-cutting/generated/multi-runtime
  change (3).
- **Uncertainty:** clear owner and seam (0) to architecture/design investigation
  still required (3).
- **Verification gap:** focused existing proof (0) to no credible equivalence
  check (3).

Do not collapse these into a magic number. Use the dimensions to explain rank:

- prioritize high recurrence/drift/locality gain with manageable delivery risk;
- split or precede high-value/high-risk work with characterization or contract
  checks;
- defer low-value cosmetic cleanup;
- create an investigation issue only when uncertainty blocks several valuable
  changes and it has a concrete deliverable.

## Cluster around stable ownership

Group findings when they share:

- one domain concept/source of truth;
- one module interface or seam;
- one generated pipeline;
- one behavior-preservation proof;
- a natural migration sequence.

Do not group merely because files are adjacent or findings share labels such as
"duplication." Do not mix unrelated low-risk cleanup into a sensitive issue.

A good issue title names the intended outcome, for example:

- `Derive frontend intent projections from the canonical Surface DSL`
- `Concentrate venue-scoped active queries behind the staff query module`
- `Split roster rendering around explicit render-data modules`

A weak title names activity without a stopping rule:

- `Clean up helpers`
- `Refactor large files`
- `Remove duplication`

## Shape deep modules

For each proposed module:

- name its interface and the facts callers must know;
- identify behavior hidden by its implementation;
- run the deletion test: would removing it spread complexity back to callers?
- avoid a new seam when there is only one adapter and no real variation;
- keep internal seams private unless callers genuinely need them;
- test through the same interface callers use;
- prefer replacing duplicated paths over layering a new abstraction above them.

The issue may require a short design step, but should not mandate an interface
that the scan has not validated.

## Slice for independent delivery

Each subissue should normally:

- have one primary architecture outcome;
- preserve one describable behavior surface;
- fit one reviewable diff or a clearly staged sequence of commits;
- include all call-site migration needed to avoid parallel old/new paths;
- remove or deprecate the replaced path in the same issue when safe;
- update relevant local docs and checks;
- be verifiable without waiting for unrelated cleanup.

Split when:

- characterization tests must land before sensitive movement;
- generator/DSL capability must land before consumer migration;
- independent subsystems can adopt the seam separately without prolonged dual
  ownership;
- one slice has materially different risk or verification.

Keep together when splitting would leave two sources of truth, temporary
pass-through layers, or an unusable half-interface.

## Dependencies and waves

Use native blockers only for technical ordering, not preference. Typical waves:

1. **Proof/guardrail:** characterization, freshness, or architecture checks.
2. **Canonical owner:** deepen the module/DSL or establish derivation.
3. **Consumer migration:** replace manual copies/bypasses and delete old paths.
4. **Navigation/cleanup:** reconcile docs, names, and obsolete compatibility.

Many low-risk issues need no blockers and can proceed independently. Avoid long
chains that serialize unrelated work.

## Exclusions and separate tracking

Do not include as refactor children:

- user-visible behavior changes;
- bug fixes discovered during scanning;
- schema/product redesign;
- dependency upgrades;
- broad formatting or renaming without locality benefit;
- speculative abstractions;
- generated-output edits without generator ownership;
- findings already owned by active issues.

Mention separately discovered bugs/features to the user and create distinct
issues only with approval.

## Epic portfolio balance

Prefer a bounded portfolio containing:

- a few high-value architecture/source-of-truth corrections;
- focused module-depth/locality improvements;
- test or verification improvements that make later refactors safer;
- navigation/tooling cleanup with measurable agent benefit;
- explicit deferrals for risky or weakly evidenced candidates.

The parent should explain why omitted findings were deferred. More children do
not make an audit more thorough.
