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

## RSA PDF Metadata Prefill

RSA upload supports a deterministic PDF scan step before saving a document. The
scan uses local Poppler-compatible `pdftotext` extraction (`RSA_PDFTOTEXT_COMMAND`
can override the binary) and the parser in `Application.StaffDocuments.RsaExtraction`.
It does not use AI, LLMs, external document processors, or third-party document
AI services.

The scan result is only a candidate prefill for the existing upload fields:
issue date, expiry date, issuing authority, and document number. The extracted
recipient name is shown for confirmation and mismatch warnings against the
selected staff member; it is not stored as authoritative staff identity. The user
or manager must confirm or edit the metadata before `staff_documents` is written,
and the saved row remains `pending_review` until the normal manager review flow
verifies or rejects it.

Failure and low-confidence cases fall back to manual confirmation instead of
blocking upload. Empty/scanned PDFs, missing `pdftotext`, command failures, and
uncertain parser output produce warnings and blank or partial fields for the user
to complete. JPG and PNG uploads are manual-only and continue through the normal
upload path without scanning.

Supported upload file types are PDF, JPEG, and PNG, with the existing 10 MB file
limit, venue scoping, role checks, live invalidation, review status transitions,
and reminder behavior unchanged. OCR for image-only PDFs is out of V1 scope and
should be added only behind a future ticket with explicit privacy and dependency
review.
