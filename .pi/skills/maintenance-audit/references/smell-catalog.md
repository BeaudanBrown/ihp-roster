# Maintainability and Agent-Navigability Smell Catalog

This is a question set, not a lint specification. A smell needs repository
context, concrete evidence, and a behavior-preserving path before it becomes an
issue.

## 1. Module depth and seam placement

Look for:

- files or modules owning unrelated reasons to change;
- one feature spread across many distant directories without a discoverable
  entry module;
- large interfaces that expose internal sequencing, configuration, or error
  details to every caller;
- shallow pass-through wrappers whose deletion would remove complexity rather
  than relocate it;
- repeated orchestration pipelines that callers must assemble correctly;
- seams placed around a technology rather than a real variation;
- one-adapter abstractions created for hypothetical replacement;
- tests reaching past the same interface callers use;
- broad helper/prelude modules that make ownership and dependencies opaque;
- import cycles, excessive fan-in/fan-out, or dependency direction contrary to
  subsystem architecture;
- temporal coupling: functions that only work after undocumented setup/order;
- parameter trains or long render signatures carrying a latent domain record.

Prefer a **deep module**: a small interface that gives callers substantial
behavior and concentrates change. Use the deletion test: if deleting the module
makes its complexity reappear in many callers, it earns its seam; if complexity
simply disappears, it was likely pass-through structure.

Do not split solely because a file is long. A cohesive long implementation can
be easier to navigate than many shallow files.

## 2. Duplication and redundancy

Search for more than identical text:

- the same domain decision encoded with different syntax;
- repeated validation, authorization, venue scoping, ordering, or filtering;
- repeated query shapes and preload sequences;
- repeated controller response/redirect/error branches;
- repeated view attributes, overlay markup, export rendering, or URL assembly;
- frontend/backend/test copies of a closed set or wire shape;
- repeated fixtures/builders with minor irrelevant differences;
- duplicate CSS rules, selectors, TypeScript event handling, or static asset
  ownership;
- multiple scripts/manifests enumerating the same files or checks;
- compatibility code that no active caller still needs;
- dead helpers, imports, assets, tests, flags, or documentation.

Classify duplication before abstracting:

- **knowledge duplication:** one rule copied in multiple places—strong target;
- **mechanical duplication:** repeated syntax with stable common meaning—possible
  target;
- **incidental similarity:** code happens to look alike but changes for different
  reasons—leave separate;
- **independent oracle:** tests intentionally repeat a compatibility value so
  drift is detected—often keep independent.

Avoid generic `Utils` dumping grounds and abstractions parameterized by every
caller difference.

## 3. Data and control-flow complexity

Look for:

- stringly typed statuses, roles, action names, identifiers, layers, intents, or
  field names;
- boolean combinations representing an unnamed state machine;
- partial functions or implicit invariants at request/data boundaries;
- repeated parsing/defaulting/error normalization;
- hidden request context or global dependencies that impede focused tests;
- functions mixing pure decisions, database access, rendering, and side effects;
- mutation code that makes scope, audit, realtime, or response evidence hard to
  see;
- branch nests that could be expressed as an explicit decision/result type;
- records passed around with fields that are repeatedly recomputed elsewhere;
- inconsistent error modes for equivalent operations;
- ordering assumptions not represented in types, names, or tests.

Changing an error, fallback, ordering, or partial-function failure can be an
observable behavior change. Characterize first; separate actual fixes from the
refactor epic unless explicitly approved.

## 4. Repository and framework conformance

Read current root/local instructions before using these prompts. Check for local
code bypassing established project mechanisms, such as:

- route/action generation replaced by hand-built paths or query strings;
- IHP QueryBuilder bypassed by raw controller SQL without a documented reason;
- request IDs parsed partially or mutation scope checked inconsistently;
- required request values relying only on permissive `fill` behavior;
- venue authority inferred from users instead of venue memberships;
- founder support access conflated with ordinary venue membership;
- CSV, overlays, live fragments, or asset paths rebuilt outside canonical
  helpers;
- frontend behavior attached through ad hoc attributes instead of Haskell-owned
  contracts and generated TypeScript;
- passive live viewers receiving state directly where server-rendered fragments
  should remain authoritative;
