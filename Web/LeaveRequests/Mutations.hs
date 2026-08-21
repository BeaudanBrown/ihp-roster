module Web.LeaveRequests.Mutations
    ( LeaveReviewDecision (..)
    , LeaveSubmissionResult (..)
    , ReviewedLeaveRequest (..)
    , leaveReviewTouchedResources
    , reviewLeaveRequest
    , submitLeaveRequest
    ) where

import Application.Helper.FrontendContract.Surface.LeaveRequests.Resource
import Application.Helper.FrontendContract.Surface.Profile.Resource (staffLeaveRequestsResource)
import Application.Helper.FrontendContract.Surface.Roster.Live (activeRosterWindowScopes)
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterSlotsContentResource,
                                                                    rosterWeekResource)
import Application.Helper.SurfaceResource
import Application.Staff.Mutations (withStaffOperationalLock)
import Application.UnavailabilityBlackout.Mutations (findOverlappingUnavailabilityBlackout,
                                                     lockVenueUnavailabilityBlackoutInCurrentTransaction)
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

data LeaveSubmissionResult
    = LeaveSubmissionStaffInactive
    | LeaveSubmissionBlocked !UnavailabilityBlackout
    | LeaveSubmissionCreated !(LiveMutationResult LeaveRequest)

submitLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveRequest -> IO LeaveSubmissionResult
submitLeaveRequest leaveRequest = do
    maybeMutationResult <- withStaffOperationalLock leaveRequest.staffId do
        staff <- fetch (Id leaveRequest.staffId :: Id Staff)
        if not staff.isActive || isJust staff.archivedAt || staff.venueId /= leaveRequest.venueId
            then pure (Left Nothing)
            else do
                lockVenueUnavailabilityBlackoutInCurrentTransaction leaveRequest.venueId
                let lastUnavailableDate = addDays (-1) leaveRequest.endDate
                findOverlappingUnavailabilityBlackout leaveRequest.venueId leaveRequest.startDate lastUnavailableDate Nothing >>= \case
                    Just blackout -> pure (Left (Just blackout))
                    Nothing -> do
                        createdLeaveRequest <- leaveRequest |> createRecord
                        void $
                            recordCurrentUserLeaveRequestEvent
                                createdLeaveRequest
                                (LeaveRequestEventTypeEnumCreated)
                                Nothing
                                (Just createdLeaveRequest.status)
                                Aeson.Null
                        pure (Right createdLeaveRequest)
    case maybeMutationResult of
        Nothing -> pure LeaveSubmissionStaffInactive
        Just (Left Nothing) -> pure LeaveSubmissionStaffInactive
        Just (Left (Just blackout)) -> pure (LeaveSubmissionBlocked blackout)
        Just (Right createdLeaveRequest) -> do
            today <- utctDay <$> getCurrentTime
            let createdStatus = createdLeaveRequest.status
            let sectionResource = leaveRequestVisibleSectionResource today createdStatus createdLeaveRequest
            mutationResult <- invalidateTouchedResources "leave.submit" (liveMutationResult createdLeaveRequest (baseLeaveTouchedResources createdLeaveRequest <> [sectionResource]))
            pure (LeaveSubmissionCreated mutationResult)

reviewLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveReviewDecision -> LeaveRequest -> IO (Maybe (LiveMutationResult ReviewedLeaveRequest))
reviewLeaveRequest decision leaveRequest = do
    maybeReviewResult <- fmap join $ withStaffOperationalLock leaveRequest.staffId do
        staff <- fetch (Id leaveRequest.staffId :: Id Staff)
        if not staff.isActive || isJust staff.archivedAt || staff.venueId /= leaveRequest.venueId
            then pure Nothing
            else do
                lockedLeaveRequest <- fetch leaveRequest.id
                let previousStatus = lockedLeaveRequest.status
                let wasApproved = previousStatus == LeaveRequestStatusEnumApproved
                updatedLeaveRequest <-
                    lockedLeaveRequest
                        |> set #status (reviewDecisionStatus decision)
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
        activeRosterScopes <- activeRosterWindowScopes
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
    [ staffLeaveRequestsResource leaveRequest.staffId
    , leaveAvailabilityWarningsResource leaveRequest.venueId
    ]

leaveReviewTouchedResources :: Day -> LeaveReviewDecision -> LeaveRequestStatusEnum -> LeaveRequest -> [SurfaceResourceValue]
leaveReviewTouchedResources today decision previousStatus leaveRequest =
    baseLeaveTouchedResources leaveRequest <> map (\status -> leaveRequestVisibleSectionResource today status leaveRequest) affectedStatuses
    where
        affectedStatuses = nub [previousStatus, reviewDecisionStatus decision]

leaveRequestVisibleSectionResource :: Day -> LeaveRequestStatusEnum -> LeaveRequest -> SurfaceResourceValue
leaveRequestVisibleSectionResource today status leaveRequest
    | leaveRequestIsArchivedOn today leaveRequest = archivedLeaveRequestsResource leaveRequest.venueId
    | otherwise = leaveRequestStatusSectionResource leaveRequest.venueId status

leaveRequestStatusSectionResource :: UUID -> LeaveRequestStatusEnum -> SurfaceResourceValue
leaveRequestStatusSectionResource venueId LeaveRequestStatusEnumApproved = approvedLeaveRequestsResource venueId
leaveRequestStatusSectionResource venueId LeaveRequestStatusEnumDenied = deniedLeaveRequestsResource venueId
leaveRequestStatusSectionResource venueId LeaveRequestStatusEnumPending = pendingLeaveRequestsResource venueId

leaveReviewRosterWeekResources :: [(UUID, UUID, Day, Day, Int)] -> VenueConfig -> LeaveReviewDecision -> Bool -> LeaveRequest -> [SurfaceResourceValue]
leaveReviewRosterWeekResources activeScopes _venueConfig decision wasApproved leaveRequest
    | not (reviewDecisionChangesRoster decision wasApproved) = []
    | otherwise =
        Set.toList $ Set.fromList
            [ resource
            | (activeVenueId, rosterGroupId, windowStart, windowEnd, _calendarRevision) <- activeScopes
            , activeVenueId == leaveRequest.venueId
            , windowStart < leaveRequest.endDate
            , windowEnd > leaveRequest.startDate
            , resource <-
                [ rosterWeekResource rosterGroupId windowStart windowEnd
                , rosterSlotsContentResource rosterGroupId windowStart windowEnd
                ]
            ]

reviewDecisionStatus :: LeaveReviewDecision -> LeaveRequestStatusEnum
reviewDecisionStatus ApproveLeave = LeaveRequestStatusEnumApproved
reviewDecisionStatus DenyLeave    = LeaveRequestStatusEnumDenied

reviewDecisionEventType :: LeaveReviewDecision -> LeaveRequestEventTypeEnum
reviewDecisionEventType ApproveLeave = LeaveRequestEventTypeEnumApproved
reviewDecisionEventType DenyLeave    = LeaveRequestEventTypeEnumDenied

reviewDecisionAuditAction :: LeaveReviewDecision -> AuditEventType
reviewDecisionAuditAction ApproveLeave = LeaveApprovedAudit
reviewDecisionAuditAction DenyLeave    = LeaveDeniedAudit

reviewDecisionChangesRoster :: LeaveReviewDecision -> Bool -> Bool
reviewDecisionChangesRoster ApproveLeave wasApproved = not wasApproved
reviewDecisionChangesRoster DenyLeave wasApproved    = wasApproved
