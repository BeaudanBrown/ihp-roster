-- Future omitted row counts use the roster's two-row minimum.
-- Existing roster and template rows are intentionally unchanged.
ALTER TABLE roster_days ALTER COLUMN row_count SET DEFAULT 2;
ALTER TABLE roster_template_days ALTER COLUMN row_count SET DEFAULT 2;
