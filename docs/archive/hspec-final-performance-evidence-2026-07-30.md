# Final Hspec Performance Evidence — Issue #208

Status: final Epic #197 benchmark and weight calibration, measured 2026-07-30

Related issues: #197, #198, #201, and #203–#208

Source snapshot: `096c392e3d48be8d51be504372fa281abe48492e` plus the
#208 weight and documentation changes in this commit. Raw logs, one-second or
half-second PostgreSQL samples, reset traces, inventories, and generated
summaries remain ignored under `output/hspec-baseline/issue-208/`.

## Result

The final topology preserves the complete gate and the already-fast harness:

- 93 registered suites and 1,322 examples;
- 41 pure suites / 539 examples and 52 database suites / 783 examples;
- 48 broad-acceptance and 45 routine-correctness suites;
- all 13 invariant families represented, no partial mandatory invariant, and
  composed `T4` still explicitly owned by multiple suites;
- 715 dynamic broad resets per complete run;
- complete six-shard warm median **23.010 seconds**;
- pure Hspec median **0.548 seconds** for 539 examples;
- final slowest/median shard ratio median **1.149**;
- serial seeded complete run **76.508 seconds**;
- no leaked shard database or test backend after successful runs.

Six shards remain the default. Reweighting reduced the observed shard-tail ratio
from 1.217 to 1.149. No shard split, lane change, or test deletion is warranted.

## Protocol

Measurements used `bin/hspec-baseline`, the host-global exclusive lock, managed
disposable PostgreSQL on native temporary storage, bounded PostgreSQL/host
sampling, and one warm-up followed by three measured runs for final median
claims. Failed conflict attempts are retained but excluded. The final command
was:

```bash
bash ./bin/in-env ./bin/hspec-baseline run \
  --name i208-final-complete-measured-N \
  --output output/hspec-baseline/issue-208/final-complete-measured-N \
  --wait-seconds 30 --sample-interval 0.5 -- \
  env TEST_SHARDS=6 hspec-test \
    --format=progress --no-color --times --print-slow-items=30
```

A separate `TEST_SHARDS=1` run used `--seed 208`. Exact suite measurements used
the inventory's `dryRunShardIndex` with `TEST_SHARD_TOTAL=93`, ensuring one
registered suite rather than a text-match approximation.

Other worktrees repeatedly started Hspec, verification, and Playwright between
captured runs. `hspec-baseline` rejected seven attempts with exit 75 and wrote
`conflicts.json`; they are not included in medians:

| Excluded artifact | Conflict |
| --- | --- |
| `complete-measured-3` | cross-worktree suite-metadata Hspec/GHC process |
| `complete-measured-3-retry` | cross-worktree focused Playwright process |
| `db-measured-1` | cross-worktree focused Hspec/GHC process |
| `db6-measured-2` | cross-worktree focused invitation-renewal Hspec/GHC process |
| `acceptance-measured-1` | cross-worktree `verify-full`/complete Hspec processes |
| `acceptance-measured-1-success` | cross-worktree complete Hspec processes |
| `acceptance-measured-2-retry` | cross-worktree eight-shard Playwright processes |

The DB and acceptance warm-ups are excluded by protocol. One additional
successful acceptance observation (`acceptance-measured-1-retry`, 24.505s) was
excluded because Playwright started after capture startup. This is why raw
artifacts contain more attempt directories than the measured tables below.

## Baseline Comparison

The issue baseline was the 2026-07-30 pre-refactor single run: 88 suites, 1,353
examples, 728 resets, 22.00-second six-shard wall, 0.5288-second pure Hspec,
1.23 shard-tail ratio, and 13 sampled test connections.

| Metric | Baseline | Final | Change |
| --- | ---: | ---: | ---: |
| Registered suites | 88 | 93 | +5 split responsibilities |
| Examples | 1,353 | 1,322 | -31 redundant examples |
| Pure suites / examples | 36 / 518 | 41 / 539 | +5 / +21 |
| DB suites / examples | 52 / 835 | 52 / 783 | 0 / -52 |
| Dynamic resets | 728 | 715 | -13 |
| Warm complete wall | 22.00s single | 23.010s median | +4.6%, within noise/target |
| Pure Hspec | 0.5288s single | 0.5482s median | +0.0194s |
| Slowest / median shard | 1.23 | 1.149 median | improved |
| Sampled max test connections | 13 single | 16 median, 24 max | bounded; zero after run |

