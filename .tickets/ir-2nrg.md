---
id: ir-2nrg
status: closed
deps: []
links: []
created: 2026-07-08T09:28:50Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [area:payroll, area:fwc, area:xero, area:exports, agent-loop]
---
# Apply venue week-based FWC award-rate rollover across pay surfaces

Ensure Bepis consistently resolves FWC/MAPD award rates by award level, employment basis, worked/reference date, and the venue week-start rollover rule so UI labels, pay math, exports, Xero pay-item keys, and wage predictions use the same effective-rate semantics.

## Design

Use existing FWC/MAPD fixed ids on award_levels (award_fixed_id, classification_fixed_id) as the level identity. Keep raw FWC operative_from/operative_to values intact. For this iteration, treat venue_config.roster_week_starts_on / the venue operational week as the pay-period proxy: a raw FWC operative date applies from the first venue week-start date on or after that raw date. Do not alter already-approved entries or stored pay-version ids. Centralize rate resolution so append-only old/new rate rows are tolerated and surfaces do not choose stale rows by created_at/open-ended ordering.

## Acceptance Criteria

Mid-week FWC rate changes are not used until the next venue week boundary; Admin and Staff pay-rate dropdown labels show the venue-effective current rate; unapproved/future pay calculations use the venue-effective rate for the worked date; approved entries remain stable using stored version context; exports and Xero preview/bucket/pay-item naming resolve rates/effective keys consistently with canonical pay calculation; regression coverage proves old vs new behavior around a mid-week operative date.

