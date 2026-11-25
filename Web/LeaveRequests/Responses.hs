module Web.LeaveRequests.Responses
    ( respondWithLeaveSubmissionResult
    , respondWithSelfServiceLeaveDeletionResult
    , leaveDeletionUnavailableMessage
    , respondWithManagerLeaveDeletionResult
    , respondWithStaffLeaveDeletionResult
    , respondWithLeaveReviewResult
    , respondWithLeaveContextError
    , respondWithLeaveRequestsContent
    ) where

import qualified Application.Helper.FrontendContract.Surface.Profile.Live as ProfileLive
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave.Live as SelfServiceLeaveLive
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh,
                                      setActorLiveResourcesRefreshIncluding)
import Application.Helper.ProfileLeave (buildDefaultLeaveRequest)
import Application.Helper.Profiling
import Application.Helper.SurfaceResource (LiveMutationResult (..),
                                           SurfaceResourceValue)
import Application.Helper.View (ToastOverlayPosition (..), errorToast,
                                renderDialogOverlayClearOob, renderToastOob, dialogOverlayMountId,
                                renderDialogOverlayBodyOnly,
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
import Web.View.LeaveRequests.Policy
import Web.View.Staff.Edit (renderStaffLeaveRequestFormFragment, staffLeaveRequestFormFragmentId)

respondWithLeaveSubmissionResult :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => LeaveResponseContext -> RequestedLeaveSubmission -> IO ResponseReceived
respondWithLeaveSubmissionResult responseContext = \case
    LeaveSubmissionMissingStaff -> respondWithLeaveContextError responseContext "No staff record found. Contact an administrator."
    LeaveSubmissionInvalid invalid -> renderInvalid invalid
    LeaveSubmissionEditDraft draft -> renderInvalid draft
    LeaveSubmissionFinished staff valid outcome -> case outcome of
        LeaveSubmissionStaffInactive -> do
            setErrorMessage "This staff member is no longer active."
            redirectToPath (leaveFallbackPath responseContext)
        LeaveSubmissionInvalidConfirmation -> renderInvalid (attachFailure #startDate invalidConfirmationMessage valid)
        LeaveSubmissionBlocked conflicts Nothing -> renderInvalid (attachFailure #startDate (policyRejection valid conflicts) valid)
        LeaveSubmissionBlocked conflicts (Just token) -> respondWithPolicyConfirmation (SubmitDraft responseContext) staff valid conflicts token
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
            else case responseContext of
                LeaveStaffResponseContext -> render (LeavePolicyPage (renderStaffLeaveRequestFormFragment (Id leaveRequest.staffId) leaveRequest))
                LeaveSelfServiceResponseContext -> render (LeavePolicyPage (renderSelfServiceLeaveFormFragment Nothing leaveRequest))
                LeavePageResponseContext -> render NewView { .. }

invalidConfirmationMessage :: Text
invalidConfirmationMessage = "This confirmation is no longer valid. Review the request again."

respondWithPolicyConfirmation :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => PolicyOperation -> Staff -> LeaveRequest -> LeavePolicyConflicts -> Text -> IO ResponseReceived
respondWithPolicyConfirmation operation staff draft conflicts token = do
    let body = renderPolicyConfirmation operation staff draft conflicts token
    if isHtmxRequest
        then do
            setHeader ("HX-Retarget", cs ("#" <> dialogOverlayMountId))
            setHeader ("HX-Reswap", "innerHTML")
            respondHtml (renderDialogOverlayBodyOnly "Confirm unavailability exception" "" body)
        else render (LeavePolicyPage body)

respondWithSelfServiceLeaveDeletionResult :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Staff -> Maybe (LiveMutationResult LeaveRequest) -> IO ResponseReceived
respondWithSelfServiceLeaveDeletionResult staff deletionResult =
    case deletionResult of
        Just result ->
            if isHtmxRequest
                then do
                    let scope = SelfServiceLeaveScopeValue (unpackId currentVenueId) (unpackId staff.id)
                    setHeader ("HX-Reswap", "none")
                    setActorLiveResourcesRefreshIncluding
                        [SelfServiceLeaveLive.selfServiceLeaveFormLiveFragment]
                        (selfServiceLeaveSurfaceScope scope)
                        result.liveMutationTouchedResources
                        [selfServiceLeaveFormMountedFragment, selfServiceLeaveHistoryMountedFragment]
                    respondHtmlProfiled $
                        renderDialogOverlayClearOob
                            <> renderToastOob ToastBottomCenter (successToast "Unavailable period deleted")
                else do
                    setSuccessMessage "Unavailable period deleted"
                    redirectToPath (leaveFallbackPath LeaveSelfServiceResponseContext)
        Nothing ->
            if isHtmxRequest
                then do
                    let scope = SelfServiceLeaveScopeValue (unpackId currentVenueId) (unpackId staff.id)
                    setHeader ("HX-Reswap", "none")
                    setActorLiveResourcesRefreshIncluding
                        [SelfServiceLeaveLive.selfServiceLeaveHistoryLiveFragment]
                        (selfServiceLeaveSurfaceScope scope)
                        Set.empty
                        [selfServiceLeaveHistoryMountedFragment]
                    respondHtmlProfiled $
                        renderDialogOverlayClearOob
                            <> renderToastOob ToastBottomCenter (errorToast leaveDeletionUnavailableMessage)
                else do
                    setErrorMessage leaveDeletionUnavailableMessage
                    redirectToPath (leaveFallbackPath LeaveSelfServiceResponseContext)

leaveDeletionUnavailableMessage :: Text
leaveDeletionUnavailableMessage = "This unavailable period is no longer available to delete. Only current and upcoming periods can be deleted."

respondWithManagerLeaveDeletionResult :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Maybe (LiveMutationResult LeaveRequest) -> IO ResponseReceived
respondWithManagerLeaveDeletionResult deletionResult
    | isHtmxRequest = case deletionResult of
        Just result -> respondWithLeaveRequestsContent result.liveMutationTouchedResources "Unavailable period deleted"
        Nothing -> respondWithLeaveDeletionToast deletionResult
    | otherwise = respondWithNativeLeaveDeletion (pathTo LeaveRequestsAction) deletionResult

respondWithStaffLeaveDeletionResult :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Maybe (Id Staff) -> Maybe (LiveMutationResult LeaveRequest) -> IO ResponseReceived
respondWithStaffLeaveDeletionResult staffId deletionResult
    | isHtmxRequest = do
        forM_ staffId \targetStaffId -> do
            let scope = ProfileScopeValue (unpackId currentVenueId) (unpackId targetStaffId)
                touchedResources = maybe Set.empty (.liveMutationTouchedResources) deletionResult
            setActorLiveResourcesRefreshIncluding
                [ProfileLive.staffLeaveSectionLiveFragment]
                (staffSurfaceScope scope)
                touchedResources
                (staffCandidateMountedFragments scope)
        respondWithLeaveDeletionToast deletionResult
    | otherwise = respondWithNativeLeaveDeletion (maybe (pathTo LeaveRequestsAction) (pathTo . EditStaffAction) staffId) deletionResult

respondWithLeaveDeletionToast :: (?context :: ControllerContext, ?respond :: Respond, ?request :: Request) => Maybe (LiveMutationResult LeaveRequest) -> IO ResponseReceived
respondWithLeaveDeletionToast deletionResult = do
    setHeader ("HX-Reswap", "none")
    let toast = case deletionResult of
            Just _ -> successToast "Unavailable period deleted"
            Nothing -> errorToast leaveDeletionUnavailableMessage
    respondHtmlProfiled $
        renderDialogOverlayClearOob <> renderToastOob ToastBottomCenter toast

respondWithNativeLeaveDeletion :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Text -> Maybe (LiveMutationResult LeaveRequest) -> IO ResponseReceived
respondWithNativeLeaveDeletion fallback deletionResult = do
    case deletionResult of
        Just _  -> setSuccessMessage "Unavailable period deleted"
        Nothing -> setErrorMessage leaveDeletionUnavailableMessage
    redirectToPath fallback

respondWithLeaveReviewResult :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => LeaveReviewDecision -> LeaveRequest -> LeaveReviewResult -> IO ResponseReceived
respondWithLeaveReviewResult decision draft = \case
    LeaveReviewBlocked conflicts (Just token) -> do
        staff <- fetch (Id draft.staffId :: Id Staff)
        respondWithPolicyConfirmation ReinstateRequest staff draft conflicts token
    LeaveReviewBlocked conflicts Nothing -> do
        setErrorMessage (policyRejection draft conflicts)
        redirectTo LeaveRequestsAction
    LeaveReviewInvalidConfirmation -> do
        setErrorMessage invalidConfirmationMessage
        redirectTo LeaveRequestsAction
    LeaveReviewUnavailable -> do
        setErrorMessage "This unavailable period can no longer be reviewed."
        redirectTo LeaveRequestsAction
    LeaveReviewCompleted result ->
        if isHtmxRequest
            then respondWithLeaveRequestsContent result.liveMutationTouchedResources successMessage
            else do
                setSuccessMessage successMessage
                redirectTo LeaveRequestsAction
  where
    successMessage = case decision of
        ApproveLeave -> "Unavailable period approved"
        DenyLeave    -> "Unavailable period denied"

respondWithLeaveRequestsContent :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Set.Set SurfaceResourceValue -> Text -> IO ResponseReceived
respondWithLeaveRequestsContent touchedResources successMessage = do
    let scope = LeaveRequestsScopeValue (unpackId currentVenueId)
    setHeader ("HX-Reswap", "none")
    setActorLiveResourcesRefresh (leaveRequestsSurfaceScope scope) touchedResources (leaveRequestsCandidateMountedFragments scope)
    respondHtmlProfiled $
        renderDialogOverlayClearOob
            <> renderToastOob ToastBottomCenter (successToast successMessage)

respondWithStaffLeaveActorInvalidation :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Staff -> Set.Set SurfaceResourceValue -> Text -> IO ResponseReceived
respondWithStaffLeaveActorInvalidation staff touchedResources successMessage = do
    let scope = ProfileScopeValue (unpackId currentVenueId) (unpackId staff.id)
    setHeader ("HX-Reswap", "none")
    setActorLiveResourcesRefresh (staffSurfaceScope scope) touchedResources (staffCandidateMountedFragments scope)
    respondHtmlProfiled (renderDialogOverlayClearOob <> renderToastOob ToastBottomCenter (successToast successMessage))

leaveFallbackPath :: LeaveResponseContext -> Text
leaveFallbackPath LeavePageResponseContext = pathTo EditProfileAction
leaveFallbackPath LeaveSelfServiceResponseContext = pathTo EditProfileAction <> "?section=leave"
leaveFallbackPath LeaveStaffResponseContext = pathTo RosterWeeksAction

respondWithLeaveRequestValidationFailure :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => LeaveResponseContext -> LeaveRequest -> IO ResponseReceived
respondWithLeaveRequestValidationFailure responseContext leaveRequest = do
    let (target, swap, body) = case responseContext of
            LeavePageResponseContext -> (dialogOverlayMountId, "innerHTML", renderNewLeaveRequestDialog leaveRequest)
            LeaveSelfServiceResponseContext -> (selfServiceLeaveFormFragmentId, "outerHTML", renderSelfServiceLeaveFormFragment Nothing leaveRequest <> renderDialogOverlayClearOob)
            LeaveStaffResponseContext -> (staffLeaveRequestFormFragmentId, "outerHTML", renderStaffLeaveRequestFormFragment (Id leaveRequest.staffId) leaveRequest <> renderDialogOverlayClearOob)
    setHeader ("HX-Retarget", cs ("#" <> target))
    setHeader ("HX-Reswap", swap)
    respondHtml body

respondWithLeaveMutationSuccess :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => LeaveResponseContext -> Set.Set SurfaceResourceValue -> Text -> IO ResponseReceived
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
                respondHtmlProfiled (renderDialogOverlayClearOob <> renderToastOob ToastBottomCenter (successToast successMessage))
    LeaveStaffResponseContext -> do
        maybeStaff <- fetchLeaveRequestTargetStaff LeaveStaffResponseContext
        case maybeStaff of
            Nothing -> respondWithLeaveContextError LeaveStaffResponseContext "No staff record found. Contact an administrator."
            Just staff -> respondWithStaffLeaveActorInvalidation staff touchedResources successMessage

respondWithLeaveContextError :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => LeaveResponseContext -> Text -> IO ResponseReceived
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
