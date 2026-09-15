# Bepis independent tooling

`tooling/cabal.project` owns small developer-tool packages that build without the
Bepis application, IHP, schema generation, or `build/Verification`.

## Run and test

```bash
bin/tooling-run workspace contract
bin/tooling-run workspace resolve --path "$PWD" --json
bin/tooling-run workspace info --json
bash ./bin/in-env cabal test --project-file=tooling/cabal.project --builddir=tooling/dist-newstyle all
bash ./bin/in-env tooling-foundation-test
```

`bin/tooling-run` enters the focused `.#tooling` Nix shell when necessary, builds
only the selected Cabal component in this worktree's `tooling/dist-newstyle`, and
executes only the path reported by the successful build. Build failure stops;
there is no stale-binary fallback or prebuilt execution mode.

## Packages

- `bepis-tooling-core`: owned atomic files and scoped Linux advisory locks.
- `bepis-workspace-state`: sole owner of strict v1 registry/identity state, slot
  allocation, named provisioning, and workspace runtime layout. It invokes local
  Git and initialization commands but has no GitHub or application dependency.

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
