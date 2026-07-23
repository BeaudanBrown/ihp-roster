# Stripe `2026-06-24.dahlia` fixtures

These deterministic offline fixtures preserve only the response and snapshot
event fields consumed by Bepis. They are curated from a reviewed test-mode
Checkout/Portal/webhook flow and checked against Stripe's OpenAPI description;
they are not raw provider payload archives.

## Provenance

- Stripe API version: `2026-06-24.dahlia`
- Stripe OpenAPI repository: `https://github.com/stripe/openapi`
- Reviewed commit: `86b6ae4db114ff06968dcc191ff4a898e9b5db7c`
- Upstream source: `openapi/spec3.json`
- Immutable upstream cache: `vendor/stripe-openapi/spec3-2026-06-24.dahlia.json.gz`
- Upstream source SHA-256: `e24a26de4188fd64dec4c043d5d3726277fdcb07556a493ea481c305b0a223d8`
- Reviewed contract slice: `vendor/stripe-openapi/bepis-contract.json`
- Offline check: `scripts/check-stripe-openapi-contract` (compares the slice and fixtures to the cached upstream source)

The fixture identifiers and values are synthetic or sanitized. Hosted URLs keep
Stripe's real HTTPS hosts and path shapes so the fixtures exercise Bepis's exact
redirect allowlist. Customer details, session tokens, payment methods, addresses,
tax data, credentials, and unrestricted provider fields are excluded.

## Reviewed refresh procedure

1. Check out `stripe/openapi` at the proposed immutable commit and confirm its
   `info.version` is the API version pinned in `Application/Billing/Stripe.hs`.
2. Run:

   ```bash
   scripts/update-stripe-openapi-contract /path/to/stripe-openapi/openapi/spec3.json
   ```

3. Refresh fixtures only from a controlled Stripe **test-mode** flow. Manually
   retain the minimum fields consumed by Bepis; never copy an unrestricted API
   response or webhook payload into this repository.
4. Replace all provider/customer identifiers and hosted URL tokens with clearly
   synthetic values. Remove payment methods, card/bank data, addresses, tax
   identifiers, email addresses, credentials, and unrelated expandable fields.
5. Run `scripts/check-stripe-openapi-contract` and the focused Billing Hspec
   suites offline.
6. Diff-review the OpenAPI slice and every fixture. The reviewer must confirm
   the pinned commit/version, consumed field changes, sanitization, discriminator
   and mode values, and all subscription lifecycle paths before merge.

Fixture refreshes are deliberate source changes. No script fetches or imports
live provider responses automatically.
