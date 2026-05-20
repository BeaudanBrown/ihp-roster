# Staff Documents

## RSA Effective Current State

RSA document rows are append-only. Uploading an RSA document always creates a new
`staff_documents` row with `status = pending_review`; existing rows are retained
for audit/history and are not edited in place.

The helper contract in `Application.StaffDocuments.Rsa` is the source of truth
for current-vs-history presentation:

- `effectiveRsaState today documents` accepts a newest-first list of RSA rows for
  one staff member and returns the effective current document, initial pending
  document, pending replacement, latest rejected replacement, and compliance
  state.
- A first upload with no reviewed history is `StaffRsaPendingReview`.
- A later pending upload with an older reviewed document is
  `StaffRsaPendingReplacement`; the pending row is reviewable, while the older
  verified/expired row remains retained as the current reviewed document.
- If a replacement is rejected and an older verified RSA still exists, the older
  row remains the effective current document and the rejected row is exposed as
  `rsaRejectedReplacement` for manager context.
- If there is no older reviewed document, a rejected latest row leaves the staff
  member in `StaffRsaRejected`.
- Expiring and expired decisions are calculated against the effective current
  reviewed document; reminder jobs target that effective current row, not a
  pending replacement.

`staffRsaComplianceRowsForVenue` uses this read model for manager/admin
compliance views so those surfaces can distinguish missing, pending review,
pending replacement, verified, expiring, expired, and rejected states without a
separate full history UI.
