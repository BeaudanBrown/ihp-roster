# Bepis independent tooling

`tooling.project` owns small developer-tool packages that build without the
Bepis application, IHP, schema generation, or `build/Verification`. The root
`hie.yaml` uses that same project for tooling components from any working
directory; `tooling/cabal.project` remains an import-only compatibility path for
existing repository-root commands.

## Run and test

```bash
bin/tooling-run workspace contract
bin/tooling-run workspace resolve --path "$PWD" --json
bin/tooling-run workspace info --json
bin/tooling-run postgres profile hspec status
bin/tooling-run runtime process observe PID OWNER LABEL WORKSPACE
bin/tooling-run epic orient --json
bin/tooling-run epic manage preflight --epic 564 --json
bin/tooling-run artifacts snapshot --root "$PWD" --inventory-command COMMAND
bin/tooling-run runners hspec-plan --lane pure --feedback routine --shards 1 --max-shards 6 --database app_test --run-id check
bash ./bin/in-env bash -c 'PATH="$BEPIS_TOOLING_BUILD_PATH" cabal test --project-file=tooling.project --builddir=tooling/dist-newstyle all'
bash ./bin/in-env tooling-foundation-test
```

`bin/tooling-run` enters the focused `.#tooling` Nix shell when necessary, builds
only the selected Cabal component in this worktree's `tooling/dist-newstyle`, and
executes only the path reported by the successful build. Build failure stops;
there is no stale-binary fallback or prebuilt execution mode. Both Nix shells
declare the same minimal compiler/tool path in `BEPIS_TOOLING_BUILD_PATH`.
Direnv layouts, script profiles, and runtime shims therefore do not reconfigure
Cabal's unchanged compiler. Only Cabal uses this path; the executed tool still
receives the caller's PATH. Raw Cabal checks should use it too, as above.
Git filters Nix environment inputs, while Cabal reads live dirty/untracked
Haskell sources. Build/output/log directories do not enter shell resolution.

## Packages

- `bepis-tooling-core`: owned atomic files and scoped Linux advisory locks.
- `bepis-workspace-state`: sole owner of strict v1 registry/identity state, slot
  allocation, named provisioning, and workspace runtime layout. It invokes local
  Git and initialization commands but has no GitHub or application dependency.
- `bepis-postgres`: typed managed/external and durable/disposable PostgreSQL
  profiles, owned-root validation, lifecycle/maintenance locks, bounded startup
  logs, E2E capacity, cleanup, development app-recovery coordination, and local
  migration-rehearsal plans/process/database cleanup with bounded failure
  evidence. Schema reconstruction, migration SQL, focused assertions, and schema
  comparison remain application-owned subprocess inputs.
- `bepis-runtime`: workspace-state-dependent owned-process evidence, concurrent
  publication, scoped process-group termination/escalation, bounded readiness,
  and optional equal-weight systemd/cgroup execution. Service launch recipes
  remain small shell adapters; runtime diagnostics are explicit commands.
- `bepis-artifacts`: application-independent owned cache roots, lifecycle locks,
  explicit path/value inventory hashing, atomic manifests, stable-input generation,
  and validate-before-publish managed trees. Application-specific inventories,
  generators, validators, retention markers, and compiler option recipes remain
  thin script adapters.
- `bepis-runners`: bounded Hspec, E2E, and profiling policy plus globally
  coordinated workspace port blocks, owned run directories, collision-safe run
  locks, signal-forwarded process groups, and durable failure evidence. The
  application compiler, database reset/seed commands, Playwright, k6, and
  telemetry processors remain subprocess owners behind thin script adapters.
- `bepis-epic-lifecycle`: live GitHub orientation plus non-mutating Git impact,
  divergence, conflict, runtime, and remote-publication inspection. Sync requires
  `--apply`; integration and cleanup require `--approve`. Mutations revalidate
  pinned refs, worktree/registry identity, remote rebase safety, and owned runtime
  state. The `epic-worktree` and `epic-worktree-manage` scripts remain adapters.

Nix package sources include only each package directory. A core source change
invalidates its dependent workspace derivation; workspace changes do not alter
core, and unrelated repository/tool-family changes alter neither. The production
source allowlist excludes the complete `tooling/` tree.

## Lock ownership

Workspace registry mutations use `<git-common-dir>/bepis/epic-worktrees/registry.lock`.
The process performing a mutation owns the exclusive lock only for that scoped
action. Haskell uses the same Linux `flock(2)` protocol as Bash and marks the file
descriptor close-on-exec so launched programs cannot retain it. Resolution never
runs GitHub, process, resource, or HLS diagnostics. Provisioning locks its short
Git creation/check and registry publication phases separately; initialization
runs unlocked. Publication rechecks conflicts and retained identities so retries
and concurrent identical requests cannot claim competing slots.

PostgreSQL maintenance fails fast on operator reset/seed contention. Hspec uses
`maintenance-run --wait` for shared schema-template publication only; each shard
clones its independent database after that lock is released.
