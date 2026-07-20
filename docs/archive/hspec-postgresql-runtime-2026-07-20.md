# Hspec PostgreSQL Runtime — Issue #200

Status: implemented and measured on 2026-07-20

Related issues: [#197](https://github.com/BeaudanBrown/ihp-roster/issues/197),
[#198](https://github.com/BeaudanBrown/ihp-roster/issues/198),
[#199](https://github.com/BeaudanBrown/ihp-roster/issues/199), and
[#200](https://github.com/BeaudanBrown/ihp-roster/issues/200)

This report records the selection evidence for the private PostgreSQL runtime
used by DB-backed Hspec. Current operating guidance lives in `Test/AGENTS.md`.
Raw benchmark artifacts remain ignored under
`output/hspec-baseline/issue-200/`.

## Selected Runtime

DB-backed `hspec-test`, `hspec-db`, and `hspec-coverage` now use a dedicated
managed PostgreSQL cluster by default:

- state root: `/tmp/bepis-hspec-postgres-<uid>-<project-id>`;
- storage on the measured host: `/dev/vda2` ext4 rather than project virtiofs;
- network exposure: none (`listen_addresses=''`) and a mode-0700 Unix socket;
- durability: `fsync=on`, `synchronous_commit=off`,
  `full_page_writes=on`;
- lifecycle: persistent while healthy for schema-template reuse, but completely
  recreated after any stop or crash;
- ownership: a marker tied to the uid and canonical checkout identity protects
  every removal.

Only commit acknowledgement is relaxed. Measurements found that it captures
most of the test-only WAL benefit while retaining filesystem synchronization
and full-page crash protection. Because all managed databases are disposable,
there is no data-recovery contract: an unavailable postmaster causes the next
`ensure` to remove the entire owned data directory and run `initdb` rather than
attempt recovery.

The normal devenv PostgreSQL instance remained at
`.devenv/state/postgres` with `fsync=on`, `synchronous_commit=on`, and
`full_page_writes=on`. External Hspec mode accepts an explicit socket but never
changes that server's settings. Production modules and configuration were not
changed.

## Reproduction Protocol

Measurements used `bin/hspec-baseline`, its host-global exclusive lock, and its
PostgreSQL/host sampling. The tool now resolves `env KEY=value` operands before
capture and prepares managed PostgreSQL before environment snapshots, ensuring
that settings, waits, and counters come from the measured server rather than
the devenv server.

Short and focused comparisons used one warm-up plus three measured runs. Full
selected-runtime verification used two serial and two six-shard complete runs.
The issue #199 virtiofs complete runs are single locked before measurements.

```bash
# Selected runtime, focused comparison
bash ./bin/in-env ./bin/hspec-baseline run \
  --name selected-feedback \
  --output output/hspec-baseline/issue-200/selected-feedback -- \
  env TEST_POSTGRES_MODE=managed \
      TEST_POSTGRES_DURABILITY=disposable \
      TEST_SHARDS=1 \
      hspec-db --match FeedbackController --format=progress --no-color

# Same managed storage with all durability enabled
bash ./bin/in-env ./bin/hspec-baseline run \
  --name durable-feedback \
  --output output/hspec-baseline/issue-200/durable-feedback -- \
  env TEST_POSTGRES_MODE=managed \
      TEST_POSTGRES_DURABILITY=durable \
      TEST_SHARDS=1 \
      hspec-db --match FeedbackController --format=progress --no-color
```

`TEST_POSTGRES_DURABILITY=custom` requires explicit `on`/`off` values for all
three settings and exists only for controlled comparisons. The manager still
creates a private test cluster; it cannot apply settings to an external server.

## Storage Result

FeedbackController supplies four real broad resets per run. Values pool the 12
reset samples from three measured runs after one warm-up.

| Same-code configuration | Hspec median | Reset median / p95 | Warm clone median |
| --- | ---: | ---: | ---: |
| Devenv virtiofs, all durability on | 2.520s | 417.4 / 647.0ms | 1.171s |
| Managed ext4, all durability on | 0.692s | 97.5 / 108.5ms | 0.238s |

Native storage reduced the reset median by 76.6%, the warm template clone
median by 79.7%, and focused Hspec time by 72.5% without changing durability.
This confirms the filesystem result from #198 after the #199 context-lifecycle
change.

## Durability Selection

AdminController Xero supplies 46 examples and 44 resets while exercising enough
transaction/WAL work to distinguish commit settings. Each row is the median of
three measured runs after one warm-up; all 15 measured runs passed 46 examples
with zero failures.

| Managed ext4 settings (`fsync` / `synchronous_commit` / `full_page_writes`) | Wall median | Hspec median | Pooled reset median / p95 | WAL sync median |
| --- | ---: | ---: | ---: | ---: |
| `on / on / on` | 39.008s | 33.773s | 88.4 / 192.1ms | 4,068 |
| `on / off / on` **selected** | 15.006s | 9.135s | 87.5 / 121.0ms | 92 |
| `off / on / on` | 13.005s | 8.274s | 81.2 / 95.2ms | 0 |
| `on / on / off` | 32.007s | 25.724s | 90.9 / 111.4ms | 4,045 |
| `off / off / off` | 13.005s | 8.068s | 80.5 / 101.4ms | 0 |

The durable runs were noisy (24–88s wall), but their Hspec minimum remained
well above the selected profile. Disabling synchronous commit removed nearly
all per-transaction WAL synchronization and reduced median Hspec time by 72.9%.
Disabling `fsync` as well saved only another 0.9s of median Hspec execution in
this comparison. The selected profile therefore keeps the stronger settings
rather than optimizing the last small difference.

## Complete-Suite Result

The registry remained 71 suites and 1,024 examples, with all 586 broad resets
unchanged. The before rows are the locked #199 post-context-lifecycle runs on
virtiofs. Selected rows are two successful #200 runs; ranges are shown rather
than presenting two runs as a robust median study.

| Complete lane | Before wall | Selected wall range | Before reset sum | Selected reset-sum range | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Serial | 1,186.232s | 99.019–114.028s | 791.006s | 52.088–59.740s | 1,024 / 0 twice |
| Six shards | 1,114.993s | 47.019–59.019s | 3,735.801s | 92.037–106.039s | 1,024 / 0 twice |

The two-run selected midpoint is 106.5s serial and 53.0s at six shards, versus
the single before runs of 1,186.2s and 1,115.0s. This is a same-host point-in-
time comparison, not a claim that all future hosts will reproduce the exact
percentages. It comfortably demonstrates a material DB-lane improvement.

Six-shard cleanup remains visible even on ext4: selected maximum shard-drop
phases were 14.0–33.5s, down from 704.0s in the before run. Final fan-out and
balance remain explicitly owned by #201.

## Safety And Recovery Validation

A bounded manager probe established all of the following:

- a healthy `ensure` reuses the same instance and database contents;
- after `pg_ctl stop -m immediate`, the next `ensure` creates a new instance and
  the marker database from the crashed instance is absent;
- a non-empty directory without the exact ownership marker is refused and its
  file is preserved;
- a managed root on this checkout's virtiofs mount is refused unless the
  diagnostic override is explicit;
- the normal devenv data directory and all three durability settings are
  identical before and after managed operations;
- an expected failing two-shard run and SIGTERM during an active DB context both
  remove every run-id shard database and backend.

The first startup implementation exposed a lifecycle bug: the postmaster
inherited the manager's flock descriptor, making later manager commands wait
indefinitely. Startup now closes that descriptor before `pg_ctl start`. The
regression probe confirms that the postmaster holds no manager lock and that a
second `ensure` plus `status` both complete within five seconds.

## Operational Commands

```bash
bash ./bin/in-env test-postgres status
bash ./bin/in-env test-postgres recreate
bash ./bin/in-env test-postgres stop
```

`stop` performs a fast PostgreSQL shutdown and removes the disposable instance;
the next DB-backed Hspec command initializes it again. Pure Hspec neither starts
nor connects to managed PostgreSQL.

## Limitations

- Complete before runs are one expensive capture each; selected verification
  has two runs per topology, not enough for production-grade percentiles.
- The measured `/tmp` filesystem is ext4. The manager also accepts local
  filesystems such as tmpfs but reports the actual location so another host can
  verify its own behavior.
- `track_io_timing` remained off, so wait events are sampled occurrences rather
  than duration attribution.
- Shard count and final suite weights were deliberately not changed; #201 owns
  that decision after this runtime correction.
