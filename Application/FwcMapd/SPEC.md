# FWC MAPD ingestion and projection

## Ownership

This subsystem retrieves, curates, validates, stores, and projects the Fair Work
Commission Modern Awards Pay Database records used for MA000009 Award rates.
`ValidatedMapdSnapshot` is the boundary between provider-facing ingestion and
rate-book consumers. Wage calculation does not belong here.

## Retrieval

- CI and tests use committed fixtures; live HTTP retrieval is runtime/operator work.
- The seven supported classifications are fixed by the reviewed Award matrix:
  `242`, `243`, `246`, `257`, `268`, `276`, and `282`.
- Classification paging is supplemented by filtered requests for every canonical
  classification ID. Page count and current-page metadata must remain consistent.
- Source records are assembled by stable provider identity and effective period.
  Value-equivalent duplicates normalize; conflicting duplicates fail independent
  of response order.

## Candidate validation

Before database publication, one complete effective-period candidate must contain:

- matching Award provenance and all seven canonical classifications;
- one permanent ordinary hourly pay rate and one casual ordinary penalty rate per
  classification;
- permanent and casual Saturday, Sunday, and public-holiday penalty rows per
  classification;
- the Award-wide clause 29.2 evening and early-morning commenced-hour additions;
- stable source identities, category ownership, and consistent effective dates.

Penalty category ownership is anchored by each classification's unique validated
`base_pay_rate_id`; MAPD penalty responses may omit `classification_fixed_id`. When
the optional classification ID is present it must match that canonical owner.

Every overtime row is excluded during curation and rejected defensively at the
validated-snapshot boundary. Missing, conflicting, unsupported, or inconsistent
records fail validation; provider absence never changes the supported matrix.

## Publication

A validated candidate's raw rows and Award-level projection publish in one database
transaction. Validation runs before that transaction. A failed candidate records an
actionable failed `fwc_mapd_sync_runs` row, does not inactivate an Award level, and
leaves the last complete projection active. Projection rows retain provenance to the
validated immediate-scope source records.

## Operational refresh policy

- A successful validated refresh must remain within the eight-day FWC wage-source
  freshness limit. The packaged NixOS module therefore sweeps weekly by default.
- Deployments should add daily sweeps from 20 June through 10 July so late-June
  Annual Wage Review publication, the 1 July post-boundary validation requirement,
  and delayed provider corrections are observed promptly.
- FWC MAPD changes outside the annual window remain covered by weekly reconciliation.
- A successful systemd sweep only proves that an app job was enqueued or already
  active. The completed `fwc_mapd_refresh` job and succeeded `fwc_mapd_sync_runs`
  row are the publication authority.

## Verification

Run:

```bash
bash ./bin/in-env hspec-test --match "FWC MAPD"
bash ./bin/in-env typecheck
bash ./bin/in-env lint
bash ./bin/in-env ./bin/doc-drift-check
```
