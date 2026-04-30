# Pipeline 64 - Xero OpenAPI Contract And Probe Hardening

Read after `IMPLEMENTATION_PLAN.md`, `plans/57-xero-payroll-integration.md`,
`plans/58-xero-connection-foundation.md`,
`plans/63-xero-timesheet-submission.md`, and `.tickets/ir-176p.md`.

## Goal

Make Xero request construction mechanically verifiable for agents, and make
live Xero diagnostics safe enough that real error responses can be collected
without leaking token material or accidentally mutating the wrong tenant.

The project should not rely on agent memory, Postman collections, or prose docs
for endpoint details. Xero's official OpenAPI specs should be vendored into the
repo as the local source of truth, then used by tests and future tooling.

## Tickets

- `ir-pedb` - Vendor Xero OpenAPI specs and contract-test request construction.
- `ir-4fba` - Harden Xero live probe scripts for agent-safe diagnostics.
- `ir-mr3v` - Generate strict local Xero mock endpoints from the vendored
  contract.

`ir-pedb` should land first. Probe hardening and local mock generation depend on
the local contract being available.

## OpenAPI Contract

Vendor the official Xero specs under:

```text
vendor/xero-openapi/
  README.md
  manifest.json
  xero-identity.yaml
  xero-payroll-au.yaml
```

The manifest should record:

- upstream repo: `https://github.com/XeroAPI/Xero-OpenAPI`
- source URLs for each vendored file
- upstream release or commit SHA
- fetched timestamp
- expected SHA256 for each file

The initial implementation needs only Identity and Payroll AU because the app
currently uses:

- `POST https://identity.xero.com/connect/token`
- `GET https://api.xero.com/connections`
- `DELETE https://api.xero.com/connections/{connectionId}`
- `GET https://api.xero.com/payroll.xro/1.0/Employees`
- `GET`/`POST https://api.xero.com/payroll.xro/1.0/PayItems`
- `GET https://api.xero.com/payroll.xro/1.0/PayrollCalendars`
- `GET`/`POST https://api.xero.com/payroll.xro/1.0/Timesheets`
- `GET`/`POST
  https://api.xero.com/payroll.xro/1.0/Timesheets/{TimesheetID}`

Add a script such as `scripts/update-xero-openapi` or a devenv shell script that
refreshes those files. It should fail if required specs or paths are missing.
Network fetching requires explicit approval when agents run it; ordinary tests
must use the committed local files.

## Request Construction Tests

Refactor `Application.Helper.Xero` only enough to expose request construction
without performing HTTP. Prefer a small internal representation over a broad
mocking framework, for example:

```haskell
data XeroHttpRequest = XeroHttpRequest
    { method :: ByteString
    , url :: Text
    , headers :: [(ByteString, ByteString)]
    , body :: Maybe Aeson.Value
    }
```

The existing runtime functions can convert that representation to
`Network.HTTP.Simple.Request` immediately before `httpLBS`.

Add a focused Hspec module such as `Test/XeroContractSpec.hs`. It should load
the vendored YAML and verify:

- base server URLs match the spec
- methods and paths match the spec
- Payroll AU requests include `Xero-Tenant-Id`
- writes include `Idempotency-Key` and JSON content type
- token requests use the Identity token endpoint and form body
- Xero Payroll AU create/update bodies use the OpenAPI array envelope where
  required, especially `POST /Timesheets` and `POST /Timesheets/{TimesheetID}`
- timesheet list query params and `If-Modified-Since` are encoded in the
  expected request locations

These tests are contract tests for local request rendering. They should not hit
Xero, require OAuth credentials, or depend on Postgres.

## Probe Hardening

`xero-pay-item-probe` is useful, but agents should treat it as a live external
system tool.

Keep these rules:

- read-only local inspection is allowed through `--connections` and `--list`
- real GETs must be clearly labelled as real Xero network calls
- no tokens or auth headers are printed
- mutation must require more than `--confirm-post`

Recommended mutation gate:

```text
--confirm-post
XERO_ALLOW_MUTATION_TENANT_ID=<tenant-id>
```

The command should refuse to POST unless the environment tenant id exactly
matches the selected connection's `tenantId`. This makes accidental mutation of
the wrong organisation harder.

Every real Xero call should write a redacted artifact under:

```text
output/xero-probes/<timestamp>-<operation>.json
```

Include:

- operation name
- tenant id and tenant name
- method
- URL path, not bearer token
- request body when present
- status code
- response body
- idempotency key when present

Exclude:

- `Authorization`
- access tokens
- refresh tokens
- client secret
- token encryption key

Document clearly that refreshing the connection rotates Xero refresh tokens and
can make `build/dev-xero-connection.sql` stale.

## Strict Local Mock

The local mock is a later layer, after the vendored specs exist. It should be a
strict request verifier, not a hand-written simulation of Xero business rules.

Use a local WAI/Warp server or equivalent Hspec harness that:

- accepts only methods and paths present in the vendored spec
- rejects missing required headers
- rejects wrong JSON envelope shapes
- returns small redacted fixture responses

Fixtures may come from OpenAPI examples or redacted Demo Company responses. Do
not commit customer data, token material, or local encrypted token rows.

## Verification

For OpenAPI contract work:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Xero contract"
```

For probe hardening:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Xero"
```

Only run real Xero probe calls when explicitly asked and when the target tenant
is known to be a Demo Company or disposable test tenant.
