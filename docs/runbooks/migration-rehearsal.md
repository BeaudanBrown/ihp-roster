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

## CI scope

The `Migration rehearsal` job is visible on pull requests and pushes targeting
the repository's actual protected/deployment branches: `roster`, `staging`, and
`master`. It runs when the diff changes the application schema, migration tree,
IHP/flake pin, shared rehearsal/PostgreSQL runner, or deployment migration
module. A manual dispatch always requires an explicit predecessor revision.
