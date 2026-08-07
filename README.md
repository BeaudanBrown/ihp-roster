# Bepis

Bepis is an IHP roster, leave, timesheet, export, and venue-operations app.
Start with `AGENTS.md`; before editing a subsystem, read its nearest local
`AGENTS.md` and README/SPEC.

## Repository Map

- `Application/Schema.sql` — canonical fresh-database schema
- `Application/Migration/` — deployed database upgrade paths
- `Application/Helper/` — shared application services and helpers
- `Web/Types.hs`, `Web/Routes.hs`, `Web/FrontController.hs` — web wiring
- `Web/Controller/` — controllers
- `Web/View/` — HSX views and layout
- `frontend/ts/` — authored browser TypeScript
- `frontend/ts/generated/` — backend-generated TypeScript contracts
- `static/` — checked-in generated JS, CSS, and vendor assets
- `Test/` — Hspec tests
- `e2e/` — Playwright tests
- `Config/nix/` — development, verification, and deployment configuration
- `docs/` — retention policy, architecture, ADRs, workstreams, and archive
- `specs/` — cross-cutting product, domain, compliance, and acceptance intent

## Commands

Run commands through the project environment:

```bash
# Fast and complete gates
bash ./bin/in-env verify-fast
bash ./bin/in-env verify-full

# Focused gates
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test
bash ./bin/in-env e2e
bash ./bin/in-env lint
bash ./bin/in-env format
bash ./bin/in-env ./bin/doc-drift-check

# Frontend generation and checks
bash ./bin/in-env frontend-build
bash ./bin/in-env frontend-check
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-surface-adapters-check
bash ./bin/in-env typed-contract-authority-check
bash ./bin/in-env frontend-watch
bash ./bin/in-env generated-code-sync

# Schema-derived types
bash ./bin/in-env regen-types

# Clean production app-library build evidence
bash ./bin/in-env production-build-profile --cores 12
```

`verify-fast` provides additive feedback. `verify-full` is the complete local
gate. CI protects typecheck plus complete Hspec. Local subsystem docs list
narrower commands and test-selection rules.

`frontend-check` runs contract drift, strict TypeScript validation including
unused-code checks, frontend unit/DOM tests, and generated JS drift. The full
verification gate additionally runs the zero-bypass typed-authority gate,
curated FrontendContract GHC warnings and Weeder reachability, CSS stale-selector
ownership, architecture freshness, and documentation drift. `dev-start` and
`just dev` first use content fingerprints to generate only stale frontend
contracts, Haskell Surface adapters, and JavaScript, then run the coordinated
frontend-generated watcher plus the frontend asset watcher. IHP's `RunDevServer`
remains the sole live owner of schema-derived `build/Generated/` Haskell types.
Foreground observability is opt-in via `IHP_ROSTER_DEV_OBSERVABILITY=1`;
`dev-stop` cleans up detached dev processes. There is no Vite dev server or true
HMR requirement. Contract-source edits regenerate both Haskell adapters and
`frontend/ts/generated/contracts.ts`; the asset watcher then rebundles dependent
JS. `generated-code-sync` (or `just regen-all`) unconditionally regenerates all
code. Frontend unit tests and Playwright E2E are not pre-commit hooks; the
tracked pre-commit hook only guards generated JS drift. Production/live NixOS
runtime serves checked-in generated static JS and does not require
Node/esbuild/TypeScript/frontend test tooling.

`verify-fast` and `verify-full` include `devenv-script-freshness-check`, ensuring
registered commands execute current checkout sources rather than stale snapshots.

## Development

```bash
bash ./bin/in-env dev-start
bash ./bin/in-env dev-wait
bash ./bin/in-env dev-workspace-info
bash ./bin/in-env dev-stop
bash ./bin/in-env seed-dev app
bash ./bin/in-env psql -d app
```

`just dev` runs foreground development. Managed workspaces derive isolated
ports, PostgreSQL state, and runtime paths; inspect them with
`dev-workspace-info --json` rather than assuming addresses. See `AGENTS.md` for
epic-worktree delegation and approval boundaries.

Bepis is live. Schema changes require both `Application/Schema.sql` and a safe
IHP migration under `Application/Migration/`. Local `make db` resets development
data and is not a production/staging upgrade path.

## Generated Boundaries

Do not hand-edit generated browser output under `static/app*.js` or generated
contracts under `frontend/ts/generated/`. Use the frontend commands above and
follow `frontend/AGENTS.md` and `static/AGENTS.md`. Runtime assets are local and
loaded through `assetPath`.

Generated screenshots, raw profiles, reports, databases, and build outputs stay
in ignored runtime/output locations. Reviewed bounded machine-readable baselines
consumed by deterministic regression tooling live beside that tooling under
`Config/nix/baselines/`; disposable analysis belongs under `.pi/tmp/`.

## Documentation And Work

- `docs/README.md` — documentation retention model
- `docs/architecture/README.md` — subsystem boundaries and queries
- `docs/adr/README.md` — durable decisions
- `docs/workstreams/` — unresolved design linked to GitHub issues
- `docs/runbooks/production-build-profiling.md` — safe NAS/grill build profiling
- GitHub Issues — only live implementation router and status tracker

## License

Apache License 2.0. See [LICENSE](./LICENSE) and
[THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md).
