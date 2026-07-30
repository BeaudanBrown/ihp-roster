---
name: maintenance-audit
description: Run the explicitly requested periodic Bepis maintainability, agent-navigability, and architecture-drift audit; create or reconcile its GitHub epic and registered epic worktree from evidence.
disable-model-invocation: true
compatibility: Requires the ihp-roster repository, Git, repository Nix wrappers, and authenticated current-repository GitHub issue tools.
---

# Maintenance Audit

Run a repeatable, evidence-led repository scan. The outcome is a prioritized
GitHub epic and native sub-issue graph for behavior-preserving maintenance—not
an opportunistic refactor and not a parallel Markdown backlog.

Invoke explicitly:

```text
/skill:maintenance-audit start [target-branch]
/skill:maintenance-audit resume <run-directory>
```

Arguments are guidance, not trusted shell input. Derive and validate paths,
branches, issue numbers, and repository identity before using them.

## Non-negotiable contract

- Preserve application behavior. Do not mix bug fixes, product changes, schema
  redesign, visual changes, or dependency upgrades into refactor issues.
- Scan before implementing. During audit mode, only audit artifacts, the
  tracker plan, worktree registration, this playbook, and minimal live
  workstream routing links may change.
- Treat code, schema, generated types, migrations, and passing tests as the
  implemented source of truth. Follow the repository's documented precedence.
- Read the nearest `AGENTS.md`, `README.md`, and `SPEC.md` before judging a
  subsystem. A local exception may be intentional architecture.
- Inspect existing GitHub issues before creating replacements. Closed audits
  are evidence, not automatically current work.
- Use typed GitHub issue tools. Dry-run every mutation and relationship first;
  apply only after the user approves the reviewed plan.
- In a checkout containing `.bepis-epic-worktree.json`, run
  `bash ./bin/in-env epic-worktree orient` first, present its frontier, and obey
  its wait/approval instructions.
- Do not edit generated output manually, production/customer data, or Nix store
  files. Do not run destructive database commands for an audit.
- Do not turn every heuristic into CI. Promote only stable, low-noise,
  architecture-owned invariants.

## Required reading

Read these references before their corresponding phase:

1. [End-to-end process](references/scan-process.md)
2. [Smell catalog](references/smell-catalog.md)
3. [Architecture drift](references/architecture-drift.md)
4. [Prioritization and slicing](references/prioritization.md)
5. [Verification and issue design](references/verification-and-issues.md)

Use [the epic template](templates/epic.md) and
[the subissue template](templates/subissue.md) when drafting the declarative
GitHub issue plan.

## Execution summary

1. Establish repository, target branch, baseline commit, scope, and an ignored
   run directory under `.pi/tmp/maintenance-audit/`.
2. Inspect current instructions, architecture tooling, workstreams, and open or
   recently closed maintenance issues. Avoid duplicate tracking.
3. If the user wants isolation from the start, dry-run and publish a provisional
   parent epic, create its Git worktree, register it, orient, present the
   frontier, and obtain approval to continue the audit there.
4. Record baseline health. Run the inventory collector and current architecture
   hotspot/convention/contract queries. Use focused checks before expensive
   gates.
5. Walk every material subsystem, not only large files. Trace representative
   request, domain, persistence, rendering, frontend, and test paths.
6. Maintain an evidence register and a source-of-truth/derivation map in the
   ignored run directory. Validate candidates against callers, tests, history,
   and local documentation.
7. Separate behavior bugs and feature requests from refactor findings. Report
   them, but do not disguise them as maintenance.
8. Rank and cluster findings around stable modules and seams. Prefer deep
   modules, locality, independently mergeable slices, and explicit non-goals.
9. Finalize a stable-key declarative issue plan. Include the parent epic,
   subissues, blockers, shared guardrails, and verification. Dry-run the whole
   graph, show it to the user, then apply only after approval.
10. Reconcile the maintenance workstream link, run orientation, present the
    ready frontier, and wait. Never select or begin a subissue automatically.
11. At the end of the cycle, improve this skill from observed process gaps and
    convert proven objective invariants into deterministic checks.

## Audit outputs

Keep these concerns separate:

- **Reusable process:** this committed skill.
- **Live status and dependencies:** GitHub parent/subissues and native
  relationships.
- **Ephemeral evidence:** `.pi/tmp/maintenance-audit/<run-id>/` (ignored).
- **Implemented architectural truth:** code-adjacent `README.md`, `SPEC.md`, and
  `AGENTS.md`, plus ADRs where rationale must persist.
- **Mechanical drift prevention:** existing verification or
  `.pi/architecture.json` commands/queries.

Never commit the evidence register as a second task tracker. Closed GitHub audit
cycles provide the historical record.

## Stop conditions

Stop and ask the user when:

- baseline failures make before/after claims unreliable;
- an apparent refactor requires observable behavior, schema, migration, auth,
  compliance, or public-contract changes;
- existing issue ownership conflicts with the proposed graph;
- worktree registration, synchronization, integration, or cleanup needs
  approval;
- the scan cannot produce concrete evidence or a credible verification plan for
  a proposed issue.
