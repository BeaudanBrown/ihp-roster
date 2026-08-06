# Staff Documents Specification

Start with `Application.StaffDocuments.Rsa` for RSA state and
`Application.StaffDocuments.RsaExtraction` for PDF metadata candidates. Web
workflow and authorization live in `Web/Controller/StaffDocuments.hs` and
`Web/StaffDocuments/Mutations.hs`; exact behavior is covered by
`Test/StaffDocumentsRsaSpec.hs` and controller tests.

## RSA History And Effective State

- RSA rows are append-only. Every upload creates a new `pending_review`
  `staff_documents` row; prior rows remain audit history.
- `effectiveRsaState` is the current/history authority for manager and staff
  panels. A pending replacement never displaces the older reviewed document.
  Rejecting a replacement likewise leaves an older verified document effective;
  without older reviewed evidence, rejection leaves the staff member rejected.
- Expiry state and reminder jobs use the effective reviewed document, not a
  pending replacement.
- Upload, review, and live invalidation remain venue-scoped and role-authorized.


## Access And Expiry

The read model remains the authority for reminders, review decisions, and
focused staff-document tests. Manager edit-staff and staff self-profile RSA
panels are intentionally not mounted; no FrontendSurface fragment or passive
resource advertises that unavailable UI.


- Linked staff may upload and download their own RSA evidence. Managers may
  upload, download, and review RSA evidence only for staff in their current
  venue; cross-venue access fails closed.
- Every RSA upload requires an expiry date and remains pending until manager
  verification. Manager/staff panels distinguish missing, pending, replacement,
  rejected, verified, expiring, and expired effective state.
- A verified effective document becomes expiring within 30 days. Deduplicated
  jobs email its linked user once for the expiring window and once after expiry,
  rechecking that the same reminder remains due before delivery. Expiry delivery
  marks the effective document expired. Pending replacements never redirect
  reminders away from the older reviewed document.

## PDF Metadata Candidates


- PDF scanning is local and deterministic through Poppler-compatible
  `pdftotext`; it does not use AI or an external document processor.
- Extracted dates, authority, document number, and subject name are candidate
  prefills only. A user or manager must confirm or correct them, and the saved
  document remains pending until normal review.
- Scanned uploads retain only minimal extraction provenance: method, confidence,
  warnings, and confirmed extracted subject name. Full certificate text and OCR
  output are not persisted. Manual uploads leave extraction provenance null.
- Missing tools, image-only PDFs, command failure, and low confidence fall back
  to manual confirmation rather than silently asserting metadata or blocking the
  upload.
- OCR or third-party extraction requires a separate privacy and dependency
  review.

The scan result is only a candidate prefill for the existing upload fields:
issue date, expiry date, issuing authority, and document number. The extracted
recipient name is shown for confirmation and mismatch warnings against the
selected staff member; when the confirmed upload is saved it is retained only as
minimal extraction provenance (`extracted_subject_name`), not as authoritative
staff identity. The user or manager must confirm or edit the metadata before
`staff_documents` is written, and the saved row remains `pending_review` until
the normal manager review flow verifies or rejects it.

Confirmed scanned-prefill uploads persist minimal provenance on `staff_documents`:
`extraction_method`, `extraction_confidence`, `extraction_warnings_json`, and
`extracted_subject_name`. Fully manual uploads leave those columns `NULL`. The
app does not persist full extracted certificate text or OCR output by default.

Failure and low-confidence cases fall back to manual confirmation after the PDF
has been uploaded for scanning instead of blocking upload. Empty/scanned PDFs,
missing `pdftotext`, command failures, and uncertain parser output produce
warnings and blank or partial fields for the user to complete.

The retained scan/upload/review controller flow remains scan-first and accepts
PDFs for the initial upload step, but it is not currently linked from profile or
edit-staff panels. Profile return paths resolve to the ordinary profile page,
not a hidden RSA section. Confirmed upload limits, venue scoping, role checks,
review status transitions, and reminder behavior remain unchanged. There is no
RSA live fragment to invalidate. OCR for image-only PDFs is out of V1 scope and
should be added only behind a future ticket with explicit privacy and dependency
review.
