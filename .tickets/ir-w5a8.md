---
id: ir-w5a8
status: closed
deps: []
links: [ir-7b1w]
created: 2026-07-09T02:39:01Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-z20h
tags: [agent-loop, staff, trial, ui]
---
# Add trial-staff invite action in staff list

Expose a compact adoption-invite action beside trial staff in the staff list/panel.

## Design

Add a compact envelope-plus icon button beside each adoptable trial staff member's name in the roster staff panel. The button has no visible label, but includes accessible text/title tooltip such as "Invite Alex Smith". Linked/non-trial staff do not show the action.

The button opens a small dialog, not the full staff edit form. The dialog contains a single email field, a short explanation that the invite lets the person claim the trial staff profile, and a pending-invites list for that staff member. Pending rows show email, lifecycle/delivery status, expiry, and a resend action.

Reuse the existing trial staff adoption invitation model, permissions, and delivery job path. Add resend support for existing pending staff-linked invitations by re-queueing delivery, refreshing delivery status, and extending expiry without creating duplicate invitations. Ensure these invitations continue to appear in the normal Admin > Invites pending list.

On successful send or resend, close the dialog and show a toast. Remove the confusing trial-staff invite email field from the larger staff profile edit modal so the roster staff list is the primary invitation entrypoint.

## Acceptance Criteria

- Managers/admins see an envelope-plus invite action beside adoptable trial staff in the roster staff panel.
- Linked/non-trial staff do not show the trial invite action.
- The action opens a simple invite dialog with email input and pending invites for that staff member.
- Pending invites can be resent from the dialog without creating duplicate invitation records.
- New and resent invitations appear in the normal Admin > Invites pending list and use the existing delivery job flow.
- Successful send/resend closes the dialog and shows a toast.
- Invalid email, linked staff, cross-venue staff, and non-manager attempts remain safely rejected/rerendered.
- The larger staff profile edit modal no longer renders the trial-staff invitation email field.

