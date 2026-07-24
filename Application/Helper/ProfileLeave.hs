module Application.Helper.ProfileLeave
    ( buildDefaultLeaveRequest
    , defaultLeaveRequestForOperationalDay
    , fetchCurrentUserLeaveRequests
    , fetchStaffLeaveRequests
    ) where

import Application.Helper.Controller (currentOperationalDayForVenue,
                                      currentVenueId, fetchCurrentUserStaff,
                                      fetchVenueConfig)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude

import Data.Time.Calendar (addDays)

fetchCurrentUserLeaveRequests :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [LeaveRequest]
fetchCurrentUserLeaveRequests = do
    maybeStaff <- fetchCurrentUserStaff
    case maybeStaff of
        Nothing    -> pure []
        Just staff -> fetchStaffLeaveRequests staff

fetchStaffLeaveRequests :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Staff -> IO [LeaveRequest]
fetchStaffLeaveRequests staff =
    query @LeaveRequest
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#staffId, unpackId staff.id)
        |> filterWhere (#deletedAt, Nothing)
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
