# Feedback

The Feedback page owns global public reading and platform moderation; Support
no longer loads feedback records or exposes feedback controls.

- `ReadModel` is the explicit global public projection. Never pass database
  feedback records or retained provenance into ordinary card rendering.
- `Management` authorizes unimpersonated platform super admins before projecting
  private metadata. Venue roles do not confer editorial authority.
- `Domain` serializes lifecycle and vote operations on the feedback row. It opens
  a transaction for standalone callers and reuses the enclosing mutation
  transaction when audit and durable invalidation must commit with the change.
- `Mutations` owns application writes, typed audit events, notification enqueue,
  and durable resources. Global moderation audits use the submission's venue,
  not the founder's selected support venue.
- `LiveUpdates` and `Surface/Feedback` own public/review/count fragments. Public
  reads remain global even though subscription authorization uses the current
  venue; the shared resource is deliberately not venue-keyed.

New submissions use the existing [email-delivery boundary](../EmailDelivery/SPEC.md).
Moderation does not send submitter notifications. No feedback data is removed by
moving the review interface: legacy notes and diagnostics remain private.

Focused verification: `hspec-test --match Feedback --match SupportController` and
`e2e e2e/feedback-moderation.spec.ts e2e/feedback-diagnostics.spec.ts` through
`bin/in-env`.
