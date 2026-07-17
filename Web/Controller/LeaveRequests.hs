module Web.Controller.LeaveRequests where

import qualified Application.Helper.FrontendContract.Surface.Profile as ProfileSurface
import qualified Application.Helper.FrontendContract.Surface.Profile.Action as ProfileAction
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError,
                                                            attachSurfaceRequestFieldErrors,
                                                            parseSurfaceActionParams,
                                                            surfaceRequestFieldErrorsMessage)
import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh)
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
                                          leaveRequestsSurfaceScope)
import Web.LeaveRequests.Mutations
import Web.LeaveRequests.ProfileSelfService
import Web.LeaveRequests.ReadModel
import Web.Profiles.FrontendSurface (ProfileScopeValue (..),
                                     profileCandidateMountedFragments,
                                     profileSurfaceScope,
                                     staffCandidateMountedFragments,
                                     staffSurfaceScope)
import Web.RosterWeeks.Responses (respondWithRosterResourceInvalidation)
import Web.RosterWeeks.StaffSelfServiceLeaveFragments (buildDefaultRosterStaffSelfServiceLeaveRequest)
import Web.RosterWeeks.Types (RosterProjectionFragment (..))
import Web.View.LeaveRequests.Index
import Web.View.LeaveRequests.New
import Web.View.RosterWeeks.StaffSelfServicePanel (renderRosterStaffSelfServiceLeaveFormFragment,
                                                   renderRosterStaffSelfServiceLeaveFormFragmentForRoster,
                                                   renderRosterStaffSelfServiceLeaveFormFragmentWithSwap)
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
            reportLeaveArchivePageErrors
            readModel <- profileActionSpan "leave.page.fetch_read_model" fetchLeaveRequestsReadModel
            profileActionSpan "leave.page.render_response" (renderProfiled (leaveRequestsIndexView readModel))

    action currentAction@ShowleaveRequestsContentLiveFragmentAction = runBepis currentAction BepisFragmentAction $
        profileActionSpan "leave.fragment.respond" do
            ensureProfileCompleted
            ensureManagerRole
            reportLeaveArchivePageErrors
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
                let baseLeaveRequest =
                        newRecord @LeaveRequest
                            |> set #venueId (unpackId currentVenueId)
                            |> set #staffId (coerce (get #id staff))
                            |> set #status (leaveRequestStatusToEnum LeavePending)
                let leaveRequest =
                        case parseSurfaceLeaveRequest responseContext of
                            Nothing -> buildLeaveRequest baseLeaveRequest
                            Just (Left errors) -> attachSurfaceRequestFieldErrors errors baseLeaveRequest
                            Just (Right submitted) -> buildLeaveRequestFromSurface submitted baseLeaveRequest

                leaveRequest
                    |> ifValid \case
                        Left invalidLeaveRequest ->
                            if isHtmxRequest
                                then respondWithLeaveRequestValidationFailure responseContext invalidLeaveRequest
                                else render NewView { leaveRequest = invalidLeaveRequest }
                        Right validLeaveRequest -> do
                            mutationResult <- submitLeaveRequest validLeaveRequest
                            if isHtmxRequest
                                then respondWithLeaveMutationSuccess responseContext mutationResult.liveMutationTouchedResources "Unavailable period submitted"
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

reportLeaveArchivePageErrors :: (?context :: ControllerContext, ?request :: Request) => IO ()
reportLeaveArchivePageErrors =
    case currentLeaveArchivePageResult of
        Left errors -> setErrorMessage (surfaceRequestFieldErrorsMessage errors)
        Right _     -> pure ()

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

