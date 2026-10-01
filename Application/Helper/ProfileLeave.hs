module Application.Helper.ProfileLeave
    ( buildDefaultLeaveRequest
    , defaultLeaveRequestForOperationalDay
    , fetchCurrentUserLeaveRequests
    , fetchStaffLeaveRequests
    , fetchStaffLeaveRequestsOn
    ) where

import Application.Helper.Controller (currentOperationalDayForVenue,
                                      currentVenueCalendarDay, currentVenueId,
                                      fetchCurrentUserStaff, fetchVenueConfig)
import Generated.Types
import IHP.ControllerPrelude


fetchCurrentUserLeaveRequests :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [LeaveRequest]
fetchCurrentUserLeaveRequests = do
    maybeStaff <- fetchCurrentUserStaff
    case maybeStaff of
        Nothing    -> pure []
        Just staff -> fetchStaffLeaveRequests staff

fetchStaffLeaveRequests :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Staff -> IO [LeaveRequest]
fetchStaffLeaveRequests staff = do
    venueConfig <- fetchVenueConfig
    today <- currentVenueCalendarDay venueConfig
    fetchStaffLeaveRequestsOn today staff

fetchStaffLeaveRequestsOn :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Day -> Staff -> IO [LeaveRequest]
fetchStaffLeaveRequestsOn today staff =
    query @LeaveRequest
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#staffId, unpackId staff.id)
        |> filterWhere (#deletedAt, Nothing)
        |> filterWhereGreaterThan (#endDate, today)
        |> orderByDesc #startDate
        |> fetch

buildDefaultLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO LeaveRequest
buildDefaultLeaveRequest = do
    venueConfig <- fetchVenueConfig
    operationalDay <- currentOperationalDayForVenue venueConfig
    pure (defaultLeaveRequestForOperationalDay operationalDay)

defaultLeaveRequestForOperationalDay :: Day -> LeaveRequest
defaultLeaveRequestForOperationalDay operationalDay =
    newRecord @LeaveRequest
        |> set #startDate operationalDay
        |> set #endDate (addDays 1 operationalDay)
