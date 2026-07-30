# End-to-End Audit Process

This process is deliberately coordinator-led. It produces evidence and an issue
graph before implementation starts.

## 1. Establish the run

From the intended target checkout:

1. Read root `AGENTS.md`, `README.md`, `docs/README.md`,
   `docs/workstreams/README.md`, and the active maintenance workstream if one
   exists.
2. Check `git status --short --branch`, `git worktree list --porcelain`, target
   branch, remotes, and `HEAD`.
3. If `.bepis-epic-worktree.json` exists, immediately run
   `bash ./bin/in-env epic-worktree orient`; present the result and wait as
   instructed.
4. Choose a run key containing UTC date and baseline short SHA, for example
   `2026-07-30-4d1ef1c`.
5. Create `.pi/tmp/maintenance-audit/<run-key>/`. This directory is ignored and
   may contain working notes, evidence, and issue-plan drafts.
6. Record scope and exclusions. A full audit covers committed application,
   tests, frontend, static assets, scripts, schema/migrations, generated-contract
   pipelines, architecture tooling, and living documentation. Exclude vendor,
   Nix store, build caches, browser artifacts, and production data.

Run the safe inventory collector:

```bash
bash .pi/skills/maintenance-audit/scripts/collect-inventory.sh
```

It prints its output directory. Never treat its rankings as findings without
reading the code.

Suggested run-directory files:

```text
run.md                    scope, baseline, commands, baseline failures
findings.md               evidence register, not a committed tracker
source-of-truth-map.md    canonical declarations and projections
issue-plan.json           draft declarative GitHub plan
inventory/                optional additional bounded command output
```

## 2. Inspect existing ownership

Before creating an epic:

- inspect open maintenance/refactor/architecture issues and their native
  relationships;
- inspect recently closed audits for still-relevant evidence, but remeasure it;
- read maintenance/backlog workstreams and archived plans only when linked;
- search issue titles and bodies for each candidate before proposing a new
  issue;
- decide whether this cycle refreshes, supersedes, or nests under an existing
  tracker.

Do not inherit an old finding merely because it was once true. Do not create a
parallel tracker for work already owned elsewhere. Link or block on existing
issues when ownership is still current.

## 3. Create the epic and worktree

There are two supported sequences.

### Preferred when a dedicated workspace is required immediately

1. Draft a provisional parent epic containing audit outcome, target branch,
   baseline SHA, behavior-preservation guardrails, scan scope, and the statement
   that children will be reconciled after evidence collection.
2. Validate it with `github_issue_plan` using a stable run key and `apply: false`.
3. Present the dry run. Apply only after explicit user approval.
4. Once the parent number exists, inspect existing paths/branches and create a
   sibling worktree. Derive names from the issue number; do not assume the
   target branch is `main`:

   ```bash
   git worktree add ../ihp-roster-epic-N -b epic-N TARGET_BRANCH
   cd ../ihp-roster-epic-N
   bash ./bin/in-env epic-worktree register --epic N --target TARGET_BRANCH
   bash ./bin/in-env epic-worktree orient
   ```

   `epic-worktree register` registers an existing Git worktree; it does not
   create one.
5. Present orientation and wait for explicit approval to conduct the audit in
   the registered workspace.
6. Reconcile the same stable-key issue plan after the scan; do not create a
   second parent.

### Alternative when the user wants findings before tracker mutation

Perform a read-only scan in the clean target checkout, publish the finalized
parent and children after approval, then create/register the epic worktree. Do
not make code changes in the target checkout.

Never use a raw worktree as a substitute for repository registration. Never
synchronize, integrate, or clean up an epic workspace implicitly.

## 4. Record baseline health

A baseline distinguishes inherited failures from regressions. Record exact
commands, commit, environment, and outcomes.

Start with bounded checks and current repository guidance. Typical commands are:

```bash
bash ./bin/in-env verify-fast
bash ./bin/in-env ./bin/doc-drift-check
```

Use `run_worker` for noisy compile/test/build commands. Do not run wrappers
concurrently. Run `verify-full` only when justified and with awareness of the
repository's memory guidance. If baseline checks fail:

- capture concise failure evidence;
- decide whether the audit can continue structurally;
- do not promise clean before/after equivalence against an unknown baseline;
- create a separate bug/tooling issue only if the user wants it tracked.

Inspect project-defined architecture capabilities before ad hoc greps. At
minimum, use the available equivalents of:

