---
id: ir-tbjx
status: open
deps: [ir-5dzy, ir-u51n]
links: [ir-9hgu]
created: 2026-04-29T04:41:29Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-t7be
tags: [workstream, coordinator:coordinator-wii, area:roster, area:bootstrap]
---
# Make roster UI, admin flows, and live updates group-aware

Expose active roster group in routes/page state, admin setup, and live-update scopes after the foundation lands.


## Notes

**2026-05-01T00:47:45Z**

Planning update 2026-05-01: slot-name management should move out of the admin roster-group card and into the roster grid as week-local slot columns. See linked ticket ir-9hgu and its child tickets for the planned refactor.

**2026-06-11T10:57:56Z**

Product/design note from 2026-06-11 discussion: consider moving roster-adjacent configuration (roster groups and shift types) out of the sparse central Admin page and into roster-context dialogs opened from the roster settings/column-edit area. Potential upside: fewer top-level pages and configuration where its effect is visible; risks: discoverability, crowded roster controls, and mixing venue-wide settings with week/group-local editing. If pursued, preserve admin deep-link/owner/admin access semantics and reuse existing admin live fragments or shared dialog renderers rather than duplicating config forms.
