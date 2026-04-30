module Web.RosterWeeks.AvailabilityInputs
    ( fetchApprovedLeaveRequestsForRosterWindow
    , fetchLeaveRequestsForRosterWindowByStatus
    , fetchRosterShiftPreferencesForWindow
    ) where

import Application.Helper.Controller (LeaveRequestStatus,
                                      leaveRequestStatusToEnum)
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import Web.Controller.Prelude

fetchApprovedLeaveRequestsForRosterWindow :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [UUID.UUID] -> Calendar.Day -> Calendar.Day -> IO [LeaveRequest]
fetchApprovedLeaveRequestsForRosterWindow =
    fetchLeaveRequestsForRosterWindowByStatus [LeaveApproved]

fetchLeaveRequestsForRosterWindowByStatus :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [LeaveRequestStatus] -> [UUID.UUID] -> Calendar.Day -> Calendar.Day -> IO [LeaveRequest]
fetchLeaveRequestsForRosterWindowByStatus statuses staffIds windowStartDate windowEndExclusive
    | null statuses || null staffIds = pure []
    | otherwise =
        query @LeaveRequest
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhereIn (#staffId, staffIds)
            |> filterWhereIn (#status, map leaveRequestStatusToEnum statuses)
            |> filterWhere (#deletedAt, Nothing)
            |> filterWhereLessThan (#startDate, windowEndExclusive)
            |> filterWhereGreaterThan (#endDate, windowStartDate)
            |> fetch

fetchRosterShiftPreferencesForWindow :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> [UUID.UUID] -> [Int] -> IO [StaffShiftPreference]
fetchRosterShiftPreferencesForWindow rosterGroupId staffIds weekdayIndexes
    | null staffIds || null weekdayIndexes = pure []
    | otherwise =
        query @StaffShiftPreference
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
            |> filterWhereIn (#staffId, staffIds)
            |> filterWhereIn (#weekdayIndex, weekdayIndexes)
            |> filterWhere (#deletedAt, Nothing)
            |> fetch