- generated static JavaScript edited instead of authored TypeScript;
- schema changes proposed without preserving migrations.

Some low-level modules legitimately use raw SQL or exact wire strings. The smell
is an unexplained bypass at the wrong seam, not the mere presence of a primitive.

## 5. File and navigation ergonomics

Look for:

- filenames and module names that do not reveal the domain concept they own;
- unrelated feature code grouped by technical layer when changes are vertical;
- multiple plausible entrypoints with no subsystem README;
- stale forwarding modules or aliases obscuring the canonical path;
- generated and hand-authored files indistinguishable to agents;
- local rules existing only in remote plans or issue comments;
- giant specs mixing unrelated behavior and support infrastructure;
- directories with no clear ownership, extension rule, or verification command;
- comments explaining obsolete mechanics rather than current invariants;
- repeated agent rediscovery caused by missing code-adjacent navigation.

Do not solve navigability by adding broad root instructions. Put durable facts
beside the owning code and keep temporary plans in GitHub/workstreams.

## 6. Test architecture and ergonomics

Look for tests that are:

- coupled to source text, formatting, import layout, or private helper names when
  a semantic/structural assertion is available;
- hard-coded lists of constructors, enum values, routes, fields, or generated
  artifacts that silently omit newly added cases;
- broad full-string snapshots where only a few stable contract facts matter;
- fixed-count or fixed-order assertions unrelated to the behavior under test;
- dependent on static UUIDs, dates, locale, timezone, clock, or shared DB state
  without making that dependency explicit;
- mostly setup due to missing builders or a poor module interface;
- duplicating policy logic to calculate expected results;
- reading implementation files and grepping strings instead of exercising the
  interface;
- over-mocked across internal seams, making safe restructuring expensive;
- bundled into huge files that prevent focused execution and ownership;
- checking that a generator copied text, rather than validating the generated
  structure or behavior.

Prefer exhaustive/table-driven cases derived from an independently owned domain
universe, property/invariant tests, semantic DOM assertions, contract tests at
real seams, and focused builders with meaningful defaults.

Guard against tautologies: never derive the expected result from the exact
implementation under test. It is valid to derive the set of cases from a
canonical DSL/type while independently asserting each case's contract.

Exact strings remain appropriate at true serialization, compatibility,
compliance, migration, or customer-copy interfaces. Keep them narrow and name
why exactness matters.

## 7. Build, verification, and operational ergonomics

Look for:

- duplicated command lists that drift across CI, Nix, Make, scripts, and docs;
- checks that scan generated/build output accidentally;
- noisy warnings hiding actionable failures;
- expensive gates required for tiny changes because focused checks are absent;
- unnecessary module fan-out increasing compile time;
- non-deterministic fixtures or scripts;
- hidden environmental assumptions and globally shared state;
- generated artifacts without freshness checks;
- architecture checks implemented as brittle text matching when parsing,
  reflection, ASTs, or runtime contracts are available;
- multiple manifests that should derive from one registry—or intentional mirrors
  lacking a sync check;
- scripts with destructive defaults or poor dry-run behavior.

A performance/build smell needs measurement. Do not promise compile or runtime
improvements from file rearrangement alone.

## 8. Documentation and tracker drift

Look for:

- living docs pointing to closed/superseded issues as active ownership;
- implemented facts surviving only in workstreams or archived plans;
- code-adjacent specs that describe old interfaces;
- issue bodies prescribing architecture superseded by current code;
- duplicate Markdown checklists mirroring GitHub status;
- root instructions accumulating subsystem-specific details;
- local `AGENTS.md` rules that are obsolete or contradicted by automation.

Follow the repository documentation precedence. Update the owning living doc as
implementation lands; do not turn the audit report into another source of truth.

## Evidence threshold

Do not file a refactor issue without most of:

- at least two concrete examples, or one demonstrably high-impact mixed module;
- caller/reference evidence;
- the current and intended ownership/seam;
- explanation of agent or maintainer cost;
- known behavior-preservation risks;
- a credible focused verification route;
- confirmation that no current issue already owns the work.

Use line count, churn, import count, and text similarity only as discovery
signals. They are not acceptance criteria by themselves.
