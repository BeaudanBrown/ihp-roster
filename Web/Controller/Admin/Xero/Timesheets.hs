module Web.Controller.Admin.Xero.Timesheets
    ( applyXeroTimesheetPreparationStaffDecisionAction
    , approveXeroTimesheetPreparationPayItemsAction
    , openXeroTimesheetPreparationAction
    , previewXeroDraftTimesheetsAction
    , previewXeroTimesheetPreparationAction
    , refreshXeroTimesheetPreparationAction
    , retryXeroDraftTimesheetSubmissionAction
    , submitXeroDraftTimesheetsAction
    , submitXeroTimesheetPreparationAction
    ) where

import Application.Helper.XeroTimesheetReadiness
import Application.Helper.XeroAdminTypes (XeroTimesheetPreparationView)
import Application.Xero.Admin.ReadModel
import Application.Xero.Timesheets.Preview
import Application.Xero.Timesheets.Prepare
import Application.Xero.Timesheets.Submission
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Web.Controller.Admin.Xero.Responses
import Web.Controller.Prelude
import Web.View.Admin.Xero.TimesheetPreparation

openXeroTimesheetPreparationAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
openXeroTimesheetPreparationAction = do
    let selectedPeriodKey = Text.strip (paramOrDefault @Text "" "periodKey")
    result <- startXeroTimesheetPreparation selectedPeriodKey
    respondWithPreparationDialog False result

refreshXeroTimesheetPreparationAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
refreshXeroTimesheetPreparationAction runId = do
    result <- refreshXeroTimesheetPreparation runId
    respondWithPreparationDialog True result

applyXeroTimesheetPreparationStaffDecisionAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
applyXeroTimesheetPreparationStaffDecisionAction runId = do
    let staffId = param @(Id Staff) "staffId"
    case parseStaffDecision of
        Left message -> respondWithPreparationDialog False (Left message)
        Right decision -> do
            result <- applyXeroPreparationStaffDecision runId staffId decision
            respondWithPreparationDialog True result

approveXeroTimesheetPreparationPayItemsAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
approveXeroTimesheetPreparationPayItemsAction runId = do
    let maybeAccountCode = Text.strip <$> paramOrNothing @Text "accountCode"
    result <- approveXeroPreparationPayItems runId maybeAccountCode
    respondWithPreparationDialog True result

previewXeroTimesheetPreparationAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
previewXeroTimesheetPreparationAction runId = do
    result <- previewXeroTimesheetPreparation runId
    respondWithPreparationDialog True result

submitXeroTimesheetPreparationAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ()
submitXeroTimesheetPreparationAction runId = do
    result <- submitXeroTimesheetPreparation runId
    respondWithPreparationDialog True result

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
            createPersistedXeroTimesheetPreview currentUser.id readinessRequest readiness duplicateCheckJson >>= \case
                Left message -> respondWithXeroTimesheetError message
                Right _ -> respondWithXeroTimesheetSuccess "Prepared Xero draft-timesheet preview."

submitXeroDraftTimesheetsAction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
submitXeroDraftTimesheetsAction = do
    requestResult <- currentTimesheetReadinessRequestForAction
    case requestResult of
        Left message -> respondWithXeroTimesheetError message
        Right readinessRequest ->
            submitXeroDraftTimesheets currentUser.id readinessRequest >>= \case
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
        else
            retryXeroDraftTimesheetSubmission submissionId >>= \case
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
        Nothing -> pure (Left "Select and verify a Xero payroll calendar before preparing draft timesheets.")

parseStaffDecision :: (?context :: ControllerContext, ?request :: Request) => Either Text XeroPreparationStaffDecision
parseStaffDecision =
    case Text.strip (paramOrDefault @Text "" "decision") of
        "approve_suggestion" -> Right ApproveSuggestedXeroEmployee
        "manual" ->
            case Text.strip (paramOrDefault @Text "" "xeroEmployeeId") of
                "" -> Left "Choose a Xero employee before saving the manual mapping."
                employeeId -> Right (SelectXeroEmployee employeeId)
        "not_paid" -> Right MarkStaffNotPaidThroughXero
        "skip" -> Right SkipStaffForPreparation
        _ -> Left "Choose a supported Xero preparation decision."

respondWithPreparationDialog ::
    (?context :: ControllerContext, ?request :: Request) =>
    Bool ->
    Either Text XeroTimesheetPreparationView ->
    IO ()
respondWithPreparationDialog shouldBroadcast result =
    if isHtmxRequest
        then do
            when shouldBroadcast (broadcastAdminXeroTimesheetsInvalidation (unpackId currentVenueId))
            respondHtml $
                case result of
                    Left message -> renderXeroTimesheetPreparationErrorDialog message
                    Right view -> renderXeroTimesheetPreparationDialog view
        else
            case result of
                Left message -> do
                    setErrorMessage message
                    redirectTo XeroAction
                Right _ -> do
                    setSuccessMessage "Updated Xero timesheet preparation."
                    redirectTo XeroAction

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
            broadcastAdminXeroTimesheetsInvalidation (unpackId currentVenueId)
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
            broadcastAdminXeroTimesheetsInvalidation (unpackId currentVenueId)
            respondWithXeroTimesheetMutation (Just (xeroErrorToast message))
        else do
            setErrorMessage message
            redirectTo XeroAction
