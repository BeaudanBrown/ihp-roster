# Hspec Critical-Path Baseline — Issue #198

Status: point-in-time measurement at the pre-refactor registry; historical after
issue #198 closes

Related issues: [#197](https://github.com/BeaudanBrown/ihp-roster/issues/197),
[#198](https://github.com/BeaudanBrown/ihp-roster/issues/198)

Source snapshot: `aa3de92caf43eec412d72b31d142775931916f91` plus
behavior-neutral measurement instrumentation on branch
`issue-198-hspec-baseline`.

This report is evidence for later issues, not a test-deletion plan. It makes no
redundancy claim from suite names, example counts, or timings.

## Reproduction Protocol

Run benchmark commands through `bin/hspec-baseline`. It takes the host-global
`/tmp/bepis-exclusive-performance.lock`, refuses to start while another known
Hspec/Playwright/profile process is active, records phase timings, samples
PostgreSQL once per second, and writes ignored raw artifacts under `output/`.
Metrics writes are staged on native `/tmp` and copied after the command so the
instrumentation does not add per-reset writes to the project virtiofs mount.

```bash
# Rebuild and validate the structural fields in the committed inventory.
bash ./bin/in-env ./bin/hspec-baseline inventory \
  --check docs/archive/hspec-suite-inventory-2026-07-19.json \
  --output output/hspec-baseline/inventory-check.json

# One captured run. Change TEST_SHARDS to 1, 2, 4, 6, or 8.
bash ./bin/in-env ./bin/hspec-baseline run \
  --name full-shards-6-default \
  --output output/hspec-baseline/issue-198/full-shards-6-default \
  --wait-seconds 120 --sample-interval 1 -- \
  env TEST_SHARDS=6 hspec-test \
    --format=progress --no-color --times --print-slow-items=30

# Rebuild summary.json from a retained raw run.
bash ./bin/in-env ./bin/hspec-baseline summarize \
  output/hspec-baseline/issue-198/full-shards-6-default

# Run the opt-in, unregistered fixture/application boundary probe.
bash ./bin/in-env ./bin/hspec-baseline run \
  --name phase-probe-measured-1 \
  --output output/hspec-baseline/issue-198/phase-probe-measured-1 -- \
  env TEST_SHARDS=1 HSPEC_BASELINE_PROBE=fixture-application \
    hspec-db --format=progress --no-color
```

Important short comparisons used one warm-up and three measured runs. Complete
runs used one successful branch run per shard count because each comparison
cost 14–29 minutes; the current default is corroborated by same-host historical
evidence recorded on #197. Failed runs are reported separately and excluded
from comparisons.

### Native-filesystem comparison protocol

The native baseline used a disposable PostgreSQL 17.9 cluster under `/tmp`
(ext4), with the same observed setting values as the devenv instance, including
`fsync=on`, `synchronous_commit=on`, and `full_page_writes=on`:

```bash
native_root="$(mktemp -d /tmp/bepis-issue198-postgres.XXXXXX)"
mkdir -p "$native_root/socket"
initdb -D "$native_root/data" --no-locale --encoding=UTF8
pg_ctl -D "$native_root/data" -l "$native_root/postgres.log" \
  -o "-k $native_root/socket -p 5432 -c listen_addresses=''" start

TEST_DB_SOCKET="$native_root/socket" PGHOST="$native_root/socket" \
  bash ./bin/in-env ./bin/hspec-baseline run \
    --name native-reset-measured-1 \
    --output output/hspec-baseline/issue-198/native-reset-measured-1 -- \
    env TEST_DB_SOCKET="$native_root/socket" PGHOST="$native_root/socket" \
      TEST_SHARDS=1 TEST_SHARD_TOTAL=70 TEST_SHARD_INDEX=40 \
      hspec-db --format=progress --no-color

pg_ctl -D "$native_root/data" stop -m fast
rm -rf "$native_root"
```

The actual comparison included one warm-up, three measured FeedbackController
runs, and one AdminController.Xero run. The disposable cluster was stopped and
removed.

## Environment

| Property | Measured value |
| --- | --- |
| Date | 2026-07-19 |
| OS | Linux 6.18.33, NixOS guest under KVM |
| CPU | 6 vCPU, exposed as Intel Core i7-4770K 3.50 GHz |
| Memory | 8,289,099,776 bytes (7.72 GiB); 12.0 GiB swap |
| Project filesystem | `virtiofs`, 128 KiB reported filesystem block size |
| PostgreSQL | 17.9 |
| Devenv PostgreSQL data | `.devenv/state/postgres`, also on `virtiofs` |
| Native comparison | `/tmp/.../data` on `/dev/vda2` ext4, 4 KiB block size |
| Durability | `fsync=on`, `synchronous_commit=on`, `full_page_writes=on`, `wal_level=replica` |
| Main PostgreSQL sizing | `max_connections=100`, `shared_buffers=128 MiB`, `work_mem=4 MiB`, `effective_io_concurrency=1` |
| Timing lock | `/tmp/bepis-exclusive-performance.lock` |
| Hspec registry | 70 suites, 1,021 examples |

The repository-wrapper no-op cost was measured after one warm-up at 0.356s
median (0.356, 0.300, 0.534s). Captured command wall time starts inside the
already-entered repo environment; add that median when comparing to a fresh
`bash ./bin/in-env ...` invocation.

## Suite And Invariant Inventory

The machine-readable inventory is
[`hspec-suite-inventory-2026-07-19.json`](hspec-suite-inventory-2026-07-19.json).
It accounts for every `TestSuite` with label, module/path, pure/DB kind, exact
dry-run example count, static `withCleanDb do` call sites, declared weight,
measured or labelled-estimated duration, major invariant family,
committed-visibility assessment, and an explicit `routine-correctness` or
conservative `broad-acceptance-candidate` role.

| Inventory fact | Count |
| --- | ---: |
| Registered suites | 70 |
| Pure suites / examples | 23 / 329 |
| DB suites / examples | 47 / 692 |
| `withCleanDb do` call sites | 586 |
| Dynamic resets in each successful complete run | 586 |
| DB suites using deprecated `beforeAll testContext` | 47 |

The static and dynamic reset counts match for this snapshot. They are kept as
separate fields because loops or future fixture structure could make call sites
and executions differ.

Common fixture-builder call sites across registered source modules are also
inventoried. The largest counts are 485 `createVenueWithConfig`, 486
`createUserRecord`, 474 `createVenueMembershipRecord`, 273 `createStaffRecord`,
114 `createRosterSlotRecord`, 104 `createRosterWeekRecord`, and 103
`createRosterDayRecord`. Counts are construction-pressure indicators, not
runtime rankings or redundancy evidence.

### Mandatory invariant map

The inventory has a row for every minimum requirement in
`specs/09-testing-and-acceptance.md`. The principal family map is:

| Requirement family | Principal suites |
| --- | --- |
| Access/onboarding (`A1`–`A7`) | UsersController, SessionsController, ProfilesController, AdminController.Access, VenueAccess, StaffController, StaffDocumentsController, ExportsController, invitation suites, Schema/DatabaseProtection |
| Rostering (`R1`–`R5`) | RosterWeeks Navigation/Workflow/Fragments/Baseline/DirectReadModel, Conflict |
| Timesheets/leave (`T1`–`T7`) | TimesheetsController, LeaveRequestsController, Conflict, UsersController, DatabaseProtection, Schema, StaffDocumentsRSA |
| Pay/exports (`P1`–`P7`) | Pay, AdminController.Config, FwcMapdSync, PublicHolidaySync, ExportsController, FixedExportGolden, Xero preview/readiness/submission |
| Billing (`B1`–`B7`) | StripeBilling, StripeContract, BillingController, Billing persistence, BillingWebhook, Mail |
| Operator-only billing evidence (`B8`) | `Application/Billing/RUNBOOK.md`, not Hspec |

Two mappings need care rather than an overclaim:

- `T4` is composed evidence: ConflictSpec proves approved-leave conflict
  evaluation, while LeaveRequestsController and roster fragments prove the
  approval invalidation/render seams. It is not currently one end-to-end
  example.
- `B6` is partial by source inspection: BillingWebhook explicitly exercises
  `subscription.updated`, failed payment, and duplicate paths. Named
  `subscription.created` and `subscription.deleted` fixtures were not found.
  This is an input to the later domain/acceptance audit, not a change made here.

The JSON records these statuses and the exact mapped suites. Its suite-level
role decision is conservative: any suite containing cross-component,
mandatory-invariant, or committed-visibility evidence stays a broad-acceptance
candidate unless #202 can safely split it. Issue #202 owns enforceable registry
metadata and issue #207 owns lane semantics.

## Compilation And Pure Lane

| Comparison | Wall | Compile phase | Test-process phase | Hspec `Finished in` |
| --- | ---: | ---: | ---: | ---: |
| Cold isolated build | 178.464s | 177.188s | 0.707s | 0.560s |
| Warm measured median | **5.003s** | **3.923s** | **0.637s** | **0.478s** |

Warm measured Hspec values were 0.482, 0.409, and 0.478s for 329 examples.
About 90.5% of warm command wall was outside Hspec's reported execution, mostly
GHC relink/startup. The pure execution target remains satisfied. Complete-run
warm compile phases varied from 3.5 to 28.4s, so filesystem/cache state can
make relinking visible, but it is not the 14–29 minute critical path.

## Isolated Reset And Filesystem Comparison

FeedbackController supplied four real `withCleanDb` resets per run. Values below
pool the 12 reset samples after one warm-up.

| Same-code comparison | Devenv virtiofs PostgreSQL | Disposable ext4 PostgreSQL |
| --- | ---: | ---: |
| Reset median | **395.286ms** | **92.990ms** |
| Reset mean | 408.267ms | 90.933ms |
| Reset p95 | 524.576ms | 108.235ms |
| Warm shard DB clone median | 1.340s | 0.235s |
| Focused Hspec median | 2.457s | 0.519s |
| Captured wall median | 9.004s | 6.003s |

The native reset median was 76.5% lower and the warm template clone median was
82.5% lower. This is a storage comparison with durability still enabled, not a
selected configuration change.

AdminController.Xero corroborated the short probe:

| Filesystem | Hspec | 44 reset sum | Non-reset upper bound |
| --- | ---: | ---: | ---: |
| virtiofs | 72.856s | 21.355s | 51.681s |
| ext4 | 27.605s | 4.066s | 23.674s |

The non-reset column still includes fixture construction, application SQL,
controller/render execution, assertions, and Hspec overhead. Storage affects
that work too; it must not be interpreted as pure application CPU time.

## Representative Focused DB Suites

These are single branch measurements except FeedbackController, whose 2.213s
Hspec value is the median of three measured runs.

| Suite | Examples | Hspec | Resets / reset sum | Fixture + application + Hspec upper bound |
| --- | ---: | ---: | ---: | ---: |
| FeedbackController | 4 | 2.213s | 4 / 1.672s median-run sum | 0.443s |
| AdminController.Xero | 46 | 72.856s | 44 / 21.355s | 51.681s |
| DevSeed | 2 | 23.474s | 2 / 0.860s | 22.713s |
| RosterWeeksController.Workflow | 47 | 31.151s | 47 / 19.328s | 11.957s |
| TimesheetsController | 57 | 35.895s | 48 / 19.192s | 16.899s |
| BillingWebhook | 8 | 3.714s | 8 / 3.275s | 0.507s |
| VenueAccess | 43 | 23.743s | 43 / 17.798s | 6.090s |
| FixedExportGolden | 7 | 14.015s | 7 / 2.890s | 11.260s |
| Pay | 25 | 15.455s | 21 / 8.159s | 7.436s |
| XeroTimesheetPreview | 13 | 27.421s | 13 / 5.832s | 21.692s |

DevSeed is the clearest fixture-heavy suite bound: only 0.860s of its 23.474s
was reset time, while the examples build deterministic scenario fixtures and
then assert their contract.

### Separate fixture/application boundary probe

An opt-in probe in `Test/BaselineProbe.hs` is not registered in `Test/Suite.hs`
and therefore does not change canonical example counts or selection. It times a
representative roster request in explicit boundaries: broad reset; venue/user/
membership fixture construction; authenticated application action; assertion.
After one warm-up, the three measured values were:

| Run | Reset | Fixture construction | Application action | Hspec `Finished in` |
| --- | ---: | ---: | ---: | ---: |
| 1 | 1,382.880ms | 104.653ms | 458.370ms | 1.952s |
| 2 | 1,227.175ms | 116.592ms | 187.916ms | 1.539s |
| 3 | 917.361ms | 114.349ms | 143.288ms | 1.184s |
| **Median** | **1,227.175ms** | **114.349ms** | **187.916ms** | **1.539s** |

This supplies a real fixture-versus-application seam without adding logging to
ordinary examples. It is representative rather than a claim that all suites
have the same phase proportions. The per-suite non-reset values above remain
upper bounds where existing tests do not expose a boundary.

## Complete Hspec And Shard Scaling

Each branch run passed 1,021 examples with zero failures. Full comparisons are
single expensive runs, not medians.

| Shards | Wall | Critical Hspec shard | Reset median / p95 | Max test connections | Slowest / median shard | WAL bytes |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 838.879s | 807.227s | 0.462s / 4.784s | 28 | 1.000 | 174.6 MB |
| 2 | **811.877s** | 785.124s | 1.044s / 5.434s | 36 | 1.244 | 185.1 MB |
| 4 | 985.713s | 946.242s | 2.301s / 12.309s | 38 | 1.127 | 209.7 MB |
| 6 (current default) | 1,347.387s | 1,338.274s | 3.740s / 27.611s | 34 | 1.572 | 227.7 MB |
| 8 | 1,736.873s | 1,701.073s | 12.104s / 23.037s | 39 | 1.739 | 258.1 MB |

Two shards were only 3.2% faster than serial in this one comparison. Six was
66.0% slower than two, and eight was 113.9% slower than two. This is baseline
evidence only; issue #201 must retune after context and PostgreSQL corrections,
not change the default from these one-off pre-fix runs.

The same 586 resets generated much more aggregate work under fan-out. Serial
reset time summed to 535.5s (66.3% of its Hspec process phase). At six shards,
reset time summed across workers to 4,632.0s (87.5% of aggregate worker
execution). Aggregate concurrent sums are resource-work indicators and are not
additive on command wall time.

WAL volume increased from 174.6 MB serially to 258.1 MB at eight shards, a
47.8% increase for the same examples. `wal_sync` counter deltas rose from
19,087 to 21,876.

### Current default shard assignment

| Shard | Declared weight | Examples | Hspec | Actual/weight | Resets | Principal assignment |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 250 | 153 | 742.279s | 2.969 | 60 | Admin Xero, XeroContract, AsyncQueue, direct roster read model |
| 2 | 250 | 76 | 208.246s | 0.833 | 40 | DevSeed, BillingController, Exports, DatabaseProtection |
| 3 | 245 | 106 | 767.795s | 3.134 | 68 | Admin Config, Xero submission, FWC, roster navigation |
| 4 | 245 | 208 | 1,274.963s | 5.204 | 168 | Roster workflow, Staff, Passkeys, Leave, BillingWebhook |
| 5 | 245 | 142 | 934.825s | 3.816 | 74 | Xero preview/readiness, Profiles, Sessions, Support |
| 6 | 245 | 336 | 1,338.274s | 5.462 | 176 | Roster fragments, Timesheets, VenueAccess, exports, Pay |

Nearly equal declared weights produced a 208–1,338s Hspec range and a 0.833–5.462
actual-to-weight ratio. The critical tail is not explained by example count
alone.

Database cleanup was also active during the tail. The longest individual shard
`DROP DATABASE` phase was 321.8s at two shards, 631.4s at four, 893.8s at six,
and 936.0s at eight. Early-shard drops overlap later-shard execution, so these
figures are not launcher overhead to add to wall time; they are measured
concurrent cleanup work and a storage/contention hypothesis for #200/#201.
Actual internal launcher/reporting overhead was below 0.2s in every captured
complete run.

### Historical corroboration

Issue #197 records a same-host six-shard run of 994 examples at 21.9 minutes,
with shards from 245 to 1,313s. Raw logs remain at
`.devenv/test/1784332191-2209790-6461/`. The current locked branch run was 22.46
minutes with shards from 208 to 1,338s. The historical run was not lock-captured
and predates the 1,021-example snapshot, so it is corroboration rather than a
branch-run median.

## PostgreSQL Connections And Waits

All 47 DB suite modules use the deprecated unbracketed `beforeAll testContext`
shape. The current default run's rolling sampled maximum grew from 0 to 11 test
connections by 10% of samples, 32 by 25%, 33 by the midpoint, and 34 by 75%.
The live count later fell as pools/connections expired and returned to zero only
after test processes exited and shard databases were dropped. The eight-shard
maximum was 39. A Timesheets focused run reached eight connections during its
explicit concurrency example.

The default run observed these one-second backend samples:

- `Client:ClientRead`: 19,140 (mostly idle pooled clients)
- `IO:DataFileExtend`: 197
- `IO:WalSync`: 138
- `IO:WalWrite`: 36
- `IO:DataFileRead`: 36
- `LWLock:WALWrite`: 7

At eight shards, `DataFileExtend` rose to 337 sampled backend observations and
`WalSync` to 161. These are sampled occurrences, not wait durations or shares of
wall time. `track_io_timing` is off on the measured server, so no duration claim
is made.

No normal captured run left a shard database or test backend. Six stale shard
databases from a pre-existing killed historical run were found and removed
before the branch full comparisons. Process-exit cleanup does not disprove the
within-process unbracketed pool lifetime identified for #199.

## Critical-Path Ranking

Measured facts and bounded interpretations, in order of impact:

1. **Broad reset plus PostgreSQL storage/WAL work dominates.** Serial reset work
   was 66.3% of Hspec process time; six-shard aggregate reset work was 87.5%.
   Reset latency rose sharply with fan-out, and a same-settings ext4 probe cut
   isolated reset median by 76.5%.
2. **Concurrent shard cleanup is substantial.** Early database drops remained
   active for hundreds of seconds on virtiofs while other shards executed.
3. **Context/pool lifetime creates connection pressure.** Forty-seven DB suites
   use deprecated unbracketed contexts; captured maxima were 28–39 test
   connections. Correct lifecycle is a correctness prerequisite before final
   throughput tuning.
4. **Non-reset DB work remains material.** Admin Xero, DevSeed, Xero preview,
   Timesheets, roster workflow, and fixed export goldens have 11–52s focused
   fixture+application upper bounds. Native storage reduced but did not erase
   these residuals.
5. **Declared weights do not model the current contended runtime.** Default
   actual/weight ratios varied by 6.6× and the slowest shard exceeded the target
   1.5× median ratio.
6. **Compilation and reporting are not the full-suite critical path.** Cold
   compile is expensive, but warm pure Hspec finishes below 0.5s and launcher/
   reporting overhead is sub-second once inside the environment.

Individual default-run slow-item times reached 30–46s, but those values include
full reset and shared PostgreSQL contention. They must not be used to call an
example redundant or intrinsically slow without a focused run.

## Recommended Intervention Order

This is issue routing, not implementation on the #198 branch:

1. **#199 context lifecycle** — remove unbracketed pool ownership first so later
   connection and failure-cleanup measurements are trustworthy.
2. **#200 disposable PostgreSQL runtime/storage** — the same-settings ext4
   comparison is the largest isolated effect; keep all changes impossible to
   apply to normal databases.
3. **#202 metadata in parallel with the harness work** — turn this candidate
   inventory into enforceable invariant/isolation/lane metadata before any
   consolidation or lane change.
4. **#203 reset reduction** — 586 broad resets are the largest repeatable work
   unit; retain committed-visibility, nested-transaction, audit, job, and
   omission-detection semantics.
5. **#204 and #206 controller/domain consolidation** — target measured non-reset
   matrices while preserving VenueAccess, fixed export, history, audit, and
   external strict-mock oracles.
6. **#201 shard retuning** — rerun 1/2/4/6/8 only after lifecycle/storage/reset
   corrections. Current evidence shows that adding workers makes the pre-fix
   runtime worse.
7. **#205/#212 guard audit and #207 acceptance lanes** — use the invariant map;
   pure Hspec is already below 0.5s, so guard deletion is not the main runtime
   lever and complete acceptance must remain mandatory.

## Validation

- `typecheck`: passed after the final instrumentation/probe changes.
- structural inventory regeneration/check: 70 suites and 1,021 examples; passed.
- opt-in phase probe: 1 example, 0 failures; canonical pure focused: 1/0;
  canonical DB focused: 4/0.
- canonical metrics-unset `hspec-test`: 1,021 examples, 0 failures across six
  shards after the review fixes; no shard database or test backend remained.
- `format`, focused HLint for the new probe/runner, Ruff for
  `bin/hspec-baseline`, and `doc-drift-check`: passed.
- repository-wide `lint` remains blocked by a pre-existing HLint suggestion in
  unchanged `Web/Timesheets/Validation.hs`; a whole-file HLint run on
  `Test/Support.hs` likewise reports an unchanged suggestion around line 246.
  Neither finding is in the #198 diff.

## Limitations And Failed Measurements

- Pure, reset, and native short comparisons use one warm-up plus three measured
  runs. Full shard counts are one successful branch run each because the set
  cost about 95 minutes; #197 supplies historical default-run corroboration.
- One initial two-shard capture failed before valid measurement because the
  baseline tool generated a `TEST_RUN_ID` long enough for PostgreSQL identifier
  truncation to collide shard database names. The tool now bounds the ID, the
  failed artifact is retained under
  `full-shards-2-attempt-1-failed-name-collision/`, and the successful two-shard
  run was repeated. It is excluded from all medians/comparisons.
- The first two fixture/application probe attempts failed at compile time while
  the new opt-in probe was being wired (`phase-probe-attempt-{1,2}-compile-failure`).
  Neither produced timing samples; both are retained as failed attempts and the
  fixed probe then received one warm-up plus three successful measurements.
- The exclusive lock coordinates compliant local agents and the tool checks for
  known benchmark/full-suite processes. It cannot eliminate unrelated host or
  hypervisor noise.
- PostgreSQL polling at one second is bounded but not free. Raw command wall
  includes that monitoring load; its process is on the `postgres` database and
  excluded from test-connection counts.
- The opt-in boundary probe separates fixture and application time for one
  representative roster path. Existing-suite residuals remain upper bounds;
  no permanent verbose SQL/test logging was enabled.
- Committed-visibility classifications are source-inspection assessments.
  `required` is reserved for explicit concurrency or a separately constructed
  context; `possible` cases require proof in #202/#203.
- The native comparison changes only filesystem location. It does not measure
  reduced durability; that belongs to #200.

## Raw Artifacts

Generated raw artifacts are intentionally ignored by Git:

- aggregate machine-readable result:
  `output/hspec-baseline/issue-198/baseline-comparison.json`
- environment-wrapper result:
  `output/hspec-baseline/issue-198/environment-wrapper.json`
- cold/warm pure runs: `output/hspec-baseline/issue-198/pure-*`
- focused DB runs: `output/hspec-baseline/issue-198/focused-*`
- separate fixture/application probe: `output/hspec-baseline/issue-198/phase-probe-*`
- reset runs: `output/hspec-baseline/issue-198/reset-*`
- native ext4 runs and server evidence:
  `output/hspec-baseline/issue-198/native-*`
- complete runs: `output/hspec-baseline/issue-198/full-shards-*`
- default slow-item extraction:
  `output/hspec-baseline/issue-198/default-slow-items.json`
- historical same-host logs: `.devenv/test/1784332191-2209790-6461/`

Each capture directory contains `environment.json`, `command.log`,
`postgres-before.json`, `postgres-after.json`, one-second PostgreSQL and host
samples, phase/reset metrics, copied shard logs, and `summary.json`.
