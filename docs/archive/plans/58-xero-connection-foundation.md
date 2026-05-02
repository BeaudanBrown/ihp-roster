# Pipeline 58 - Xero Connection Foundation

Read after `IMPLEMENTATION_PLAN.md`, `docs/archive/plans/57-xero-payroll-integration.md`,
`AGENTS.md`, `Web/Controller/AGENTS.md`, and `Web/View/AGENTS.md`.

**Current status, 2026-04-30:** the original venue-admin access wording in this
plan is superseded. Current code and tests restrict Xero connection, sync,
mapping, preview, and submission surfaces to the current venue owner or a super
admin. Venue admins should not see or manage Xero controls.

## Goal

Implement the first local Xero integration slice: a venue owner can open the
Xero UI, start Xero OAuth, authorize a demo company, return to ihp-roster, and
see the connected Xero tenant recorded for the current venue.

This plan intentionally stops before employee sync, earnings-rate sync, payroll
calendar sync, mapping UI, timesheet preview, or draft-timesheet submission.

This file is the repo-local implementation handoff.

## Local Preconditions

The developer has already created a Xero OAuth app and put local secrets in
`.env`. Never print or inspect `.env` contents. Verify presence only with
non-secret checks such as:

```bash
bash ./bin/in-env sh -c 'test -n "$XERO_CLIENT_ID" && test -n "$XERO_CLIENT_SECRET" && test -n "$XERO_REDIRECT_URI" && test -n "$XERO_TOKEN_ENCRYPTION_KEY" && echo "xero env present"'
```

The Xero app redirect URI must match the local callback URL exactly. The
expected local value is:

```text
http://localhost:8000/XeroOAuthCallback
```

## Product Shape

Add a Xero management surface for venue owners and super admins.

For an unconnected venue, show:

- status: not connected
- a `Connect Xero` button that starts the OAuth flow
- a short warning that connecting grants access to the selected Xero
  organisation for payroll integration setup

For a connected venue, show:

- status: connected
- tenant name
- tenant id, if useful for debugging
- connected timestamp and actor, if available
- reconnect and disconnect actions

Keep the first UI native/full-page. This is a low-frequency external OAuth
workflow, not a live collaborative surface.

## Data Model

Add `xero_connections` as a venue-scoped protected record.

Recommended fields:

- `venue_id UUID NOT NULL REFERENCES venues(id) ON DELETE RESTRICT`
- `tenant_id TEXT NOT NULL`
- `tenant_name TEXT`
- `connection_status TEXT NOT NULL`
- `scopes TEXT NOT NULL`
- `encrypted_refresh_token TEXT NOT NULL`
- `encrypted_access_token TEXT`
- `access_token_expires_at TIMESTAMP WITH TIME ZONE`
- `last_refreshed_at TIMESTAMP WITH TIME ZONE`
- `last_sync_at TIMESTAMP WITH TIME ZONE`
- `last_error TEXT`
- `connected_by_user_id UUID REFERENCES users(id) ON DELETE RESTRICT`
- `connected_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()`
- `disconnected_by_user_id UUID REFERENCES users(id) ON DELETE RESTRICT`
- `disconnected_at TIMESTAMP WITH TIME ZONE`
- normal timestamps if consistent with nearby tables

Use explicit text checks instead of Postgres enum types if that avoids IHP
schema-parser edge cases. Suggested statuses:

- `active`
- `disconnected`
- `reauthorization_required`
- `error`

At most one active connection should exist per venue. Prefer a partial unique
index for active rows if it parses cleanly; otherwise enforce in controller
logic and tests.

Add `xero_oauth_states` for short-lived CSRF/state validation.

Recommended fields:

- `venue_id UUID NOT NULL REFERENCES venues(id) ON DELETE RESTRICT`
- `user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT`
- `state_token TEXT NOT NULL UNIQUE`
- `requested_scopes TEXT NOT NULL`
- `redirect_uri TEXT NOT NULL`
- `expires_at TIMESTAMP WITH TIME ZONE NOT NULL`
- `consumed_at TIMESTAMP WITH TIME ZONE`
- `created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()`

OAuth state rows may be deleted by cleanup later, but the first slice can leave
expired rows in place.

Protect Xero connection rows from hard delete from day one. Disconnect should
mark status and disconnected metadata rather than deleting token history.

## Configuration

Add a narrow config/helper module that reads:

- `XERO_CLIENT_ID`
- `XERO_CLIENT_SECRET`
- `XERO_REDIRECT_URI`
- `XERO_TOKEN_ENCRYPTION_KEY`

Fail clearly in development if the Xero section is used without required
configuration. Do not make the whole app fail to boot merely because Xero env is
missing; other app surfaces should remain usable.

The token encryption secret is app-owned, not from Xero. Use it only server-side
for encrypting token material at rest.

## Xero OAuth Client Boundary

Add a small Xero client boundary under `Application/Xero/` or
`Application/Helper/Xero/`, whichever best matches existing app patterns.

It should provide:

