# Managed E2E And Development Runtime — Issue #213

Status: implemented and measured 2026-07-30

## Selected Layout

Hspec, E2E, and development have distinct UID/check-out-hash identities:

- `/tmp/bepis-hspec-postgres-<uid>-<checkout>/`: disposable Hspec PostgreSQL;
- `/tmp/bepis-e2e-postgres-<uid>-<checkout>/`: disposable E2E PostgreSQL;
- `/tmp/bepis-dev-postgres-<uid>-<checkout>/`: durable-settings development PostgreSQL;
- `/tmp/bepis-e2e-runtime-<uid>-<checkout>/`: E2E locks, run builds, PIDs, logs, and test results;
- `/tmp/bepis-dev-runtime-<uid>-<checkout>/`: managed development PIDs, sockets, and logs.

Every removable root has a same-UID, canonical-checkout ownership marker,
rejects symlink/non-native state, and refuses broad roots. E2E's reusable
coordination directory is bounded to 100 zero-length port-lock files; these are
stable lock identities, not per-run artifacts. Per-run lock files and run
payloads are reclaimed. PostgreSQL lifecycle
is serialized with `flock`. The development profile uses `fsync=on`,
`synchronous_commit=on`, and `full_page_writes=on`; healthy stop/start preserves
its data. Hspec and E2E use disposable settings and remain separate.

E2E shares one private postmaster inside a checkout but creates unique
run/shard databases. Every simultaneous E2E run holds a shared lifecycle lock,
allocates an exclusive runtime port block, and uses its own app, Stripe mock,
MailHog, build, logs, and report merge directory. Cleanup requires the exclusive
lifecycle lock. Different worktrees derive different PostgreSQL, runtime, and
port authorities from their canonical paths and registered workspace slots.

Merged Playwright HTML is the only normal durable E2E output copied back to
`.devenv/e2e/<run-id>/`; `.devenv/e2e/latest-report` points to it. Successful
runs remove their volatile runtime directory, and the last concurrent run stops
and removes disposable E2E PostgreSQL data. A failed run first copies logs and test
results to `.devenv/e2e/<run-id>/failure`, then remains inspectable through
`e2e-runtime` until the next run automatically removes inactive native runtime
or an operator applies dry-run-first cleanup. The durable failure bundle remains
on checkout storage. `E2E_KEEP_RUNTIME=1` is the explicit successful-run
diagnostic override.

## Operator Interface

```bash
# E2E PostgreSQL
e2e-postgres ensure|status|root|shell|log|recreate|stop
e2e-postgres cleanup              # dry run
e2e-postgres cleanup --apply

# E2E volatile runs
e2e-runtime root|status|runs
e2e-runtime log RUN_ID 100
e2e-runtime cleanup               # dry run
e2e-runtime cleanup --apply

# Development PostgreSQL
dev-postgres ensure|status|root|shell|log|recreate|stop
dev-postgres legacy-status
dev-postgres acknowledge-legacy

# Development app/runtime
dev-workspace-info
dev-start && dev-wait
dev-status
dev-stop
```

Managed mode ignores inherited `PGHOST`. External authority requires either
`E2E_POSTGRES_MODE=external` with absolute `E2E_DB_SOCKET`, or
`DEV_POSTGRES_MODE=external` with absolute `DEV_POSTGRES_SOCKET`. Recreate and
cleanup are refused for external E2E; development recreate is refused and stop
leaves the external server untouched.

The shell now evaluates `dev-workspace-info --shell` after `.env`, so generic
`psql` and IHP tooling resolve the same development socket as `dev-start`.

## Existing Development Data

No `.devenv/postgres` or `.devenv/state/postgres` directory is deleted, moved,
or rewritten. `dev-postgres ensure` warns while legacy state exists and remains
unreviewed. README documents explicit `pg_dump`/`pg_restore`, rollback through
external mode, and acknowledgement. The managed development cluster survives a
healthy stop/start but can be removed by reboot or `/tmp` cleanup; operators
must export data they need to retain beyond temporary-storage lifetime.

A lifecycle probe wrote a row, stopped PostgreSQL, restarted it, and read the
same row successfully. `dev-stop` stopped owned app/watch/MailHog/PostgreSQL
processes while retaining the data directory.

## Before/After Measurements

This host mounts the checkout on native Btrfs rather than the virtiofs host from
#200; `/tmp` is tmpfs. The recorded mount probe was:

