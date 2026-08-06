# Typed Authority Enum Migration #338 Runbook

Migration: `1787000000.sql`

## Forward

1. Take the normal database backup and record its restore location.
2. Apply migrations through the deployment migration runner.
3. If preflight aborts, inspect every value/count named in the exception. Do not
   delete or coerce an unknown value without a separate product decision.
4. Verify:

```sql
SELECT pg_typeof(feedback_type), count(*) FROM user_feedback_items GROUP BY 1;
SELECT pg_typeof(colour_key), colour_key, count(*) FROM shift_types GROUP BY 1, 2 ORDER BY 2;
```

The forward migration preserves rows. Historical empty shift colours become the
canonical persisted `no_colour`; Haskell projects that constructor back to an
empty CSS/HTML colour value.

## Rollback

Rollback is data-preserving and may be applied only before any future enum value
is introduced:

```sql
BEGIN;

ALTER TABLE user_feedback_items
    ALTER COLUMN feedback_type DROP DEFAULT,
    ALTER COLUMN feedback_type TYPE TEXT USING feedback_type::TEXT,
    ALTER COLUMN feedback_type SET DEFAULT 'bug'::TEXT;

ALTER TABLE shift_types
    ALTER COLUMN colour_key DROP DEFAULT,
    ALTER COLUMN colour_key TYPE TEXT
        USING CASE
            WHEN colour_key::TEXT = 'no_colour' THEN ''
            ELSE replace(colour_key::TEXT, 'palette_', 'palette-')
        END,
    ALTER COLUMN colour_key SET DEFAULT ''::TEXT;

ALTER TABLE user_feedback_items
    ADD CONSTRAINT user_feedback_items_feedback_type_check
    CHECK ((feedback_type = 'bug') OR (feedback_type = 'suggestion') OR (feedback_type = 'other'));
ALTER TABLE shift_types
    ADD CONSTRAINT shift_types_colour_key_check
    CHECK (colour_key = '' OR colour_key = 'palette-1' OR colour_key = 'palette-2' OR colour_key = 'palette-3' OR colour_key = 'palette-4' OR colour_key = 'palette-5' OR colour_key = 'palette-6' OR colour_key = 'palette-7' OR colour_key = 'palette-8' OR colour_key = 'palette-9' OR colour_key = 'palette-10');

DROP TYPE shift_type_colour_key_enum;
DROP TYPE feedback_type_enum;

COMMIT;
```

After rollback, deploy the pre-#338 application build. Restore the backup if the
migration transaction or application verification cannot be completed safely.
