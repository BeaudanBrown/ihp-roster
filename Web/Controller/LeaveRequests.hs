module Web.Controller.LeaveRequests where

import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchCurrentUserLeaveRequests)
import Application.Helper.Profiling
import Application.Helper.View (ToastOverlayPosition (..), dialogOverlayMountId,
                                errorToast, renderToastOob, successToast)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Coerce (coerce)
import qualified Data.Text.IO as TextIO
import qualified Data.Time.Calendar as Calendar
import Data.Time.Clock (getCurrentTime)
import Web.Controller.Prelude
import Web.LeaveRequests.ProfileSelfService
import Web.LeaveRequests.Projection
import Web.View.LeaveRequests.Index
import Web.View.LeaveRequests.New
import Web.View.RosterWeeks.StaffSelfServicePanel (renderRosterStaffSelfServiceLeaveFormFragment)

instance Controller LeaveRequestsController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect

    action LeaveRequestsAction = do
        ensureProfileCompleted
        ensureManagerRole
        renderProfiled . leaveRequestsIndexView =<< fetchLeaveRequestsProjectionCached

    action ShowLeaveRequestsContentFragmentAction = do
        ensureProfileCompleted
        ensureManagerRole
        maybeHtml <- renderLeaveRequestsProjectionFragment LeaveRequestsProjectionContent
        when (isNothing maybeHtml) do
            TextIO.putStrLn "leave_projection_miss: fragment=content"
        respondHtmlProfiled (fromMaybe mempty maybeHtml)

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
        ensureVenueWritable
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
                            broadcastLeaveRequestsInvalidation leaveRequestsContentFragmentRefs
                            if isHtmxRequest
                                then respondWithLeaveMutationSuccess responseContext "Unavailable period submitted" True
                                else do
                                    setSuccessMessage "Unavailable period submitted"
                                    redirectToPath (leaveFallbackPath responseContext)

    action ApproveLeaveRequestAction { leaveRequestId } = do
        ensureProfileCompleted
        ensureManagerRole
        ensureVenueWritable
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
        broadcastLeaveRequestsInvalidation leaveRequestsContentFragmentRefs
        if isHtmxRequest
            then respondWithLeaveRequestsContent "Unavailable period approved" False
            else do
                setSuccessMessage "Unavailable period approved"
                redirectTo LeaveRequestsAction

    action DenyLeaveRequestAction { leaveRequestId } = do
        ensureProfileCompleted
        ensureManagerRole
        ensureVenueWritable
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
        broadcastLeaveRequestsInvalidation leaveRequestsContentFragmentRefs
        if isHtmxRequest
            then respondWithLeaveRequestsContent "Unavailable period denied" False
            else do
                setSuccessMessage "Unavailable period denied"
                redirectTo LeaveRequestsAction

    action DeleteLeaveRequestAction { leaveRequestId } = do
        ensureVenueWritable
        leaveRequest <- fetch leaveRequestId
        let responseContext = requestedLeaveResponseContext
        ensureLeaveProfileAccess responseContext
        ensureRecordInCurrentVenue leaveRequest.venueId
        accessDeniedUnless (isNothing leaveRequest.deletedAt)
        ensureLeaveDeleteAllowed leaveRequest
        unless (leaveRequestCanBeDeleted leaveRequest) do
            setErrorMessage "Reviewed unavailable periods cannot be deleted."
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
        broadcastLeaveRequestsInvalidation leaveRequestsContentFragmentRefs
        if isHtmxRequest
            then respondWithLeaveMutationSuccess responseContext "Unavailable period cancelled" False
            else do
                setSuccessMessage "Unavailable period cancelled"
                redirectToPath (leaveFallbackPath responseContext)

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
            , renderToastOob ToastBottomCenter (successToast successMessage)
            ]

data LeaveResponseContext
    = LeavePageResponseContext
    | LeaveProfileResponseContext
    | LeaveRosterResponseContext
    deriving (Eq, Show)

parseLeaveResponseContext :: Text -> LeaveResponseContext
parseLeaveResponseContext responseContext
    | responseContext == "profile" = LeaveProfileResponseContext
    | responseContext == "roster" = LeaveRosterResponseContext
    | otherwise = LeavePageResponseContext

