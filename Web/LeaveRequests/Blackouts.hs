module Web.LeaveRequests.Blackouts
    ( BlackoutException (..)
    , blackoutExceptions
    , currentVenueCalendarDay
    , fetchCurrentAndFutureUnavailabilityBlackouts
    ) where

import Data.Coerce (coerce)
import Web.Controller.Prelude

data BlackoutException = BlackoutException
    { blackoutExceptionRequest :: !LeaveRequest
    , blackoutExceptionStaff   :: !Staff
    }

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

blackoutExceptions :: Day -> [LeaveRequest] -> [Staff] -> UnavailabilityBlackout -> [BlackoutException]
blackoutExceptions today leaveRequests staffMembers blackout =
    [ BlackoutException leaveRequest staff
    | leaveRequest <- leaveRequests
    , leaveRequest.venueId == blackout.venueId
    , isNothing leaveRequest.deletedAt
    , leaveRequest.status `elem` [LeaveRequestStatusEnumPending, LeaveRequestStatusEnumApproved]
    , let firstRelevantDay = max today (max leaveRequest.startDate blackout.startDate)
    , firstRelevantDay <= blackout.endDate
    , not (leaveRequestIsArchivedOn firstRelevantDay leaveRequest)
    , staff <- staffMembers
    , coerce (get #id staff) == leaveRequest.staffId
    ]
