module Web.RosterWeeks.AvailabilityInputs
    ( fetchApprovedLeaveRequestsForRosterWindow
    , fetchLeaveRequestsForRosterWindowByStatus
    , fetchRosterShiftPreferencesForWindow
    ) where

import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import Web.Controller.Prelude

fetchApprovedLeaveRequestsForRosterWindow :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [UUID.UUID] -> Calendar.Day -> Calendar.Day -> IO [LeaveRequest]
fetchApprovedLeaveRequestsForRosterWindow =
    fetchLeaveRequestsForRosterWindowByStatus [LeaveRequestStatusEnumApproved]

fetchLeaveRequestsForRosterWindowByStatus :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [LeaveRequestStatusEnum] -> [UUID.UUID] -> Calendar.Day -> Calendar.Day -> IO [LeaveRequest]
fetchLeaveRequestsForRosterWindowByStatus statuses staffIds windowStartDate windowEndExclusive
    | null statuses || null staffIds = pure []
    | otherwise =
        query @LeaveRequest
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhereIn (#staffId, staffIds)
            |> filterWhereIn (#status, statuses)
            |> filterWhere (#deletedAt, Nothing)
            |> filterWhereLessThan (#startDate, windowEndExclusive)
            |> filterWhereGreaterThan (#endDate, windowStartDate)
            |> fetch

fetchRosterShiftPreferencesForWindow :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [UUID.UUID] -> [Int] -> IO [StaffShiftPreference]
fetchRosterShiftPreferencesForWindow staffIds weekdayIndexes
    | null staffIds || null weekdayIndexes = pure []
    | otherwise =
        query @StaffShiftPreference
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhereIn (#staffId, staffIds)
            |> filterWhereIn (#weekdayIndex, weekdayIndexes)
            |> filterWhere (#deletedAt, Nothing)
            |> fetch
