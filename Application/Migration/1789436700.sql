-- #552: operation-local reviewed identities. NULL deliberately means fresh
-- review is required for legacy in-flight preparation; never backfill all.
-- Completed runs and their existing submission/source history remain unchanged.
-- Recovery: the prior app ignores this additive nullable column; retain it and
-- its customer selections when rolling back application code.
ALTER TABLE xero_timesheet_preparation_runs ADD COLUMN selected_entries_json JSONB DEFAULT NULL;
