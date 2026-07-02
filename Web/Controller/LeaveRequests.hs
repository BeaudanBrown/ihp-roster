module Web.Controller.LeaveRequests where

import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchStaffLeaveRequests)
import Application.Helper.Profiling
import Application.Helper.View (ToastOverlayPosition (..), dialogOverlayMountId,
                                errorToast, renderToastOob, successToast)
import Application.Helper.View.Oob (outerHtmlOobSwap)
import Data.Coerce (coerce)
import qualified Data.Text.IO as TextIO
import Web.Controller.Prelude
import Web.LeaveRequests.Mutations
import Web.LeaveRequests.ProfileSelfService
import Web.LeaveRequests.ReadModel
import Web.Profiles.LeaveFragments
import Web.Profiles.LiveUpdates (profileLeaveRequestsFragment)
import Web.RosterWeeks.StaffSelfServiceLeaveFragments
import Web.View.LeaveRequests.Index
import Web.View.LeaveRequests.New
import Web.View.RosterWeeks.StaffSelfServicePanel (renderRosterStaffSelfServiceLeaveFormFragment)
import Web.View.Staff.Edit (renderStaffLeaveRequestFormFragment,
                            renderStaffLeaveRequestsListFragmentOob)

instance Controller LeaveRequestsController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect

    action currentAction@LeaveRequestsAction = runBepis currentAction BepisPageAction $
        profileActionSpan "leave.page.render" do
            ensureProfileCompleted
            ensureManagerRole
            readModel <- profileActionSpan "leave.page.fetch_read_model" fetchLeaveRequestsReadModel
            profileActionSpan "leave.page.render_response" (renderProfiled (leaveRequestsIndexView readModel))

    action currentAction@ShowLeaveRequestsContentFragmentAction = runBepis currentAction BepisFragmentAction $
        profileActionSpan "leave.fragment.respond" do
            ensureProfileCompleted
            ensureManagerRole
            if paramOrDefault @Text "" "swapOob" == "true"
                then do
                    readModel <- profileActionSpan "leave.fragment.fetch_read_model" fetchLeaveRequestsReadModel
                    respondHtmlProfiled $
                        renderArchivePageContentOob
                            readModel.leaveReadModelRequests
                            readModel.leaveReadModelStaffMembers
                            readModel.leaveReadModelCurrentViewerStaffId
                            readModel.leaveReadModelToday
                            currentLeaveArchivePage
                else do
                    maybeHtml <- profileActionSpan "leave.fragment.render" (renderLeaveRequestsFragment LeaveRequestsContent)
                    when (isNothing maybeHtml) do
                        TextIO.putStrLn "leave_fragment_miss: fragment=content"
                    respondHtmlProfiled (fromMaybe mempty maybeHtml)

    action currentAction@NewLeaveRequestAction = runBepis currentAction BepisFormAction do
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

    action currentAction@CreateLeaveRequestAction = runBepis currentAction BepisMutationAction do
        ensureStaffSelfServiceAccess
        ensureVenueWritable
        let responseContext = requestedLeaveResponseContext
        ensureLeaveProfileAccess responseContext
        maybeStaff <- fetchLeaveRequestTargetStaff responseContext
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
                            _ <- submitLeaveRequest leaveRequest
                            if isHtmxRequest
                                then respondWithLeaveMutationSuccess responseContext "Unavailable period submitted"
                                else do
                                    setSuccessMessage "Unavailable period submitted"
                                    redirectToPath (leaveFallbackPath responseContext)

    action currentAction@ApproveLeaveRequestAction { leaveRequestId } = runBepis currentAction BepisMutationAction do
        ensureProfileCompleted
        ensureManagerRole
        ensureVenueWritable
        leaveRequest <- fetch leaveRequestId
        ensureRecordInCurrentVenue leaveRequest.venueId
        accessDeniedUnless (isNothing leaveRequest.deletedAt)
        _ <- reviewLeaveRequest ApproveLeave leaveRequest
        if isHtmxRequest
            then respondWithLeaveRequestsContent "Unavailable period approved"
            else do
                setSuccessMessage "Unavailable period approved"
                redirectTo LeaveRequestsAction

    action currentAction@DenyLeaveRequestAction { leaveRequestId } = runBepis currentAction BepisMutationAction do
        ensureProfileCompleted
        ensureManagerRole
        ensureVenueWritable
        leaveRequest <- fetch leaveRequestId
        ensureRecordInCurrentVenue leaveRequest.venueId
        accessDeniedUnless (isNothing leaveRequest.deletedAt)
        _ <- reviewLeaveRequest DenyLeave leaveRequest
        if isHtmxRequest
            then respondWithLeaveRequestsContent "Unavailable period denied"
            else do
                setSuccessMessage "Unavailable period denied"
                redirectTo LeaveRequestsAction

