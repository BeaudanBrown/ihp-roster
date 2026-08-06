# ADR 0001: Documentation Operating Model

Status: superseded

Date: 2026-05-02

Superseded: 2026-08-06 by the `docs/README.md` retention model in issue #278.

## Context

The repository had several overlapping documentation layers: root agent
instructions, product specs, numbered plan files, tickets, and scattered local
guides. The numbered plans mixed future tasks, current behavior, historical
decisions, and stale status. That made agents read too much context and made it
hard to tell whether a statement described implemented behavior or future work.

## Decision

Use code-adjacent living docs for implemented behavior and keep future work in
explicit workstreams.

- `README.md`, `SPEC.md`, and `AGENTS.md` next to code describe current
  subsystem behavior and local editing rules.
- `docs/workstreams/` describes future or partial feature streams and links to
  GitHub Issues.
- `docs/adr/` records durable architecture decisions.
- GitHub Issues is the live implementation graph.
- Old numbered plans move to `docs/archive/plans/` as historical context.

## Consequences

Agents should read less global prose before changing code. Future features can
still have structured design notes, but they must name the living docs they will
update as slices land. Implemented behavior should not live only in a
workstream.

The cost is discipline: closing a feature stream now includes documentation
reconciliation, not just passing tests.

## Alternatives Considered

- Keep numbered plans as the main design layer. Rejected because status and
  behavior drift had already accumulated.
- Put all docs under a central `docs/` tree. Rejected because agents work more
  reliably when local rules are near the files they govern.
- Keep everything in root `AGENTS.md`. Rejected because large always-loaded
  instruction files are harder for agents to follow.

## Links

- `docs/README.md`
- `docs/workstreams/README.md`
