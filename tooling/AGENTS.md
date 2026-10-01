# Independent Tooling Guidelines

This tree is an application-independent Cabal project. Do not import IHP,
`App.cabal`, `Application/Schema.sql`, generated application types, or production
modules. Keep package sources narrow in `Config/nix/flake/tooling-source.nix`.

Add a module only with an immediate caller. Prefer a small interface hiding
ownership, locking, atomic publication, or validated state behavior over generic
helpers. Workspace-state owns deterministic runtime layout, but remains
independent of service/process lifecycle and network access.

Run selected commands through `bin/tooling-run`; it builds the current worktree
before execution and must never fall back to an old binary. Locks interoperate
with Linux `flock`: acquire only for the protected mutation, use the published
path, and keep descriptors close-on-exec. Write owned state through same-directory
atomic replacement; never imply rollback removed durable or user-created state.

Focused verification:

```bash
bash ./bin/in-env bash -c 'PATH="$BEPIS_TOOLING_BUILD_PATH" cabal test --project-file=tooling.project --builddir=tooling/dist-newstyle all'
bash ./bin/in-env tooling-foundation-test
bash ./bin/in-env postgres-lifecycle-test
bash ./bin/in-env runtime-lifecycle-test
bash ./bin/in-env runner-lifecycle-test
nix build .#bepis-tooling-core .#bepis-workspace-state .#bepis-postgres .#bepis-runtime .#bepis-runners
```
