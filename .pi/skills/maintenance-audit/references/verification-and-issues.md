# Verification and GitHub Issue Design

A behavior-preserving refactor must state what "same behavior" means and how it
will be observed. Compilation alone is insufficient; broad snapshots alone are
too brittle.

## Behavior-preservation contract

For each issue, identify applicable invariants:

- routes, query parameters, status codes, redirects, and error modes;
- authorization, venue scope, support mode, and visibility;
- database query semantics, constraints, transaction boundaries, ordering, and
  persisted values;
- rendered HTML semantics, stable customer copy, form fields, attributes, and
  accessibility behavior;
- JSON/CSV/wire serialization and external compatibility;
- live fragment/OOB responses, invalidation targets, and passive refetch paths;
- frontend events, intent/conflict handling, generated contracts, and static
  artifact behavior;
- date/timezone/week-offset behavior;
- side-effect count/order, audit facts, jobs, emails, or external requests;
- performance characteristics when the existing contract depends on them.

If the intended result changes one of these, classify it as behavior work rather
than silently broadening a refactor.

## Verification strategy

### Before movement

- Record baseline commit and command results.
- Locate existing tests through the module's public interface.
- Add characterization only where behavior is sensitive and current proof is
  inadequate.
- Prefer narrow semantic assertions over broad snapshots.
- Preserve independent external or compliance oracles.

### During each issue

Use the nearest `AGENTS.md` and current repository commands. Typical mapping:

| Area touched | Focused proof | Broader proof |
|---|---|---|
| Pure Haskell/domain module | focused Hspec/property tests | typecheck + pure/full Hspec as appropriate |
| Controller/query/auth | focused DB-backed/controller Hspec | typecheck + relevant integration/E2E |
| View/HSX/navigation | focused view/controller tests | relevant Playwright behavior/screenshots when visual semantics matter |
| Frontend contract/TypeScript | generator freshness + frontend unit/type checks | architecture contract checks + relevant E2E |
| CSS/static asset organization | ownership/stale-selector/style checks | layout audit + relevant E2E/screenshots |
| Schema/generated types | parser/generator/typecheck; preserving migration required for actual schema change | local DB/startup flow and focused schema tests |
| Script/tooling | syntax/unit/fixture test, dry-run behavior | owning verification aggregate |
| Documentation/agent navigation | link/drift check and path validation | `doc-drift-check`/architecture docs gate |

Run repository wrappers serially. Use `run_worker` for noisy checks. On
memory-constrained hosts, follow root guidance before compile-heavy gates.

At integration, run the broadest gate justified by the combined epic, commonly
`verify-full`, after focused issue checks have passed. Do not use one late broad
gate as a substitute for child-level proof.

### Equivalence techniques

Use the strongest practical independent evidence:

- existing interface-level tests passing before and after;
- characterization fixtures captured before restructuring and reviewed for
  stability;
- property/invariant tests across generated case universes;
- semantic DOM/accessibility assertions rather than whitespace-sensitive HTML;
- parsed JSON/CSV/schema comparisons rather than incidental formatting, unless
  exact bytes are the contract;
- query/result assertions rather than SQL-source fragments, unless query shape
  itself is a measured performance invariant;
- generated artifact freshness plus independent contract tests;
- architecture facts/AST/reflection rather than source grep for structural
  rules.

Never derive expected behavior using the production function/interpreter under
test. Deriving the set of cases from a canonical DSL is useful only when the
assertion remains independently meaningful.

## Required epic content

Use `templates/epic.md`. The parent must include:

- audit date, target branch, and baseline SHA;
- outcome and no-behavior-change guardrail;
- scan scope and method;
- baseline health, including inherited failures;
- source-of-truth/architecture themes;
- ranked issue lanes and ordering rationale;
- shared verification and integration gate;
- explicit non-goals and deferred findings;
- living docs/workstream reconciliation;
- completion criteria.

Do not paste the entire temporary evidence register into the parent. Summarize
validated evidence and put issue-specific detail in children.

## Required subissue content

Use `templates/subissue.md`. Every child must include:

- concrete path/symbol/caller evidence;
- why current organization causes repeated knowledge, drift, or navigation cost;
- canonical source/module/seam and proposed direction;
- in-scope migration and deletion of replaced paths;
- behavior-preservation invariants;
- focused and broader verification commands/observations;
- non-goals and behavior work explicitly excluded;
- dependencies/blockers and affected living docs;
- acceptance criteria that describe the resulting architecture, not line count.

A child is not ready-for-agent if it says only "investigate" or "refactor" and
cannot explain how completion is verified.

## Declarative publication

- Choose a stable plan key, for example
  `maintenance-audit-YYYY-MM-DD-BASESHA`.
- Use stable plan-local keys such as `epic`, `surface-contract-derivation`, and
  `roster-render-module`; never use array positions.
- Inspect labels before depending on them.
- Include native `parent` relationships and `blockedBy` plan keys.
- Run `github_issue_plan` with `apply: false` for the complete graph.
- Review titles, body summaries, labels, states, relationships, duplicates, and
  validation warnings with the user.
- Apply only after explicit approval.
- If blocker publication requires separate operations, dry-run and approve those
  operations independently.
- Inspect the resulting parent and representative children by issue number or
  provenance marker.
- Re-running the same plan key should reconcile, not duplicate, an interrupted
  publication.

## Worktree and issue lifecycle

After publication:

1. create the sibling Git worktree on a distinct branch;
2. register the existing path with `epic-worktree register`;
3. orient and wait for explicit child selection;
4. after each implementation, commit and present verification before requesting
   issue closure;
5. orient again after approved closure;
6. use `epic-worktree-manage preflight` before synchronization/integration;
7. synchronization needs `sync --apply`; integration and cleanup each require
   their own approval;
8. close the parent separately before approved cleanup.

The audit coordinator must not auto-assign, auto-start, auto-close, integrate, or
clean up work based solely on a passing check.

## Completion criteria for the audit itself

The scan/planning phase is complete when:

- all material repository areas received a documented pass;
- architecture source-of-truth flows were mapped;
- accepted findings have concrete evidence and verification;
- rejected/deferred findings have a brief reason in temporary evidence;
- the complete issue graph was dry-run, approved, applied, and inspected;
- the maintenance workstream points to the fresh live epic;
- the registered worktree orients successfully;
- the user has been shown the frontier and no implementation began implicitly.
