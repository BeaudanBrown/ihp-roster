module Web.LeaveRequests.Responses
    ( respondWithLeaveSubmissionResult
    , respondWithLeaveReviewResult
    , respondWithLeaveContextError
    , respondWithLeaveRequestsContent
    ) where

import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave.Live as SelfServiceLeaveLive
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh,
                                      setActorLiveResourcesRefreshIncluding)
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest)
import Application.Helper.Profiling
import Application.Helper.SurfaceResource (LiveMutationResult (..),
                                           SurfaceResourceValue)
import Application.Helper.View (ToastOverlayPosition (..), errorToast,
                                renderDialogOverlayClearOob, renderToastOob,
                                successToast)
import qualified Data.Set as Set
import Web.Controller.Prelude
import Web.LeaveRequests.FrontendSurface
import Web.LeaveRequests.Request
import Web.LeaveRequests.SelfService
import Web.Profiles.FrontendSurface (ProfileScopeValue (..),
                                     staffCandidateMountedFragments,
                                     staffSurfaceScope)
import Web.View.LeaveRequests.New
import Web.View.Staff.Edit (renderStaffLeaveRequestFormFragment)

respondWithLeaveSubmissionResult :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => LeaveResponseContext -> RequestedLeaveSubmission -> IO ()
respondWithLeaveSubmissionResult responseContext = \case
    LeaveSubmissionMissingStaff -> respondWithLeaveContextError responseContext "No staff record found. Contact an administrator."
    LeaveSubmissionInvalid invalid -> renderInvalid invalid
    LeaveSubmissionFinished valid outcome -> case outcome of
        LeaveSubmissionStaffInactive -> do
            setErrorMessage "This staff member is no longer active."
            redirectToPath (leaveFallbackPath responseContext)
        LeaveSubmissionBlocked blackout ->
            renderInvalid (attachFailure #startDate ("Unavailable submissions are blocked for these dates: " <> blackout.reason) valid)
        LeaveSubmissionCreated result ->
            if isHtmxRequest
                then respondWithLeaveMutationSuccess responseContext result.liveMutationTouchedResources "Unavailable period submitted"
                else do
                    setSuccessMessage "Unavailable period submitted"
                    redirectToPath (leaveFallbackPath responseContext)
  where
    renderInvalid leaveRequest =
        if isHtmxRequest
            then respondWithLeaveRequestValidationFailure responseContext leaveRequest
            else render NewView { .. }

respondWithLeaveReviewResult :: (?context :: ControllerContext, ?request :: Request) => LeaveReviewDecision -> Maybe (LiveMutationResult ReviewedLeaveRequest) -> IO ()
respondWithLeaveReviewResult decision = \case
    Nothing -> do
        setErrorMessage "This staff member is no longer active."
        redirectTo LeaveRequestsAction
    Just result ->
        if isHtmxRequest
            then respondWithLeaveRequestsContent result.liveMutationTouchedResources successMessage
            else do
                setSuccessMessage successMessage
                redirectTo LeaveRequestsAction
  where
    successMessage = case decision of
        ApproveLeave -> "Unavailable period approved"
        DenyLeave    -> "Unavailable period denied"

respondWithLeaveRequestsContent :: (?context :: ControllerContext, ?request :: Request) => Set.Set SurfaceResourceValue -> Text -> IO ()
respondWithLeaveRequestsContent touchedResources successMessage = do
    let scope = LeaveRequestsScopeValue (unpackId currentVenueId)
    setHeader ("HX-Reswap", "none")
    setActorLiveResourcesRefresh (leaveRequestsSurfaceScope scope) touchedResources (leaveRequestsCandidateMountedFragments scope)
    respondHtmlProfiled $
        renderDialogOverlayClearOob
            <> renderToastOob ToastBottomCenter (successToast successMessage)

respondWithStaffLeaveActorInvalidation :: (?context :: ControllerContext, ?request :: Request) => Staff -> Set.Set SurfaceResourceValue -> Text -> IO ()
respondWithStaffLeaveActorInvalidation staff touchedResources successMessage = do
    let scope = ProfileScopeValue (unpackId currentVenueId) (unpackId staff.id)
    setHeader ("HX-Reswap", "none")
    setActorLiveResourcesRefresh (staffSurfaceScope scope) touchedResources (staffCandidateMountedFragments scope)
    respondHtmlProfiled (renderToastOob ToastBottomCenter (successToast successMessage))

leaveFallbackPath :: LeaveResponseContext -> Text
leaveFallbackPath LeavePageResponseContext = pathTo EditProfileAction
leaveFallbackPath LeaveSelfServiceResponseContext = pathTo EditProfileAction <> "?section=leave"
leaveFallbackPath LeaveStaffResponseContext = pathTo RosterWeeksAction

respondWithLeaveRequestValidationFailure :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => LeaveResponseContext -> LeaveRequest -> IO ()
respondWithLeaveRequestValidationFailure responseContext leaveRequest = case responseContext of
    LeavePageResponseContext -> respondHtml (renderNewLeaveRequestDialog leaveRequest)
    LeaveSelfServiceResponseContext -> respondHtml (renderSelfServiceLeaveFormFragment Nothing leaveRequest)
    LeaveStaffResponseContext -> respondHtml (renderStaffLeaveRequestFormFragment (Id leaveRequest.staffId) leaveRequest)

respondWithLeaveMutationSuccess :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => LeaveResponseContext -> Set.Set SurfaceResourceValue -> Text -> IO ()
respondWithLeaveMutationSuccess responseContext touchedResources successMessage = case responseContext of
    LeavePageResponseContext -> respondWithLeaveRequestsContent touchedResources successMessage
    LeaveSelfServiceResponseContext -> do
        maybeStaff <- fetchCurrentUserStaff
        case maybeStaff of
            Nothing -> respondWithLeaveContextError LeaveSelfServiceResponseContext "No staff record found. Contact an administrator."
            Just staff -> do
                let scope = SelfServiceLeaveScopeValue (unpackId currentVenueId) (unpackId staff.id)
                setHeader ("HX-Reswap", "none")
                setActorLiveResourcesRefreshIncluding
                    [SelfServiceLeaveLive.selfServiceLeaveFormLiveFragment]
                    (selfServiceLeaveSurfaceScope scope)
                    touchedResources
                    [selfServiceLeaveFormMountedFragment, selfServiceLeaveHistoryMountedFragment]
                respondHtmlProfiled (renderToastOob ToastBottomCenter (successToast successMessage))
    LeaveStaffResponseContext -> do
        maybeStaff <- fetchLeaveRequestTargetStaff LeaveStaffResponseContext
        case maybeStaff of
            Nothing -> respondWithLeaveContextError LeaveStaffResponseContext "No staff record found. Contact an administrator."
            Just staff -> respondWithStaffLeaveActorInvalidation staff touchedResources successMessage

respondWithLeaveContextError :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => LeaveResponseContext -> Text -> IO ()
respondWithLeaveContextError responseContext errorMessage = case responseContext of
    LeavePageResponseContext -> do
        setErrorMessage errorMessage
        redirectToPath (leaveFallbackPath responseContext)
    LeaveSelfServiceResponseContext -> do
        leaveRequest <- buildDefaultLeaveRequest
        respondHtmlProfiled $
            renderSelfServiceLeaveFormFragment Nothing leaveRequest
                <> renderToastOob ToastBottomCenter (errorToast errorMessage)
    LeaveStaffResponseContext -> do
        leaveRequest <- buildDefaultLeaveRequest
        let formHtml = maybe mempty (`renderStaffLeaveRequestFormFragment` leaveRequest) (paramOrNothing @(Id Staff) "staffId")
        respondHtmlProfiled (mconcat [formHtml, renderToastOob ToastBottomCenter (errorToast errorMessage)])
