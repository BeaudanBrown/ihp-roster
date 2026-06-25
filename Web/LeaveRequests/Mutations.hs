module Web.LeaveRequests.Mutations
    ( LeaveReviewDecision (..)
    , ReviewedLeaveRequest (..)
    , leaveReviewTouchedResources
    , reviewLeaveRequest
    , submitLeaveRequest
    ) where

import Application.Helper.LiveResource
import Application.Helper.WeekBoundaries (affectedVenueWeekOffsetsForDateRange)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Web.Controller.Prelude
import Web.LiveResourceInvalidation (invalidateTouchedResources)

data LeaveReviewDecision
    = ApproveLeave
    | DenyLeave
    deriving (Eq, Show)

data ReviewedLeaveRequest = ReviewedLeaveRequest
    { reviewedLeaveRequest            :: !LeaveRequest
    , reviewedLeaveWasAlreadyApproved :: !Bool
    }
    deriving (Eq, Show)

submitLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveRequest -> IO (LiveMutationResult LeaveRequest)
submitLeaveRequest leaveRequest = do
    createdLeaveRequest <- withTransaction do
        createdLeaveRequest <- leaveRequest |> createRecord
        void $
            recordCurrentUserLeaveRequestEvent
                createdLeaveRequest
                (unsafeEnumFromText @LeaveRequestEventTypeEnum "created")
                Nothing
                (Just createdLeaveRequest.status)
                Aeson.Null
        pure createdLeaveRequest
    invalidateTouchedResources "leave.submit" (liveMutationResult createdLeaveRequest (baseLeaveTouchedResources createdLeaveRequest))

reviewLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveReviewDecision -> LeaveRequest -> IO (LiveMutationResult ReviewedLeaveRequest)
reviewLeaveRequest decision leaveRequest = do
    let wasApproved = parseLeaveRequestStatus leaveRequest.status == Just LeaveApproved
    updatedLeaveRequest <- withTransaction do
        updatedLeaveRequest <-
            leaveRequest
                |> set #status (leaveRequestStatusToEnum (reviewDecisionStatus decision))
                |> updateRecord
        void $
            recordCurrentUserLeaveRequestEvent
                updatedLeaveRequest
                (reviewDecisionEventType decision)
                (Just leaveRequest.status)
                (Just updatedLeaveRequest.status)
                Aeson.Null
        void $ recordCurrentUserAuditEvent
            (reviewDecisionAuditAction decision)
            "leave_requests"
            (unpackId (get #id leaveRequest))
            (Aeson.object
                [ "staffId" Aeson..= leaveRequest.staffId
                , "startDate" Aeson..= leaveRequest.startDate
                , "endDate" Aeson..= leaveRequest.endDate
                , "previousStatus" Aeson..= inputValue leaveRequest.status
                , "newStatus" Aeson..= inputValue updatedLeaveRequest.status
                ]
            )
        pure updatedLeaveRequest

    venueConfig <- fetchVenueConfig
    let touchedResources = leaveReviewTouchedResources venueConfig decision wasApproved updatedLeaveRequest
    invalidateTouchedResources "leave.review" $
        liveMutationResult
            ReviewedLeaveRequest
                { reviewedLeaveRequest = updatedLeaveRequest
                , reviewedLeaveWasAlreadyApproved = wasApproved
                }
            touchedResources

baseLeaveTouchedResources :: LeaveRequest -> [LiveResource]
baseLeaveTouchedResources leaveRequest =
    [ LeaveRequestsResource leaveRequest.venueId
    , StaffLeaveRequestsResource leaveRequest.staffId
    ]

leaveReviewTouchedResources :: VenueConfig -> LeaveReviewDecision -> Bool -> LeaveRequest -> [LiveResource]
leaveReviewTouchedResources venueConfig decision wasApproved leaveRequest =
    baseLeaveTouchedResources leaveRequest <> calendarResources
    where
        calendarResources =
            if reviewDecisionChangesRoster decision wasApproved
                then
                    [ LeaveCalendarResource leaveRequest.venueId weekOffset
                    | weekOffset <- affectedVenueWeekOffsetsForDateRange venueConfig leaveRequest.startDate leaveRequest.endDate
                    ]
                else []

reviewDecisionStatus :: LeaveReviewDecision -> LeaveRequestStatus
reviewDecisionStatus ApproveLeave = LeaveApproved
reviewDecisionStatus DenyLeave    = LeaveDenied

reviewDecisionEventType :: LeaveReviewDecision -> LeaveRequestEventTypeEnum
reviewDecisionEventType ApproveLeave = unsafeEnumFromText @LeaveRequestEventTypeEnum "approved"
reviewDecisionEventType DenyLeave = unsafeEnumFromText @LeaveRequestEventTypeEnum "denied"

reviewDecisionAuditAction :: LeaveReviewDecision -> Text
reviewDecisionAuditAction ApproveLeave = "leave_approved"
reviewDecisionAuditAction DenyLeave    = "leave_denied"

reviewDecisionChangesRoster :: LeaveReviewDecision -> Bool -> Bool
reviewDecisionChangesRoster ApproveLeave wasApproved = not wasApproved
reviewDecisionChangesRoster DenyLeave wasApproved    = wasApproved
