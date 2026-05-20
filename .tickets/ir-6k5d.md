---
id: ir-6k5d
status: open
deps: [ir-q8vs, ir-96hz]
links: []
created: 2026-05-20T07:24:35Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-sh3h
tags: [agent-loop, area:staff, area:compliance, area:rsa, area:ui]
---
# Add RSA upload scan and confirmation flow

Wire the extraction service into the RSA upload UI so users can scan a PDF, review candidate metadata, edit fields, and then submit the existing upload.

## Design

Extend the StaffDocuments controller/view flow with a deterministic prefill path. Preserve the current manual form and upload endpoint as fallback. For PDFs, run extraction before final create, render candidate issue/expiry dates, issuer, document number, extracted-name check, confidence/warnings, and the selected file context. Require explicit confirmation before createRsaDocument. Keep non-PDF images manual unless OCR is added in a later ticket. Avoid storing unconfirmed extraction text.

## Acceptance Criteria

Staff and managers can upload a PDF and see prefilled editable metadata before saving; confirmation creates a pending_review staff_documents row with the confirmed values and original file; extraction failure shows a clear manual-entry fallback without losing the selected context; name mismatch with the selected staff is visible and does not silently block upload; existing manual PDF/JPG/PNG upload behavior remains available; access checks and venue scoping match the current RSA document controller tests.


## Notes

**2026-05-20T07:39:42Z**

Refinement: scan/confirm flow should preserve the one-current-RSA UX. A confirmed upload creates a new pending replacement. Users/managers should see the current document state clearly, with replacement pending/rejected states understandable rather than exposing a full history UI.
