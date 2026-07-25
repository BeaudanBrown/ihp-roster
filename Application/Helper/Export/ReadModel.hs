module Application.Helper.Export.ReadModel where

import Application.Helper.Controller
import Application.Helper.Pay (payVersionManifestForEntry)
import Application.VenueTime.Model (requireMelbourneDateRangeUTC)
import Data.Coerce (coerce)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Time.Calendar (Day)
import Generated.Types
import IHP.ControllerPrelude

fetchCurrentVenueActiveShiftTypes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueActiveShiftTypes =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> orderByAsc #sortOrder
        |> orderByAsc #name
        |> fetch

fetchReportStaffMap :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Staff)
fetchReportStaffMap entries =
    if null staffIds
        then pure Map.empty
        else do
            staffMembers <- query @Staff
                |> filterWhereIn (#id, map Id staffIds)
                |> filterWhere (#isActive, True)
                |> fetch
            pure (Map.fromList (map (\staff -> (coerce (get #id staff), staff)) staffMembers))
    where
        staffIds = List.nub (map (.staffId) entries)

fetchApprovedTimesheetEntries ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO [TimesheetEntry]
fetchApprovedTimesheetEntries rangeStart rangeEnd = do
    let (rangeStartsAt, rangeEndsAt) = requireMelbourneDateRangeUTC rangeStart rangeEnd
    query @TimesheetEntry
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isApproved, True)
        |> filterWhere (#deletedAt, Nothing)
        |> filterWhereGreaterThanOrEqualTo (#startsAt, rangeStartsAt)
        |> filterWhereLessThan (#startsAt, rangeEndsAt)
        |> orderByAsc #startsAt
        |> fetch

fetchStaffMap :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Staff)
fetchStaffMap entries =
    if null staffIds
        then pure Map.empty
        else do
            staff <- query @Staff |> filterWhereIn (#id, map Id staffIds) |> fetch
            pure (Map.fromList (map (\staffMember -> (coerce (get #id staffMember), staffMember)) staff))
    where
        staffIds = List.nub (map (.staffId) entries)

fetchApproverMap :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID User)
fetchApproverMap entries =
    if null approverIds
        then pure Map.empty
        else do
            users <- query @User |> filterWhereIn (#id, map Id approverIds) |> fetch
            pure (Map.fromList (map (\user -> (coerce (get #id user), user)) users))
    where
        approverIds = List.nub (mapMaybe (.approvedByUserId) entries)

fetchVersionManifestsForEntries :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Text)
fetchVersionManifestsForEntries entries =
    pure (Map.fromList (mapMaybe entryManifest entries))
    where
        entryManifest entry =
            fmap (\manifest -> (coerce (get #id entry), manifest)) (payVersionManifestForEntry entry)
