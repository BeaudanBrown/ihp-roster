---
id: ir-hnpv
status: closed
deps: [ir-jtmv]
links: []
created: 2026-05-29T03:16:08Z
type: task
priority: 1
assignee: beaudan
parent: ir-5v0t
tags: [agent-loop, research, confirmation]
---
# Confirm admin surface migration order and focus constraints

Research current admin simple surfaces and confirm which can be migrated together safely.

## Design

Inspect VenueSettings, Invites, Exports, RosterGroups, ShiftTypes, Admin controller mutation responses, existing focus protection, and any recent tickets affecting admin config. Confirm whether shift types/roster groups need special handling because of focused-field protection or row editing.

## Acceptance Criteria

Ticket note records final migration order, target ids, focused-field constraints, and any sections deferred; no production behavior changes are made.


## Notes

**2026-06-30T01:54:25Z**

Admin surface migration order confirmed. Low-risk first batch for ir-cg2x: (1) venue settings target admin-venue-settings-fragment, GET ShowAdminVenueSettingsFragmentAction, scope AdminVenueConfigScope, dependency AdminVenueSettingsResource. Forms are toggle-only and have no special focus protection; can migrate directly to hx-swap=none + typed OOB content plus existing flash/toast behavior. (2) invites target admin-invites-fragment, GET ShowAdminInvitesFragmentAction with AdminInvitesSurfaceKey carrying the current rosterGroupId query. Create/revoke forms are simple; no focus protection needed. Preserve rosterGroupId in success responses and redirect fallback. (3) exports target admin-exports-fragment, GET ShowAdminExportsFragmentAction, scope AdminExportsScope. Currently hidden from Admin page but fragment/controller code exists; export generation is a write/action surface with recent jobs list. Can migrate with the same simple single-fragment response helper if keeping existing tests. Defer or separate: shift types and roster groups. Shift types target admin-shift-types-fragment and already declare focused-field protection on input[data-admin-shift-type-field-key]:focus with container form[data-admin-shift-type-row]; autosave inputs/selects and optional Xero refresh make it special, so migrate after simple surfaces in ir-hsnv. Roster groups target admin-roster-groups-fragment; no live focused-field protection today, but row editing/reorder/active-count constraints make it safer after invites/settings/exports in ir-2fvy. Current direct helpers to replace later: respondToVenueSettingsMutation, respondToInvitesSectionMutation, and export generation response should move to simple non-cached fragment models or direct single-fragment typed render helpers; avoid introducing SurfaceProjection/cache for these admin surfaces.
