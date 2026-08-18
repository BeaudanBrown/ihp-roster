# Live invalidation outbox pruning

The durable live-invalidation outbox retains event replay history for seven days.
`live_resource_versions` is independent authority and is never pruned by this
service, so a process reconnecting after the replay window rehydrates current
resource versions and forces authoritative fragment resync where needed.

## Approval and backup preflight

Deleting expired event rows is intentional and irreversible. Before first
enablement, a named operator must approve the #387 retention change, record the
normal full-database backup identifier, and verify that backup by restoring it
to an isolated database. Do not enable the timer from a backup that has only
been listed but not restored.

Using the deployment's existing secured database environment and backup store:

```bash
pg_dump --format=custom --dbname="$DATABASE_URL" --file="$SECURE_BACKUP_PATH"
pg_restore --list "$SECURE_BACKUP_PATH" >/dev/null
createdb "$ISOLATED_RESTORE_DATABASE"
pg_restore --exit-on-error --single-transaction \
  --dbname="$ISOLATED_RESTORE_DATABASE" "$SECURE_BACKUP_PATH"
psql --dbname="$ISOLATED_RESTORE_DATABASE" --command='SELECT count(*) FROM live_invalidation_events; SELECT count(*) FROM live_resource_versions;'
dropdb "$ISOLATED_RESTORE_DATABASE"
```

Keep paths, URLs, counts, and approval evidence in the private operator record,
not this repository. Confirm the isolated restore contains both outbox and
resource-version tables and that normal schema readiness succeeds against it.

## Deployment

Enable the app-owned NixOS timer with the database service user:

```nix
services.ihpRoster = {
  serviceUser = "ihp-roster";
  liveInvalidations.outboxPruning = {
    enable = true;
    retentionDays = 7;
    batchSize = 1000;
    onCalendar = "daily";
    randomizedDelaySec = "30m";
  };
};
```

The private deployment repository at `~/documents/bepis-dotfiles/` must apply
the equivalent options to both production and its staging-prefixed
`services.ihpRoster` configuration. Keep database URLs, credentials, and private
SQL in that repository's existing secret/configuration seams; do not copy them
into this repository.

The persistent timer runs `LiveInvalidationOutboxPrune` after schema readiness,
outside request traffic and the application worker queue. Each transaction
deletes at most 1,000 oldest expired event headers. Event-resource children
cascade; current resource versions remain.

## Observe and diagnose

```bash
systemctl status live-invalidation-outbox-prune.timer
systemctl status live-invalidation-outbox-prune.service
systemctl list-timers live-invalidation-outbox-prune.timer
journalctl -u live-invalidation-outbox-prune.service
```

Each successful invocation emits one bounded `live_invalidation_outbox_prune`
line containing deleted and remaining-expired counts, completed batches, oldest
remaining event, exact table cardinalities, and relation sizes. Retry lines
contain only the bounded attempt number. No resource payload, key, venue,
provider, or user data is logged.

A non-zero remaining-expired count means locked rows were skipped or concurrent
work arrived at the cutoff. The persistent daily timer retries safely. Repeated
failure requires checking PostgreSQL lock/statement timeout evidence and table
size before manually starting the same unit; do not run ad-hoc deletion SQL.

## Disable or recover

Disable the timer, not the application listener, when investigating:

```bash
systemctl stop live-invalidation-outbox-prune.timer
systemctl disable live-invalidation-outbox-prune.timer
```

Pruning is irreversible for historical event headers, but does not remove
freshness authority. Recovery after any long listener outage is restart/reconnect:
the listener rehydrates `live_resource_versions`, then resumes ordered replay
from the retained frontier. Do not reconstruct deleted events or clear current
versions.

If pruning exposes a broader database-integrity failure, stop app/worker writes
and the timer, then use the deployment's normal disaster-recovery procedure to
restore the verified full backup as one consistent database. Never selectively
restore event rows into a live database: sequence, version, and business state
could disagree. Re-deploy the matching application revision, run schema
readiness, verify resource-version cardinality, and only then resume traffic.
