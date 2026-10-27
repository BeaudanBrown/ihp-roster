-- Standalone manual runs retain immutable provenance without an automatic
-- settings row. Existing links, snapshots and delivery revisions are unchanged.
ALTER TABLE payroll_report_runs ALTER COLUMN settings_id DROP NOT NULL;
ALTER TABLE payroll_report_runs ADD COLUMN configuration_id UUID;
ALTER TABLE payroll_report_runs ADD COLUMN recipient_group_id UUID;
ALTER TABLE payroll_report_runs ADD COLUMN recipient_group_revision INT;
-- Template identity is historical provenance, deliberately not a foreign key:
-- deleting a saved template must not delete or strand its prepared artifacts.
ALTER TABLE payroll_report_runs ADD CONSTRAINT payroll_report_runs_recipient_group_fkey FOREIGN KEY (recipient_group_id) REFERENCES recipient_groups (id) ON DELETE RESTRICT;
ALTER TABLE payroll_report_runs ADD CONSTRAINT payroll_report_runs_schedule_link_check CHECK ((origin <> 'payroll_report_scheduled') OR (settings_id IS NOT NULL));
ALTER TABLE payroll_report_runs ADD CONSTRAINT payroll_report_runs_group_snapshot_check CHECK (((recipient_group_id IS NULL) AND (recipient_group_revision IS NULL)) OR ((recipient_group_id IS NOT NULL) AND (recipient_group_revision IS NOT NULL) AND (recipient_group_revision >= 0)));
ALTER TABLE payroll_report_runs ADD CONSTRAINT payroll_report_runs_manual_provenance_check CHECK ((settings_id IS NOT NULL) OR ((origin = 'payroll_report_manual') AND (configuration_id IS NOT NULL) AND (recipient_group_id IS NOT NULL)));
CREATE INDEX payroll_report_runs_template_week_idx ON payroll_report_runs (venue_id, configuration_id, reporting_week);
