module Web.LeaveRequests.Mutations
    ( LeaveReviewDecision (..)
    , ReviewedLeaveRequest (..)
    , cancelLeaveRequest
    , reviewLeaveRequest
    , submitLeaveRequest
    ) where

import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Time.Clock (getCurrentTime)
import Web.Controller.Prelude
import Web.LeaveRequests.Projection
import Web.Profiles.LiveUpdates

data LeaveReviewDecision
    = ApproveLeave
    | DenyLeave
    deriving (Eq, Show)

data ReviewedLeaveRequest = ReviewedLeaveRequest
    { reviewedLeaveRequest            :: !LeaveRequest
    , reviewedLeaveWasAlreadyApproved :: !Bool
    }
    deriving (Eq, Show)

submitLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveRequest -> IO LeaveRequest
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
    broadcastLeaveRequestsInvalidation leaveRequestsContentFragmentRefs
    refreshProfileLeaveRequests
    pure createdLeaveRequest

reviewLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveReviewDecision -> LeaveRequest -> IO ReviewedLeaveRequest
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

    when (reviewDecisionChangesRoster decision wasApproved) do
        invalidateAffectedRosterWeeksForLeave updatedLeaveRequest
    broadcastLeaveRequestsInvalidation leaveRequestsContentFragmentRefs
    refreshProfileLeaveRequestsForStaffId updatedLeaveRequest.staffId
    pure ReviewedLeaveRequest
        { reviewedLeaveRequest = updatedLeaveRequest
        , reviewedLeaveWasAlreadyApproved = wasApproved
        }

cancelLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveRequest -> IO LeaveRequest
cancelLeaveRequest leaveRequest = do
    now <- getCurrentTime
    softDeletedLeaveRequest <- withTransaction do
        softDeletedLeaveRequest <-
            leaveRequest
                |> set #deletedAt (Just now)
                |> set #deletedByUserId (Just (unpackId currentUser.id))
                |> set #deleteReason (Just "user_deleted")
                |> updateRecord
        void $
            recordCurrentUserLeaveRequestEvent
                softDeletedLeaveRequest
                (unsafeEnumFromText @LeaveRequestEventTypeEnum "deleted")
                (Just leaveRequest.status)
                Nothing
                (Aeson.object ["deletedAt" Aeson..= now])
        void $ recordCurrentUserAuditEvent
            "leave_deleted"
            "leave_requests"
            (unpackId (get #id leaveRequest))
            (Aeson.object
                [ "staffId" Aeson..= leaveRequest.staffId
                , "startDate" Aeson..= leaveRequest.startDate
                , "endDate" Aeson..= leaveRequest.endDate
                , "deletedStatus" Aeson..= inputValue leaveRequest.status
                , "deletedAt" Aeson..= now
                ]
            )
        pure softDeletedLeaveRequest
    broadcastLeaveRequestsInvalidation leaveRequestsContentFragmentRefs
    refreshProfileLeaveRequestsForStaffId leaveRequest.staffId
    pure softDeletedLeaveRequest

reviewDecisionStatus :: LeaveReviewDecision -> LeaveRequestStatus
reviewDecisionStatus ApproveLeave = LeaveApproved
reviewDecisionStatus DenyLeave = LeaveDenied

reviewDecisionEventType :: LeaveReviewDecision -> LeaveRequestEventTypeEnum
reviewDecisionEventType ApproveLeave = unsafeEnumFromText @LeaveRequestEventTypeEnum "approved"
reviewDecisionEventType DenyLeave = unsafeEnumFromText @LeaveRequestEventTypeEnum "denied"

reviewDecisionAuditAction :: LeaveReviewDecision -> Text
reviewDecisionAuditAction ApproveLeave = "leave_approved"
reviewDecisionAuditAction DenyLeave = "leave_denied"

reviewDecisionChangesRoster :: LeaveReviewDecision -> Bool -> Bool
reviewDecisionChangesRoster ApproveLeave wasApproved = not wasApproved
reviewDecisionChangesRoster DenyLeave wasApproved = wasApproved
