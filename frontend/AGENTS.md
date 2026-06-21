# Frontend TypeScript Agent Notes

Read this before editing `frontend/ts/`.

## Source And Generated Files

- App-owned JavaScript source lives in `frontend/ts/`.
- Generated browser assets live in `static/app*.js` and are still loaded by IHP through `assetPath`.
- Generated TypeScript contracts live in `frontend/ts/generated/` and are backend-owned. Do not hand-edit generated files.
- Use Nix/devenv entrypoints, not developer-facing `npm`/`npx` commands.

## Testing

- Use `bash ./bin/in-env frontend-test` for fast TypeScript unit/DOM tests.
- `bash ./bin/in-env frontend-check` runs contract drift, TypeScript validation, frontend unit/DOM tests, and generated JS drift.
- Put importable logic tests under `frontend/ts/tests/` and prefer small modules under `frontend/ts/shared/` or feature-local modules.
- Unit/DOM tests should cover pure decisions, parser/contract boundaries, and DOM helpers that can be exercised without the IHP server.
- Use Playwright via `bash ./bin/in-env e2e ...` for browser/server integration: HTMX, Bootstrap behavior, websockets/live updates, layout, roster interactions, mobile behavior, and anything requiring real browser APIs.
- Do not add frontend unit tests or Playwright E2E to pre-commit hooks. The hook is for generated asset drift only.
