module Web.LeaveRequests.Mutations
    ( LeaveReviewDecision (..)
    , LeaveSubmissionResult (..)
    , ReviewedLeaveRequest (..)
    , deleteActiveLeaveRequest
    , leaveReviewTouchedResources
    , reviewLeaveRequest
    , submitLeaveRequest
    ) where

import Application.Helper.FrontendContract.Surface.LeaveRequests.Resource
import Application.Helper.FrontendContract.Surface.Profile.Resource (staffLeaveRequestsResource)
import Application.Helper.FrontendContract.Surface.Roster.Live (activeRosterWindowScopes)
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterGroupStaffResource,
                                                                    rosterSlotsContentResource,
                                                                    rosterWeekResource)
import Application.Helper.SurfaceResource
import Application.Staff.Mutations (withStaffOperationalLocksInCurrentTransaction)
import Application.UnavailabilityBlackout.Mutations (findOverlappingUnavailabilityBlackout,
                                                     lockVenueUnavailabilityBlackoutInCurrentTransaction)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import Web.Controller.Prelude
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)

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
submitLeaveRequest leaveRequest =
    withDurableLiveMutationOutcome publicationFor do
        maybeMutationResult <- withStaffOperationalLocksInCurrentTransaction [leaveRequest.staffId] do
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
                today <- fetchVenueConfig >>= currentVenueCalendarDay
                let createdStatus = createdLeaveRequest.status
                let sectionResource = leaveRequestVisibleSectionResource today createdStatus createdLeaveRequest
                pure $
                    LeaveSubmissionCreated $
                        liveMutationResult createdLeaveRequest (baseLeaveTouchedResources createdLeaveRequest <> [sectionResource])
  where
    publicationFor (LeaveSubmissionCreated result) = Just ("leave.submit", result.liveMutationTouchedResources)
    publicationFor _ = Nothing

deleteActiveLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveRequest -> IO (Maybe (LiveMutationResult LeaveRequest))
deleteActiveLeaveRequest leaveRequest =
    withDurableLiveMutationOutcome publicationFor do
        fmap join $ withStaffOperationalLocksInCurrentTransaction [leaveRequest.staffId] do
            lockedRequest <-
                query @LeaveRequest
                    |> filterWhere (#id, leaveRequest.id)
                    |> filterWhere (#venueId, leaveRequest.venueId)
                    |> filterWhere (#staffId, leaveRequest.staffId)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOneOrNothing
            now <- getCurrentTime
            venueConfig <- fetchVenueConfig
            today <- venueCalendarDayAt venueConfig now
            case lockedRequest of
                Just request | not (leaveRequestIsArchivedOn today request) -> do
                    let reason = "staff_deleted_request" :: Text
                    deletedRequest <-
                        request
                            |> set #deletedAt (Just now)
                            |> set #deletedByUserId (Just (unpackId authenticatedCurrentUser.id))
                            |> set #deleteReason (Just reason)
                            |> updateRecord
                    void $
                        recordCurrentUserLeaveRequestEvent
                            deletedRequest
                            LeaveRequestEventTypeEnumDeleted
                            (Just request.status)
                            Nothing
                            (Aeson.object ["reason" Aeson..= reason])
                    void $
                        recordCurrentUserAuditEvent
                            LeaveDeletedAudit
                            "leave_requests"
                            (unpackId request.id)
                            (Aeson.object
                                [ "staffId" Aeson..= request.staffId
                                , "startDate" Aeson..= request.startDate
                                , "endDate" Aeson..= request.endDate
                                , "previousStatus" Aeson..= inputValue request.status
                                , "deletedAt" Aeson..= now
                                ])
                    rosterResources <-
                        if request.status == LeaveRequestStatusEnumApproved
                            then approvedLeaveDeletionRosterResources request
                            else pure []
                    pure $ Just $ liveMutationResult deletedRequest
                        (baseLeaveTouchedResources deletedRequest <> [leaveRequestVisibleSectionResource today request.status request] <> rosterResources)
                _ -> pure Nothing
  where
    publicationFor = fmap (\result -> ("leave.delete", result.liveMutationTouchedResources))

reviewLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveReviewDecision -> LeaveRequest -> IO (Maybe (LiveMutationResult ReviewedLeaveRequest))
reviewLeaveRequest decision leaveRequest =
    withDurableLiveMutationOutcome publicationFor do
        maybeReviewResult <- fmap join $ withStaffOperationalLocksInCurrentTransaction [leaveRequest.staffId] do
            staff <- fetch (Id leaveRequest.staffId :: Id Staff)
            if not staff.isActive || isJust staff.archivedAt || staff.venueId /= leaveRequest.venueId
                then pure Nothing
                else do
                    lockedLeaveRequest <- fetch leaveRequest.id
                    today <- fetchVenueConfig >>= currentVenueCalendarDay
                    if isJust lockedLeaveRequest.deletedAt || leaveRequestIsArchivedOn today lockedLeaveRequest
                        then pure Nothing
                        else do
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
                            pure (Just (updatedLeaveRequest, previousStatus, wasApproved, today))

        forM maybeReviewResult \(updatedLeaveRequest, previousStatus, wasApproved, today) -> do
            activeRosterScopes <- activeRosterWindowScopes
            let touchedResources = leaveReviewTouchedResources today decision previousStatus updatedLeaveRequest <> (if reviewDecisionChangesRoster decision wasApproved then leaveRosterWindowResources activeRosterScopes updatedLeaveRequest else [])
            pure $
                liveMutationResult
                    ReviewedLeaveRequest
                        { reviewedLeaveRequest = updatedLeaveRequest
                        , reviewedLeaveWasAlreadyApproved = wasApproved
                        }
                    touchedResources
  where
    publicationFor = fmap (\result -> ("leave.review", result.liveMutationTouchedResources))

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

approvedLeaveDeletionRosterResources :: (?modelContext :: ModelContext) => LeaveRequest -> IO [SurfaceResourceValue]
approvedLeaveDeletionRosterResources request = do
    activeScopes <- activeRosterWindowScopes
    -- Venue group resources also reach listeners in other app processes. Do
    -- not rely on current staff-group membership: existing assignments may
    -- still be visible in a group the staff member has since moved out of.
    groups <- query @RosterGroup
        |> filterWhere (#venueId, request.venueId)
        |> fetch
    pure (map (rosterGroupStaffResource . unpackId . (.id)) groups <> leaveRosterWindowResources activeScopes request)

leaveRosterWindowResources :: [(UUID, UUID, Day, Day, Int)] -> LeaveRequest -> [SurfaceResourceValue]
leaveRosterWindowResources activeScopes leaveRequest =
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
