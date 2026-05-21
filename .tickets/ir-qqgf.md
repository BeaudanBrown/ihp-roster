---
id: ir-qqgf
status: open
deps: [ir-asw6]
links: [ir-asw6]
created: 2026-05-21T03:35:31Z
type: feature
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, roster, admin, follow-up]
---
# Configure shift type badge colours in admin

Add manual venue-admin colour selection for shift type badges after automatic colour keys are in place.

## Design

Future follow-up, intentionally outside the current day-column readability slice. Build on shift_types colour_key and the fixed palette/default rule. Admin shift type edit/create UI should allow choosing an available palette colour or default, prevent duplicate non-default colours among active shift types, and handle activation collision validation/reassignment deliberately.

## Acceptance Criteria

Venue admins can configure shift type badge colours from the shift type screen. Active shift types cannot share non-default palette colours. Default remains reusable. Roster badges reflect configured values.

