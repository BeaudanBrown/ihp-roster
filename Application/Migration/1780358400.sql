ALTER TABLE xero_timesheet_preparation_decisions
    DROP CONSTRAINT IF EXISTS xero_timesheet_preparation_decisions_decision_kind_check;

ALTER TABLE xero_timesheet_preparation_decisions
    ADD CONSTRAINT xero_timesheet_preparation_decisions_decision_kind_check
    CHECK (decision_kind = 'staff_auto_match' OR decision_kind = 'staff_manual_mapping' OR decision_kind = 'staff_not_paid' OR decision_kind = 'staff_step_approved' OR decision_kind = 'pay_item_create' OR decision_kind = 'account_code' OR decision_kind = 'calendar_selection');
