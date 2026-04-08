module Web.Controller.LeaveRequests where

import Application.Helper.RosterGroups (fetchCurrentVenueRosterGroups)
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveFragmentRef (..),
                                      LiveUpdateScope (..),
                                      broadcastLiveInvalidation,
                                      currentLiveUpdateVersion)
import Application.Helper.SurfaceProjection
import Application.Helper.View (ToastOverlayConfig (..),
                                ToastOverlayPosition (..), dialogOverlayMountId,
                                renderToastOverlayHostOob)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import Data.Time.Calendar (addDays)
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Controller.RosterWeeks (broadcastRosterWeekInvalidation,
                                   buildRosterContentFragmentRef,
                                   buildRosterStaffPanelFragmentRef)
import Web.View.LeaveRequests.Index
import Web.View.LeaveRequests.New

instance Controller LeaveRequestsController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue
        ensureProfileCompleted

    action LeaveRequestsAction = do
        render . leaveRequestsIndexView =<< fetchLeaveRequestsProjectionCached

    action ShowLeaveRequestsContentFragmentAction = do
        respondHtml . fromMaybe mempty =<< renderLeaveRequestsProjectionFragment LeaveRequestsProjectionContent

    action NewLeaveRequestAction = do
        maybeStaff <- fetchCurrentUserStaff
        case maybeStaff of
            Nothing -> do
                setErrorMessage "No staff record found. Contact an administrator."
                redirectTo LeaveRequestsAction
            Just _ -> do
                today <- utctDay <$> getCurrentTime
                let leaveRequest =
                        newRecord @LeaveRequest
                            |> set #startDate today
                            |> set #endDate (addDays 1 today)
                if isHtmxRequest
                    then respondHtml (renderNewLeaveRequestDialog leaveRequest)
                    else render NewView { .. }

    action CreateLeaveRequestAction = do
        maybeStaff <- fetchCurrentUserStaff
        case maybeStaff of
            Nothing -> do
                setErrorMessage "No staff record found. Contact an administrator."
                redirectTo LeaveRequestsAction
            Just staff -> do
                let leaveRequest =
                        newRecord @LeaveRequest
                            |> set #venueId (unpackId currentVenueId)
                            |> set #staffId (coerce (get #id staff))
                            |> set #status (leaveRequestStatusToEnum LeavePending)
                            |> buildLeaveRequest

                leaveRequest
                    |> ifValid \case
                        Left leaveRequest ->
                            if isHtmxRequest
                                then respondHtml (renderNewLeaveRequestDialog leaveRequest)
                                else render NewView { .. }
                        Right leaveRequest -> do
                            _ <- withTransaction do
                                createdLeaveRequest <- leaveRequest |> createRecord
                                void $
                                    recordCurrentUserLeaveRequestEvent
                                        createdLeaveRequest
                                        (unsafeEnumFromText @LeaveRequestEventTypeEnum "created")
                                        Nothing
                                        (Just createdLeaveRequest.status)
                                        Aeson.Null
                                pure createdLeaveRequest
                            broadcastLeaveRequestsInvalidation [buildLeaveRequestsContentFragmentRef]
                            if isHtmxRequest
                                then respondWithLeaveRequestsContent "Leave request submitted" True
                                else do
                                    setSuccessMessage "Leave request submitted"
                                    redirectTo LeaveRequestsAction

    action ApproveLeaveRequestAction { leaveRequestId } = do
        ensureManagerRole
        leaveRequest <- fetch leaveRequestId
        ensureRecordInCurrentVenue leaveRequest.venueId
        updatedLeaveRequest <- withTransaction do
            let wasApproved = parseLeaveRequestStatus leaveRequest.status == Just LeaveApproved
            updatedLeaveRequest <-
                leaveRequest
                    |> set #status (leaveRequestStatusToEnum LeaveApproved)
                    |> updateRecord
            void $
                recordCurrentUserLeaveRequestEvent
                    updatedLeaveRequest
                    (unsafeEnumFromText @LeaveRequestEventTypeEnum "approved")
                    (Just leaveRequest.status)
                    (Just updatedLeaveRequest.status)
                    Aeson.Null
            void $ recordCurrentUserAuditEvent
                "leave_approved"
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
            pure (updatedLeaveRequest, wasApproved)
        let (savedLeaveRequest, wasApproved) = updatedLeaveRequest
        unless wasApproved do
            invalidateAffectedRosterWeeksForLeave savedLeaveRequest
        broadcastLeaveRequestsInvalidation [buildLeaveRequestsContentFragmentRef]
        if isHtmxRequest
            then respondWithLeaveRequestsContent "Leave request approved" False
            else do
                setSuccessMessage "Leave request approved"
                redirectTo LeaveRequestsAction

    action DenyLeaveRequestAction { leaveRequestId } = do
        ensureManagerRole
        leaveRequest <- fetch leaveRequestId
        ensureRecordInCurrentVenue leaveRequest.venueId
        deniedLeaveRequest <- withTransaction do
            let wasApproved = parseLeaveRequestStatus leaveRequest.status == Just LeaveApproved
            updatedLeaveRequest <-
                leaveRequest
                    |> set #status (leaveRequestStatusToEnum LeaveDenied)
                    |> updateRecord
            void $
                recordCurrentUserLeaveRequestEvent
                    updatedLeaveRequest
                    (unsafeEnumFromText @LeaveRequestEventTypeEnum "denied")
                    (Just leaveRequest.status)
                    (Just updatedLeaveRequest.status)
                    Aeson.Null
            void $ recordCurrentUserAuditEvent
                "leave_denied"
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
            pure (updatedLeaveRequest, wasApproved)
        let (savedLeaveRequest, wasApproved) = deniedLeaveRequest
        when wasApproved do
            invalidateAffectedRosterWeeksForLeave savedLeaveRequest
        broadcastLeaveRequestsInvalidation [buildLeaveRequestsContentFragmentRef]
        if isHtmxRequest
            then respondWithLeaveRequestsContent "Leave request denied" False
            else do
                setSuccessMessage "Leave request denied"
                redirectTo LeaveRequestsAction

    action DeleteLeaveRequestAction { leaveRequestId } = do
        leaveRequest <- fetch leaveRequestId
        ensureRecordInCurrentVenue leaveRequest.venueId
        ensureLeaveDeleteAllowed leaveRequest
        unless (leaveRequestCanBeDeleted leaveRequest) do
            setErrorMessage "Reviewed leave requests cannot be deleted."
            redirectTo LeaveRequestsAction
        withTransaction do
            void $
                recordCurrentUserLeaveRequestEvent
                    leaveRequest
                    (unsafeEnumFromText @LeaveRequestEventTypeEnum "deleted")
                    (Just leaveRequest.status)
                    Nothing
                    Aeson.Null
            void $ recordCurrentUserAuditEvent
                "leave_deleted"
                "leave_requests"
                (unpackId (get #id leaveRequest))
                (Aeson.object
                    [ "staffId" Aeson..= leaveRequest.staffId
                    , "startDate" Aeson..= leaveRequest.startDate
                    , "endDate" Aeson..= leaveRequest.endDate
                    , "deletedStatus" Aeson..= inputValue leaveRequest.status
                    ]
                )
            deleteRecord leaveRequest
        broadcastLeaveRequestsInvalidation [buildLeaveRequestsContentFragmentRef]
        if isHtmxRequest
            then respondWithLeaveRequestsContent "Leave request deleted" False
            else do
                setSuccessMessage "Leave request deleted"
                redirectTo LeaveRequestsAction

fetchStaffMembersForCurrentVenue :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [Staff]
fetchStaffMembersForCurrentVenue =
    query @Staff |> filterWhere (#venueId, unpackId currentVenueId) |> orderByAsc #lastName |> fetch

fetchVisibleLeaveRequests :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [LeaveRequest]
fetchVisibleLeaveRequests = do
    if hasRole ManagerRole'
        then
            query @LeaveRequest
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> orderByDesc #startDate
                |> fetch
        else do
            maybeStaff <- fetchCurrentUserStaff
            case maybeStaff of
                Nothing -> pure []
                Just staff ->
                    query @LeaveRequest
                        |> filterWhere (#venueId, unpackId currentVenueId)
                        |> filterWhere (#staffId, coerce (get #id staff))
                        |> orderByDesc #startDate
                        |> fetch

data LeaveRequestsProjection = LeaveRequestsProjection
    { leaveProjectionRequests :: [LeaveRequest]
    , leaveProjectionStaffMembers :: [Staff]
    , leaveProjectionCurrentViewerStaffId :: Maybe UUID
    }

data LeaveRequestsProjectionFragment
    = LeaveRequestsProjectionPage
    | LeaveRequestsProjectionContent
    deriving (Eq, Show)

leaveRequestsProjectionDefinition :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => SurfaceProjectionDefinition () LeaveRequestsProjection LeaveRequestsProjectionFragment
leaveRequestsProjectionDefinition =
    SurfaceProjectionDefinition
        { surfaceName = "leave-requests"
        , cachePolicy = defaultSurfaceProjectionCachePolicy
        , scopeKey = const (tshow currentVenueId)
        , viewerKey = pure (tshow currentUser.id)
        , currentVersion = const (currentLiveUpdateVersion (buildLeaveRequestsScope currentVenueId))
        , loadProjection = const fetchLeaveRequestsProjection
        , renderFragment = renderLeaveRequestsProjectionHtml
        , buildFragmentRef = \() fragment ->
            case fragment of
                LeaveRequestsProjectionPage -> buildLeaveRequestsPageFragmentRef
                LeaveRequestsProjectionContent -> buildLeaveRequestsContentFragmentRef
        }

fetchLeaveRequestsProjectionCached :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO LeaveRequestsProjection
fetchLeaveRequestsProjectionCached =
    loadSurfaceProjection leaveRequestsProjectionDefinition ()

renderLeaveRequestsProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveRequestsProjectionFragment -> IO (Maybe Blaze.Html)
renderLeaveRequestsProjectionFragment fragment =
    renderSurfaceProjectionFragment leaveRequestsProjectionDefinition () fragment

fetchLeaveRequestsProjection :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO LeaveRequestsProjection
fetchLeaveRequestsProjection = do
    leaveProjectionStaffMembers <- fetchStaffMembersForCurrentVenue
    leaveProjectionRequests <- fetchVisibleLeaveRequests
    leaveProjectionCurrentViewerStaffId <- fmap (fmap (coerce . get #id)) fetchCurrentUserStaff
    pure LeaveRequestsProjection { .. }

renderLeaveRequestsProjectionHtml :: (?context :: ControllerContext, ?request :: Request) => LeaveRequestsProjection -> LeaveRequestsProjectionFragment -> Maybe Blaze.Html
renderLeaveRequestsProjectionHtml projection fragment =
    case fragment of
        LeaveRequestsProjectionPage ->
            Just (renderLeaveRequestsShell (leaveRequestsIndexView projection))
        LeaveRequestsProjectionContent ->
            Just
                (renderLeaveRequestsContentFragment
                    projection.leaveProjectionRequests
                    projection.leaveProjectionStaffMembers
                    projection.leaveProjectionCurrentViewerStaffId
                )

leaveRequestsIndexView :: (?context :: ControllerContext) => LeaveRequestsProjection -> IndexView
leaveRequestsIndexView LeaveRequestsProjection { leaveProjectionRequests, leaveProjectionStaffMembers, leaveProjectionCurrentViewerStaffId } =
    IndexView
        { leaveRequests = leaveProjectionRequests
        , staffMembers = leaveProjectionStaffMembers
        , currentViewerStaffId = leaveProjectionCurrentViewerStaffId
        , liveUpdateScope = Just (buildLeaveRequestsScope currentVenueId)
        }

respondWithLeaveRequestsContent :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => Text -> Bool -> IO ()
respondWithLeaveRequestsContent successMessage renderMainFragmentOob = do
    staffMembers <- fetchStaffMembersForCurrentVenue
    leaveRequests <- fetchVisibleLeaveRequests
    currentViewerStaffId <- fmap (fmap (coerce . get #id)) fetchCurrentUserStaff
    let mainFragment =
            if renderMainFragmentOob
                then renderLeaveRequestsContentFragmentOob leaveRequests staffMembers currentViewerStaffId
                else renderLeaveRequestsContentFragment leaveRequests staffMembers currentViewerStaffId
    respondHtml $
        mconcat
            [ mainFragment
            , [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            , renderToastOverlayHostOob ToastBottomCenter
                [ ToastOverlayConfig
                    { toastOverlayTitle = Just "Success"
                    , toastOverlayMessage = successMessage
                    , toastOverlayClass = "app-toast-success"
                    , toastOverlayAutoHideMs = 3200
                    }
                ]
            ]

ensureLeaveDeleteAllowed :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LeaveRequest -> IO ()
ensureLeaveDeleteAllowed leaveRequest =
    if hasRole ManagerRole'
        then pure ()
        else do
            maybeStaff <- fetchCurrentUserStaff
            let canDeleteOwn = maybe False (\staff -> coerce (get #id staff) == leaveRequest.staffId) maybeStaff
            accessDeniedUnless canDeleteOwn

buildLeaveRequest :: (?context :: ControllerContext, ?request :: Request) => LeaveRequest -> LeaveRequest
buildLeaveRequest leaveRequest =
    leaveRequest
        |> fill @'["startDate", "endDate", "notes"]
        |> validateField #endDate (validateEndDate leaveRequest.startDate)
    where
        validateEndDate startDate endDate =
            if isLeaveDateRangeValid startDate endDate
                then Success
                else Failure "Available again must be at least one day after unavailable from"

invalidateAffectedRosterWeeksForLeave :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveRequest -> IO ()
invalidateAffectedRosterWeeksForLeave leaveRequest = do
    venueConfig <- fetchVenueConfig
    let affectedOffsets =
            affectedWeekOffsetsForDateRange
                venueConfig.weekOffsetEpoch
                leaveRequest.startDate
                leaveRequest.endDate

    rosterGroups <- fetchCurrentVenueRosterGroups
    forM_ rosterGroups \rosterGroup ->
        forM_ affectedOffsets \weekOffset ->
            broadcastRosterWeekInvalidation
                rosterGroup.id
                weekOffset
                [ buildRosterContentFragmentRef rosterGroup.id weekOffset
                , buildRosterStaffPanelFragmentRef rosterGroup.id weekOffset
                ]

buildLeaveRequestsScope :: Id Venue -> LiveUpdateScope
buildLeaveRequestsScope venueId =
    LeaveRequestsScope
        { venueId = unpackId venueId
        }

buildLeaveRequestsContentFragmentRef :: (?context :: ControllerContext) => LiveFragmentRef
buildLeaveRequestsContentFragmentRef =
    LiveFragmentRef
        { fragmentKey = LeaveRequestsContentFragment
        , targetId = leaveRequestsContentFragmentId
        , url = pathTo ShowLeaveRequestsContentFragmentAction
        , deferUntilBlur = False
        }

buildLeaveRequestsPageFragmentRef :: (?context :: ControllerContext) => LiveFragmentRef
buildLeaveRequestsPageFragmentRef =
    LiveFragmentRef
        { fragmentKey = LeaveRequestsContentFragment
        , targetId = leaveRequestsShellId
        , url = pathTo LeaveRequestsAction
        , deferUntilBlur = False
        }

broadcastLeaveRequestsInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    [LiveFragmentRef] ->
    IO ()
broadcastLeaveRequestsInvalidation fragments =
    unless (null fragments) do
        liftIO $
            broadcastLiveInvalidation
                (buildLeaveRequestsScope currentVenueId)
                (cs <$> getHeader "X-Live-Update-Client-Id")
                fragments
