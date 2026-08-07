# Production Build Profiling Runbook

Use `production-build-profile` to collect comparable evidence for the exact
`app-lib` derivation selected by `optimized-prod-server`:

```bash
bash ./bin/in-env production-build-profile --cores 12
```

The command resolves `optimized-prod-server`, finds its unique `app-lib`
derivation, and runs one clean local Nix build. If the output already exists,
Nix `--rebuild` forces the build without deleting that or any unrelated store
path. If it is absent, normal Nix realisation provides the same clean sandboxed
build. The profiler disables configured remote builders for the measured build,
uses one Nix job, and passes `--cores` through to GHC.

Artifacts are bounded and written under
`output/production-build/<timestamp>/`:

- `profile.json` — comparison authority;
- `profile.md` — concise human summary;
- `build.log` — final 4 MiB of build output at most.

`Config/nix/baselines/production-build/` retains reviewed baseline summaries;
`staging-ea144503-grill.json` is the current staging baseline for this work.
Do not commit raw logs or output links.

## Safe NAS And Grill Procedure

1. SSH to the intended builder and confirm `hostname`; do not initiate a remote
   build from another machine because local process and cgroup evidence would
   describe the wrong host.
2. Use a clean checkout at the exact revision. Record a dirty profile only for
   profiler development, never as a release baseline.
3. Confirm no other Nix build is active. The Nix daemon cgroup is shared, so
   concurrent builds invalidate its memory evidence.
4. Check available RAM and swap with `free -h` and `/proc/swaps`. Stop local dev
   hot reload and HLS before a compile-heavy run. Do not stop customer services
   or reduce normal production capacity merely to manufacture a passing result.
5. Run the command above in a durable terminal session. It performs no NixOS
   switch, store deletion, database action, or customer-runtime mutation.
6. Retain `profile.json`; compare derivation paths, revision, core settings,
   configure flags, wall/CPU time, memory, sizes, modules, extension totals, and
   largest interfaces before comparing headline memory numbers.

Use `--output-dir DIR` for a named artifact directory. Compare two retained
profiles with:

```bash
bash ./bin/in-env production-build-profile \
  --compare <before>/profile.json <after>/profile.json \
  --output <after>/comparison.json
```

The bounded comparison records identities, whether builder system/core settings
match, and absolute deltas for time, memory, swap, package sizes, module count,
and largest interface size.

Apply stable packaging and interface budgets to a retained profile with:

```bash
bash ./bin/in-env production-build-budget-check <artifact-dir>/profile.json
```

With no profile argument, first run `production-package-smoke`; the check then
inspects that exact realized app-lib without rebuilding it. Stable CI budgets do
not assert host memory. For final NAS release evidence only, run the validator
explicitly after the clean eight-core NAS profile:

```bash
bash ./bin/in-env node scripts/production-build-budget.mjs \
  --budget Config/nix/baselines/production-build/final-regression-budget.json \
  --profile <nas-artifact-dir>/profile.json \
  --enforce-measured-memory
```

Measured-memory enforcement fails unless the profile is clean, forced, locally
successful on hostname `nas`, uses eight effective GHC cores, and stays at or
below the reviewed 13 GiB sampled builder-process RSS ceiling. The original
8 GiB target failed at 11.80 GiB on the clean final representative-load run;
the operator approved 13 GiB (about 10% headroom) rather than lowering builder
cores or hiding the measured swap growth. Retain the resulting profile and a
bounded issue summary; do not commit raw logs.

Use `--no-rebuild` only to inspect an already-present historical output; it
intentionally provides no build memory or CPU evidence and is not a complete
baseline.

## Interpreting Memory

`builder_process_peak_rss_bytes` is the sampled sum of resident memory for local
`nixbld` processes. It excludes file cache, but shared pages can be counted in
more than one process. `nix_daemon_cgroup_peak_growth_bytes` is the increase in
`nix-daemon.service` cgroup memory from the start of the run. It includes builder
memory, file cache, and any concurrent daemon work; it is not process RSS.

Use both values. Do not infer process RSS from host used memory, because Linux
page cache can remain after a build. A nonzero `swap_delta_bytes` means memory
pressure affected the run and must remain part of the comparison.

Nix may complete the forced compile and then report that the rebuilt output
differs from the existing output. The command records this as
`succeeded_output_differs`, preserves Nix's exit status and
`rebuilt_output_differs`, and still accepts the complete profiling evidence.
Treat output nondeterminism as explicit evidence, not as a missing build.
