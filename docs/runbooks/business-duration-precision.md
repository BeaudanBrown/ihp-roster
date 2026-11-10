# Whole-second business durations: rollout check

Owner: [epic #672](https://github.com/BeaudanBrown/ihp-roster/issues/672).

Business durations use signed whole seconds. Each duration is rounded independently
(nearest second, half-seconds away from zero), after subtracting its timestamps.
Stored timestamps and approved payroll quantities/amounts are not rewritten.
Technical timers retain their precision. There is no schema migration or backfill.

## Before deployment

Run the repository-owned audit against the intended database as an authorised
operator. Choose the venue UUID and inclusive Operational-date range explicitly;
repeat for all venues and historical periods that will be recalculated/exported.
The example dates are not an instruction to ignore older data.

```bash
sudo -u postgres psql -X -d rozzy \
  -v venue_id=REPLACE_WITH_VENUE_UUID \
  -v range_start=2026-01-01 -v range_end=2026-12-31 \
  -f Application/Deployment/business-duration-audit.sql
```

The script opens a read-only repeatable-read transaction with a 15-second timeout.
It checks non-deleted roster/timesheet intervals, recorded breaks, and segments
of their active pay calculations. Superseded calculations and deleted entries are
not scanned. Each category reports counts and at most 100 example IDs/durations;
no names, comments, recipients or money are emitted. Missing categories mean no
intervals matched: confirm database, venue and date range before interpreting an
empty result. A timeout is an incomplete audit, not a clean result; narrow the
range and retry deliberately.

Both fractional **durations** and fractional **endpoints** matter: two endpoints
with the same fractional part can produce an integral duration but fractional
pieces when split at an hour/day boundary. Normal minute-precision input has
neither. Non-zero findings require operator review before rollout; independent
rounding does not promise conservation across arbitrary fractional splits. Do
not silently repair timestamps or recalculate approved payroll.

Stored repeating decimal hours are not an audit failure. For example,
`0.166666666667` hours intentionally reconstructs to `600` seconds. The approved
quantity and amount remain unchanged.

## Staging acceptance and promotion

With separately approved deployment, test the failing missed-break download,
ordinary/overnight and DST exports, unchanged approved totals, and the configured
report's email subject/body. Confirm genuine export inconsistencies produce the
complete authorised timesheet list and no partial file. Browser and native
responses must both offer timesheet links. Test mail only with authorised
recipients/transport; a manual send does not disable scheduled delivery.

Promotion and production deployment require separate approval. Do not update
production simply because the staging branch/pin changed.

## Rollback

Restore the previously approved application pin/deployment generation through the
normal deployment procedure. Do not delete tables, modify timestamps, or rewrite
approved calculations. An application rollback does not undo approvals or emails
created since deployment. Previously generated files remain historical snapshots;
the old application may again reject the nanosecond-overrun case.
