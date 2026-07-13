# Bepis Component Pipeline Refactor

Status: superseded by `bepis-effect-evidence-finalization.md`

This workstream introduced the transitional component-pipeline idea that led to
the final Bepis runtime fact architecture. Its durable outcome was the decision
to keep semantics visible and typed, but not to maintain descriptive metadata
beside real effects.

The final architecture is documented in `bepis-effect-evidence-finalization.md`:

- controllers use `runBepis` with the bound action value and operation kind;
- helpers that perform real effects emit typed `BepisFact` values;
- `emitBepisFact` collects facts and emits telemetry;
- generated architecture contracts come from Haskell;
- source scanners locate usage and enforce no-legacy rules, but do not infer
  Bepis semantics from regex.

Historical details for the transitional pipeline are intentionally omitted here
so this file does not read as current implementation guidance.