The one-second wall difference is explained by repeated-run reset variance, not
a new test critical path. Final measured reset-sum values were 45.885, 46.467,
and 41.079 seconds across concurrent workers. The corresponding complete walls
were 23.010, 23.510, and 20.505 seconds. Every value remains comfortably below
the 60-second acceptance threshold.

The suite count increased because five source modules now expose separately
registered pure and database bindings. Twenty-one examples moved into the
sub-second pure lane. The example reduction accounts for consolidated
controller/domain matrices (#204/#206), duplicate guard removal (#205), and
three consolidated database scenarios (#203). Dedicated cross-venue,
authorization, billing, immutable-ledger, wage, export, and migration evidence
remains registered.

## Final Complete Runs

| Run | Wall | Compile | Critical shard | Slowest / median | Reset median / p95 | Reset sum | Max test connections |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| measured 1 | 23.010s | 2.229s | 20.312s | 1.170 | 63.6 / 81.6ms | 45.885s | 14 |
| measured 2 | 23.510s | 2.811s | 19.769s | 1.128 | 62.8 / 89.7ms | 46.467s | 24 |
| measured 3 | 20.505s | 2.157s | 17.604s | 1.149 | 56.5 / 71.5ms | 41.079s | 16 |
| **median** | **23.010s** | **2.229s** | **19.769s** | **1.149** | **62.8 / 81.6ms** | **45.885s** | **16** |

The final assignment has equal declared weights of 17.4 seconds:

| Shard | Examples | Median Hspec | Range | Principal indivisible suites |
| ---: | ---: | ---: | ---: | --- |
| 1 | 211 | 12.323s | 10.798–12.628s | Admin Xero, Profiles, Xero preview |
| 2 | 292 | 16.937s | 14.888–17.261s | roster fragments, BillingController, Xero readiness |
| 3 | 189 | 16.674s | 14.909–16.683s | Timesheets, Passkeys, Users |
| 4 | 192 | 19.769s | 17.604–20.312s | DevSeed, Staff, Leave |
| 5 | 249 | 19.348s | 17.190–19.910s | roster workflow, fixed exports, BillingWebhook |
| 6 | 189 | 17.781s | 15.733–17.787s | VenueAccess, WageEngine adapter, Admin Config |

All three measured runs passed 1,322 examples with zero failures and reported
`mandatory-acceptance-excluded=[none]`.

## Weight Calibration

Exact focused measurements found one material stale estimate: the database
WageEngine adapter was declared as 0.5 seconds but measured 5.178 seconds because
its 200-entry approved-ledger reconstruction example alone takes about 4.2
seconds. Current billing and Xero estimates also predated their final suites.
Weights were rounded according to `Test/AGENTS.md`, not fitted to milliseconds.

| Suite | Focused Hspec | Old | Final |
| --- | ---: | ---: | ---: |
| Billing persistence | 0.435s | 0.6 | 0.4 |
| Billing read-only | 0.401s | 0.8 | 0.4 |
| Billing reconciliation | 0.421s | 0.5 | 0.4 |
| BillingController | 2.915s | 1.5 | 3.0 |
| BillingWebhook | 2.116s | 0.9 | 2.0 |
| Wage cutover migration | 0.097s | 0.2 | 0.1 |
| WageEngine minimum DataVic | 0.054s | 0.2 | 0.1 |
| WageEngine adapter | 5.178s | 0.5 | 5.0 |
| Wage source enforcement | 0.198s | 0.5 | 0.2 |
| Fixed export golden | 4.692s | 4.5 | 4.5 |
| Xero preview | 1.783s | 3.5 | 2.0 |
| Xero readiness | 2.198s | 3.5 | 2.0 |
| Xero submission | 1.072s | 2.0 | 1.0 |

Pure billing, venue-time, roster-award, pay-policy, WageEngine rule/contract, and
source-policy suites remain coarse 0.1-second units. Pure execution as a whole
remains below one second, so further fitting has no feedback value.

## Lane And Serial Measurements

| Selection | Examples | Repeated wall median | Hspec/critical median | Resets | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| pure, serial | 539 | 3.001s | **0.548s Hspec** | 0 | 3/3 pass |
| DB, six shards | 783 | 22.004s | 19.024s critical | 715 | 3/3 pass |
| acceptance feedback, six shards | 925 | 21.505s | 19.051s critical | 680 | 3/3 pass |
| complete, six shards | 1,322 | 23.010s | 19.769s critical | 715 | 3/3 pass |
| complete, serial, seed 208 | 1,322 | 76.508s | 73.989s Hspec | 715 | pass |

Acceptance-only still omitted `A4,R4,R5,T4,P2,P3,P5,B1,B2,B4,B7`, confirming
#207's decision that it is diagnostic rather than complete evidence. DB-only and
acceptance-only cost approximately as much as complete sharded Hspec.

The cold/warm comparison is intentionally scoped to managed PostgreSQL setup on
the complete gate. Pure has no PostgreSQL setup, while DB and acceptance reuse
the same compiled Hspec binary and managed-server lifecycle as complete Hspec;
a separate cold compiler cache would not be lane-specific evidence. Their lane
tables therefore compare warm feedback topology, not compilation-cache state.

A final cold managed-PostgreSQL complete run passed in 20.503 seconds. Its six
shard clones summed to 2.017 seconds versus a warm measured median of 0.763
seconds. Lower reset latency made its total wall faster than the warm median, so
no cold-versus-warm speedup claim is made; the setup penalty is bounded and not
the critical path.

## PostgreSQL Lifecycle And Waits

Final measured complete runs created and dropped six shard databases each.
Median create sum was 0.763 seconds and median drop sum was 3.430 seconds. Each
run ended with only the expected canonical `app_test` database at zero backends;
no `app_test_*` shard database or test backend remained.

Across three final runs the bounded samples observed 425 `Client:ClientRead`, 13
`IO:DataFileExtend`, one transaction lock, one tuple lock, and one `WALInsert`
LWLock occurrence. These are sampled occurrences, not wait durations. There is
no dominant PostgreSQL wait regression. Connection peaks are transient pool and
concurrency-test activity: median maximum 16, maximum 24, and zero after each
run.

## Slowest Evidence

The final serial run identifies stable indivisible costs without concurrent
worker distortion:

- DevSeed complete fixture: 4.798s;
- WageEngine 200-entry approved-ledger reconstruction: 4.307s;
- DevSeed scenario overrides: 4.211s;
- fixed export golden cases: roughly 0.65–0.80s each;
- Admin Xero, billing rendering, sessions, and Xero readiness examples: mostly
  0.2–0.4s each.

These are high-value fixture, immutable-ledger, exact-golden, security, and
external-contract evidence. The final shard ratio is below 1.5, so no follow-up
split is justified solely by timing.

## Coverage Reconciliation

The final inventory still owns every automated `A1–A7`, `R1–R5`, `T1–T7`,
`P1–P7`, and `B1–B7` requirement. `T4` remains deliberately composed; no
invariant is partial. Stripe `B8` remains operator-only runbook evidence.

All MA000009 matrix module references resolve to current registered modules:
FWC/DataVic source ingestion, VenueTime, WageEngine rules/components/minimums,
adapter/immutable ledger, source policy, roster award duration, fixed exports,
and Xero imported-item behavior. The matrix's retired `PaySpec` table was
updated for the exhaustive roster-only selector-suppression example. Billing,
wage, export/Xero, migration, generated-contract, audit, and source-freshness
responsibilities remain represented by the 13 enforced invariant families.

## Validation

- final inventory generation and metadata validation: pass;
- focused domain suite measurements: all pass;
- repeated pure, DB, acceptance, and complete runs: all measured runs pass;
- complete serial seed 208: 1,322 examples, zero failures;
- exact required CI sequence
  `bash ./bin/in-env typecheck && bash ./bin/in-env hspec-test`: pass;
- that unforced `hspec-test` automatically selected six equal 17.4-weight
  shards, ran 1,322 examples with zero failures, and reported no mandatory
  omissions (shards finished in 11.962–19.015s);
- no shard database/backend leak after normal completion;
- `doc-drift-check` covers the corrected MA000009 matrix mapping;
- raw conflict attempts are retained and excluded rather than hidden.
