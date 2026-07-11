module Web.Controller.LeaveRequests where

import Application.Helper.LiveUpdate (setActorLiveFragmentsRefresh,
                                      setActorLiveResourcesRefresh)
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchStaffLeaveRequests)
import Application.Helper.Profiling
import Application.Helper.RosterGroups (fetchCurrentVenueRosterGroupOrDefault)
import Application.Helper.SurfaceResource (LiveMutationResult (..),
                                           SurfaceResourceValue)
import Application.Helper.View (ToastOverlayPosition (..), dialogOverlayMountId,
                                errorToast, renderToastOob, successToast)
import Data.Coerce (coerce)
import qualified Data.Set as Set
import qualified Data.Text.IO as TextIO
import Web.Controller.Prelude
import Web.LeaveRequests.FrontendSurface (LeaveRequestsScopeValue (..),
                                          leaveRequestsCandidateMountedFragments,
                                          leaveRequestsSurfaceScope,
                                          leaveRequestsSurfaceWireFragments)
import Web.LeaveRequests.Mutations
import Web.LeaveRequests.ProfileSelfService
import Web.LeaveRequests.ReadModel
import Web.Profiles.FrontendSurface (ProfileScopeValue (..),
                                     profileSectionFragmentForSection,
                                     profileSurfaceScope,
                                     profileSurfaceWireFragments,
                                     staffSectionFragmentForSection,
                                     staffSurfaceScope,
                                     staffSurfaceWireFragments)
import Web.RosterWeeks.Responses (respondWithRosterFragments)
import Web.RosterWeeks.StaffSelfServiceLeaveFragments (buildDefaultRosterStaffSelfServiceLeaveRequest)
import Web.RosterWeeks.Types (RosterProjectionFragment (..))
import Web.View.LeaveRequests.Index
import Web.View.LeaveRequests.New
import Web.View.RosterWeeks.StaffSelfServicePanel (renderRosterStaffSelfServiceLeaveFormFragment,
                                                   renderRosterStaffSelfServiceLeaveFormFragmentForRoster)
import Web.View.Staff.Edit (renderStaffLeaveRequestFormFragment)

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

    action currentAction@ShowleaveRequestsContentLiveFragmentAction = runBepis currentAction BepisFragmentAction $
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
                    let requestedFragment = requestedLeaveRequestsFragment
                    maybeHtml <- profileActionSpan "leave.fragment.render" (renderLeaveRequestsFragment requestedFragment)
                    when (isNothing maybeHtml) do
                        TextIO.putStrLn ("leave_fragment_miss: fragment=" <> tshow requestedFragment)
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
        result <- reviewLeaveRequest ApproveLeave leaveRequest
        if isHtmxRequest
            then respondWithLeaveRequestsContentForReview result.liveMutationTouchedResources "Unavailable period approved"
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
        result <- reviewLeaveRequest DenyLeave leaveRequest
        if isHtmxRequest
            then respondWithLeaveRequestsContentForReview result.liveMutationTouchedResources "Unavailable period denied"
            else do
                setSuccessMessage "Unavailable period denied"
                redirectTo LeaveRequestsAction

requestedLeaveRequestsFragment :: (?request :: Request) => LeaveRequestsFragment
requestedLeaveRequestsFragment =
    case paramOrDefault @Text "leave-requests-content" "fragment" of
        "leave-section-count" -> LeaveRequestsSectionCount requestedLeaveSection
        "leave-section-list"  -> LeaveRequestsSectionList requestedLeaveSection
        _                     -> LeaveRequestsContent

requestedLeaveSection :: (?request :: Request) => Text
requestedLeaveSection =
    case paramOrDefault @Text leavePendingSection "section" of
        section | section `elem` [leavePendingSection, leaveApprovedSection, leaveDeniedSection, leaveArchiveSection] -> section
        _ -> leavePendingSection

