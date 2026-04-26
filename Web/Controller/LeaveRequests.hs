module Web.Controller.LeaveRequests where

import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveFragmentRef (..),
                                      LiveUpdateScope (..),
                                      broadcastLiveInvalidation,
                                      currentLiveUpdateVersion)
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchCurrentUserLeaveRequests)
import Application.Helper.Profiling
import Application.Helper.RosterGroups (fetchCurrentVenueRosterGroups)
import Application.Helper.SurfaceProjection
import Application.Helper.View (ToastOverlayConfig (..),
                                ToastOverlayPosition (..), dialogOverlayMountId,
                                renderToastOverlayHostOob)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.RosterWeeks.LiveUpdates (broadcastRosterWeekInvalidation)
import Web.RosterWeeks.Projection (buildRosterContentFragmentRef,
                                   buildRosterStaffPanelFragmentRef)
import Web.View.LeaveRequests.Index
import Web.View.LeaveRequests.New
import Web.View.Profiles.Edit (renderProfileLeaveRequestFormFragment,
                               renderProfileLeaveRequestsContentFragment,
                               renderProfileLeaveRequestsListFragmentOob,
                               profileLeaveRequestFormFragmentId,
                               profileLeaveRequestsContentFragmentId,
                               profileLeaveRequestsListFragmentId)

instance Controller LeaveRequestsController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue

    action LeaveRequestsAction = do
        ensureProfileCompleted
        ensureManagerRole
        renderProfiled . leaveRequestsIndexView =<< fetchLeaveRequestsProjectionCached

    action ShowLeaveRequestsContentFragmentAction = do
        ensureProfileCompleted
        ensureManagerRole
        respondHtmlProfiled . fromMaybe mempty =<< renderLeaveRequestsProjectionFragment LeaveRequestsProjectionContent

    action NewLeaveRequestAction = do
        ensureStaffSelfServiceAccess
        maybeStaff <- fetchCurrentUserStaff
        let responseContext = requestedLeaveResponseContext
        ensureLeaveProfileAccess responseContext
        case maybeStaff of
            Nothing -> do
                respondWithLeaveContextError responseContext "No staff record found. Contact an administrator."
            Just _ -> do
                leaveRequest <- buildDefaultLeaveRequest
                if isHtmxRequest
                    then respondHtml (renderNewLeaveRequestDialog leaveRequest)
                    else render NewView { .. }

    action CreateLeaveRequestAction = do
        ensureStaffSelfServiceAccess
        maybeStaff <- fetchCurrentUserStaff
        let responseContext = requestedLeaveResponseContext
        ensureLeaveProfileAccess responseContext
        case maybeStaff of
            Nothing -> do
                respondWithLeaveContextError responseContext "No staff record found. Contact an administrator."
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
                                then respondWithLeaveRequestValidationFailure responseContext leaveRequest
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
                                then respondWithLeaveMutationSuccess responseContext "Leave request submitted" True
                                else do
                                    setSuccessMessage "Leave request submitted"
                                    redirectToPath (leaveFallbackPath responseContext)

    action ApproveLeaveRequestAction { leaveRequestId } = do
        ensureProfileCompleted
        ensureManagerRole
        leaveRequest <- fetch leaveRequestId
        ensureRecordInCurrentVenue leaveRequest.venueId
        accessDeniedUnless (isNothing leaveRequest.deletedAt)
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
        ensureProfileCompleted
        ensureManagerRole
        leaveRequest <- fetch leaveRequestId
        ensureRecordInCurrentVenue leaveRequest.venueId
        accessDeniedUnless (isNothing leaveRequest.deletedAt)
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
        let responseContext = requestedLeaveResponseContext
        ensureLeaveProfileAccess responseContext
        ensureRecordInCurrentVenue leaveRequest.venueId
        accessDeniedUnless (isNothing leaveRequest.deletedAt)
        ensureLeaveDeleteAllowed leaveRequest
        unless (leaveRequestCanBeDeleted leaveRequest) do
            setErrorMessage "Reviewed leave requests cannot be deleted."
            redirectToPath (leaveFallbackPath responseContext)
        now <- getCurrentTime
        withTransaction do
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
        broadcastLeaveRequestsInvalidation [buildLeaveRequestsContentFragmentRef]
        if isHtmxRequest
            then respondWithLeaveMutationSuccess responseContext "Leave request cancelled" False
            else do
                setSuccessMessage "Leave request cancelled"
                redirectToPath (leaveFallbackPath responseContext)

