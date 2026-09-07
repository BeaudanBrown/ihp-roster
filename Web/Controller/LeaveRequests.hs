module Web.Controller.LeaveRequests where

import Application.Helper.FrontendContract.ClosedScalar (parseClosedScalarLiteral)
import Application.Helper.FrontendContract.Surface.LeaveRequests (LeaveSectionValue (..))
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as LeaveRequestsSurface
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests.Action as LeaveRequestsAction
import Application.Helper.FrontendContract.Surface.LeaveRequests.Resource (unavailabilityBlackoutsResource)
import Application.Helper.FrontendContract.Surface.Request (attachSurfaceRequestFieldErrors,
                                                            surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest,
                                        fetchStaffLeaveRequests)
import Application.Helper.Profiling
import Application.Helper.SurfaceResource (LiveMutationResult (..),
                                           SurfaceResourceValue,
                                           liveMutationResult)
import Application.Helper.View (ToastOverlayPosition (..), errorToast,
                                renderToastOob)
import qualified Application.UnavailabilityBlackout.Mutations as BlackoutMutations
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Web.Controller.Prelude
import Web.LeaveRequests.Blackouts (currentVenueCalendarDay,
                                    fetchCurrentAndFutureUnavailabilityBlackouts)
import Web.LeaveRequests.Mutations
import Web.LeaveRequests.ReadModel
import Web.LeaveRequests.Request
import Web.LeaveRequests.Responses
import Web.LeaveRequests.SelfService
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)
import Web.View.LeaveRequests.Index
import Web.View.LeaveRequests.New
import Web.View.Staff.Edit (renderStaffVisibleUnavailabilityBlackoutsFragment)

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

    action currentAction@ShowSelfServiceLeaveFragmentAction = runBepis currentAction BepisFragmentAction do
        ensureStaffSelfServiceAccess
        maybeStaff <- fetchCurrentUserStaff
        case maybeStaff of
            Nothing -> respondWithLeaveContextError LeaveSelfServiceResponseContext "No staff record found. Contact an administrator."
            Just staff ->
                if paramOrDefault @Text "form" "fragment" == "history"
                    then do
                        leaveRequests <- fetchStaffLeaveRequests staff
                        respondHtmlProfiled (renderSelfServiceLeaveHistoryFragment Nothing leaveRequests)
                    else do
                        leaveRequest <- buildDefaultLeaveRequest
                        respondHtmlProfiled (renderSelfServiceLeaveFormFragment Nothing leaveRequest)

    action currentAction@ShowVisibleUnavailabilityBlackoutsFragmentAction = runBepis currentAction BepisFragmentAction do
        let requestedSurface = paramOrDefault @Text "self-service" "surface"
        if requestedSurface == "staff"
            then ensureManagerRole
            else ensureStaffSelfServiceAccess
        venueConfig <- fetchVenueConfig
        today <- currentVenueCalendarDay venueConfig
        blackouts <- fetchCurrentAndFutureUnavailabilityBlackouts today
        if requestedSurface == "staff"
            then respondHtmlProfiled (renderStaffVisibleUnavailabilityBlackoutsFragment blackouts)
            else respondHtmlProfiled (renderVisibleUnavailabilityBlackoutsFragment blackouts)

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
        let responseContext = requestedLeaveResponseContext
        case responseContext of
            LeaveStaffResponseContext -> ensureManagerRole
            _                         -> ensureStaffSelfServiceAccess
        ensureVenueWritable
        ensureLeaveProfileAccess responseContext
        submitRequestedLeave responseContext >>= respondWithLeaveSubmissionResult responseContext

    action currentAction@CreateUnavailabilityBlackoutAction = runBepis currentAction BepisMutationAction do
        ensureProfileCompleted
        ensureUnavailabilityBlackoutManager
        ensureVenueWritable
        venueConfig <- fetchVenueConfig
        today <- currentVenueCalendarDay venueConfig
        let baseBlackout =
                newRecord @UnavailabilityBlackout
                    |> set #venueId (unpackId currentVenueId)
                    |> set #startDate today
                    |> set #endDate today
        let blackout =
                case LeaveRequestsAction.parseCreateUnavailabilityBlackoutActionParams of
                    Left errors -> attachSurfaceRequestFieldErrors errors baseBlackout
                    Right fields ->
                        baseBlackout
                            |> set #startDate (surfaceFieldValue @LeaveRequestsSurface.StartDate fields)
                            |> set #endDate (surfaceFieldValue @LeaveRequestsSurface.EndDate fields)
                            |> set #reason (surfaceFieldValue @LeaveRequestsSurface.Reason fields)
                            |> validateUnavailabilityBlackout today
        blackout |> ifValid \case
            Left invalidBlackout ->
                respondWithBlackoutValidationFailure invalidBlackout "Check the blackout period and try again."
            Right validBlackout -> do
                mutation <- withDurableLiveMutationOutcome blackoutPublication $
                    fmap (fmap (\created -> liveMutationResult created [unavailabilityBlackoutsResource created.venueId])) $
                        BlackoutMutations.createUnavailabilityBlackoutInCurrentTransaction validBlackout
                case mutation of
                    Left overlapError ->
                        respondWithBlackoutValidationFailure (attachFailure #startDate overlapError validBlackout) overlapError
                    Right created ->
                        respondWithBlackoutMutation created "Unavailability blackout created"

    action currentAction@UpdateUnavailabilityBlackoutAction { unavailabilityBlackoutId } = runBepis currentAction BepisMutationAction do
        ensureProfileCompleted
        ensureUnavailabilityBlackoutManager
        ensureVenueWritable
        existing <- fetch unavailabilityBlackoutId
        ensureRecordInCurrentVenue existing.venueId
        venueConfig <- fetchVenueConfig
        today <- currentVenueCalendarDay venueConfig
        let earliestAllowedStart = min today existing.startDate
        let blackout =
                case LeaveRequestsAction.parseUpdateUnavailabilityBlackoutActionParams of
                    Left errors -> attachSurfaceRequestFieldErrors errors existing
                    Right fields ->
                        existing
                            |> set #startDate (surfaceFieldValue @LeaveRequestsSurface.StartDate fields)
                            |> set #endDate (surfaceFieldValue @LeaveRequestsSurface.EndDate fields)
                            |> set #reason (surfaceFieldValue @LeaveRequestsSurface.Reason fields)
                            |> validateUnavailabilityBlackout earliestAllowedStart
        blackout |> ifValid \case
            Left invalidBlackout ->
                respondWithBlackoutValidationFailure invalidBlackout "Check the blackout period and try again."
            Right validBlackout -> do
                mutation <- withDurableLiveMutationOutcome blackoutUpdatePublication $
                    fmap (fmap (\updated -> liveMutationResult updated [unavailabilityBlackoutsResource updated.venueId])) $
                        BlackoutMutations.updateUnavailabilityBlackoutInCurrentTransaction validBlackout
                case mutation of
                    Left mutationError ->
                        respondWithBlackoutValidationFailure (attachFailure #startDate mutationError validBlackout) mutationError
                    Right updated ->
                        respondWithBlackoutMutation updated "Unavailability blackout updated"

    action currentAction@DeleteUnavailabilityBlackoutAction { unavailabilityBlackoutId } = runBepis currentAction BepisMutationAction do
        ensureProfileCompleted
        ensureUnavailabilityBlackoutManager
        ensureVenueWritable
        blackout <- fetch unavailabilityBlackoutId
        ensureRecordInCurrentVenue blackout.venueId
        deleted <- withDurableLiveMutationOutcome blackoutDeletePublication do
            wasDeleted <- BlackoutMutations.deleteUnavailabilityBlackoutInCurrentTransaction blackout
            pure $
                if wasDeleted
                    then Just (liveMutationResult blackout [unavailabilityBlackoutsResource blackout.venueId])
                    else Nothing
        case deleted of
            Just result -> respondWithBlackoutMutation result "Unavailability blackout removed"
            Nothing -> do
                setErrorMessage "This blackout period no longer exists."
                redirectTo LeaveRequestsAction

    action currentAction@ApproveLeaveRequestAction { leaveRequestId } = runBepis currentAction BepisMutationAction do
        ensureProfileCompleted
        ensureManagerRole
        ensureVenueWritable
        leaveRequest <- fetch leaveRequestId
        ensureRecordInCurrentVenue leaveRequest.venueId
        accessDeniedUnless (isNothing leaveRequest.deletedAt)
        reviewLeaveRequest ApproveLeave leaveRequest >>= respondWithLeaveReviewResult ApproveLeave

    action currentAction@DenyLeaveRequestAction { leaveRequestId } = runBepis currentAction BepisMutationAction do
        ensureProfileCompleted
        ensureManagerRole
        ensureVenueWritable
        leaveRequest <- fetch leaveRequestId
        ensureRecordInCurrentVenue leaveRequest.venueId
        accessDeniedUnless (isNothing leaveRequest.deletedAt)
        reviewLeaveRequest DenyLeave leaveRequest >>= respondWithLeaveReviewResult DenyLeave

reportLeaveArchivePageErrors :: (?context :: ControllerContext, ?request :: Request) => IO ()
reportLeaveArchivePageErrors =
    case currentLeaveArchivePageResult of
        Left errors -> setErrorMessage (surfaceRequestFieldErrorsMessage errors)
        Right _     -> pure ()

requestedLeaveRequestsFragment :: (?request :: Request) => LeaveRequestsFragment
requestedLeaveRequestsFragment =
    case paramOrDefault @Text "leave-requests-content" "fragment" of
        "unavailability-blackouts" -> UnavailabilityBlackouts
        "leave-side-panel-content"  -> LeaveSidePanelContent
        "leave-availability-warnings" -> LeaveAvailabilityWarnings
        "leave-section-count"         -> LeaveRequestsSectionCount requestedLeaveSection
        "leave-section-list"          -> LeaveRequestsSectionList requestedLeaveSection
        _                     -> LeaveRequestsContent

requestedLeaveSection :: (?request :: Request) => LeaveSectionValue
requestedLeaveSection =
    fromMaybe LeavePendingSection (parseClosedScalarLiteral (paramOrDefault @Text "pending" "section"))

ensureUnavailabilityBlackoutManager :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
ensureUnavailabilityBlackoutManager = ensureAdminRole

respondWithBlackoutValidationFailure :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => UnavailabilityBlackout -> Text -> IO ()
respondWithBlackoutValidationFailure submittedBlackout errorMessage =
    if isHtmxRequest
        then do
            readModel <- fetchLeaveRequestsReadModel
            respondHtmlProfiled $
                renderUnavailabilityBlackoutsValidationFragment
                    readModel.leaveReadModelVenueToday
                    readModel.leaveReadModelBlackouts
                    readModel.leaveReadModelRequests
                    readModel.leaveReadModelStaffMembers
                    (Just submittedBlackout)
                    <> renderToastOob ToastBottomCenter (errorToast errorMessage)
        else do
            setErrorMessage errorMessage
            redirectTo LeaveRequestsAction

respondWithBlackoutMutation :: (?context :: ControllerContext, ?request :: Request) => LiveMutationResult UnavailabilityBlackout -> Text -> IO ()
respondWithBlackoutMutation mutationResult successMessage = do
    if isHtmxRequest
        then respondWithLeaveRequestsContent mutationResult.liveMutationTouchedResources successMessage
        else do
            setSuccessMessage successMessage
            redirectTo LeaveRequestsAction

blackoutPublication :: Either Text (LiveMutationResult UnavailabilityBlackout) -> Maybe (Text, Set.Set SurfaceResourceValue)
blackoutPublication = either (const Nothing) (\result -> Just ("blackout.create", result.liveMutationTouchedResources))

blackoutUpdatePublication :: Either Text (LiveMutationResult UnavailabilityBlackout) -> Maybe (Text, Set.Set SurfaceResourceValue)
blackoutUpdatePublication = either (const Nothing) (\result -> Just ("blackout.update", result.liveMutationTouchedResources))

blackoutDeletePublication :: Maybe (LiveMutationResult UnavailabilityBlackout) -> Maybe (Text, Set.Set SurfaceResourceValue)
blackoutDeletePublication = fmap (\result -> ("blackout.delete", result.liveMutationTouchedResources))

validateUnavailabilityBlackout :: Day -> UnavailabilityBlackout -> UnavailabilityBlackout
validateUnavailabilityBlackout today blackout =
    let normalized =
            blackout
                |> normalizeTextField #reason
                |> validateField #reason (\reason -> if Text.length reason < 3 then Failure "Reason must be at least 3 characters" else Success)
                |> validateField #reason (boundedText 160)
        withStartValidation =
            normalized
                |> validateField #startDate (\startDate -> if startDate < today then Failure "First blocked date cannot be before today" else Success)
     in withStartValidation
            |> validateField #endDate (validateBlackoutEndDate withStartValidation.startDate)
  where
    validateBlackoutEndDate startDate endDate
        | endDate < startDate = Failure "Last blocked date cannot be before first blocked date"
        | diffDays endDate startDate > 365 = Failure "Blackout periods cannot exceed 366 days"
        | otherwise = Success
