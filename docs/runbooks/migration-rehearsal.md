# Migration Rehearsal

Use this workflow to obtain advisory upgrade evidence for a candidate Bepis
commit. It never connects to development, staging, or production PostgreSQL and
does not activate a deployment.

## Operator command

Read the deployed `ihp-roster` revision from the private deployment lock, then
run the candidate checkout against it:

```bash
PRODUCTION_REVISION="$(jq -er '.nodes[.nodes.root.inputs["ihp-roster"]].locked.rev' ~/documents/bepis-dotfiles/flake.lock)"
bash ./bin/in-env migration-rehearsal --from-ref "$PRODUCTION_REVISION" --keep-failure-artifacts
```

Run from a clean candidate checkout containing the production revision in Git
history. The harness rejects external PostgreSQL modes and caller-supplied
database targets. It reports `predecessor_commit` and `candidate_commit`; retain
those SHAs with the operator evidence.

The production repository may rename its lock node in future. If the `jq`
lookup fails, inspect that repository's `flake.lock` and substitute the revision
which pins this `ihp-roster` input; do not substitute the IHP framework revision
or a branch name.

## Evidence and diagnosis

A warm rehearsal normally completes in under 60 seconds. Cold CI targets under
90 seconds after existing Nix realization. The harness owns two uniquely named
databases in its managed disposable PostgreSQL profile and drops both on
success, failure, or interruption.

With `--keep-failure-artifacts`, failure evidence is retained under:

```text
.pi/tmp/migration-rehearsal/<run-id>/
```

CI uploads that bounded directory as
`migration-rehearsal-<candidate-sha>` for seven days. Output and artifacts are
bounded to 64 KiB per diagnostic log and suppress fixture rows and raw server
details. Start diagnosis from:

- `failed_revision` and `server_sqlstate`: the pinned IHP runner rejected a
  migration; `55P04` means a newly added enum value was used before its revision
  committed.
- `missing_candidate_revisions`: the runner returned without recording every
  candidate migration.
- `focused assertion failed`: inspect the named revision-owned synthetic
  assertion under `Application/Migration/Rehearsal/`.
- `schema_convergence=diverged`: inspect `schema.diff`; the upgraded database
  differs from a fresh candidate IHP plus `Application/Schema.sql` database.
- runner or IHP-source mismatch: enter the candidate's `bin/in-env` environment
  and ensure both Git revisions and their locked sources are available.

Artifacts are diagnostic evidence, not backups, and contain no production
customer rows.

## Three distinct checks

1. **Fresh-schema checks** parse current `Application/Schema.sql`, regenerate
   types, and exercise current-schema tests. They cannot prove an existing
   database upgrades through every migration revision.
2. **Migration rehearsal** reconstructs a named Git predecessor, records its
   historical revisions, runs pending revisions through the candidate-pinned
   IHP runner, executes synthetic data assertions, and compares with a fresh
   candidate schema. Pull requests use the exact current PR base SHA and
   GitHub's tested merge commit, keeping the predecessor ancestral even when the
   base advances; protected/deploy branch pushes use the pre-push SHA.
3. **`rozzy-staging-refresh-db`** in the private deployment workflow refreshes a
   production clone into staging. It is the final acceptance check for the live
   customer-data shape and operator environment. It is not the routine CI
   implementation and must retain its own access, backup, and approval controls.

A passing rehearsal is advisory evidence for the deployment operator. It does
not authorize production activation, run `nixos-rebuild`, add a production
systemd blocker, or replace `rozzy-staging-refresh-db` and the deployment
approval boundary.

## Framework rollout and rollback (IHP 1.5 to 1.6)

Local synthetic evidence is preparation, not staging acceptance. If the private
lock revision is not an ancestor of the candidate, stop the deployed-revision
rehearsal: obtain a separately approved integration decision. An ancestral
pre-upgrade revision can be tested as a **synthetic framework baseline only**;
never substitute its result for the deployed revision or infer the running
host's identity from a local lock file.

Before activation, the operator must retain:

