# Documentation Retention Model

Code, `Application/Schema.sql`, types, tests, generated contracts, and
deterministic checks are authoritative for implemented behavior. Prose should
help a reader navigate those sources or preserve information they cannot show.
It must not mirror discoverable implementation details.

## Document Roles

- `AGENTS.md`: actionable local editing constraints, non-obvious hazards,
  source pointers, and verification commands.
- `README.md`: subsystem ownership, boundaries, and entry points.
- `SPEC.md`: durable cross-module invariants and externally observable
  contracts that code alone does not make clear.
- `specs/`: cross-cutting product, domain, legal, compliance, and acceptance
  intent, including intent not yet implemented.
- `docs/adr/`: why a consequential decision was made and what it constrains.
- `docs/workstreams/`: unresolved design and integration intent for work not
  fully implemented; each workstream links to its GitHub issues.
- `docs/runbooks/` and subsystem runbooks: exact operator procedures,
  diagnostics, recovery, and rollback.
- GitHub Issues: live scope, status, dependencies, findings, and next actions.
- `docs/archive/`: evidence or historical context with an identified continuing
  use. Git history is the default archive for superseded repository prose.

## Retention Rubric

Retain prose only when it provides durable navigation, ownership, a non-obvious
invariant, consequential rationale, product/compliance intent, or an operating
procedure. Prefer a link to an authoritative source over a field, action,
helper, file, or test inventory.

Remove prose that narrates implementation, duplicates parent instructions,
tracks work or completion, records generated counts, or preserves history
already available in Git. Do not move removed narration into another document.

Update documentation only when a retained navigation path, invariant,
rationale, or operating procedure changes. An implementation change by itself
does not require a prose mirror.

Legal, compliance, security, tenancy, migration, financial, and externally
sourced evidence must not be weakened or deleted without issue-specific review
and evidence that its obligation or retention value has ended.

Keep inventories, audit findings, and other disposable analysis under
`.pi/tmp/`; do not commit them as reports or parallel trackers. Reviewed bounded
machine-readable baselines consumed by deterministic regression tooling are
configuration and stay beside that tooling rather than under `docs/`.
