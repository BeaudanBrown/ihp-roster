---
id: ir-30cs
status: closed
deps: []
links: []
created: 2026-07-09T02:41:25Z
type: task
priority: 2
assignee: Beaudan Brown
tags: [tests, sharding]
---
# Add weighted Hspec suite sharding

Replace positional modulo Hspec sharding with weight-aware greedy suite assignment and document future rebalancing instructions.


## Notes

**2026-07-09T02:55:55Z**

Implemented weighted Hspec sharding in Test/Suite.hs:
- TestSuite now carries suiteWeight.
- Full-suite selection greedily assigns highest-weight suites to the currently lightest shard.
- Shard headers include total assigned weight.
- Seeded and retuned initial weights using recent full-suite shard results; AdminController and DevSeed are the current standalone bottlenecks.

Documented future rebalancing instructions in Test/AGENTS.md, including how to inspect .devenv/test/latest/shard-*.log and adjust suiteWeight values without relying on suite order.

Verification:
- bash ./bin/in-env typecheck
- TEST_SHARDS=4 bash ./bin/in-env hspec-test --match SurfaceGuard
- bash ./bin/in-env ./bin/doc-drift-check
- bash ./bin/in-env hspec-test
- TEST_SHARDS=12 bash ./bin/in-env hspec-test --match SurfaceGuard
