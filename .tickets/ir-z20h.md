---
id: ir-z20h
status: open
deps: []
links: [ir-9jap]
created: 2026-07-09T02:39:01Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, area:ui, area:admin, venue:rooks]
---
# Rooks demo UI and admin polish

Implement concrete non-payroll UX and admin improvements from the Rooks demo notes.

## Design

Keep these as focused polish chunks rather than broad onboarding or payroll scope. Preserve existing authorization, live-surface, overlay, and frontend asset conventions. Mandatory passkeys become a venue-level admin/owner toggle; super-admin support policy stays separate.

## Acceptance Criteria

New staff creation defaults active without exposing an active toggle; venues can require passkeys for admins/owners; trial staff invite affordance is visible from the staff list; single-roster-group venues hide unnecessary roster-group configuration; roster slot-name sections can be minimised; shift preferences save without a full reload and are clearer; time picker range is venue-configurable or documented through existing operational-day bounds; modal close, create-venue width, accordion lag, and Mac colour picker issues are fixed or explicitly documented with follow-ups.