- hotspot/refactoring radar;
- architecture convention report;
- generated-contract report;
- module neighborhoods for top candidates;
- focused controller/request-flow/table queries where relevant.

Architecture output is evidence with provenance and confidence, not an oracle.

## 5. Perform the broad pass

Cover every material top-level area. For each area:

1. Read its nearest local instructions and living contract.
2. Inspect module/file shape, public interface, imports, callers, tests, and
   generated relationships.
3. Sample both high-ranked hotspots and ordinary files; ranking tools miss
   semantic duplication and bad seams.
4. Trace representative end-to-end paths instead of reviewing files in
   isolation.
5. Review recent churn and co-located changes. Repeated shotgun edits are often
   stronger evidence than line count.
6. Record candidates using the evidence format below.

Recommended passes:

- schema, migrations, generated Haskell types, persistence modules;
- domain/application helpers and cross-cutting policy;
- routes, front controller, controllers, feature modules, views/layout;
- Haskell-owned frontend contracts, generated TypeScript, authored TypeScript,
  checked-in static output, CSS ownership;
- Hspec support/fixtures/specs, Playwright support/specs, architecture tests;
- Nix/scripts/Makefile/verification/documentation navigation.

## 6. Perform the architecture-derivation pass

Build the source-of-truth map described in `architecture-drift.md`. For every
closed-world concept encountered, ask:

- Where is it declared canonically?
- Which representations should be generated or derived?
- Which manual copies are intentionally independent?
- What happens when a new constructor, field, route, role, surface, or enum is
  added?
- Does the compiler/generator/check fail, or can consumers silently drift?
- Do tests verify behavior independently or merely copy implementation strings?

Trace suspicious literals back to their owner before proposing an abstraction.

## 7. Validate each candidate

A candidate becomes a finding only after checking:

- exact paths and representative line ranges;
- all meaningful callers/references, preferably with LSP/structural tools;
- local docs and intentional exceptions;
- relevant tests and current behavior contract;
- recent history/churn where useful;
- whether an existing helper/DSL already owns the behavior;
- whether the proposed seam has real variation or merely speculative adapters;
- whether behavior equivalence can be demonstrated.

Evidence-register entry:

```markdown
## F-NN — Short name
- Category:
- Paths/callers:
- Concrete evidence:
- Current source of truth:
- Drift or maintenance mechanism:
- Proposed module/seam direction:
- Behavior-preservation risks:
- Verification:
- Existing issue overlap:
- Confidence: high | medium | low
- Disposition: issue | merge-with | defer | bug/feature-separate | no-action
```

Record rejected candidates too, briefly. This prevents repeated rediscovery and
helps calibrate future scans, but keep the register ephemeral.

## 8. Triage and design the issue graph

Use `prioritization.md`. Cluster findings by stable behavior seam, not by smell
word or arbitrary file-size threshold. Each child must be independently
reviewable and have:

- concrete evidence;
- a proposed direction rather than an unvalidated implementation mandate;
- behavior-preservation contract and non-goals;
- affected living docs;
- focused and integration verification;
- blockers and ordering only when technically real.

Do not create one issue per tiny duplicate. Do not create a giant "clean up
module" child with no stopping rule.

## 9. Publish through a declarative plan

1. Use one stable plan key for the entire cycle.
2. Draft the parent and all accepted children using the templates.
3. Re-check every candidate against current GitHub ownership.
4. Validate the complete plan with `github_issue_plan`, `apply: false`.
5. Present issue count, titles, hierarchy, blockers, labels, and any warnings.
6. Apply only after explicit approval.
7. Publish/verify native parent and blocker relationships with dry runs first
   where separate relationship operations are required.
8. Inspect the resulting parent and a sample of children to confirm markers and
   bodies reconciled correctly.
9. Update the maintenance workstream to link the new live epic and remove stale
   live-tracker references. Do not copy issue status into the workstream.

## 10. Hand off and improve the process

From the registered epic worktree:

```bash
bash ./bin/in-env epic-worktree orient
```

Present ready, active/interrupted, and blocked lanes. Wait for the user to choose
work. Do not assign, start, move, or close issues automatically.

After the cycle, perform a short process retrospective:

- add newly proven smell prompts to this skill;
- simplify steps that produced noise;
- turn stable objective rules into architecture/verification checks;
- keep subjective heuristics periodic rather than gating;
- move implemented subsystem truths to local living docs;
- keep temporary scan evidence uncommitted.
