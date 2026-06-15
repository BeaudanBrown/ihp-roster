module Application.Helper.VenueScopedQueries
    ( fetchActiveVenueShiftTypes
    , fetchActiveVenueStaff
    , fetchLinkedActiveVenueStaff
    , fetchRosterableVenueStaff
    ) where

import Generated.Types
import IHP.ControllerPrelude

-- | Deprecated ambiguous name retained for existing callers. Prefer
-- 'fetchRosterableVenueStaff' for roster surfaces or 'fetchLinkedActiveVenueStaff'
-- for timesheet/payroll/Xero eligibility.
fetchActiveVenueStaff :: (?modelContext :: ModelContext) => Id Venue -> IO [Staff]
fetchActiveVenueStaff = fetchRosterableVenueStaff

-- | Active, non-archived staff for roster planning. Includes trial placeholders
-- where user_id IS NULL.
fetchRosterableVenueStaff :: (?modelContext :: ModelContext) => Id Venue -> IO [Staff]
fetchRosterableVenueStaff venueId =
    query @Staff
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> fetch

-- | Active, non-archived staff with a linked user account. Use for
-- timesheet/payroll/Xero eligibility.
fetchLinkedActiveVenueStaff :: (?modelContext :: ModelContext) => Id Venue -> IO [Staff]
fetchLinkedActiveVenueStaff venueId =
    query @Staff
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> filterWhereSql (#userId, "IS NOT NULL")
        |> fetch

fetchActiveVenueShiftTypes :: (?modelContext :: ModelContext) => Id Venue -> IO [ShiftType]
fetchActiveVenueShiftTypes venueId =
    query @ShiftType
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> fetch