respondWithLeaveRequestsContent :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => Text -> IO ()
respondWithLeaveRequestsContent successMessage = do
    readModel <- fetchLeaveRequestsReadModel
    respondHtmlProfiled $
        fromMaybe mempty (renderLeaveRequestsFragmentFromReadModel (LeaveRequestsFragmentOob outerHtmlOobSwap) readModel LeaveRequestsContent)
            <> [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            <> renderToastOob ToastBottomCenter (successToast successMessage)

data LeaveResponseContext
    = LeavePageResponseContext
    | LeaveProfileResponseContext
    | LeaveRosterResponseContext
    | LeaveStaffResponseContext
    deriving (Eq, Show)

parseLeaveResponseContext :: Text -> LeaveResponseContext
parseLeaveResponseContext responseContext
    | responseContext == "profile" = LeaveProfileResponseContext
    | responseContext == "roster" = LeaveRosterResponseContext
    | responseContext == "staff" = LeaveStaffResponseContext
    | otherwise = LeavePageResponseContext

effectiveLeaveResponseContext :: (?context :: ControllerContext) => LeaveResponseContext -> LeaveResponseContext
effectiveLeaveResponseContext requestedContext
    | requestedContext == LeaveRosterResponseContext = LeaveRosterResponseContext
    | requestedContext == LeaveStaffResponseContext = LeaveStaffResponseContext
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
leaveFallbackPath LeaveStaffResponseContext = pathTo RosterWeeksAction

respondWithLeaveRequestValidationFailure :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => LeaveResponseContext -> LeaveRequest -> IO ()
respondWithLeaveRequestValidationFailure responseContext leaveRequest =
    case responseContext of
        LeavePageResponseContext ->
            respondHtml (renderNewLeaveRequestDialog leaveRequest)
        LeaveProfileResponseContext ->
            respondHtml (renderProfileLeaveRequestFormFragment leaveRequest)
        LeaveRosterResponseContext ->
            respondHtml (renderRosterStaffSelfServiceLeaveFormFragment leaveRequest)
        LeaveStaffResponseContext ->
            respondHtml (renderStaffLeaveRequestFormFragment (Id leaveRequest.staffId) leaveRequest)

respondWithLeaveMutationSuccess :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => LeaveResponseContext -> Text -> IO ()
respondWithLeaveMutationSuccess responseContext successMessage =
    case responseContext of
        LeavePageResponseContext ->
            respondWithLeaveRequestsContent successMessage
        LeaveProfileResponseContext -> do
            maybeStaff <- fetchCurrentUserStaff
            case maybeStaff of
                Nothing -> respondWithLeaveContextError LeaveProfileResponseContext "No staff record found. Contact an administrator."
                Just staff ->
                    respondWithProfileLeaveFragments
                        staff
                        [profileLeaveRequestsFragment]
                        (renderToastOob ToastBottomCenter (successToast successMessage))
        LeaveRosterResponseContext ->
            respondWithRosterStaffSelfServiceLeaveFragments
                [RosterStaffSelfServiceLeaveFormFragment]
                (renderToastOob ToastBottomCenter (successToast successMessage))
        LeaveStaffResponseContext -> do
            maybeStaff <- fetchLeaveRequestTargetStaff LeaveStaffResponseContext
            case maybeStaff of
                Nothing -> respondWithLeaveContextError LeaveStaffResponseContext "No staff record found. Contact an administrator."
                Just staff -> do
                    leaveRequest <- buildDefaultLeaveRequest
                    leaveRequests <- fetchStaffLeaveRequests staff
                    respondHtmlProfiled $
                        mconcat
                            [ renderStaffLeaveRequestFormFragment staff.id leaveRequest
                            , renderStaffLeaveRequestsListFragmentOob leaveRequests
                            , renderToastOob ToastBottomCenter (successToast successMessage)
                            ]

ensureLeaveProfileAccess :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveResponseContext -> IO ()
ensureLeaveProfileAccess responseContext =
    case responseContext of
        LeavePageResponseContext    -> ensureProfileCompleted
        LeaveProfileResponseContext -> pure ()
        LeaveRosterResponseContext  -> ensureProfileCompleted
        LeaveStaffResponseContext   -> ensureManagerRole

fetchLeaveRequestTargetStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LeaveResponseContext -> IO (Maybe Staff)
fetchLeaveRequestTargetStaff LeaveStaffResponseContext = do
    case paramOrNothing @(Id Staff) "staffId" of
        Nothing -> pure Nothing
        Just staffId -> do
            staff <- fetch staffId
            ensureRecordInCurrentVenue staff.venueId
            pure (Just staff)
fetchLeaveRequestTargetStaff _ = fetchCurrentUserStaff

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
            leaveRequest <- buildDefaultRosterStaffSelfServiceLeaveRequest
            respondHtmlProfiled $
                mconcat
                    [ renderRosterStaffSelfServiceLeaveFormFragment leaveRequest
                    , renderToastOob ToastBottomCenter (errorToast errorMessage)
                    ]
        LeaveStaffResponseContext -> do
            leaveRequest <- buildDefaultLeaveRequest
            let formHtml = maybe mempty (`renderStaffLeaveRequestFormFragment` leaveRequest) (paramOrNothing @(Id Staff) "staffId")
            respondHtmlProfiled $
                mconcat
                    [ formHtml
                    , renderToastOob ToastBottomCenter (errorToast errorMessage)
                    ]

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
