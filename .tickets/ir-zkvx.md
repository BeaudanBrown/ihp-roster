---
id: ir-zkvx
status: open
deps: [ir-6k5d]
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

