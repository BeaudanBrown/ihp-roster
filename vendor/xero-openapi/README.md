# Xero OpenAPI Vendor Files

This directory vendors the official Xero OpenAPI files used by the app's offline
request-construction contract tests.

Upstream: https://github.com/XeroAPI/Xero-OpenAPI

Current pinned commit: `d13ffb45b17881ce5a5ee11ecb5f2be59f795eb6`

Files:

- `xero-identity.yaml`
- `xero-payroll-au.yaml`
- `manifest.json`

Refresh with:

```bash
scripts/update-xero-openapi
```

The refresh script downloads the specs, validates that the endpoints used by the
app are present, computes SHA256 checksums, and rewrites `manifest.json`.
