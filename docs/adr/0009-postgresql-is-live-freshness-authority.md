# ADR 0009: PostgreSQL Is Live Freshness Authority

Date: 2026-08-20

## Context

A process-local publish path can make the writer's subscribers fresh while a
worker, another app process, a disconnected listener, or a restarting process
misses the same business change. Minting local versions also makes reconnect
correctness depend on which process handled the mutation.

## Decision

Every live-visible write commits its business/domain/audit changes, one ordered
outbox event, typed resource children, and current resource versions in one
PostgreSQL transaction. PostgreSQL is the only live freshness and version
authority.

Producers cannot publish after commit, mint process-local versions, or broadcast
directly to local subscribers. Each app process runs a durable listener that
hydrates current resource versions on every connection, replays retained events
in order, and dispatches explicit database sequence numbers through its local
subscription/socket hub. The hub retains only subscriptions and observed
sequence numbers needed for duplicate/out-of-order suppression and delivery.

Outbox history is retained for at least seven days. Current resource versions
are retained independently and indefinitely, so reconnect after pruning still
forces an authoritative fragment resync.

## Consequences

Worker and web producers use one mutation contract; multiple listeners and
at-least-once replay are safe. A database publication failure rolls back the
business write. Process-local delivery may be asynchronous after commit, so
actor responses use declared actor refresh metadata rather than relying on a
writer-local passive broadcast. Listener health and outbox retention become
operational requirements.

## Alternatives Considered

- Publish to the writer's in-memory hub after commit: rejected because a crash
  or another process can silently miss freshness.
- Use process-local counters plus WebSocket reconnect: rejected because counters
  are not shared or restart-safe.
- Retain outbox events forever: rejected because independent current versions
  provide freshness authority after bounded history pruning.

## Links

- Tickets: #383, #387, #388, #389, #390, #391
- Workstreams: None
- Living docs: `Application/Helper/LiveUpdate.SPEC.md`,
  `docs/runbooks/live-invalidation-outbox-pruning.md`
