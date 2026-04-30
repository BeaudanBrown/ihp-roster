module Application.Xero.Admin.Timesheets
    ( previewXeroDraftTimesheetsAction
    , retryXeroDraftTimesheetSubmissionAction
    , submitXeroDraftTimesheetsAction
    ) where

import Application.Helper.XeroTimesheetReadiness
import Application.Xero.Admin.ReadModel
import Application.Xero.Admin.Responses
import Application.Xero.Timesheets.Preview
import Application.Xero.Timesheets.Submission
import qualified Data.Aeson as Aeson
import Web.Controller.Prelude

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
        then respondWithXeroSectionFragmentAndToast (Just (xeroSuccessToast message))
        else do
            setSuccessMessage message
            redirectTo XeroAction

respondWithXeroTimesheetError ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO ()
respondWithXeroTimesheetError message =
    if isHtmxRequest
        then respondWithXeroSectionFragmentAndToast (Just (xeroErrorToast message))
        else do
            setErrorMessage message
            redirectTo XeroAction
