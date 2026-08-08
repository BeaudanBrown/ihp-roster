module Web.Controller.Admin.Xero.Timesheets
    ( applyXeroTimesheetPreparationStaffDecisionAction
    , approveXeroTimesheetPreparationPayItemsAction
    , confirmXeroTimesheetPreparationSubmissionAction
    , continueXeroTimesheetPreparationStaffStepAction
    , openXeroTimesheetPreparationAction
    , refreshXeroTimesheetPreparationAction
    , runXeroTimesheetPreparationAction
    , runXeroTimesheetPreparationSubmissionAction
    , showXeroTimesheetPreparationWaitFragmentAction
    , selectXeroTimesheetPreparationPeriodAction
    , showXeroTimesheetPreparationStaffMappingsFragmentAction
    , showXeroTimesheetPreparationSummaryAction
    , submitXeroTimesheetPreparationAction
    ) where

import Application.Helper.FrontendContract.AppShell (AccountCodeField,
                                                     ApplyXeroTimesheetPreparationStaffDecisionOverlay,
                                                     ApproveXeroTimesheetPreparationPayItemsOverlay,
                                                     ConfirmXeroTimesheetPreparationSubmissionOverlay,
                                                     ContinueXeroTimesheetPreparationStaffOverlay,
                                                     OpenXeroTimesheetPreparationOverlay,
                                                     PeriodKeyField,
                                                     RefreshXeroTimesheetPreparationOverlay,
                                                     RunXeroTimesheetPreparationOverlay,
                                                     RunXeroTimesheetPreparationSubmissionOverlay,
                                                     SelectXeroTimesheetPreparationPeriodOverlay,
                                                     StaffIdField,
                                                     SubmitXeroTimesheetPreparationOverlay,
                                                     XeroEmployeeSelectionField)
import Application.Helper.FrontendContract.AppShell.Request (AppShellActionFields,
                                                             parseAppShellActionParams)
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
import Application.Xero.ReferenceTrust.Presentation (XeroPreparationReferencePresentation (..),
                                                     xeroPreparationReferencePresentation)
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
                                 reviewXeroTimesheetPreparationSubmissionMutation,
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
    case parseAppShellActionParams @OpenXeroTimesheetPreparationOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right _ -> startOrWaitForXeroTimesheetPreparation

runXeroTimesheetPreparationAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
runXeroTimesheetPreparationAction =
    case parseAppShellActionParams @RunXeroTimesheetPreparationOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right _ -> observeXeroTimesheetPreparationReferenceState >>= respondToPreparationReferenceState

startOrWaitForXeroTimesheetPreparation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
startOrWaitForXeroTimesheetPreparation = do
    maybeConnection <- fetchCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> respondWithPreparationErrorToast "Connect Xero before preparing draft timesheets."
        Just connection -> do
            now <- getCurrentTime
            missingReferenceDemand <- fetchXeroMissingReferenceDemand connection
            trustState <- requestTrustedXeroReferenceData now (Just currentUser.id) connection missingReferenceDemand
            respondToPreparationReferenceState (Right trustState)

observeXeroTimesheetPreparationReferenceState ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO (Either Text XeroReferenceTrustState)
observeXeroTimesheetPreparationReferenceState = do
    fetchCurrentVenueXeroConnection >>= \case
        Nothing -> pure (Left "Connect Xero before preparing draft timesheets.")
        Just connection -> do
            now <- getCurrentTime
            missingReferenceDemand <- fetchXeroMissingReferenceDemand connection
            Right <$> fetchXeroReferenceTrustState now connection missingReferenceDemand

respondToPreparationReferenceState ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Either Text XeroReferenceTrustState ->
    IO ()
respondToPreparationReferenceState = \case
    Left message -> respondWithPreparationErrorToast message
    Right trustState ->
        case xeroPreparationReferencePresentation trustState.trustDecision of
            XeroPreparationReferenceReady -> do
                result <- liveMutationValue <$> runXeroTimesheetPreparationMutation
                respondWithPreparationDialog result
            XeroPreparationReferenceWaiting _ -> respondWithPreparationReferenceWait trustState
            XeroPreparationReferenceBlocked message -> respondWithPreparationErrorToast message

respondWithPreparationReferenceWait ::
    (?context :: ControllerContext, ?request :: Request) =>
    XeroReferenceTrustState ->
    IO ()
respondWithPreparationReferenceWait trustState =
    if isHtmxRequest
        then respondHtml (renderXeroTimesheetPreparationReferenceSyncWaitingDialog (unpackId currentVenueId) trustState)
        else do
            setSuccessMessage "Xero payroll reference data is syncing in the background."
            redirectTo XeroAction

showXeroTimesheetPreparationWaitFragmentAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
showXeroTimesheetPreparationWaitFragmentAction = do
    trustState <- observeXeroTimesheetPreparationReferenceState
    respondHtml $
        either
            renderXeroTimesheetPreparationReferenceSyncWaitFragmentError
            renderXeroTimesheetPreparationReferenceSyncWaitFragment
            trustState

refreshXeroTimesheetPreparationAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
refreshXeroTimesheetPreparationAction runId =
    case parseAppShellActionParams @RefreshXeroTimesheetPreparationOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right _ -> do
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
applyXeroTimesheetPreparationStaffDecisionAction runId =
    case parseAppShellActionParams @ApplyXeroTimesheetPreparationStaffDecisionOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right fields ->
            case parseStaffDecision fields of
                Left message -> respondWithPreparationDialog (Left message)
                Right decision -> do
                    let staffId = Id (surfaceFieldValue @StaffIdField fields)
                    result <- liveMutationValue <$> applyXeroTimesheetPreparationStaffDecisionMutation runId staffId decision
                    respondWithPreparationDialog result

continueXeroTimesheetPreparationStaffStepAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
continueXeroTimesheetPreparationStaffStepAction runId =
    case parseAppShellActionParams @ContinueXeroTimesheetPreparationStaffOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right _ -> do
            result <- liveMutationValue <$> approveXeroTimesheetPreparationStaffStepMutation runId
            respondWithPreparationDialog result

selectXeroTimesheetPreparationPeriodAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
selectXeroTimesheetPreparationPeriodAction runId =
    case parseAppShellActionParams @SelectXeroTimesheetPreparationPeriodOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right fields -> do
            let selectedPeriodKey = Text.strip (surfaceFieldValue @PeriodKeyField fields)
            result <- liveMutationValue <$> selectXeroTimesheetPreparationPeriodMutation runId selectedPeriodKey
            respondWithPreparationDialog result

approveXeroTimesheetPreparationPayItemsAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
approveXeroTimesheetPreparationPayItemsAction runId =
    case parseAppShellActionParams @ApproveXeroTimesheetPreparationPayItemsOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right fields -> do
            let maybeAccountCode = Text.strip <$> surfaceFieldValue @AccountCodeField fields
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
confirmXeroTimesheetPreparationSubmissionAction runId =
    case parseAppShellActionParams @ConfirmXeroTimesheetPreparationSubmissionOverlay of
        Left errors -> respondWithPreparationErrorToast (surfaceRequestFieldErrorsMessage errors)
        Right _ -> do
            result <- liveMutationValue <$> reviewXeroTimesheetPreparationSubmissionMutation runId
            case result of
                Left message -> respondWithPreparationErrorToast message
                Right view -> respondHtml (renderXeroTimesheetPreparationSubmittingDialog view)

runXeroTimesheetPreparationSubmissionAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
runXeroTimesheetPreparationSubmissionAction runId =
    case parseAppShellActionParams @RunXeroTimesheetPreparationSubmissionOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right _ -> submitXeroTimesheetPreparation runId Nothing

submitXeroTimesheetPreparationAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
submitXeroTimesheetPreparationAction runId =
    case parseAppShellActionParams @SubmitXeroTimesheetPreparationOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right fields ->
            submitXeroTimesheetPreparation runId (Text.strip <$> surfaceFieldValue @AccountCodeField fields)

submitXeroTimesheetPreparation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    Maybe Text ->
    IO ()
submitXeroTimesheetPreparation runId maybeAccountCode = do
    result <- liveMutationValue <$> submitXeroTimesheetPreparationMutation runId maybeAccountCode
    case result of
        Right view | view.preparationState == XeroPreparationSubmitted ->
            if isHtmxRequest
                then respondWithXeroTimesheetMutationAndCloseDialog (Just (xeroSuccessToast "Submitted Xero draft timesheets."))
                else do
                    setSuccessMessage "Submitted Xero draft timesheets."
                    redirectTo XeroAction
        _ -> respondWithPreparationDialog result

parseStaffDecision :: AppShellActionFields ApplyXeroTimesheetPreparationStaffDecisionOverlay -> Either Text XeroPreparationStaffDecision
parseStaffDecision fields =
    case Text.strip (surfaceFieldValue @XeroEmployeeSelectionField fields) of
        "" -> Left "Choose a Xero employee or Not paid through Xero before approving."
        "not_applicable" -> Right MarkStaffNotPaidThroughXero
        employeeId -> Right (SelectXeroEmployee employeeId)

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
