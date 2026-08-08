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
`staging-ea144503-grill.json` is the historical pre-boundary comparison point,
while `issue-350-final-regression-gates.json` records the accepted closeout
profiles and target disposition. Do not commit raw logs or output links.

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
not assert or cap host memory. NAS memory remains retained benchmark evidence:
record the clean revision, effective cores, RSS, cgroup growth, swap, and service
load, but do not turn a sampled machine-global value into a release gate. Retain
the resulting profile and a bounded issue summary; do not commit raw logs.

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

## Diagnosing A Killed Or OOM Build

1. Preserve the profile directory and bounded `build.log`; do not immediately
   rerun with different core settings and overwrite the failed context.
2. Record `hostname`, revision, dirty state, configured/effective cores,
   `free -b`, `/proc/swaps`, `uptime`, active customer services, and whether
   another Nix build shared the daemon cgroup.
3. Check the build exit status and the end of `build.log` for `Killed`, signal 9,
   exit 137, or `./Setup build` termination. Correlate the build window with
   privileged host OOM logs (`journalctl -k` or the operator's equivalent);
   absence of accessible kernel logs is not proof that no OOM occurred.
4. Compare RSS, cgroup growth, swap delta, wall/CPU time, derivation identity,
   and effective cores with a same-builder clean profile. Treat concurrent work,
   changed services, changed cores, or output/configuration differences as
   non-comparable evidence.
5. First run the deterministic budget and package checks. If they pass, diagnose
   machine pressure separately from app-owned output growth. Lower parallelism
   may be tested as an operational mitigation only in a new named profile; it
   does not revise the accepted build architecture or erase the failed run.

Never delete store paths, stop customer services, switch NixOS configuration,
or reset data as part of diagnosis. Escalate repeated unexplained kills with the
retained profile, service context, and kernel evidence.

Nix may complete the forced compile and then report that the rebuilt output
differs from the existing output. The command records this as
`succeeded_output_differs`, preserves Nix's exit status and
`rebuilt_output_differs`, and still accepts the complete profiling evidence.
Treat output nondeterminism as explicit evidence, not as a missing build.
