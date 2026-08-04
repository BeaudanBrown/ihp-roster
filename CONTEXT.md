# Bepis Domain Language

Bepis models venue staffing, roster planning, availability, and worked-time records.

## Rostering

**Shift assignment**:
The required assignment of a roster shift: either one specific staff member or the explicit Open state.
_Avoid_: Nullable staff, optional assignment

**Roster shift**:
A planned period of work with a shift assignment.
_Avoid_: Slot, empty shift

**Open shift**:
The explicit assignment state of a roster shift that needs a staff member, whether the roster is draft or live. It is not a missing or unknown assignment.
_Avoid_: OpenShift, null staff, unassigned shift, empty slot

**Roster template**:
A reusable roster-group plan at Day or Week scale whose shifts may be assigned to staff or Open.
_Avoid_: Schedule preset, copied roster

**Day template**:
A roster template containing one relative roster day.

**Week template**:
A roster template containing seven ordered relative roster days.

**Template draft**:
A manager’s single private work-in-progress design for creating or editing a roster template. It is not available for roster application until saved.

**Roster notification run**:
One manager-requested email send for a live roster-group week, with an immutable roster and recipient snapshot shared by every delivery job in the run.
_Avoid_: Roster publication, email blast

## Support

**Support impersonation**:
A super-admin session mode that uses one selected venue user as the effective venue identity while retaining the real platform identity, truthful audit attribution, and Support access.
_Avoid_: Role preview, fake login, cosmetic user switch