- Exact candidate commit, optimized package store paths and closure, plus the
  actual running system generation and previous app/worker/script package paths.
  Keep both generations available; do not garbage-collect the rollback closure.
- A timestamped database backup and successful restore into a separately named,
  isolated database. Compare synthetic fixture data and sequence state locally;
  customer backup/restore needs its own approval, access and retention controls.
  Rehearsal diagnostics are not the backup.
- The unchanged session encryption secret and its provisioned location. Verify
  app and worker reference the intended `IHP_SESSION_SECRET_FILE`; do not print,
  copy into Git, or rotate the secret as a shortcut for session invalidation.

Use `production-package-smoke` and `deployment-module-check` through `bin/in-env`
for non-mutating artifact and unit-wiring checks. The reviewed script-to-consumer
mapping is in
[`production-script-inventory.tsv`](../../Config/nix/production-script-inventory.tsv).
Do not execute bootstrap or backfill entrypoints merely to test their paths.
The HTTP process no longer starts job workers; a healthy HTTP endpoint alone is
not rollout success. On the approved staging host inspect app/worker `ExecStart`,
active state and environment-file paths without dumping secret values. Verify
each enabled timer's service path and next trigger against the evaluated module.
Use mock providers and synthetic recipients for delivery checks; do not manually
fire external sweeps against live provider credentials.

### Session compatibility boundary

IHP 1.6 accepts both the old cereal-encoded login ID and its new raw UUID ASCII
login value. IHP 1.5's cereal-only authentication reader does **not** accept the
new value. Expect reauthentication after rollback for users who logged in on
1.6; do not promise transparent mixed-version sessions or alternate versions
behind a load balancer without a separately verified compatibility strategy.
The encoding characterization is retained in
[`SessionsSpec.hs`](../../Test/Controller/SessionsSpec.hs); it tests the actual
new writer, unchanged cereal reader, and the old writer's reauthentication
value. This is not an encrypted-cookie/browser rollback rehearsal.

On approved staging, retain a synthetic legacy login and a new-version login,
then exercise each before and after switching the whole app/worker generation.
Verify controlled login redirection rather than 500s, successful fresh login,
session-version revocation, passkey login and privileged step-up, venue selection,
and support/impersonation boundaries. A passkey credential in PostgreSQL is not
the same thing as a session's step-up evidence: reauthentication must not grant
stale privileged authority or delete credential registrations.

### Activation, abort and recovery

Use the private deployment workflow's reviewed generation activation and rollback
procedure on the approved host; do not improvise production activation from this
local runbook. Before starting, record the observation window and acceptable
error/queue thresholds with the operator. Keep synthetic tracing privacy checks
and the observability procedure in
[`production-observability.md`](production-observability.md) beside that evidence.

Abort for authentication 500s or authority leakage, payroll/export divergence,
worker non-delivery or failed restart recovery, missing timer wiring, database
connection exhaustion, sensitive telemetry, or success responses reported as
errors. Verify graceful termination flushes telemetry and that worker restart
recovers pending synthetic work without duplicate externally visible delivery.
Pause affected scheduled work and drain traffic using the approved host workflow
before switching app, worker and script consumers together to the retained
previous generation. Recheck login/reauthentication, authority, queue progress
and timer state before resuming work.

A framework-only change with identical application schema/migration trees and
passing schema convergence needs no invented business DDL. Confirm this again
against the **actual deployed revision**. Do not restore a pre-upgrade database
merely to roll back executables: it would discard writes since the backup.
If a real data/schema incompatibility requires restore, first stop writers,
retain the failed database, and obtain an explicit data-loss/reconciliation and
recovery decision. Any newly required DDL needs its own data-preserving migration
and reviewed rollback procedure before activation.

Staging approval, production rollout, integration, epic closure and worktree
cleanup remain separate operator decisions.

## CI scope

The `Migration rehearsal` job is visible on pull requests and pushes targeting
the repository's actual protected/deployment branches: `roster`, `staging`, and
`master`. It runs when the diff changes the application schema, migration tree,
IHP/flake pin, shared rehearsal/PostgreSQL runner, or deployment migration
module. A manual dispatch always requires an explicit predecessor revision.
