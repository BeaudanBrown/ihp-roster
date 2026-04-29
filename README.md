# Bepis

Bepis is an IHP roster, leave, timesheet, export, and venue operations app.

The repository is tuned for agent-assisted work. Start with `AGENTS.md`, then read
the nearest subdirectory `AGENTS.md` before changing controllers, views, tests, or
application helpers.

## Repository Map

- `Application/Schema.sql` - source of truth for generated model types.
- `Application/Helper/` - shared domain, controller, and view helpers.
- `Web/Types.hs` - controller action types and app-level web types.
- `Web/Routes.hs` - `AutoRoute` instances.
- `Web/FrontController.hs` - mounted controllers and request context setup.
- `Web/Controller/` - controller implementations.
- `Web/View/` - HSX views and layout shell.
- `Test/` - Hspec coverage.
- `e2e/` - Playwright coverage.
- `plans/` and `specs/` - product and implementation planning.

## Local Workflow

Run project commands through the wrapper unless you are already inside the
activated devenv shell:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test
bash ./bin/in-env e2e
bash ./bin/in-env lint
bash ./bin/in-env format
```

For browser or integration work, use the managed dev server helpers:

```bash
bash ./bin/in-env dev-start
bash ./bin/in-env dev-wait
bash ./bin/in-env dev-stop
```

After schema edits, run:

```bash
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
```

Apply the schema to the local dev database with `make db` while the dev server is
running. This resets the local dev schema.

## Static Assets

Runtime assets are local and loaded through `assetPath` from
`Web/View/Layout.hs`.

- Bootstrap `5.3.8`
- Bootstrap Icons `1.11.3`
- HTMX `1.9.12`
- IHP-provided Flatpickr and Morphdom assets
- App CSS entrypoint: `static/app.css`
- App JS entrypoints: `static/app-bootstrap.js`, `static/app-date-pickers.js`,
  `static/app-passkeys.js`, `static/app-live-updates.js`, and `static/app.js`

Feature CSS is split under `static/css/`; update the narrowest matching file
instead of growing `static/app.css`.

## CI

`.github/workflows/test.yml` runs the same wrapper commands agents use locally:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test
```

Deployment is managed outside this workflow. Production NixOS configuration lives
under `Config/nix/`.

## Generated And Local Artifacts

Generated screenshots, profiles, reports, local databases, Nix build outputs, and
dev shell state are ignored. Keep durable visual references in documentation
assets, not under `output/`.
