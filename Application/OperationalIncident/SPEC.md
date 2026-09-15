# Operational incident contract

## Reconciliation interface

Producers submit one bounded observation to `reconcileOperationalIncident`.
`category + scopeKey + stableIdentity` is the durable incident identity. The
module serializes concurrent evaluation, records transitions, snapshots active
platform super-admin recipients and atomically enqueues one shared
`email_delivery` job per recipient. Calls must not include raw exceptions,
provider responses, customer/payroll content, addresses or secrets in symptom
codes or metadata.

A higher `impactRank` is the producer's explicit declaration that impact became
meaningfully worse. Equal/lower ranks update current facts without mail. There
are no reminder clocks.

| Transition | Condition | Notification |
| --- | --- | --- |
| `opened` | first active observation | one per eligible recipient |
| `impact_escalated` | active observation with a higher declared impact rank | one per eligible recipient |
| `recovered` | authoritative inactive observation after open state | only when a prior transition reached SMTP `sent` |
| `recurred` | authoritative active observation after recovery | one per eligible recipient |

Recipient reconciliation is terminal at event creation. Zero eligible
recipients is retained as `eligibleRecipientCount = 0`; adding an administrator
later does not replay a historical event. A later real transition uses the then
current eligible set. Email transport remains at-least-once, so a crash after
SMTP acceptance can still duplicate inbox receipt.

## Category and identity table

| Category | Scope / stable identity | Meaningful impact rank |
| --- | --- | --- |
| `wage_source` | global source (`fwc` or `datavic`) | usable-payroll coverage classes, not symptom count |
| `holiday_override` | global jurisdiction/year/review-cycle | review window then expired |
| `xero_connection` | venue / connection | reauthorization required |
| `xero_reference_sync` | venue / exhausted sync operation | newly affected reference category set |
| `xero_submission` | venue / submission run | failed then uncertain-provider state |
| `host_worker` | host / worker identity | heartbeat loss then overdue runnable work |
| `host_schedule` | host / schedule identity | missed grace then additional critical dependency |
| `backup` | host / repository | execution failure or overdue successful snapshot |
| `restore_verification` | host / repository | verification failure or overdue verification |
| `email_delivery` | global / durable email job | provider bounce, complaint, failure or suppression |

Provider health and usable business coverage are separate facts. Holiday
overrides can mitigate coverage but cannot resolve a DataVic provider incident.
A healthy Xero connection cannot resolve an uncertain submission.

## Metadata and retention

Symptom codes are a JSON string array capped at 2 KiB. Safe metadata is a JSON
object capped at 4 KiB and contains identifiers, categories, bounded timestamps
and operator-action labels only. Incident and event history is retained for
operational audit; no automatic pruning or destructive migration is introduced.
Email addresses remain in the existing recipient snapshot table under the same
retention/access model as durable email jobs.
