# Bepis Domain Language

Bepis models venue staffing, roster planning, availability, and worked-time records.

## Rostering

**Shift assignment**:
The required assignment of a roster shift: either one specific staff member or the explicit Open state.
_Avoid_: Nullable staff, optional assignment

**Roster shift**:
A planned period of work with a shift assignment.
_Avoid_: Slot, empty shift

**Roster lane**:
A roster day’s named, ordered placement lane. A roster window presents the normalized union of its days’ lanes; lane identity does not extend beyond its roster day.
_Avoid_: Roster-group lane, week slot definition

**Operational day**:
The venue hospitality day selected for a complete shift or Timesheet entry, running from 06:00 through the following 05:59. It assigns the complete work period to one Roster, Timesheet, export, and payroll window.
_Avoid_: Local start date, creation timestamp, earnings component date

**Roster day**:
One roster group’s plan for an operational day. It is the atomic unit of roster planning and publication.
_Avoid_: Day offset, roster week day

**Earnings component date**:
The actual venue-local date on which one segment of a shift occurred. It determines applicable Award conditions but never moves part of a shift out of its operational-day window.
_Avoid_: Operational day, pay-period assignment date

**Roster window**:
Seven consecutive operational days presented together, beginning on the venue’s configured roster window start day. It is a projection over roster-day history, not historical identity.
_Avoid_: Roster week record, pay week

**Roster window start day**:
The venue weekday that defines Roster, Timesheet, export, and Bepis weekly Award-rate windows. Venue owners align external payroll calendars with it when required.
_Avoid_: Roster start date, Xero pay-period start

**Xero pay period**:
The provider-supplied date range selected for one Xero Timesheet preparation. It groups submission dates but does not redefine Bepis Award-rate rollover.
_Avoid_: Roster window

**Published roster day**:
A roster day whose planned shifts are visible to staff and eligible for Timesheet suggestions.
_Avoid_: Live roster week

**Draft roster day**:
A roster day whose planned shifts are hidden from staff and ineligible for Timesheet suggestions.
_Avoid_: Unpublished week

**Open shift**:
The explicit assignment state of a roster shift that needs a staff member, whether its roster day is Draft or Published. It is not a missing or unknown assignment.
_Avoid_: OpenShift, null staff, unassigned shift, empty slot

**Roster template**:
A reusable detached roster-group Week snapshot whose shifts may be assigned to staff or Open. It contains one plan for each calendar weekday; the roster window start day changes presentation order, never weekday meaning.
_Avoid_: Schedule preset, copied roster

**Roster notification run**:
One manager-requested email send for a Published roster-group window, with an immutable roster and recipient snapshot shared by every delivery job in the run.
_Avoid_: Roster publication, email blast

## Support

**Support impersonation**:
A super-admin session mode that uses one selected venue user as the effective venue identity while retaining the real platform identity, truthful audit attribution, and Support access.
_Avoid_: Role preview, fake login, cosmetic user switch
