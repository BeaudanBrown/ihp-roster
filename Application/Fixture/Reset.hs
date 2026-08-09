module Application.Fixture.Reset
    ( applicationTableNames
    , resetDatabase
    ) where

import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Database.PostgreSQL.Simple.Types as PGTypes
import IHP.ModelSupport (sqlExecDiscardResult)
import IHP.Prelude

-- | Closed manifest of application-owned tables from Application/Schema.sql.
-- Keep this explicit: reset code must never discover framework or migration
-- bookkeeping tables from a live database.
applicationTableNames :: [Text]
applicationTableNames =
    [ "venues"
    , "users"
    , "email_verification_tokens"
    , "passkeys"
    , "passkey_recovery_codes"
    , "passkey_setup_tokens"
    , "password_reset_tokens"
    , "user_preferences"
    , "venue_memberships"
    , "venue_invitations"
    , "venue_onboarding_invitations"
    , "staff"
    , "staff_documents"
    , "shift_types"
    , "roster_groups"
    , "staff_roster_groups"
    , "slot_names"
    , "day_names"
    , "venue_config"
    , "staff_pay_versions"
    , "shift_type_pay_versions"
    , "fwc_mapd_sync_runs"
    , "fwc_mapd_awards"
    , "fwc_mapd_classifications"
    , "fwc_mapd_pay_rates"
    , "fwc_mapd_penalty_rates"
    , "fwc_mapd_wage_allowances"
    , "award_levels"
    , "award_level_base_rates"
    , "award_level_penalty_rates"
    , "award_time_penalty_allowances"
    , "public_holidays"
    , "app_jobs"
    , "roster_templates"
    , "roster_template_designs"
    , "roster_template_days"
    , "roster_template_columns"
    , "roster_template_shifts"
    , "roster_weeks"
    , "roster_days"
    , "roster_week_slot_definitions"
    , "roster_slots"
    , "roster_notification_runs"
    , "staff_shift_preferences"
    , "leave_requests"
    , "leave_request_events"
    , "unavailability_blackouts"
    , "audit_events"
    , "user_feedback_items"
    , "export_jobs"
    , "venue_billing_customers"
    , "billing_checkout_attempts"
    , "venue_subscriptions"
    , "billing_events"
    , "venue_billing_controls"
    , "xero_connections"
    , "xero_oauth_states"
    , "xero_sync_runs"
    , "xero_reference_sync_leases"
    , "xero_employees"
    , "xero_earnings_rates"
    , "xero_imported_pay_items"
    , "xero_accounts"
    , "xero_payroll_calendars"
    , "xero_pay_runs"
    , "xero_staff_mappings"
    , "xero_earnings_rate_mappings"
    , "xero_pay_item_account_code_selections"
    , "xero_pay_item_requirement_records"
    , "timesheet_entries"
    , "timesheet_pay_calculations"
    , "timesheet_pay_time_segments"
    , "timesheet_pay_earnings_components"
    , "timesheet_entry_versions"
    , "export_job_entries"
    , "xero_submission_runs"
    , "xero_timesheet_preparation_runs"
    , "xero_timesheet_preparation_decisions"
    , "xero_timesheet_submissions"
    , "xero_timesheet_submission_entries"
    , "venue_membership_role_events"
    ]

resetDatabase :: (?modelContext :: ModelContext) => IO ()
resetDatabase =
    sqlExecDiscardResult
        (PGTypes.Query (TextEncoding.encodeUtf8 resetStatement))
        ()
  where
    resetStatement =
        "TRUNCATE TABLE "
            <> Text.intercalate ", " applicationTableNames
            <> " RESTART IDENTITY CASCADE"
