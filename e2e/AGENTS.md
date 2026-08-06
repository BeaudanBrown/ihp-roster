# Playwright E2E Agent Guide

## Commands

Use the repository wrapper; it selects pinned Playwright and isolated runtime
state. Do not use bare `npx playwright`.

```bash
bash ./bin/in-env e2e
bash ./bin/in-env e2e-fast
bash ./bin/in-env e2e e2e/auth.spec.ts
bash ./bin/in-env env PLAYWRIGHT_RETRIES=0 e2e e2e/auth.spec.ts
bash ./bin/in-env e2e-report
bash ./bin/in-env screenshot-page /RosterWeeks output/check.png --selector '#roster-week-shell'
bash ./bin/in-env pwcli --help
```

`e2e` is the complete gate; `e2e-fast` runs each source behavior on desktop and
the canonical Pixel profile. Focused/interactive runs default to one shard;
complete runs use isolated app/database shards. Do not treat a focused or fast
run as complete evidence.

Managed E2E owns disposable native PostgreSQL/runtime state. Inspect it through
`e2e-runtime` and `e2e-postgres`; never infer sockets, ports, database names, or
precreate managed roots. External mode requires an explicit mode/socket pair and
refuses destructive lifecycle operations. Failure artifacts are copied under
`.devenv/e2e/`; use dry-run-first cleanup commands.

## Writing Tests

Put `*.spec.ts` under `e2e/`. Use helpers from `e2e/test-helpers.ts`:

- `gotoWhenReady` for cold compile/startup transitions
- `loginAs` for reusable ordinary sessions
- fresh-session/passkey helpers when authentication, passkeys, or step-up is the
  behavior under test
- `openRoster` for canonical roster-grid setup
- export helpers for report navigation/download assertions

Wait for the destination shell as well as the URL. Assert concrete outcomes,
not sleeps: never use `page.waitForTimeout` to settle normal flows. Prefer stable
IDs/data attributes and behavior over Bootstrap classes, broad body text, or
pixel-perfect screenshots. Use `E2E_TIMEOUT` names; do not add numeric timeout
literals to specs/helpers.

For HTMX, assert shell/fragment changes and navigation behavior. For
`FrontendSurface`, assert generated mount config, subscriptions/request headers,
semantic refetch/resync, and the exact protection behavior affected by the
change; do not rely on deprecated client-ID DOM state.

## Fixtures And Isolation

Fixtures live in `e2e/fixtures/seed.sql`, use fixed UUIDs and idempotent inserts,
and prefix dynamic emails/identifiers with `e2e-`. Use `uniqueE2EValue` for
worker-visible dynamic values. Every spec file must work in a separate shard DB
and must not rely on test order or shared mutation state.

Seeded ordinary users are `e2e-test@example.com`, `e2e-admin@example.com`, and
`e2e-worker@example.com`, with password `test-password-123`. Auth fixtures also
need venue config and memberships. Keep fixed-row mutations resettable at seed
start; clean dependent rows before users. Never clear shared MailHog globally—
match a unique recipient.

Do not weaken canonical wage/payroll fixture completeness or cross-venue
separation to simplify a test. Real external API probes are diagnostics, not CI
or production authority.

## Browser Exploration And Responsive Work

Use the stateful Playwright Agent CLI for exploration: start with
`pi-playwright doctor`, then the project `pwcli` adapter. Confirm
`dev-workspace-info --json`, seed only local development data, and use role auth
helpers. Never browse production/customer data or commit browser profiles,
storage state, traces, or exploratory artifacts. Convert useful flows into
normal deterministic specs.

Desktop, canonical mobile, narrow Android, and tablet projects protect different
layout/input behavior. Use `@canonical-mobile` only for device-independent
assertions; keep overflow, breakpoint, touch, wheel, snapping, and dialog-fit
checks profile-sensitive. Use structural assertions first and opt-in screenshot
suites for visual diagnosis.

## Verification And Diagnosis

Before blaming Playwright, inspect `e2e-runtime runs`, its run log, and
`e2e-postgres status`. Distinguish app/test failures from startup/runtime
infrastructure failures. Run the focused file while iterating, then the required
fast or complete tier. Use profile commands only for performance investigations;
profile outputs are evidence, not regression gates.
