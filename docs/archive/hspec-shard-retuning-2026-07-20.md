# Hspec Shard Retuning — Issue #201

Status: implemented and measured on 2026-07-20

Related issues: [#197](https://github.com/BeaudanBrown/ihp-roster/issues/197),
[#198](https://github.com/BeaudanBrown/ihp-roster/issues/198),
[#199](https://github.com/BeaudanBrown/ihp-roster/issues/199),
[#200](https://github.com/BeaudanBrown/ihp-roster/issues/200), and
[#201](https://github.com/BeaudanBrown/ihp-roster/issues/201)

This report records the point-in-time fan-out and suite-weight selection after
bracketed database contexts (#199) and the managed native-filesystem PostgreSQL
runtime (#200). Current operating and classification guidance lives in
`Test/AGENTS.md`.

Source snapshot: `be3ce8c33be906635ddb5e50dd6deacc3ed095b4` plus the
issue #201/#202 implementation in this commit. Raw logs, one-second PostgreSQL
samples, reset traces, and generated summaries remain ignored under
`output/hspec-baseline/issue-201/`.

## Result

The automatic DB-backed cap is **six shards**. Six is the smallest topology on
the measured minimum wall-time plateau:

- six-shard median wall: **37.020s**;
- eight-shard median wall: **37.019s**;
- both round to **37.02s**, a 1.1ms difference that is not meaningful at this
  sampling resolution;
- compared with eight, six used 23.4% less aggregate Hspec worker time, 24.6%
  fewer aggregate reset-seconds, 19.8% less aggregate database-drop time, and
  a median maximum of 17 rather than 25 test connections;
- six also had the lower median slowest/median shard ratio, 1.056 versus 1.089.

`TEST_SHARDS` still forces any positive shard count. `TEST_DB_SHARDS_MAX` still
overrides the automatic cap, and the existing database/reset diagnostics remain
available. Focused commands still default to one process, and `hspec-pure`
still avoids managed PostgreSQL and shard-database setup.

## Protocol

The measurements used `bin/hspec-baseline`, its host-global exclusive lock, and
its bounded PostgreSQL/host sampling. The host and PostgreSQL runtime are the
same as the selected issue #200 environment: six vCPUs, managed PostgreSQL 17.9
on `/tmp` ext4, `fsync=on`, `synchronous_commit=off`, and
`full_page_writes=on`.

Each topology received one warm-up and three measured complete runs:

```bash
bash ./bin/in-env ./bin/hspec-baseline run \
  --name i201-s6-measured-1 \
  --output output/hspec-baseline/issue-201/shards-6-measured-1 -- \
  env TEST_SHARDS=6 hspec-test \
    --format=progress --no-color --times --print-slow-items=10
```

All 20 matrix runs passed. Every complete run executed 72 suites, 1,028
examples, 586 measured broad resets, and zero failures. Failed runs would have
been retained and excluded from medians; there were none.

Before the matrix, every suite was run once as an exact one-suite registry shard
after a fresh schema-template reset. The sum of focused Hspec durations was
99.288s. Runtime weights were then rounded to avoid fitting transient noise:
nearest 0.5s at or above one second, nearest 0.1s below one second, with a 0.1s
minimum. Sharding uses these estimated seconds directly.

## Fan-out Measurements

Values are medians of the three measured complete runs. Aggregate worker and
reset time sum concurrent shard work and are resource-pressure indicators, not
wall-time components to add together. Wait values are sampled backend
occurrences, not wait durations.

| Shards | Wall | Critical Hspec shard | Slowest / median shard | Throughput | Aggregate worker | Reset median / p95 | Reset sum | DB create sum | DB drop sum | Max test connections |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 97.022s | 89.262s | 1.000 | 10.60 examples/s | 89.419s | 82.0 / 117.3ms | 51.144s | 3.466s | 0s | 13 |
| 2 | 64.019s | 48.454s | 1.010 | 16.06 examples/s | 96.780s | 88.3 / 118.5ms | 54.149s | 0.466s | 6.837s | 9 |
| 4 | 44.014s | 35.504s | 1.050 | 23.36 examples/s | 136.339s | 120.6 / 159.2ms | 74.509s | 1.202s | 13.888s | 11 |
| **6** | **37.020s** | **30.601s** | **1.056** | **27.77 examples/s** | **170.705s** | **153.6 / 224.4ms** | **93.871s** | **2.781s** | **23.041s** | **17** |
| 8 | 37.019s | 30.639s | 1.089 | 27.77 examples/s | 222.773s | 204.4 / 313.9ms | 124.440s | 3.951s | 28.713s | 25 |

Scaling stops after six: eight adds workers and PostgreSQL pressure without
materially increasing aggregate throughput. The eight-shard reset median is
2.49x serial, while six is 1.87x serial. Database create/drop work and live
connections likewise rise with fan-out.

### Sampled PostgreSQL waits

| Shards | `ClientRead` | `DataFileExtend` | `WalSync` | `WALWrite` LWLock | `LockManager` LWLock |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 62 | 4 | 6 | 1 | 0 |
| 2 | 55 | 1 | 1 | 0 | 0 |
| 4 | 78 | 1 | 4 | 1 | 0 |
| 6 | 119 | 1 | 3 | 1 | 3 |
| 8 | 134 | 3 | 5 | 3 | 3 |

`ClientRead` is predominantly idle pooled clients. The bounded samples show no
new dominant I/O wait after #200, but connection and lock/WAL observations grow
at the higher fan-outs. `track_io_timing` remains off, so no duration attribution
is made.

## Weight And Tail Result

The largest exact focused suites were:

| Suite | Examples | Focused Hspec |
| --- | ---: | ---: |
| `AdminController.Xero` | 46 | 11.347s |
| `RosterWeeksController.Fragments` | 40 | 8.172s |
| `DevSeed` | 2 | 7.734s |
| `TimesheetsController` | 57 | 7.543s |
| `RosterWeeksController.Workflow` | 47 | 6.412s |
| `VenueAccess` | 43 | 5.375s |

These are the current indivisible critical-path suites. Controller/domain
consolidation issues #204 and #206 are the appropriate follow-up seams; this
ticket does not split examples or weaken their acceptance responsibility.

With the measured weights, selected six-shard assignments are nearly equal at
16.7–16.8 estimated seconds. Across the three measured runs:

| Shard | Weight | Examples | Median Hspec | Range |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 16.8 | 269 | 25.463s | 24.071–32.186s |
| 2 | 16.8 | 151 | 25.266s | 21.227–29.591s |
| 3 | 16.8 | 190 | 30.265s | 27.521–35.996s |
| 4 | 16.8 | 132 | 30.601s | 28.227–35.781s |
| 5 | 16.8 | 165 | 28.349s | 25.504–33.309s |
| 6 | 16.7 | 121 | 29.592s | 25.657–34.986s |

Every measured six-shard run remained below the 1.5 target; the worst observed
slowest/median ratio was 1.103. Example count is intentionally not used as a
weight proxy.

## Limitations

- Three measured runs establish a local selection median, not a cross-host
  universal optimum. The explicit overrides remain for measured hosts.
- One serial run was slower than its peers (118.020s versus approximately
  97.02s) and one six-shard run was slower (43.023s versus approximately
  37.02s). Both passed and remain included in their medians.
- Per-suite weights use one exact focused measurement and coarse rounding.
  Issue #208 owns final remeasurement after later reset/consolidation work.
- The matrix predates issue #203's reset reduction. If that work materially
  changes relative suite costs, rerun this protocol rather than preserving the
  current numbers by convention.