effectiveLeaveResponseContext :: (?context :: ControllerContext) => LeaveResponseContext -> LeaveResponseContext
effectiveLeaveResponseContext requestedContext
    | requestedContext == LeaveRosterResponseContext = LeaveRosterResponseContext
    | not (hasRole ManagerRole') = LeaveProfileResponseContext
    | otherwise = requestedContext

requestedLeaveResponseContext :: (?context :: ControllerContext, ?request :: Request) => LeaveResponseContext
requestedLeaveResponseContext =
    effectiveLeaveResponseContext $
        maybe inferredFromHtmxTarget parseLeaveResponseContext (paramOrNothing @Text "responseContext")
    where
        inferredFromHtmxTarget =
            case cs <$> getHeader "HX-Target" of
                Just targetId | targetId `elem` profileLeaveTargetFragmentIds -> LeaveProfileResponseContext
                _ -> LeavePageResponseContext

leaveFallbackPath :: LeaveResponseContext -> Text
leaveFallbackPath LeavePageResponseContext = pathTo EditProfileAction
leaveFallbackPath LeaveProfileResponseContext =
    pathTo EditProfileAction <> "?section=leave"
leaveFallbackPath LeaveRosterResponseContext = pathTo RosterWeeksAction

respondWithLeaveRequestValidationFailure :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => LeaveResponseContext -> LeaveRequest -> IO ()
respondWithLeaveRequestValidationFailure responseContext leaveRequest =
    case responseContext of
        LeavePageResponseContext ->
            respondHtml (renderNewLeaveRequestDialog leaveRequest)
        LeaveProfileResponseContext ->
            respondHtml (renderProfileLeaveRequestFormFragment leaveRequest)
        LeaveRosterResponseContext ->
            respondHtml (renderRosterStaffSelfServiceLeaveFormFragment leaveRequest)

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
                    , renderToastOob ToastBottomCenter (successToast successMessage)
                    ]
        LeaveRosterResponseContext -> do
            leaveRequest <- buildDefaultRosterLeaveRequest
            respondHtmlProfiled $
                mconcat
                    [ renderRosterStaffSelfServiceLeaveFormFragment leaveRequest
                    , renderToastOob ToastBottomCenter (successToast successMessage)
                    ]

ensureLeaveProfileAccess :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LeaveResponseContext -> IO ()
ensureLeaveProfileAccess responseContext =
    case responseContext of
        LeavePageResponseContext    -> ensureProfileCompleted
        LeaveProfileResponseContext -> pure ()
        LeaveRosterResponseContext  -> ensureProfileCompleted

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
                    , renderToastOob ToastBottomCenter (errorToast errorMessage)
                    ]
        LeaveRosterResponseContext -> do
            leaveRequest <- buildDefaultRosterLeaveRequest
            respondHtmlProfiled $
                mconcat
                    [ renderRosterStaffSelfServiceLeaveFormFragment leaveRequest
                    , renderToastOob ToastBottomCenter (errorToast errorMessage)
                    ]

ensureLeaveDeleteAllowed :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LeaveRequest -> IO ()
ensureLeaveDeleteAllowed leaveRequest =
    if hasRole ManagerRole'
        then pure ()
        else do
            maybeStaff <- fetchCurrentUserStaff
            let canDeleteOwn = maybe False (\staff -> coerce (get #id staff) == leaveRequest.staffId) maybeStaff
            accessDeniedUnless canDeleteOwn

buildDefaultRosterLeaveRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO LeaveRequest
buildDefaultRosterLeaveRequest = do
    venueConfig <- fetchVenueConfig
    operationalDay <- currentOperationalDayForVenue venueConfig
    pure $
        newRecord @LeaveRequest
            |> set #startDate operationalDay
            |> set #endDate (Calendar.addDays 1 operationalDay)

buildLeaveRequest :: (?context :: ControllerContext, ?request :: Request) => LeaveRequest -> LeaveRequest
buildLeaveRequest leaveRequest =
    leaveRequest
        |> requireParam #startDate "startDate" "Please choose an unavailable from date"
        |> requireParam #endDate "endDate" "Please choose an available again date"
        |> fill @'["startDate", "endDate", "notes"]
        |> normalizeMaybeTextField #notes
        |> validateField #notes (validateMaybe (boundedText 1000))
        |> validateField #endDate (validateEndDate leaveRequest.startDate)
    where
        validateEndDate startDate endDate =
            if isLeaveDateRangeValid startDate endDate
                then Success
                else Failure "Available again must be at least one day after unavailable from"
