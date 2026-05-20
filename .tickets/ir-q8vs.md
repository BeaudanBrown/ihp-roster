---
id: ir-q8vs
status: closed
deps: []
links: []
created: 2026-05-20T07:24:35Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-sh3h
tags: [agent-loop, area:staff, area:compliance, area:rsa]
---
# Add deterministic RSA PDF extraction service

Introduce an application helper for extracting text and candidate metadata from RSA PDFs using local deterministic tooling.

## Design

Add a focused Application/StaffDocuments extraction module. Shell out to configured local Poppler/pdftotext or equivalent packaged command for text-layer PDFs, preferably layout-preserving output. Parse broad certificate patterns rather than a single template: date ranges, valid-from/until labels, certificate-number labels, RSA/program/authority keywords, and plausible recipient-name lines. Return a structured result with candidates, confidence/warnings, extraction method/version, and failure reason. Do not mutate staff_documents in this layer.

## Acceptance Criteria

Unit tests cover the current sample shape via sanitized fixture text, date range parsing such as '21 January 2024 - 21 January 2027', certificate-number variants, authority extraction, recipient-name candidate extraction, empty/scanned-PDF failure behavior, and parser warnings. Production/runtime dependencies needed for extraction are declared in Nix packaging. No controller or schema behavior changes are required in this ticket.


## Notes

**2026-05-20T07:46:19Z**

Implemented deterministic RSA PDF text extraction helper using local pdftotext, with parser candidates/warnings/failure result and focused Hspec coverage for sample text, date ranges, document numbers, authority/name extraction, empty text fallback, and low-confidence warnings. Verified with focused RSA extraction/staff-document specs and typecheck.