respondWithLeaveRequestsContent :: (?context :: ControllerContext, ?request :: Request) => Set.Set SurfaceResourceValue -> Text -> IO ()
respondWithLeaveRequestsContent touchedResources successMessage = do
    let scope = LeaveRequestsScopeValue (unpackId currentVenueId)
    setHeader ("HX-Reswap", "none")
    setActorLiveResourcesRefresh (leaveRequestsSurfaceScope scope) touchedResources (leaveRequestsCandidateMountedFragments scope)
    respondHtmlProfiled $
        [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            <> renderToastOob ToastBottomCenter (successToast successMessage)

respondWithLeaveRequestsContentForReview :: (?context :: ControllerContext, ?request :: Request) => Set.Set SurfaceResourceValue -> Text -> IO ()
respondWithLeaveRequestsContentForReview = respondWithLeaveRequestsContent

respondWithProfileLeaveActorInvalidation :: (?context :: ControllerContext, ?request :: Request) => Staff -> Set.Set SurfaceResourceValue -> Text -> IO ()
respondWithProfileLeaveActorInvalidation staff touchedResources successMessage = do
    let scope = ProfileScopeValue (unpackId currentVenueId) (unpackId staff.id)
    setHeader ("HX-Reswap", "none")
    setActorLiveResourcesRefresh (profileSurfaceScope scope) touchedResources (profileCandidateMountedFragments scope)
    respondHtmlProfiled (renderToastOob ToastBottomCenter (successToast successMessage))

respondWithStaffLeaveActorInvalidation :: (?context :: ControllerContext, ?request :: Request) => Staff -> Set.Set SurfaceResourceValue -> Text -> IO ()
respondWithStaffLeaveActorInvalidation staff touchedResources successMessage = do
    let scope = ProfileScopeValue (unpackId currentVenueId) (unpackId staff.id)
    setHeader ("HX-Reswap", "none")
    setActorLiveResourcesRefresh (staffSurfaceScope scope) touchedResources (staffCandidateMountedFragments scope)
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

data SurfaceLeaveRequest = SurfaceLeaveRequest
    { surfaceLeaveStartDate :: !Day
    , surfaceLeaveEndDate   :: !Day
    , surfaceLeaveNotes     :: !Text
    }

parseSurfaceLeaveRequest ::
    (?request :: Request) =>
    LeaveResponseContext ->
    Maybe (Either [SurfaceRequestFieldError] SurfaceLeaveRequest)
parseSurfaceLeaveRequest LeavePageResponseContext = Nothing
parseSurfaceLeaveRequest LeaveProfileResponseContext =
    Just $
        toProfileLeaveRequest
            <$> ProfileAction.parseCreateProfileLeaveRequestActionParams
  where
    toProfileLeaveRequest fields =
        SurfaceLeaveRequest
            { surfaceLeaveStartDate = surfaceFieldValue @ProfileSurface.StartDate fields
            , surfaceLeaveEndDate = surfaceFieldValue @ProfileSurface.EndDate fields
            , surfaceLeaveNotes = surfaceFieldValue @ProfileSurface.Notes fields
            }
parseSurfaceLeaveRequest LeaveStaffResponseContext =
    Just $
        toStaffLeaveRequest
            <$> ProfileAction.parseCreateStaffLeaveRequestActionParams
  where
    toStaffLeaveRequest fields =
        SurfaceLeaveRequest
            { surfaceLeaveStartDate = surfaceFieldValue @ProfileSurface.StartDate fields
            , surfaceLeaveEndDate = surfaceFieldValue @ProfileSurface.EndDate fields
            , surfaceLeaveNotes = surfaceFieldValue @ProfileSurface.Notes fields
            }
parseSurfaceLeaveRequest LeaveRosterResponseContext =
    Just $
        toRosterLeaveRequest
            <$> parseSurfaceActionParams @RosterSurface.RosterSurface @RosterSurface.CreateRosterSelfServiceLeaveRequest
  where
    toRosterLeaveRequest fields =
        SurfaceLeaveRequest
            { surfaceLeaveStartDate = surfaceFieldValue @RosterSurface.StartDate fields
            , surfaceLeaveEndDate = surfaceFieldValue @RosterSurface.EndDate fields
            , surfaceLeaveNotes = surfaceFieldValue @RosterSurface.Notes fields
            }

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

respondWithLeaveMutationSuccess :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => LeaveResponseContext -> Set.Set SurfaceResourceValue -> Text -> IO ()
respondWithLeaveMutationSuccess responseContext touchedResources successMessage =
    case responseContext of
        LeavePageResponseContext ->
            respondWithLeaveRequestsContent touchedResources successMessage
        LeaveProfileResponseContext -> do
            maybeStaff <- fetchCurrentUserStaff
            case maybeStaff of
                Nothing -> respondWithLeaveContextError LeaveProfileResponseContext "No staff record found. Contact an administrator."
                Just staff ->
                    respondWithProfileLeaveActorInvalidation staff touchedResources successMessage
        LeaveRosterResponseContext -> do
            (rosterGroupId, weekOffset) <- resolveRosterLeaveScope
            leaveRequest <- buildDefaultRosterStaffSelfServiceLeaveRequest
            respondWithRosterResourceInvalidation
                rosterGroupId
                weekOffset
                touchedResources
                [RosterProjectionContent]
                ( renderRosterStaffSelfServiceLeaveFormFragmentWithSwap (Just "outerHTML") (Just (rosterGroupId, weekOffset)) leaveRequest
                    <> renderToastOob ToastBottomCenter (successToast successMessage)
                )
        LeaveStaffResponseContext -> do
            maybeStaff <- fetchLeaveRequestTargetStaff LeaveStaffResponseContext
            case maybeStaff of
                Nothing -> respondWithLeaveContextError LeaveStaffResponseContext "No staff record found. Contact an administrator."
                Just staff ->
                    respondWithStaffLeaveActorInvalidation staff touchedResources successMessage

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
        |> validateLeaveRequest

buildLeaveRequestFromSurface :: SurfaceLeaveRequest -> LeaveRequest -> LeaveRequest
buildLeaveRequestFromSurface submitted leaveRequest =
    leaveRequest
        |> set #startDate submitted.surfaceLeaveStartDate
        |> set #endDate submitted.surfaceLeaveEndDate
        |> set #notes (Just submitted.surfaceLeaveNotes)
        |> validateLeaveRequest

validateLeaveRequest :: LeaveRequest -> LeaveRequest
validateLeaveRequest leaveRequest =
    let normalized =
            leaveRequest
                |> normalizeMaybeTextField #notes
                |> validateField #notes (validateMaybe (boundedText 1000))
     in normalized
            |> validateField #endDate (validateEndDate normalized.startDate)
  where
    validateEndDate startDate endDate =
        if isLeaveDateRangeValid startDate endDate
            then Success
            else Failure "Available again must be at least one day after unavailable from"