fetchStaffMembersForCurrentVenue :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [Staff]
fetchStaffMembersForCurrentVenue =
    query @Staff |> filterWhere (#venueId, unpackId currentVenueId) |> orderByAsc #lastName |> fetch

fetchVisibleLeaveRequests :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO [LeaveRequest]
fetchVisibleLeaveRequests = do
    if hasRole ManagerRole'
        then
            query @LeaveRequest
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#deletedAt, Nothing)
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
                        |> filterWhere (#deletedAt, Nothing)
                        |> orderByDesc #startDate
                        |> fetch

data LeaveRequestsProjection = LeaveRequestsProjection
    { leaveProjectionRequests             :: [LeaveRequest]
    , leaveProjectionStaffMembers         :: [Staff]
    , leaveProjectionCurrentViewerStaffId :: Maybe UUID
    , leaveProjectionToday                :: Day
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
    profileActionSpanWithDetail "leave.projection.load" do
        before <- readSurfaceProjectionCacheStats
        projection <- loadSurfaceProjection leaveRequestsProjectionDefinition ()
        after <- readSurfaceProjectionCacheStats
        pure (projection, surfaceProjectionCacheDeltaDetail before after)

renderLeaveRequestsProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveRequestsProjectionFragment -> IO (Maybe Blaze.Html)
renderLeaveRequestsProjectionFragment fragment =
    profileActionSpanWithDetail "leave.projection.render_fragment" do
        before <- readSurfaceProjectionCacheStats
        html <- renderSurfaceProjectionFragment leaveRequestsProjectionDefinition () fragment
        after <- readSurfaceProjectionCacheStats
        pure (html, surfaceProjectionCacheDeltaDetail before after)

fetchLeaveRequestsProjection :: (?modelContext :: ModelContext, ?context :: ControllerContext) => IO LeaveRequestsProjection
fetchLeaveRequestsProjection = do
    leaveProjectionStaffMembers <- profileActionSpan "leave.fetch_staff_members" fetchStaffMembersForCurrentVenue
    leaveProjectionRequests <- profileActionSpan "leave.fetch_requests" fetchVisibleLeaveRequests
    leaveProjectionCurrentViewerStaffId <- fmap (fmap (coerce . get #id)) fetchCurrentUserStaff
    leaveProjectionToday <- liftIO (utctDay <$> getCurrentTime)
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
                    projection.leaveProjectionToday
                )

leaveRequestsIndexView :: (?context :: ControllerContext) => LeaveRequestsProjection -> IndexView
leaveRequestsIndexView LeaveRequestsProjection { leaveProjectionRequests, leaveProjectionStaffMembers, leaveProjectionCurrentViewerStaffId, leaveProjectionToday } =
    IndexView
        { leaveRequests = leaveProjectionRequests
        , staffMembers = leaveProjectionStaffMembers
        , currentViewerStaffId = leaveProjectionCurrentViewerStaffId
        , today = leaveProjectionToday
        , liveUpdateScope = Just (buildLeaveRequestsScope currentVenueId)
        }

respondWithLeaveRequestsContent :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => Text -> Bool -> IO ()
respondWithLeaveRequestsContent successMessage renderMainFragmentOob = do
    projection <- fetchLeaveRequestsProjectionCached
    let mainFragment =
            if renderMainFragmentOob
                then renderLeaveRequestsContentFragmentOob projection.leaveProjectionRequests projection.leaveProjectionStaffMembers projection.leaveProjectionCurrentViewerStaffId projection.leaveProjectionToday
                else renderLeaveRequestsContentFragment projection.leaveProjectionRequests projection.leaveProjectionStaffMembers projection.leaveProjectionCurrentViewerStaffId projection.leaveProjectionToday
    respondHtmlProfiled $
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

data LeaveResponseContext
    = LeavePageResponseContext
    | LeaveProfileResponseContext
    deriving (Eq, Show)

parseLeaveResponseContext :: Text -> LeaveResponseContext
parseLeaveResponseContext responseContext
    | responseContext == "profile" = LeaveProfileResponseContext
    | otherwise = LeavePageResponseContext

effectiveLeaveResponseContext :: (?context :: ControllerContext) => LeaveResponseContext -> LeaveResponseContext
effectiveLeaveResponseContext requestedContext
    | not (hasRole ManagerRole') = LeaveProfileResponseContext
    | otherwise = requestedContext

requestedLeaveResponseContext :: (?context :: ControllerContext, ?request :: Request) => LeaveResponseContext
requestedLeaveResponseContext =
    effectiveLeaveResponseContext $
        fromMaybe inferredFromHtmxTarget (parseLeaveResponseContext <$> paramOrNothing @Text "responseContext")
    where
        inferredFromHtmxTarget =
            case cs <$> getHeader "HX-Target" of
                Just targetId
                    | targetId `elem`
                        [ profileLeaveRequestsContentFragmentId
                        , profileLeaveRequestFormFragmentId
                        , profileLeaveRequestsListFragmentId
                        ] -> LeaveProfileResponseContext
                _ -> LeavePageResponseContext

leaveFallbackPath :: LeaveResponseContext -> Text
leaveFallbackPath LeavePageResponseContext = pathTo EditProfileAction
leaveFallbackPath LeaveProfileResponseContext =
    pathTo EditProfileAction <> "?section=leave"

respondWithLeaveRequestValidationFailure :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => LeaveResponseContext -> LeaveRequest -> IO ()
respondWithLeaveRequestValidationFailure responseContext leaveRequest =
    case responseContext of
        LeavePageResponseContext ->
            respondHtml (renderNewLeaveRequestDialog leaveRequest)
        LeaveProfileResponseContext ->
            respondHtml (renderProfileLeaveRequestFormFragment leaveRequest)

respondWithLeaveMutationSuccess :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => LeaveResponseContext -> Text -> Bool -> IO ()
respondWithLeaveMutationSuccess responseContext successMessage renderMainFragmentOob =
    case responseContext of
        LeavePageResponseContext ->
            respondWithLeaveRequestsContent successMessage renderMainFragmentOob
        LeaveProfileResponseContext -> do
            leaveRequests <- fetchCurrentUserLeaveRequests
            leaveRequest <- buildDefaultLeaveRequest
            respondHtmlProfiled $
                mconcat
                    [ renderProfileLeaveRequestFormFragment leaveRequest
                    , renderProfileLeaveRequestsListFragmentOob leaveRequests
                    , renderToastOverlayHostOob ToastBottomCenter
                        [ ToastOverlayConfig
                            { toastOverlayTitle = Just "Success"
                            , toastOverlayMessage = successMessage
                            , toastOverlayClass = "app-toast-success"
                            , toastOverlayAutoHideMs = 3200
                            }
                        ]
                    ]

ensureLeaveProfileAccess :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LeaveResponseContext -> IO ()
ensureLeaveProfileAccess responseContext =
    case responseContext of
        LeavePageResponseContext -> ensureProfileCompleted
        LeaveProfileResponseContext -> pure ()

respondWithLeaveContextError :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => LeaveResponseContext -> Text -> IO ()
respondWithLeaveContextError responseContext errorMessage =
    case responseContext of
        LeavePageResponseContext -> do
            setErrorMessage errorMessage
            redirectToPath (leaveFallbackPath responseContext)
        LeaveProfileResponseContext -> do
            leaveRequest <- buildDefaultLeaveRequest
            respondHtmlProfiled $
                mconcat
                    [ renderProfileLeaveRequestFormFragment leaveRequest
                    , renderToastOverlayHostOob ToastBottomCenter
                        [ ToastOverlayConfig
                            { toastOverlayTitle = Just "Error"
                            , toastOverlayMessage = errorMessage
                            , toastOverlayClass = "app-toast-danger"
                            , toastOverlayAutoHideMs = 4200
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
            affectedVenueWeekOffsetsForDateRange
                venueConfig
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
