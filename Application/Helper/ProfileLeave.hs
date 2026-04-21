module Application.Helper.ProfileLeave
    ( buildDefaultLeaveRequest
    , fetchCurrentUserLeaveRequests
    ) where

import Application.Helper.Controller (currentVenueId, fetchCurrentUserStaff)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude

import Data.Time.Calendar (addDays)
import Data.Time.Clock (utctDay)

fetchCurrentUserLeaveRequests :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [LeaveRequest]
fetchCurrentUserLeaveRequests = do
    maybeStaff <- fetchCurrentUserStaff
    case maybeStaff of
        Nothing -> pure []
        Just staff ->
            query @LeaveRequest
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#staffId, unpackId staff.id)
                |> orderByDesc #startDate
                |> fetch

buildDefaultLeaveRequest :: (?context :: ControllerContext) => IO LeaveRequest
buildDefaultLeaveRequest = do
    today <- utctDay <$> getCurrentTime
    pure $
        newRecord @LeaveRequest
            |> set #startDate today
            |> set #endDate (addDays 1 today)