```text
$ findmnt -T "$PWD" -no TARGET,FSTYPE,SOURCE,OPTIONS
/home btrfs /dev/sda2[/home] rw,relatime,ssd,discard=async,space_cache=v2,subvolid=256,subvol=/home

$ findmnt -T /tmp/bepis-e2e-postgres-1000-9bcdfd5705ad -no TARGET,FSTYPE,SOURCE,OPTIONS
/tmp tmpfs tmpfs rw,nosuid,nodev,size=32876864k

$ findmnt -T /tmp/bepis-e2e-runtime-1000-9bcdfd5705ad -no TARGET,FSTYPE,SOURCE,OPTIONS
/tmp tmpfs tmpfs rw,nosuid,nodev,size=32876864k

$ findmnt -T /tmp/bepis-dev-postgres-1000-9bcdfd5705ad -no TARGET,FSTYPE,SOURCE,OPTIONS
/tmp tmpfs tmpfs rw,nosuid,nodev,size=32876864k

$ findmnt -T /tmp/bepis-dev-runtime-1000-9bcdfd5705ad -no TARGET,FSTYPE,SOURCE,OPTIONS
/tmp tmpfs tmpfs rw,nosuid,nodev,size=32876864k
```

Results therefore demonstrate bounded benefit even before the expected larger
virtual-filesystem difference.

| Measurement | Checkout/Btrfs | Managed `/tmp` | Change |
| --- | ---: | ---: | ---: |
| E2E reset median, 10 runs | 0.302369s | 0.271776s | -10.1% |
| E2E reset p95 | 0.309456s | 0.289591s | -6.4% |
| Dev first startup-to-ready | 77.741s | 68.897s | -11.4% |
| Dev later startup-to-ready | — | 55.741s | warm observation |
| `/NewSession` median, 20 requests | 0.000498s | 0.000328s | -34.1% |
| `/NewSession` p95 | 0.000916s | 0.000783s | -14.5% |

Startup observations are single runs with different compiler-cache state and
are not regression thresholds. They show that PostgreSQL is no longer the
critical path: development startup is dominated by IHP/GHC loading, while the
complete default-sharded E2E wall is dominated by Playwright browser work.

The original focused E2E baseline could not reach Playwright because the local
pinned npm modules were absent; after `npm ci`, the old single-shard dev-server
path also exceeded its 120-second readiness budget. The final compiled focused
path passed four tests in 20.924 seconds. The complete final default path passed
209 tests in 105.0 seconds; its critical shard took about 1.5 minutes.

## Concurrency And Cleanup Evidence

- Two simultaneous focused E2E runs passed 4/4 each with distinct run IDs,
  databases, port slots, app ports, MailHog ports, and report directories.
- Development, DB-backed Hspec, and focused E2E ran together in one checkout:
  dev remained healthy, E2E passed 4/4, Hspec passed 1/1, and all three used
  distinct PostgreSQL roots.
- The two-worktree acceptance test passed independent app/MailHog ports,
  development runtime roots, development/E2E/Hspec PostgreSQL roots, same-named
  `app` data, stop independence, symlink refusal, and cleanup.
- Process-group interruption removed the interrupted E2E shard database and
  left no app, Stripe mock, MailHog listener, or active lifecycle lock.
- Post-run inspection found no `app_e2e_*` databases or E2E server/mock process.
- Successful-run reclamation reduced accumulated E2E tmpfs runtime from
  1,707,100,582 bytes to 51 bytes, left zero run directories, stopped the
  disposable E2E postmaster, reduced its managed root to 4 KiB, and preserved
  `.devenv/e2e/latest-report/index.html`.
- Manual runtime and PostgreSQL cleanup remain dry-run-first and refuse cleanup
  while an E2E run holds the shared lifecycle lock.

The first direct-PID cancellation probe killed only the generated command
wrapper; the underlying test completed and cleaned itself shortly afterward.
Terminal and CI cancellation signal the process group, which is the supported
probe and cleaned correctly. Parent and shard scripts also trap normal
INT/TERM/EXIT and explicitly terminate their owned children.

## Complete Acceptance

- Serial complete E2E: 209 tests, zero failures, two retry-passing flaky tests,
  8m35s.
- Default eight-shard complete E2E: 209 passed, zero failures/flakes, 105.0s.
- Default E2E used eight unique shard databases and app ports 10180–10250 in an
  exclusive run port slot.
- Focused E2E failure exposed an obsolete partial MA000009 seed. The fixture now
  carries all seven canonical classifications, both employment bases, all four
  rate kinds, both additions, recent validated FWC provenance, and statewide
  DataVic target-year provenance. Approval coverage passes.
- Tests that mutate Alpha staff preferred/name state now restore it; the roster
  settings interaction retries the concrete tab activation contract rather
  than racing a passive fragment replacement. A four-file serial regression
  group passes 18/18.
- `dev-start`/`dev-wait`, status, shell, stop/start persistence, external-mode
  authority/refusal, script freshness, frontend contracts/type/unit checks,
  and cross-worktree concurrency all pass.
