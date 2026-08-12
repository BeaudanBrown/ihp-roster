module Application.Helper.VenueScopedQueries
    ( fetchActiveVenueShiftTypes
    , fetchLinkedActiveVenueStaff
    , fetchVenueShiftTypes
    , sortShiftTypesForDisplay
    ) where

import Application.Helper.Staff (sortStaffForDisplay)
import Data.List (sortOn)
import Generated.Types
import IHP.ControllerPrelude

-- | Active, non-archived staff with a linked user account. Use for
-- timesheet/payroll/Xero eligibility.
fetchLinkedActiveVenueStaff :: (?modelContext :: ModelContext) => Id Venue -> IO [Staff]
fetchLinkedActiveVenueStaff venueId =
    sortStaffForDisplay <$> (query @Staff
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> filterWhereSql (#userId, "IS NOT NULL")
        |> fetch)

-- | Canonical administrator-defined shift-type order. Keep filtering separate
-- so every venue list preserves the same order after applying its own eligibility.
sortShiftTypesForDisplay :: [ShiftType] -> [ShiftType]
sortShiftTypesForDisplay =
    sortOn (\shiftType -> (shiftType.sortOrder, shiftType.createdAt, tshow shiftType.id))

fetchVenueShiftTypes :: (?modelContext :: ModelContext) => Id Venue -> IO [ShiftType]
fetchVenueShiftTypes venueId =
    sortShiftTypesForDisplay <$> (query @ShiftType
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#archivedAt, Nothing)
        |> fetch)

fetchActiveVenueShiftTypes :: (?modelContext :: ModelContext) => Id Venue -> IO [ShiftType]
fetchActiveVenueShiftTypes venueId =
    filter (.isActive) <$> fetchVenueShiftTypes venueId
