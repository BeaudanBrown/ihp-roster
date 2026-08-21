# Invitation Email Delivery

## Boundary

`Application.InvitationDelivery.Enqueue` creates versioned shared-email envelopes for
venue and venue-onboarding invitations. Production creation and replacement flows call
it inside the same transaction that writes and revokes invitation rows.

`Application.InvitationDelivery.Email` owns delivery-time eligibility, URL generation,
typed mail projection, invitation delivery facts, final-failure projection, and venue
invite invalidation. `Application.EmailDelivery` alone owns transport, disabled
delivery, retries, and terminal job results.

## Contract

- Envelopes reference invitation row IDs and snapshot only the destination address; no
  generated acceptance URL or separate token is persisted in a job.
- Pre-account recipients use the invitation ID as their stable recipient identity.
- Existing invitation row locks serialize delivery against acceptance, renewal,
  revocation, and corrected-email replacement.
- Consumed, revoked/replaced, expired, already-delivered, missing, and snapshot-mismatch
  invitations skip without transport.
- Valid sent and disabled delivery marks the invitation sent. Final provider failure
  records only `Email delivery failed after ten attempts.`; provider details are not
  copied into invitation state.
- Migration `1788002400.sql` retires active legacy delivery jobs while preserving all
  terminal history. No legacy producer or handler remains.

## Verification

```bash
bash ./bin/in-env hspec-test --match "Venue invitation helper" --match "Venue onboarding invitation helper"
bash ./bin/in-env hspec-test --match "StaffController" --match "VenueAccess"
bash ./bin/in-env typecheck
```
