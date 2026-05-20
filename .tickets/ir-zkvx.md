---
id: ir-zkvx
status: closed
deps: [ir-6k5d, ir-96hz]
links: []
created: 2026-05-20T07:24:35Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-sh3h
tags: [agent-loop, area:staff, area:compliance, area:rsa, area:schema]
---
# Persist RSA extraction audit metadata

Record minimal provenance for confirmed RSA metadata extraction without storing unnecessary certificate text.

## Design

Add nullable staff_documents extraction provenance fields only if implementation confirms they are useful for support/debugging: extraction_method, extraction_confidence, extraction_warnings_json, and extracted_subject_name or equivalent. Do not store full raw OCR/text output by default. Keep confirmed issue/expiry/issuer/document number in existing columns. Update generated types and schema tests if schema changes are made.

## Acceptance Criteria

Confirmed scanned-prefill uploads can be distinguished from fully manual uploads; stored provenance is minimal, venue-scoped, and does not include full certificate text; schema constraints remain parser-safe; generated types and focused schema/domain tests pass. If implementation chooses no schema change, this ticket records the rationale in notes and closes after tests confirm behavior is still auditable enough through existing audit events.


## Notes

**2026-05-20T07:39:42Z**

Refinement: provenance/history should not make the user-facing UI complex. Keep append-only rows for audit/posterity; expose current document only unless a later audit/history view is explicitly requested. Consider documenting current-vs-historical row semantics rather than adding broad history UI.

**2026-05-20T08:15:20Z**

Added nullable staff_documents RSA extraction provenance columns, persisted scan confirmation metadata without raw extracted text, updated docs/tests, and verified regen-types/typecheck/focused Hspec.
