module Web.LeaveRequests.Mutations
    ( LeaveReviewDecision (..)
    , LeaveSubmissionResult (..)
    , LeaveReviewResult (..)
    , LeavePolicyConflicts (..)
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
import Application.UnavailabilityBlackout.Mutations (lockVenueUnavailabilityBlackoutInCurrentTransaction)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import Web.Controller.Prelude
import Web.LeaveRequests.Policy
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
    | LeaveSubmissionBlocked !LeavePolicyConflicts !(Maybe Text)
    | LeaveSubmissionInvalidConfirmation
    | LeaveSubmissionCreated !(LiveMutationResult LeaveRequest)

data LeaveReviewResult
    = LeaveReviewUnavailable
    | LeaveReviewBlocked !LeavePolicyConflicts !(Maybe Text)
    | LeaveReviewInvalidConfirmation
    | LeaveReviewCompleted !(LiveMutationResult ReviewedLeaveRequest)

submitLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe Text -> LeaveRequest -> IO LeaveSubmissionResult
submitLeaveRequest token draft = withDurableLiveMutationOutcome publicationFor do
    result <- withStaffOperationalLocksInCurrentTransaction [draft.staffId] do
        lockVenueUnavailabilityBlackoutInCurrentTransaction draft.venueId
        staff <- fetch (Id draft.staffId :: Id Staff)
        authority <- fetchLeaveAuthority draft.venueId
        let mayOverride = maybe False (\role -> hasVenueRole role Manager) authority && hasRole Manager
        if isNothing authority || not staff.isActive || isJust staff.archivedAt || staff.venueId /= draft.venueId
                || (not mayOverride && staff.userId /= Just (unpackId effectiveCurrentUser.id))
            then pure LeaveSubmissionStaffInactive
            else do
                config <- fetchVenueConfig
                today <- currentVenueCalendarDay config
                checkLeavePolicy Nothing mayOverride token today config.unavailableStaffDailyMaximum draft >>= \case
                    InvalidConfirmation -> pure LeaveSubmissionInvalidConfirmation
                    Block conflicts confirmation -> pure (LeaveSubmissionBlocked conflicts confirmation)
                    Admit conflicts -> do
                        created <- draft |> set #status LeaveRequestStatusEnumPending |> createRecord
                        void $ recordCurrentUserLeaveRequestEvent created LeaveRequestEventTypeEnumCreated Nothing (Just created.status) Aeson.Null
                        recordOverride created conflicts
                        let section = leaveRequestVisibleSectionResource today created.status created
                        pure $ LeaveSubmissionCreated $ liveMutationResult created (baseLeaveTouchedResources created <> [section])
    pure (fromMaybe LeaveSubmissionStaffInactive result)
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

reviewLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe Text -> LeaveReviewDecision -> LeaveRequest -> IO LeaveReviewResult
reviewLeaveRequest token decision leaveRequest = withDurableLiveMutationOutcome publicationFor do
    result <- withStaffOperationalLocksInCurrentTransaction [leaveRequest.staffId] do
        lockVenueUnavailabilityBlackoutInCurrentTransaction leaveRequest.venueId
        staff <- fetch (Id leaveRequest.staffId :: Id Staff)
        authority <- fetchLeaveAuthority leaveRequest.venueId
        locked <- fetch leaveRequest.id
        config <- fetchVenueConfig
        today <- currentVenueCalendarDay config
        let previous = locked.status
        let wasApproved = previous == LeaveRequestStatusEnumApproved
        if not (hasRole Manager && maybe False (\role -> hasVenueRole role Manager) authority) || not staff.isActive || isJust staff.archivedAt
                || staff.venueId /= locked.venueId || locked.staffId /= leaveRequest.staffId || locked.venueId /= leaveRequest.venueId
                || isJust locked.deletedAt || leaveRequestIsArchivedOn today locked
            then pure LeaveReviewUnavailable
            else do
                policy <- case (decision, previous) of
                    (ApproveLeave, LeaveRequestStatusEnumDenied) ->
                        checkLeavePolicy (Just ("approve-denied:" <> tshow (unpackId locked.id))) True token today config.unavailableStaffDailyMaximum locked
                    _ | isJust token -> pure InvalidConfirmation
                    _ -> pure (Admit (LeavePolicyConflicts [] []))
                case policy of
                    Block conflicts confirmation -> pure (LeaveReviewBlocked conflicts confirmation)
                    InvalidConfirmation -> pure LeaveReviewInvalidConfirmation
                    Admit conflicts -> do
                        updated <- locked |> set #status (reviewDecisionStatus decision) |> updateRecord
                        void $ recordCurrentUserLeaveRequestEvent updated (reviewDecisionEventType decision) (Just previous) (Just updated.status) Aeson.Null
                        void $ recordCurrentUserAuditEvent (reviewDecisionAuditAction decision) "leave_requests" (unpackId locked.id) (Aeson.object
                            [ "staffId" Aeson..= locked.staffId
                            , "startDate" Aeson..= locked.startDate
                            , "endDate" Aeson..= locked.endDate
                            , "previousStatus" Aeson..= inputValue previous
                            , "newStatus" Aeson..= inputValue updated.status
                            ])
                        recordOverride updated conflicts
                        activeScopes <- activeRosterWindowScopes
                        let touched = leaveReviewTouchedResources today decision previous updated <> (if reviewDecisionChangesRoster decision wasApproved then leaveRosterWindowResources activeScopes updated else [])
                        pure $ LeaveReviewCompleted $ liveMutationResult (ReviewedLeaveRequest updated wasApproved) touched
    pure (fromMaybe LeaveReviewUnavailable result)
  where
    publicationFor (LeaveReviewCompleted result) = Just ("leave.review", result.liveMutationTouchedResources)
    publicationFor _ = Nothing

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
