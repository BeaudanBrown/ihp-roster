# Stripe `2026-06-24.dahlia` fixtures

These deterministic offline fixtures preserve the pinned response and snapshot
event shapes used by Bepis. They are curated from the confirmed test-mode
Checkout/Portal/webhook flow and Stripe's pinned API reference; they are not raw
provider payload archives.

Identifiers, customer details, session tokens, and URL fragments are sanitized.
Hosted URLs retain Stripe's real HTTPS hosts and path shapes so the same fixtures
also exercise the redirect allowlist. Do not add payment methods, addresses, tax
data, credentials, or unrestricted payloads here.
