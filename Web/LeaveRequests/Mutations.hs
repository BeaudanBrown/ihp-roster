module Web.LeaveRequests.Mutations
    ( LeaveReviewDecision (..)
    , ReviewedLeaveRequest (..)
    , leaveReviewTouchedResources
    , reviewLeaveRequest
    , submitLeaveRequest
    ) where

import Application.Helper.FrontendContract.Surface.LeaveRequests.Resource
import Application.Helper.FrontendContract.Surface.Profile.Resource (staffLeaveRequestsResource)
import Application.Helper.FrontendContract.Surface.Roster.Live (activeRosterWeekScopes)
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterSlotsContentResource,
                                                                    rosterWeekResource)
import Application.Helper.SurfaceResource
import Application.Helper.WeekBoundaries (affectedVenueWeekOffsetsForDateRange)
import Application.Staff.Mutations (withStaffOperationalLock)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import Data.Time.Clock (getCurrentTime, utctDay)
import Data.UUID (UUID)
import Web.Controller.Prelude
import Web.SurfaceInvalidation (invalidateTouchedResources)

data LeaveReviewDecision
    = ApproveLeave
    | DenyLeave
    deriving (Eq, Show)

data ReviewedLeaveRequest = ReviewedLeaveRequest
    { reviewedLeaveRequest            :: !LeaveRequest
    , reviewedLeaveWasAlreadyApproved :: !Bool
    }
    deriving (Eq, Show)

submitLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveRequest -> IO (Maybe (LiveMutationResult LeaveRequest))
submitLeaveRequest leaveRequest = do
    maybeCreatedLeaveRequest <- fmap join $ withStaffOperationalLock leaveRequest.staffId do
        staff <- fetch (Id leaveRequest.staffId :: Id Staff)
        if not staff.isActive || isJust staff.archivedAt || staff.venueId /= leaveRequest.venueId
            then pure Nothing
            else do
                createdLeaveRequest <- leaveRequest |> createRecord
                void $
                    recordCurrentUserLeaveRequestEvent
                        createdLeaveRequest
                        (unsafeEnumFromText @LeaveRequestEventTypeEnum "created")
                        Nothing
                        (Just createdLeaveRequest.status)
                        Aeson.Null
                pure (Just createdLeaveRequest)
    forM maybeCreatedLeaveRequest \createdLeaveRequest -> do
        today <- utctDay <$> getCurrentTime
        let createdStatus = fromMaybe LeavePending (parseLeaveRequestStatus createdLeaveRequest.status)
        let sectionResource = leaveRequestVisibleSectionResource today createdStatus createdLeaveRequest
        invalidateTouchedResources "leave.submit" (liveMutationResult createdLeaveRequest (baseLeaveTouchedResources createdLeaveRequest <> [sectionResource]))

reviewLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveReviewDecision -> LeaveRequest -> IO (Maybe (LiveMutationResult ReviewedLeaveRequest))
reviewLeaveRequest decision leaveRequest = do
    maybeReviewResult <- fmap join $ withStaffOperationalLock leaveRequest.staffId do
        staff <- fetch (Id leaveRequest.staffId :: Id Staff)
        if not staff.isActive || isJust staff.archivedAt || staff.venueId /= leaveRequest.venueId
            then pure Nothing
            else do
                lockedLeaveRequest <- fetch leaveRequest.id
                let previousStatus = parseLeaveRequestStatus lockedLeaveRequest.status
                let wasApproved = previousStatus == Just LeaveApproved
                updatedLeaveRequest <-
                    lockedLeaveRequest
                        |> set #status (leaveRequestStatusToEnum (reviewDecisionStatus decision))
                        |> updateRecord
                void $
                    recordCurrentUserLeaveRequestEvent
                        updatedLeaveRequest
                        (reviewDecisionEventType decision)
                        (Just lockedLeaveRequest.status)
                        (Just updatedLeaveRequest.status)
                        Aeson.Null
                void $ recordCurrentUserAuditEvent
                    (reviewDecisionAuditAction decision)
                    "leave_requests"
                    (unpackId (get #id lockedLeaveRequest))
                    (Aeson.object
                        [ "staffId" Aeson..= lockedLeaveRequest.staffId
                        , "startDate" Aeson..= lockedLeaveRequest.startDate
                        , "endDate" Aeson..= lockedLeaveRequest.endDate
                        , "previousStatus" Aeson..= inputValue lockedLeaveRequest.status
                        , "newStatus" Aeson..= inputValue updatedLeaveRequest.status
                        ]
                    )
                pure (Just (updatedLeaveRequest, previousStatus, wasApproved))

    forM maybeReviewResult \(updatedLeaveRequest, previousStatus, wasApproved) -> do
        venueConfig <- fetchVenueConfig
        activeRosterScopes <- activeRosterWeekScopes
        today <- utctDay <$> getCurrentTime
        let touchedResources = leaveReviewTouchedResources today decision previousStatus updatedLeaveRequest <> leaveReviewRosterWeekResources activeRosterScopes venueConfig decision wasApproved updatedLeaveRequest
        invalidateTouchedResources "leave.review" $
            liveMutationResult
                ReviewedLeaveRequest
                    { reviewedLeaveRequest = updatedLeaveRequest
                    , reviewedLeaveWasAlreadyApproved = wasApproved
                    }
                touchedResources

baseLeaveTouchedResources :: LeaveRequest -> [SurfaceResourceValue]
baseLeaveTouchedResources leaveRequest =
    [staffLeaveRequestsResource leaveRequest.staffId]

leaveReviewTouchedResources :: Day -> LeaveReviewDecision -> Maybe LeaveRequestStatus -> LeaveRequest -> [SurfaceResourceValue]
leaveReviewTouchedResources today decision previousStatus leaveRequest =
    baseLeaveTouchedResources leaveRequest <> map (\status -> leaveRequestVisibleSectionResource today status leaveRequest) affectedStatuses
    where
        affectedStatuses = nub [fromMaybe LeavePending previousStatus, reviewDecisionStatus decision]

leaveRequestVisibleSectionResource :: Day -> LeaveRequestStatus -> LeaveRequest -> SurfaceResourceValue
leaveRequestVisibleSectionResource today status leaveRequest
    | leaveRequestIsArchivedOn today leaveRequest = archivedLeaveRequestsResource leaveRequest.venueId
    | otherwise = leaveRequestStatusSectionResource leaveRequest.venueId status

leaveRequestStatusSectionResource :: UUID -> LeaveRequestStatus -> SurfaceResourceValue
leaveRequestStatusSectionResource venueId LeaveApproved = approvedLeaveRequestsResource venueId
leaveRequestStatusSectionResource venueId LeaveDenied = deniedLeaveRequestsResource venueId
leaveRequestStatusSectionResource venueId LeavePending = pendingLeaveRequestsResource venueId

leaveReviewRosterWeekResources :: [(UUID, UUID, Int)] -> VenueConfig -> LeaveReviewDecision -> Bool -> LeaveRequest -> [SurfaceResourceValue]
leaveReviewRosterWeekResources activeScopes venueConfig decision wasApproved leaveRequest
    | not (reviewDecisionChangesRoster decision wasApproved) = []
    | otherwise =
        Set.toList $ Set.fromList
            [ resource
            | weekOffset <- affectedVenueWeekOffsetsForDateRange venueConfig leaveRequest.startDate leaveRequest.endDate
            , (activeVenueId, rosterGroupId, activeWeekOffset) <- activeScopes
            , activeVenueId == leaveRequest.venueId
            , activeWeekOffset == weekOffset
            , resource <-
                [ rosterWeekResource rosterGroupId weekOffset
                , rosterSlotsContentResource rosterGroupId weekOffset
                ]
            ]

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
