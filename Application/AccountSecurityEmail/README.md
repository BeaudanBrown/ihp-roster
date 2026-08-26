# Account-security email delivery

## Boundary

Email verification, password-reset, and passkey setup/recovery producers persist
the token and enqueue one permanent-deduplicated `email_delivery` envelope in the
same transaction. Envelopes contain the token row ID, snapshotted recipient
address, and recipient account ID. They never contain a raw token or generated
URL.

`Application.AccountSecurityEmail.Email` owns delivery-time projection and
eligibility. `Application.EmailDelivery` alone owns SMTP, disabled delivery,
retries, and terminal job results.

## Secret handling

Password-reset and passkey token rows continue to store the one-way token hash
used by public endpoints. Newly issued rows also retain a nullable, short-lived,
authenticated-encrypted delivery projection. AES-256-GCM derives a domain-separated
key from IHP's existing session-secret material, available identically to the web
and worker processes. The ciphertext is cleared after sent, skipped, disabled,
consumed, replaced, revoked-by-staff-removal, or final-failure completion.

Email-verification rows retain their existing random token column. No additional
secret copy is introduced.

Migration `1788003000.sql` adds only nullable ciphertext columns. Existing active
tokens remain valid and require no backfill because their email was handled by
the retired synchronous path.

## Delivery validity

Token row locks serialize delivery against consumption and replacement. Delivery
requires:

- the exact token/account/address snapshot;
- an unconsumed, unexpired token;
- an active account whose current email still matches the snapshot;
- an unverified account for verification mail;
- for administrator-issued password/passkey links, an active target venue
  membership and current venue-admin, venue-owner, or active-super-admin issuer
  authority;
- valid self-issuance provenance for self passkey links.

Obsolete enabled jobs complete as `delivery_skipped`. Disabled delivery validates
provenance but completes as `delivery_disabled` and is never replayed merely by
reenabling SMTP. Provider failures use the shared ten-attempt policy; final
failure clears recoverable delivery material without persisting provider detail.

## Verification

```bash
bash ./bin/in-env hspec-test --match "Account security email delivery"
bash ./bin/in-env hspec-test --match "PasskeysController" --match "SessionsController" --match "UsersController"
bash ./bin/in-env typecheck
```
