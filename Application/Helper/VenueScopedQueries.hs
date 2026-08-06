module Application.Helper.VenueScopedQueries
    ( fetchActiveVenueShiftTypes
    , fetchLinkedActiveVenueStaff
    ) where

import Generated.Types
import IHP.ControllerPrelude

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
