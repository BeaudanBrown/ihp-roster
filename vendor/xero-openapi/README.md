# Xero OpenAPI Vendor Files

This directory contains the contracts used by Bepis's offline Xero
request-construction tests.

## Official upstream files

These files are unmodified downloads from one commit of
<https://github.com/XeroAPI/Xero-OpenAPI>:

- `xero-identity.yaml`
- `xero-payroll-au.yaml` (Payroll AU v1)
- `xero-payroll-au-v2.yaml`
- `xero-accounting.yaml` (upstream name: `xero_accounting.yaml`)

`manifest.json` records the shared upstream commit, exact source URL, and SHA256
for each file. Never edit an official file locally.

## Local contract supplement

`xero-payroll-au-v2-earnings-rates.local.yaml` is a **local Bepis contract
supplement, not official Xero OpenAPI**. At the retrieval date recorded in that
file and `manifest.json`, Xero's official Payroll AU v2 source did not contain
`/earningsRates`. The supplement records the official documentation provenance
and Bepis's explicit request/response assumptions.

The upstream refresh script preserves this file. It deliberately fails if the
official v2 source gains an Earnings Rates path, so an operator must remove the
exception rather than accidentally maintaining two authorities.

## Refresh and verification

Refresh all official files from current upstream `master`:

```bash
scripts/update-xero-openapi
```

For a reproducible refresh, pass a full upstream commit SHA:

```bash
scripts/update-xero-openapi <40-character-commit>
```

Verify committed checksums, provenance, required operations, and official/local
separation without network access:

```bash
python3 scripts/check-xero-openapi-contract
```

The safe read-only provider-gap probe requires an explicitly selected connection,
refuses CI, checks the expected tenant id, and prints only response structure:

```bash
XERO_ALLOW_LIVE_PROBE=1 \
XERO_ALLOW_LIVE_PROBE_TENANT_ID=<tenant-id> \
xero-pay-item-probe app --connection-id=<connection-uuid> --probe-earnings-rates-v2
```

The probe uses only an already-valid stored access token and refuses rather than
refreshing or persisting connection state. Use the normal Xero workflow first if
the stored token is near expiry. Run the probe only against a Demo Company or
disposable test tenant, and never as routine test verification.
