module Web.Controller.Admin.Xero.Timesheets
    ( applyXeroTimesheetPreparationStaffDecisionAction
    , approveXeroTimesheetPreparationPayItemsAction
    , confirmXeroTimesheetPreparationSubmissionAction
    , continueXeroTimesheetPreparationStaffStepAction
    , openXeroTimesheetPreparationAction
    , refreshXeroTimesheetPreparationAction
    , runXeroTimesheetPreparationAction
    , runXeroTimesheetPreparationSubmissionAction
    , selectXeroTimesheetPreparationPeriodAction
    , showXeroTimesheetPreparationStaffMappingsFragmentAction
    , showXeroTimesheetPreparationSummaryAction
    , submitXeroTimesheetPreparationAction
    ) where

import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                renderToastOverlayHostOob)
import Application.Helper.XeroAdminTypes (XeroTimesheetPreparationState (XeroPreparationSubmitted),
                                          XeroTimesheetPreparationView (..))
import Application.Xero.Admin.ReadModel
import Application.Xero.ReferenceDemand (fetchXeroMissingReferenceDemand)
import Application.Xero.ReferenceTrust
import Application.Xero.ReferenceTrust.ReadModel (XeroReferenceTrustState (..),
                                                  fetchXeroReferenceTrustState)
import Application.Xero.ReferenceTrust.Service
import Application.Xero.Timesheets.Prepare (XeroPreparationStaffDecision (..),
                                            loadXeroTimesheetPreparationView)
import qualified Data.Text as Text
import Web.Admin.Xero.Mutations (applyXeroTimesheetPreparationStaffDecisionMutation,
                                 approveXeroTimesheetPreparationPayItemsMutation,
                                 approveXeroTimesheetPreparationStaffStepMutation,
                                 previewXeroTimesheetPreparationMutation,
                                 refreshXeroTimesheetPreparationMutation,
                                 runXeroTimesheetPreparationMutation,
                                 selectXeroTimesheetPreparationPeriodMutation,
                                 submitXeroTimesheetPreparationMutation)
import Web.Controller.Admin.Xero.Responses
import Web.Controller.Prelude
import Web.View.Admin.Xero.TimesheetPreparation

openXeroTimesheetPreparationAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
openXeroTimesheetPreparationAction =
    startOrWaitForXeroTimesheetPreparation

runXeroTimesheetPreparationAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
runXeroTimesheetPreparationAction =
    startOrWaitForXeroTimesheetPreparation

startOrWaitForXeroTimesheetPreparation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
startOrWaitForXeroTimesheetPreparation = do
    let maybeWaitStartedAt = paramOrNothing @UTCTime "referenceWaitStartedAt"
        maybeReferenceDemand = paramOrNothing @Text "referenceDemand"
    maybeConnection <- fetchCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> respondWithPreparationErrorToast "Connect Xero before preparing draft timesheets."
        Just connection -> do
            now <- getCurrentTime
            currentTrustState <- fetchXeroReferenceTrustState now connection NoMissingPayrollReferenceDemand
            missingReferenceDemand <-
                case maybeReferenceDemand of
                    Just "snapshot" | referenceSnapshotStillBlocks currentTrustState.trustDecision -> pure NoMissingPayrollReferenceDemand
                    Just "missing_payroll_staff" | referenceSyncActivityIsActive currentTrustState.syncActivity -> pure MissingPayrollEligibleStaffReference
                    _ -> fetchXeroMissingReferenceDemand connection
            trustState <- ensureTrustedXeroReferenceData now (Just currentUser.id) connection missingReferenceDemand
            case trustState.trustDecision of
                UseTrustedXeroReferenceSnapshot -> do
                    result <- liveMutationValue <$> runXeroTimesheetPreparationMutation
                    respondWithPreparationDialog result
                StartOrJoinXeroReferenceSync -> respondWithPreparationReferenceWait now maybeWaitStartedAt missingReferenceDemand trustState
                WaitForTrustedXeroReferenceSnapshot _ -> respondWithPreparationReferenceWait now maybeWaitStartedAt missingReferenceDemand trustState
                ReconnectXeroForReferenceData -> respondWithPreparationErrorToast "Reconnect Xero before preparing draft timesheets."
                BlockStaleXeroReferenceData _ -> respondWithPreparationErrorToast "Xero reference data is out of date and could not be refreshed. Contact support before preparing draft timesheets."

respondWithPreparationReferenceWait ::
    (?context :: ControllerContext, ?request :: Request) =>
    UTCTime ->
    Maybe UTCTime ->
    XeroMissingReferenceDemand ->
    XeroReferenceTrustState ->
    IO ()
respondWithPreparationReferenceWait now maybeWaitStartedAt missingReferenceDemand trustState =
    if isHtmxRequest
        then respondHtml (renderXeroTimesheetPreparationReferenceSyncWaitingDialog now (fromMaybe now maybeWaitStartedAt) missingReferenceDemand trustState)
        else do
            setSuccessMessage "Xero payroll reference data is syncing in the background."
            redirectTo XeroAction

referenceSnapshotStillBlocks :: XeroReferenceTrustDecision -> Bool
referenceSnapshotStillBlocks = \case
    StartOrJoinXeroReferenceSync -> True
    WaitForTrustedXeroReferenceSnapshot _ -> True
    ReconnectXeroForReferenceData -> True
    BlockStaleXeroReferenceData _ -> True
    UseTrustedXeroReferenceSnapshot -> False

referenceSyncActivityIsActive :: XeroReferenceSyncActivity -> Bool
referenceSyncActivityIsActive = \case
    XeroReferenceSyncQueued -> True
    XeroReferenceSyncRunning -> True
    XeroReferenceSyncRetryWaiting _ -> True
    _ -> False

refreshXeroTimesheetPreparationAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
refreshXeroTimesheetPreparationAction runId = do
    result <- liveMutationValue <$> refreshXeroTimesheetPreparationMutation runId
    respondWithPreparationDialog result

showXeroTimesheetPreparationStaffMappingsFragmentAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
showXeroTimesheetPreparationStaffMappingsFragmentAction runId = do
    result <- loadXeroTimesheetPreparationView runId
    respondHtml $
        case (AdminAction.parseShowXeroTimesheetPreparationStaffMappingsActionParams, result) of
            (Left errors, _) -> [hsx|<section id="xero-preparation-staff-mappings"><div class="alert alert-danger mb-0">{surfaceRequestFieldErrorsMessage errors}</div></section>|]
            (_, Left message) -> [hsx|<section id="xero-preparation-staff-mappings"><div class="alert alert-danger mb-0">{message}</div></section>|]
            (Right fields, Right view) ->
                renderXeroTimesheetPreparationStaffMappingsFragment
                    (surfaceFieldValue @Surface.ShowMatched fields)
                    (Id <$> surfaceFieldValue @Surface.EditStaffId fields)
                    view

applyXeroTimesheetPreparationStaffDecisionAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
applyXeroTimesheetPreparationStaffDecisionAction runId = do
    let staffId = param @(Id Staff) "staffId"
    case parseStaffDecision of
        Left message -> respondWithPreparationDialog (Left message)
        Right decision -> do
            result <- liveMutationValue <$> applyXeroTimesheetPreparationStaffDecisionMutation runId staffId decision
            respondWithPreparationDialog result

continueXeroTimesheetPreparationStaffStepAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
continueXeroTimesheetPreparationStaffStepAction runId = do
    result <- liveMutationValue <$> approveXeroTimesheetPreparationStaffStepMutation runId
    respondWithPreparationDialog result

selectXeroTimesheetPreparationPeriodAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
selectXeroTimesheetPreparationPeriodAction runId = do
    let selectedPeriodKey = Text.strip (paramOrDefault @Text "" "periodKey")
    result <- liveMutationValue <$> selectXeroTimesheetPreparationPeriodMutation runId selectedPeriodKey
    respondWithPreparationDialog result

approveXeroTimesheetPreparationPayItemsAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
approveXeroTimesheetPreparationPayItemsAction runId = do
    let maybeAccountCode = Text.strip <$> paramOrNothing @Text "accountCode"
    result <- liveMutationValue <$> approveXeroTimesheetPreparationPayItemsMutation runId maybeAccountCode
    case result of
        Left message -> respondWithPreparationDialog (Left message)
        Right _      -> showXeroTimesheetPreparationSummaryAction runId

showXeroTimesheetPreparationSummaryAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
showXeroTimesheetPreparationSummaryAction runId = do
    result <- liveMutationValue <$> previewXeroTimesheetPreparationMutation runId
    case result of
        Right view -> respondWithPreparationDialog (Right view)
        Left _ -> loadXeroTimesheetPreparationView runId >>= respondWithPreparationDialog

confirmXeroTimesheetPreparationSubmissionAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
confirmXeroTimesheetPreparationSubmissionAction runId = do
    result <- loadXeroTimesheetPreparationView runId
    case result of
        Left message -> respondWithPreparationErrorToast message
        Right view -> respondHtml (renderXeroTimesheetPreparationSubmittingDialog view)

runXeroTimesheetPreparationSubmissionAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
runXeroTimesheetPreparationSubmissionAction = submitXeroTimesheetPreparationAction

submitXeroTimesheetPreparationAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
submitXeroTimesheetPreparationAction runId = do
    let maybeAccountCode = Text.strip <$> paramOrNothing @Text "accountCode"
    result <- liveMutationValue <$> submitXeroTimesheetPreparationMutation runId maybeAccountCode
    case result of
        Right view | view.preparationState == XeroPreparationSubmitted ->
            if isHtmxRequest
                then respondWithXeroTimesheetMutationAndCloseDialog (Just (xeroSuccessToast "Submitted Xero draft timesheets."))
                else do
                    setSuccessMessage "Submitted Xero draft timesheets."
                    redirectTo XeroAction
        _ -> respondWithPreparationDialog result

parseStaffDecision :: (?context :: ControllerContext, ?request :: Request) => Either Text XeroPreparationStaffDecision
parseStaffDecision =
    case Text.strip (paramOrDefault @Text "" "decision") of
        "select_employee" ->
            case Text.strip (paramOrDefault @Text "" "xeroEmployeeSelection") of
                "" -> Left "Choose a Xero employee or Not paid through Xero before approving."
                "not_applicable" -> Right MarkStaffNotPaidThroughXero
                employeeId -> Right (SelectXeroEmployee employeeId)
        "not_paid" -> Right MarkStaffNotPaidThroughXero
        _ -> Left "Choose a supported Xero preparation decision."

respondWithPreparationDialog ::
    (?context :: ControllerContext, ?request :: Request) =>
    Either Text XeroTimesheetPreparationView ->
    IO ()
respondWithPreparationDialog result =
    if isHtmxRequest
        then do
            case result of
                Left message -> respondWithPreparationErrorToast message
                Right view -> respondHtml (renderXeroTimesheetPreparationDialog view)
        else
            case result of
                Left message -> do
                    setErrorMessage message
                    redirectTo XeroAction
                Right _ -> do
                    setSuccessMessage "Updated Xero timesheet preparation."
                    redirectTo XeroAction

respondWithPreparationErrorToast :: (?context :: ControllerContext, ?request :: Request) => Text -> IO ()
respondWithPreparationErrorToast message = do
    setHeader ("HX-Reswap", "none")
    respondHtml (renderToastOverlayHostOob ToastBottomCenter [xeroErrorToast message])
