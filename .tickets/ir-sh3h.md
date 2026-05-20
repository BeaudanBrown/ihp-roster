---
id: ir-sh3h
status: open
deps: []
links: []
created: 2026-05-20T07:24:35Z
type: epic
priority: 1
assignee: Beaudan Brown
parent: ir-9jap
tags: [agent-loop, area:staff, area:compliance, area:rsa, venue:rooks]
---
# Automate RSA PDF metadata prefill

Add deterministic RSA document extraction so staff/managers can upload an RSA PDF and get candidate metadata prefilled before confirming the existing staff document upload fields.

## Design

Use the existing staff_documents RSA pipeline as the source of truth. No AI/LLM or external document AI. Prefer local Poppler/pdftotext text extraction for PDFs with embedded text; OCR is out of V1 except as a documented future fallback. Extraction returns candidate values, confidence/warnings, and never silently verifies compliance. Users/admins confirm or edit before saving. Name extracted from the certificate is used for mismatch warnings against the selected staff member, not stored as authoritative staff identity unless a later ticket adds a field.

## Acceptance Criteria

Uploading an RSA PDF can prefill issue date, expiry date, issuing authority, and document number where confidently detected; extracted person name is surfaced as a warning/check against the selected staff member; failed/low-confidence extraction falls back to the current manual form; non-PDF JPG/PNG uploads still work manually; final saved staff_documents metadata is user-confirmed; no AI/LLM or third-party document processor is introduced; access controls, venue scoping, review status, file limits, and reminder behavior remain intact.

