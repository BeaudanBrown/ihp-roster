module Application.Helper.VenueScopedQueries
    ( fetchActiveVenueShiftTypes
    , fetchActiveVenueStaff
    ) where

import Generated.Types
import IHP.ControllerPrelude

fetchActiveVenueStaff :: (?modelContext :: ModelContext) => Id Venue -> IO [Staff]
fetchActiveVenueStaff venueId =
    query @Staff
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> fetch

fetchActiveVenueShiftTypes :: (?modelContext :: ModelContext) => Id Venue -> IO [ShiftType]
fetchActiveVenueShiftTypes venueId =
    query @ShiftType
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> fetch
