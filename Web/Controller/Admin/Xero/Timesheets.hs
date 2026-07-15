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
import Application.Helper.FrontendContract.Surface.Request (parseSurfaceActionParams,
                                                            surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                renderToastOverlayHostOob)
import Application.Helper.XeroAdminTypes (XeroTimesheetPreparationState (XeroPreparationSubmitted),
                                          XeroTimesheetPreparationView (..))
import Application.Xero.Admin.ReadModel
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
openXeroTimesheetPreparationAction = do
    result <- liveMutationValue <$> runXeroTimesheetPreparationMutation
    respondWithPreparationDialog result

runXeroTimesheetPreparationAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
runXeroTimesheetPreparationAction = do
    result <- liveMutationValue <$> runXeroTimesheetPreparationMutation
    respondWithPreparationDialog result

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
        case (parseSurfaceActionParams @Surface.AdminXeroSurface @Surface.ShowXeroTimesheetPreparationStaffMappings, result) of
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
