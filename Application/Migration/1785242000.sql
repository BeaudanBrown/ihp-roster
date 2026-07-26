-- #239 deployment marker.
--
-- The Haskell backfill must run after the additive ledger migrations and before
-- the legacy SQL calculators are retired. NixOS deployments enforce that order
-- in wage-cutover.service, which runs BackfillTimesheetPayLedger and then
-- Application/Deployment/retire-legacy-wage-calculators.sql before app startup.
-- Keeping this migration as a marker lets the normal migration runner complete
-- before the Haskell deployment step on both upgrades and fresh databases.
SELECT 1;
