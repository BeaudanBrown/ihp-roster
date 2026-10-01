# Operational notification rollout and recovery

## Boundaries

This rollout introduces additive incident/event/recipient history, provider
delivery visibility, Xero and wage-source producers, public-holiday override
review cycles, and the Rozzy host watchdog. It does not authorize production
migration, Nix build/switch, a real Resend send, isolated production restore
verification, historical-email replay, retention changes, or epic closure.

Operational email remains active platform-super-admin only. Venue membership is
not authority. Safe incident metadata is limited to source/category, local
operation identifiers, bounded counts, schedule/deadline facts, symptom/action
codes, and host unit results. Never include customer, staff, payroll, token,
credential, raw provider payload/error, database value, backup contents, or
snapshot identifiers.

There is no fallback channel. A Resend outage cannot report itself by email; a
host cannot report its own total loss. Durable database state, the watchdog's
root-owned local outbox, Support, and external host monitoring are the recovery
boundaries.

## Preflight and rehearsal

1. Obtain separate approvals for production migration, application deployment,
   the `bepis-dotfiles` build/switch, controlled Resend evidence, and first
   isolated restore verification. Do not combine these approvals.
2. Rehearse all application migrations on an isolated recent production clone
   per [migration rehearsal](migration-rehearsal.md). Record row counts and
   checksums for legacy mail jobs, wage-source notification state, Xero
   submissions, users, and venues before and after. The additive migrations must
   preserve those rows.
3. Confirm the wage-source cutover sentinel is present. Existing active generic
   wage alerts may be retired by the bounded cutover; terminal notification and
   provider history remains. No migration creates delivery jobs or bulk incident
   events, so deployment cannot replay historical email.
4. In `bepis-dotfiles`, configure the dedicated `rozzy/resend-api-key` SOPS key
   without displaying or reading it during review. Confirm the application and
   watchdog sender/domain are authorized in Resend.
5. Build approved application and host closures separately. Do not switch.
   Capture the exact application and dotfiles commits and confirm the host closure
   evaluates the `bepis_watchdog` PostgreSQL/OS role, watchdog timer, backup
   evidence hook, and restore-verification timer.
6. Take and verify the normal pre-deployment backup. This is not the new isolated
   restore-verification execution.

## Coordinated activation

The database role must exist before migrations grant its narrow functions, while
the watchdog must not poll an older schema. Use this order:

1. As root, create `/run/bepis-maintenance`. Confirm the watchdog is suppressed.
2. Apply the separately approved dotfiles switch. This creates the matching OS
   and PostgreSQL role and installs units, but maintenance suppression prevents
   observations and direct dispatch.
3. Deploy the matching application and apply migrations through the normal
   migration service. Do not run migration SQL manually. Confirm only
   `bepis_watchdog` can execute `bepis_watchdog_poll`,
   `bepis_watchdog_record_event`, `bepis_watchdog_record_dispatch`, and
   `bepis_watchdog_record_status`; it has no direct table grants.
4. Verify application startup, worker startup, one completed `worker_heartbeat`,
   Support incident/delivery rendering, and unchanged customer workflows.
5. Remove `/run/bepis-maintenance`. Start one approved watchdog poll and inspect
   its bounded state/status without printing recipient addresses or credentials.
   Healthy startup sends no email.
6. Separately approve and perform controlled non-customer lifecycle evidence:
   one open and recovery, one suppressed-provider outcome plus audited resend,
   and a stopped-worker open/recovery. Reuse the same logical idempotency keys;
   do not generate reminders.
7. Leave `bepis-restore-verification.timer` stopped or masked until its first
   production execution is separately approved. That execution uses one immutable
   snapshot, a unique temporary database, the shared restore/verification lock,
   and configured CPU/I/O/memory/time bounds. It never replaces `rozzy`.

## Acceptance observations

For each scenario, inspect incident identity, ordered transition events, eligible
recipient snapshot, queue/direct-dispatch outcome, provider state, and Support.
Repeat the observation and restart the responsible process to prove no duplicate
logical send.

- Combined public-holiday failure/staleness is one DataVic incident; genuine
  source recovery resolves it. A verified override suppresses coverage symptoms
  only for its protected year, not provider health.
- Override review warning occurs exactly seven days before the deadline; first
  observation after expiry emits overdue only. Audited extension creates a new
  cycle; validated retirement resolves the active cycle.
- Xero reauthorization, exhausted reference sync, and each uncertain/blocked
  submission remain distinct actionable identities. Healthy connection state
  never resolves an uncertain submission and no path auto-resubmits payroll.
- Out-of-order/replayed Resend webhooks do not regress provider state. Suppressed,
  failed, complained, and bounced outcomes remain visible; only audited
  operational resend by an active super admin is allowed.
- Stopped worker, stale heartbeat, overdue runnable jobs, missing recipients,
  email configuration/delivery failure, failed backup execution, stale actual
  snapshot, failed restore verification, and overdue verification use local
  single-fire transitions. Future jobs and disabled timers are excluded.

## Rollback and recovery

1. Restore `/run/bepis-maintenance`, then stop/mask watchdog and restore-
   verification timers before rolling back either repository. Preserve
   `/var/lib/bepis-watchdog`; deleting it can lose dedupe/outbox evidence.
2. Prefer forward-fixing application code. The tables, functions, columns, enum
   values, sentinel, incident/provider history, and review-cycle audit are
   additive and may remain during application rollback. Do not drop or rewrite
   them without a separate destructive-data plan.
3. If the application must roll back first, keep the watchdog suppressed because
   its least-privilege functions may not exist in the older schema. If dotfiles
   must roll back first, application incidents and queued delivery continue; host
   detection pauses.
4. A database outage leaves local events unsynchronized. A Resend outage leaves
   the same event/recipient send pending under its stable idempotency key. Recover
   dependencies, inspect state, then allow reconciliation; never synthesize a new
   event or bulk replay old rows.
5. Restore-verification interruption or failure must terminate sessions and drop
   only its uniquely named temporary database. If cleanup fails, keep the timer
   stopped and remove the verified orphan manually after confirming it is not
   `rozzy`. Never convert verification into restore.
6. Rollback is complete only after worker heartbeat, schedules, backup snapshot
   freshness, notification delivery, and Support are healthy without unexpected
   sends. Epic closure and host cleanup remain separate operator decisions.