- authorization URL builder
- token exchange for OAuth callback `code`
- connected tenant lookup via Xero connections API
- token refresh helper, even if only minimally used in this slice
- typed success/error results that controllers can handle without stringly
  parsing

Required scopes for the first connection:

- `offline_access`
- `payroll.employees.read`
- `payroll.settings`
- `payroll.timesheets`

Add `payroll.timesheets.read` only if manual verification shows the configured
Xero app does not treat the write scope as sufficient for reads.

Do not request employee-write or settings-write scopes in this slice.

## Controller Actions

Add Admin-controller actions or a dedicated Xero controller if the route shape is
cleaner. Minimal actions:

- `StartXeroConnectionAction`
- `XeroOAuthCallbackAction`
- `DisconnectXeroConnectionAction`

`StartXeroConnectionAction` should:

- require authenticated current user
- require current venue
- require completed profile
- require venue owner or super-admin Xero access
- create an unconsumed OAuth state row for the current venue/user
- redirect to Xero's authorization URL

`XeroOAuthCallbackAction` should:

- validate callback `state`
- reject missing, expired, already-consumed, wrong-user, or wrong-venue state
- handle `error` callback params from Xero
- exchange `code` for tokens
- fetch connected tenants
- select the tenant to store
- encrypt token material before persistence
- mark the OAuth state consumed
- upsert or supersede the venue connection
- record audit events
- redirect back to `/Xero` with success or error flash

If Xero returns more than one connected tenant, the first implementation may
store the first tenant and leave explicit tenant picker UI for the next slice,
but the code should make that behavior obvious and easy to replace.

`DisconnectXeroConnectionAction` should:

- require venue owner or super-admin Xero access
- mark the active connection `disconnected`
- clear or retain encrypted tokens according to the chosen retention policy
- record disconnected actor/time and audit
- redirect back to `/Xero`

## Audit

Record structured audit events for:

- Xero connection started
- Xero connection completed
- Xero connection failed
- Xero connection disconnected
- Xero token refresh failed, if refresh is exercised

Include support-mode distinction automatically if the existing audit helper
already captures it; otherwise include enough payload to identify current venue,
actor, source channel, tenant id/name, and failure class.

Never include raw access tokens, refresh tokens, client secret, or encryption key
in audit payloads or logs.

## Xero UI Integration

Extend the Xero/admin controller and views so the owner-only Xero page loads the
current venue's active Xero connection and renders the Xero section.

Keep the section visually consistent with existing admin configuration sections.
Use normal form buttons and redirects for connect/disconnect.

Suggested accordion placement: after `Exports`, because Xero builds on payroll
export/report foundations.

## Verification

Required local checks after schema/code changes:

```bash
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test
bash ./bin/in-env lint
```

After schema changes, apply to the dev database and restart the dev app:

```bash
bash ./bin/in-env dev-start
bash ./bin/in-env dev-wait
make db
bash ./bin/in-env dev-stop
bash ./bin/in-env dev-start
bash ./bin/in-env dev-wait
```

Manual verification:

1. Confirm Xero env vars are present without printing values.
2. Ensure the Xero developer app has redirect URI
   `http://localhost:8000/XeroOAuthCallback`.
3. Run `bash ./bin/in-env seed-dev app` if a deterministic owner login is
   needed.
4. Log in as a venue owner.
5. Open `/Xero`.
6. Confirm the Xero management page renders.
7. Click `Connect Xero`.
8. Authorize the demo company in Xero.
9. Return to ihp-roster.
10. Confirm `/Xero` shows connected tenant details.
11. Disconnect and confirm the status changes without hard deleting history.

## Test Coverage

Add focused controller/unit coverage for:

- Xero config missing errors are local to Xero actions
- OAuth state creation stores venue, user, scopes, redirect URI, and expiry
- callback rejects missing or invalid state
- callback rejects expired or already-consumed state
- callback handles Xero `error` response without storing tokens
- successful callback stores encrypted token material and tenant metadata
- raw token strings are not stored in plaintext
- disconnect marks connection status and actor metadata
- non-owner venue roles cannot start, callback, or disconnect for a venue

Use a mocked Xero client boundary for callback tests. Do not depend on live Xero
API calls in automated tests.

## Acceptance Criteria

This slice is complete when:

1. `/Xero` contains a Xero section for venue owners and super admins.
2. A local owner can start OAuth from the Xero section.
3. The app validates OAuth state on callback.
4. The app exchanges the callback code, fetches connected tenants, and stores the
   selected Xero tenant for the current venue.
5. Xero token material is encrypted at rest.
6. Disconnect/reconnect behavior is represented in UI and state.
7. Audit events exist for connection success/failure/disconnect.
8. Tests cover the local controller and token-storage behavior with a mocked
   Xero client boundary.
9. The manual demo-company flow works locally without reading or printing
   `.env`.

## Out Of Scope

- employee sync
- pay item / earnings-rate sync
- payroll calendar sync
- staff mapping UI
- earnings-rate mapping UI
- timesheet preview
- draft-timesheet submission
- Xero employee or pay item creation
- production deployment secret wiring
