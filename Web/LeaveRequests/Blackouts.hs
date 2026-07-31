module Web.LeaveRequests.Blackouts
    ( BlackoutException (..)
    , blackoutExceptions
    , currentVenueCalendarDay
    , fetchCurrentAndFutureUnavailabilityBlackouts
    ) where

import Data.Coerce (coerce)
import Data.Time.Clock (getCurrentTime)
import Web.Controller.Prelude

data BlackoutException = BlackoutException
    { blackoutExceptionRequest :: !LeaveRequest
    , blackoutExceptionStaff   :: !Staff
    }

currentVenueCalendarDay :: (?modelContext :: ModelContext) => VenueConfig -> IO Day
currentVenueCalendarDay venueConfig = do
    now <- getCurrentTime
    localDay :: Day <- sqlQueryScalar
        "SELECT (?::timestamptz AT TIME ZONE ?)::date"
        (now, venueConfig.timezone)
    pure localDay

fetchCurrentAndFutureUnavailabilityBlackouts ::
    (?modelContext :: ModelContext, ?context :: ControllerContext) =>
    Day ->
    IO [UnavailabilityBlackout]
fetchCurrentAndFutureUnavailabilityBlackouts today =
    query @UnavailabilityBlackout
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhereGreaterThanOrEqualTo (#endDate, today)
        |> orderByAsc #startDate
        |> fetch

blackoutExceptions :: [LeaveRequest] -> [Staff] -> UnavailabilityBlackout -> [BlackoutException]
blackoutExceptions leaveRequests staffMembers blackout =
    [ BlackoutException leaveRequest staff
    | leaveRequest <- leaveRequests
    , leaveRequest.venueId == blackout.venueId
    , isNothing leaveRequest.deletedAt
    , leaveRequest.status `elem` [LeaveRequestStatusEnumPending, LeaveRequestStatusEnumApproved]
    , leaveRequest.startDate <= blackout.endDate
    , addDays (-1) leaveRequest.endDate >= blackout.startDate
    , staff <- staffMembers
    , coerce (get #id staff) == leaveRequest.staffId
    ]
