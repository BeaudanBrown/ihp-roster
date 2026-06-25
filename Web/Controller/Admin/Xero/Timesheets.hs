module Web.Controller.Admin.Xero.Timesheets
    ( applyXeroTimesheetPreparationStaffDecisionAction
    , approveXeroTimesheetPreparationPayItemsAction
    , confirmXeroTimesheetPreparationSubmissionAction
    , continueXeroTimesheetPreparationStaffStepAction
    , openXeroTimesheetPreparationAction
    , previewXeroDraftTimesheetsAction
    , refreshXeroTimesheetPreparationAction
    , retryXeroDraftTimesheetSubmissionAction
    , runXeroTimesheetPreparationAction
    , runXeroTimesheetPreparationSubmissionAction
    , selectXeroTimesheetPreparationPeriodAction
    , showXeroTimesheetPreparationStaffMappingsFragmentAction
    , showXeroTimesheetPreparationSummaryAction
    , submitXeroDraftTimesheetsAction
    , submitXeroTimesheetPreparationAction
    ) where

import Application.Helper.LiveResource (LiveMutationResult (..))
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                renderToastOverlayHostOob)
import Application.Helper.XeroAdminTypes (XeroTimesheetPreparationState (XeroPreparationSubmitted),
                                          XeroTimesheetPreparationView (..))
import Application.Helper.XeroTimesheetReadiness
import Application.Xero.Admin.ReadModel
import Application.Xero.Timesheets.Prepare (XeroPreparationStaffDecision (..),
                                            loadXeroTimesheetPreparationView)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Web.Admin.Xero.Mutations (applyXeroTimesheetPreparationStaffDecisionMutation,
                                 approveXeroTimesheetPreparationPayItemsMutation,
                                 approveXeroTimesheetPreparationStaffStepMutation,
                                 createPersistedXeroTimesheetPreviewMutation,
                                 previewXeroTimesheetPreparationMutation,
                                 refreshXeroTimesheetPreparationMutation,
                                 retryXeroDraftTimesheetSubmissionMutation,
                                 runXeroTimesheetPreparationMutation,
                                 selectXeroTimesheetPreparationPeriodMutation,
                                 submitXeroDraftTimesheetsMutation,
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
    let showMatched = paramOrDefault @Bool False "showMatched"
        editStaffId = paramOrNothing @(Id Staff) "editStaffId"
    respondHtml $
        case result of
            Left message -> [hsx|<section id="xero-preparation-staff-mappings"><div class="alert alert-danger mb-0">{message}</div></section>|]
            Right view -> renderXeroTimesheetPreparationStaffMappingsFragment showMatched editStaffId view

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

previewXeroDraftTimesheetsAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
previewXeroDraftTimesheetsAction = do
    requestResult <- currentTimesheetReadinessRequestForAction
    case requestResult of
        Left message -> respondWithXeroTimesheetError message
        Right readinessRequest -> do
            readiness <- validateXeroTimesheetReadiness readinessRequest
            let duplicateCheckJson =
                    Aeson.object
                        [ "remoteTimesheetCount" Aeson..= (0 :: Int)
                        , "remoteTimesheets" Aeson..= ([] :: [Aeson.Value])
                        ]
            previewResult <- createPersistedXeroTimesheetPreviewMutation currentUser.id readinessRequest readiness duplicateCheckJson
            case liveMutationValue previewResult of
                Left message -> respondWithXeroTimesheetError message
                Right _ -> respondWithXeroTimesheetSuccess "Prepared Xero draft-timesheet preview."

submitXeroDraftTimesheetsAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
submitXeroDraftTimesheetsAction = do
    requestResult <- currentTimesheetReadinessRequestForAction
    case requestResult of
        Left message -> respondWithXeroTimesheetError message
        Right readinessRequest -> do
            submissionResult <- submitXeroDraftTimesheetsMutation currentUser.id readinessRequest
            case liveMutationValue submissionResult of
                Left message -> respondWithXeroTimesheetError message
                Right run
                    | run.status == "submitted" -> respondWithXeroTimesheetSuccess "Submitted Xero draft timesheets."
                    | run.status == "partially_failed" -> respondWithXeroTimesheetError "Submitted Xero draft timesheets with employee-level errors."
                    | run.status == "blocked" -> respondWithXeroTimesheetError "Xero draft-timesheet submission is blocked by readiness checks."
                    | otherwise -> respondWithXeroTimesheetError "Xero draft-timesheet submission did not complete successfully."

retryXeroDraftTimesheetSubmissionAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetSubmission ->
    IO ()
retryXeroDraftTimesheetSubmissionAction submissionId = do
    authorized <- submissionBelongsToCurrentVenue submissionId
    if not authorized
        then respondWithXeroTimesheetError "Xero timesheet submission was not found for this venue."
        else do
            retryResult <- retryXeroDraftTimesheetSubmissionMutation submissionId
            case liveMutationValue retryResult of
                Left message -> respondWithXeroTimesheetError message
                Right submission
                    | submission.status == "submitted" -> respondWithXeroTimesheetSuccess "Retried and submitted the Xero draft timesheet."
                    | otherwise -> respondWithXeroTimesheetError "Retry did not complete successfully."

currentTimesheetReadinessRequestForAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO (Either Text XeroTimesheetReadinessRequest)
currentTimesheetReadinessRequestForAction = do
    maybeConnection <- fetchCurrentVenueXeroConnection
    maybeCalendarSelection <- fetchCurrentVenueXeroPayrollCalendarSelection maybeConnection
    currentVenueXeroTimesheetReadinessRequest maybeConnection maybeCalendarSelection >>= \case
        Just readinessRequest -> pure (Right readinessRequest)
        Nothing -> pure (Left "Choose a Xero pay period before preparing draft timesheets.")

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

submissionBelongsToCurrentVenue ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Id XeroTimesheetSubmission ->
    IO Bool
submissionBelongsToCurrentVenue submissionId = do
    count <-
        query @XeroTimesheetSubmission
            |> filterWhere (#id, submissionId)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchCount
    pure (count == 1)

respondWithXeroTimesheetSuccess ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO ()
respondWithXeroTimesheetSuccess message =
    if isHtmxRequest
        then do
            respondWithXeroTimesheetMutation (Just (xeroSuccessToast message))
        else do
            setSuccessMessage message
            redirectTo XeroAction

respondWithXeroTimesheetError ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO ()
respondWithXeroTimesheetError message =
    if isHtmxRequest
        then do
            respondWithXeroTimesheetMutation (Just (xeroErrorToast message))
        else do
            setErrorMessage message
            redirectTo XeroAction
