# Melbourne venue time

## Ownership

`Application.VenueTime` is the sole pure authority that converts Melbourne civil
time to instants for Award and roster work. It has no database, HTTP, form, or UI
responsibility. `Australia/Melbourne` is fixed by the module; callers do not supply
a timezone.

## Civil resolution

- Unique local times resolve without an occurrence choice.
- Repeated autumn times require `FirstOccurrence` or `SecondOccurrence`.
  Endpoint ordering is resolved before calendar-day rollover, so equal local
  clocks from the first occurrence to the second form a positive same-day interval.
- Nonexistent spring times return `NonexistentCivilTime`.
- An occurrence attached to a unique time is rejected rather than ignored.
- Invalid `TimeOfDay` values and non-positive intervals return typed errors.
- `ResolvedInstant`, `ResolvedInterval`, and `AwardSegment` constructors are hidden.
  UTC and local facts are therefore always derived from the same authority.

The module uses the embedded IANA Melbourne TZif history. The `tz` parser does not
interpret the TZif POSIX footer after its final explicit 2037 transition, so the
module applies Melbourne's embedded recurring footer rule from 2038 onward:
standard UTC+10, daylight UTC+11, daylight ending on the first Sunday in April at
03:00 and starting on the first Sunday in October at 02:00. Tests cover the
post-table rule so transition-table exhaustion cannot silently freeze an offset.

## Award segmentation

A positive resolved interval segments at Melbourne local 00:00, 07:00, and 19:00.
Every segment carries an authoritative local date, weekday/weekend kind, and Award
window while duration remains the exact UTC elapsed duration, including fractional
seconds and DST transitions. Segment durations conserve the source interval.

## Copy semantics

`copyIntervalToDate` preserves the source start/end local clock values and the
end-date offset relative to the start date. It resolves both copied endpoints on
the target date instead of adding a UTC duration. A repeated target endpoint still
requires an explicit occurrence selection; a nonexistent target endpoint fails.

## Persistence integration

`Application.VenueTime.Model` is the typed database/form integration seam. It
accepts only `Australia/Melbourne`, stores start/end instants plus that timezone
snapshot atomically, derives all local facts from those values, and validates
paired break instants inside the shift. A break may start at the shift start or
end at the shift end, but must itself have positive elapsed duration. Copy
occurrence selections are applied only to target endpoints that actually repeat,
so one week-copy selection can coexist with ordinary shifts.

## Verification

```bash
bash ./bin/in-env hspec-pure --match "Melbourne civil-time authority"
bash ./bin/in-env typecheck
```
