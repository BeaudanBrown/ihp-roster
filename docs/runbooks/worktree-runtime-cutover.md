# Cut over a worktree registry from v1 to v2

This is a one-time, **offline local development** procedure for a repository
that already has a v1 epic registry. It is not part of shell entry or workspace
startup. It does not change Git branches, copy PostgreSQL data, or touch staging
or production. Run only with operator approval. A fresh repository with no v1
registry needs no import; use only updated tooling there.

## Quiesce and inventory

1. Pause automation and coordinate with everyone using this Git common
   directory. Do not provision, remove, move, start, or reset any worktree
   until validation is complete. Stop development stacks and finish or stop
   browser/test/profile runners through their owning commands **before**
   updating the old checkouts. End old shells and any background launchers
   holding previously resolved settings. A registry lock by itself cannot
   drain an already running process or fence an old primary checkout, which
   can resolve slot 0 without reading the registry.
2. From the primary checkout, get its canonical Git common directory with
   `realpath -- "$(git rev-parse --path-format=absolute --git-common-dir)"`.
   The registry and lock are `bepis/epic-worktrees/registry.json` and
   `bepis/epic-worktrees/registry.lock` beneath it. Retain a protected,
   byte-for-byte backup of the v1 registry and record `git worktree list
   --porcelain`. Verify the registry owner matches the canonical Git common
   directory. Keep the backup outside every checkout. Never move the old file
   out of its live path: the v1 writer treats a missing registry as empty.
3. Record each existing runtime's path, slot, effective port offset, service
   ports, state directory, and PostgreSQL mode, root and socket. Prefer the
   configuration that actually ran, including `.env` and local overrides.
   The old `dev-workspace-info --json` is useful in each old checkout with its
   usual configuration, but it can create a state directory. Use `--shell`
   output or verified service configuration for ports absent from the JSON.
   Use existing evidence for unavailable worktrees and settings that changed. Do not
   record an external PostgreSQL root as managed, start or stop its server,
   or delete any database or runtime directories.
4. Verify quiescence, not just the absence of a PID file. Account for managed
   PostgreSQL, service process groups, and live runner leases; inspect the
   expected listeners. An unowned, unreadable, or ambiguous process is not
   proof of absence. Never signal a process based only on a PID, a listener,
   or a matching working directory. If evidence is ambiguous, stop the cutover.

Keep existing epic identity markers; they still identify epic metadata. Do not
update or delete them as part of this import.

## Stage and publish

Create a private `runtime.json` containing an array with one entry per v1
record. Copy `path` and `slot` exactly; use the observed `portOffset` and all
verified managed evidence locations in the two arrays. The arrays may be
empty for a worktree confirmed never started. Include the primary checkout
with slot `0` if it has existing runtime settings; do not omit a custom
primary offset. Example row:

```json
{
  "path": "/absolute/checkout/feature",
  "slot": 2,
  "portOffset": 0,
  "stateDirectories": ["/absolute/owned/runtime-state"],
  "managedPostgresRoots": ["/absolute/owned/postgres-data"]
}
```

Do not silently drop stale epic records or invent their offset or evidence
paths. Resolve missing evidence before importing. Duplicate slots and shared
state paths are invalid. Inventory any existing port overlaps and record
which stacks cannot run together; do not change their ports or PostgreSQL
configuration during import. For example, at offset zero, slot 1’s OTLP/gRPC
and slot 0’s OTLP/HTTP both use port 4318. Import preserves those assignments;
new allocations avoid all reserved ports.

Prepare the candidate beside the protected backup. Set `common`, `v1_backup`,
`runtime_json`, and `candidate` to verified absolute paths. Use a new candidate
path; never write directly to the live registry:

```bash
jq -e --arg common "$common" --slurpfile reservations "$runtime_json" \
  'select(.version == 1 and .commonGitDir == $common)
   | select(($reservations | length) == 1 and ($reservations[0] | type) == "array")
   | .version = 2 | .runtime = $reservations[0]' "$v1_backup" > "$candidate"
```

Review the candidate. With the operator barrier still in place, replace the
live file atomically under the **existing** lock; never unlink or replace
that lock. Compare the live bytes with the backup under lock first:

```bash
(
  set -euo pipefail
  umask 077
  registry_dir="${common:?}/bepis/epic-worktrees"
  registry="$registry_dir/registry.json"
  lock="$registry_dir/registry.lock"
  test "$(realpath -- "$registry_dir")" = "$registry_dir"
  test -f "$registry" && test ! -L "$registry" || exit 1
  test -f "$lock" && test ! -L "$lock" || exit 1
  exec 9<>"$lock"
  flock -x 9
  cmp -s -- "$registry" "${v1_backup:?}"
  pending="$(mktemp -- "$registry_dir/.registry.cutover.XXXXXXXX")"
  cp -- "${candidate:?}" "$pending"
  sync -f -- "$pending"
  mv -fT -- "$pending" "$registry"
  sync -f -- "$registry_dir"
)
```

The version change at the same path makes old registry readers and allocators
fail closed. Do not try to start an old checkout to verify this. Before lifting
the operator barrier, update the primary and surviving worktrees, then use the
new `workspace info --json` via `bin/tooling-run` in each preserved checkout
with its normal configuration. Compare slot, ports, state path and PostgreSQL
root/socket to the pre-cutover inventory. An epic's metadata should also
resolve through the updated `epic-worktree resolve`. Do not invoke `workspace
runtime` during validation: it allocates and takes the registry lock. Keep
older checkouts offline until updated.

## Abort or recover

If preflight fails, do not publish or enable new starts. If validation fails
after publication, keep all starts and registry writers paused. To roll back
**before any v2 allocation or runtime start**, compare the live registry with
the published candidate under the same lock, then atomically restore the
byte-for-byte v1 backup by reversing source and expected-live file in the
publication procedure. Return to the old tooling as a unit. If anything
changed or started under v2, do not restore v1 blindly: first quiesce again
and reconcile any new allocations. The backup is recovery evidence, not a
second live registry.

For the active schema, see [workspace state](<../../tooling/workspace-state/src/Bepis/Tooling/Workspace/State.hs>).
