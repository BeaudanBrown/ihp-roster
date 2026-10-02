# Daysheets

[Product contract](../../specs/07-daysheets.md) · [Engineering contract](SPEC.md)

`Contract` and `Validation` own definition meaning. `Formula` bounds the linked
DSL graph before it becomes an expression tree. `Schema` and `Wire` reuse the
backend FrontendContract DSL and exact carrier parsing; no separate JavaScript
formula language belongs here. `Number` and `Results` supply exact arithmetic
and unavailable-result laws for evaluation.

These pure modules do not authorize venue access, persist daily data, resolve
operational-day instants, or send reports. Callers must preserve the product's
pinned-definition/current-venue boundaries. Tests live in
`Test/DaysheetContractSpec.hs` and `Test/DaysheetNumberSpec.hs`.

Focused checks:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-pure --match Daysheet
```