respondWithLeaveRequestsContent :: (?context :: ControllerContext, ?request :: Request) => Text -> IO ()
respondWithLeaveRequestsContent successMessage = do
    let scope = LeaveRequestsScopeValue (unpackId currentVenueId)
    setHeader ("HX-Reswap", "none")
    setActorLiveFragmentsRefresh (leaveRequestsSurfaceScope scope) (leaveRequestsSurfaceWireFragments (leaveRequestsCandidateMountedFragments scope))
    respondHtmlProfiled $
        [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            <> renderToastOob ToastBottomCenter (successToast successMessage)

respondWithLeaveRequestsContentForReview :: (?context :: ControllerContext, ?request :: Request) => Set.Set SurfaceResourceValue -> Text -> IO ()
respondWithLeaveRequestsContentForReview touchedResources successMessage = do
    let scope = LeaveRequestsScopeValue (unpackId currentVenueId)
    setHeader ("HX-Reswap", "none")
    setActorLiveResourcesRefresh (leaveRequestsSurfaceScope scope) touchedResources (leaveRequestsCandidateMountedFragments scope)
    respondHtmlProfiled $
        [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            <> renderToastOob ToastBottomCenter (successToast successMessage)

respondWithProfileLeaveActorInvalidation :: (?context :: ControllerContext, ?request :: Request) => Staff -> Text -> IO ()
respondWithProfileLeaveActorInvalidation staff successMessage = do
    let scope = ProfileScopeValue (unpackId currentVenueId) (unpackId staff.id)
    setHeader ("HX-Reswap", "none")
    setActorLiveFragmentsRefresh (profileSurfaceScope scope) (profileSurfaceWireFragments [profileSectionFragmentForSection "leave"])
    respondHtmlProfiled (renderToastOob ToastBottomCenter (successToast successMessage))

respondWithStaffLeaveActorInvalidation :: (?context :: ControllerContext, ?request :: Request) => Staff -> Text -> IO ()
respondWithStaffLeaveActorInvalidation staff successMessage = do
    let scope = ProfileScopeValue (unpackId currentVenueId) (unpackId staff.id)
    setHeader ("HX-Reswap", "none")
    setActorLiveFragmentsRefresh (staffSurfaceScope scope) (staffSurfaceWireFragments [staffSectionFragmentForSection scope "leave"])
    respondHtmlProfiled (renderToastOob ToastBottomCenter (successToast successMessage))

resolveRosterLeaveScope :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (Id RosterGroup, Int)
resolveRosterLeaveScope = do
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing @(Id RosterGroup) "rosterGroupId")
    let weekOffset = paramOrDefault @Int 0 "weekOffset"
    pure (currentRosterGroup.id, weekOffset)

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
        LeaveRosterResponseContext -> do
            (rosterGroupId, weekOffset) <- resolveRosterLeaveScope
            respondHtml (renderRosterStaffSelfServiceLeaveFormFragmentForRoster rosterGroupId weekOffset leaveRequest)
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
                    respondWithProfileLeaveActorInvalidation staff successMessage
        LeaveRosterResponseContext -> do
            (rosterGroupId, weekOffset) <- resolveRosterLeaveScope
            respondWithRosterFragments
                rosterGroupId
                weekOffset
                [RosterProjectionContent, RosterProjectionStaffSelfServiceLeaveForm]
                (renderToastOob ToastBottomCenter (successToast successMessage))
        LeaveStaffResponseContext -> do
            maybeStaff <- fetchLeaveRequestTargetStaff LeaveStaffResponseContext
            case maybeStaff of
                Nothing -> respondWithLeaveContextError LeaveStaffResponseContext "No staff record found. Contact an administrator."
                Just staff ->
                    respondWithStaffLeaveActorInvalidation staff successMessage

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
            (rosterGroupId, weekOffset) <- resolveRosterLeaveScope
            respondHtmlProfiled $
                mconcat
                    [ renderRosterStaffSelfServiceLeaveFormFragmentForRoster rosterGroupId weekOffset leaveRequest
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
