module Application.Xero.Timesheets.Submission
    ( retryXeroDraftTimesheetSubmission
    , submitXeroDraftTimesheets
    , xeroTimesheetSubmissionRequestJson
    )
where

import Application.Helper.Xero
import Application.Helper.XeroTimesheetReadiness
import Application.Xero.Connection
import Application.Xero.Timesheets.Preview
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Time.Clock (UTCTime)
import qualified Data.Vector as Vector
import Generated.Types
import IHP.ControllerPrelude

submitXeroDraftTimesheets ::
    (?modelContext :: ModelContext) =>
    Id User ->
    XeroTimesheetReadinessRequest ->
    IO (Either Text XeroSubmissionRun)
submitXeroDraftTimesheets submittedByUserId request = do
    readXeroConfig >>= \case
        Left message -> pure (Left message)
        Right xeroConfig -> do
            maybeConnection <- fetchActiveSubmissionXeroConnection request.readinessVenueId
            case maybeConnection of
                Nothing -> pure (Left "Active Xero connection was not found.")
                Just connection -> do
                    refreshXeroConnectionAccess xeroConfig connection >>= \case
                        Left message -> pure (Left message)
                        Right (refreshedConnection, accessToken) -> do
                            xeroClient <- currentXeroClient
                            remoteTimesheetsResult <- fetchRemoteTimesheetsForDuplicateCheck xeroClient accessToken refreshedConnection.tenantId
                            case remoteTimesheetsResult of
                                Left message -> pure (Left message)
                                Right remoteTimesheets -> do
                                    let duplicateSnapshot = duplicateCheckSnapshotJson remoteTimesheets
                                        readinessRequest = request { readinessRemoteTimesheets = remoteTimesheets }
                                    readiness <- validateXeroTimesheetReadiness readinessRequest
                                    previewInput <- fetchPreviewInput readinessRequest refreshedConnection
                                    case buildXeroTimesheetPreviewRun previewInput of
                                        Left message -> pure (Left message)
                                        Right previewRun ->
                                            persistAndSubmitPreview submittedByUserId xeroClient accessToken refreshedConnection readinessRequest readiness duplicateSnapshot previewRun

retryXeroDraftTimesheetSubmission ::
    (?modelContext :: ModelContext) =>
    Id XeroTimesheetSubmission ->
    IO (Either Text XeroTimesheetSubmission)
retryXeroDraftTimesheetSubmission submissionId = do
    maybeSubmission <-
        query @XeroTimesheetSubmission
            |> filterWhere (#id, submissionId)
            |> fetchOneOrNothing
    case maybeSubmission of
        Nothing -> pure (Left "Xero timesheet submission was not found.")
        Just submission
            | submission.status == "submitted" -> pure (Left "Xero timesheet submission has already been submitted.")
            | otherwise -> retryExistingSubmission submission

retryExistingSubmission ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetSubmission ->
    IO (Either Text XeroTimesheetSubmission)
retryExistingSubmission submission = do
    run <- fetch (Id submission.xeroSubmissionRunId :: Id XeroSubmissionRun)
    connection <- fetch (Id submission.xeroConnectionId :: Id XeroConnection)
    readXeroConfig >>= \case
        Left message -> pure (Left message)
        Right xeroConfig ->
            refreshXeroConnectionAccess xeroConfig connection >>= \case
                Left message -> pure (Left message)
                Right (refreshedConnection, accessToken) -> do
                    xeroClient <- currentXeroClient
                    fetchRemoteTimesheetsForDuplicateCheck xeroClient accessToken refreshedConnection.tenantId >>= \case
                        Left message -> pure (Left message)
                        Right remoteTimesheets -> do
                            let readinessRequest =
                                    XeroTimesheetReadinessRequest
                                        { readinessVenueId = Id run.venueId
                                        , readinessPeriodStart = run.payPeriodStart
                                        , readinessPeriodEnd = run.payPeriodEnd
                                        , readinessRemoteTimesheets = remoteTimesheets
                                        }
                                duplicateSnapshot = duplicateCheckSnapshotJson remoteTimesheets
                            readiness <- validateXeroTimesheetReadiness readinessRequest
                            _ <-
                                run
                                    |> set #readinessSnapshotJson (xeroReadinessSnapshotJson readiness)
                                    |> set #xeroDuplicateCheckJson duplicateSnapshot
                                    |> updateRecord
                            updatedSubmission <-
                                if not readiness.xeroTimesheetReady
                                    then markSubmissionBlocked submission (blockedReadinessSummary readiness)
                                    else submitExistingSubmission xeroClient accessToken refreshedConnection submission
                            refreshRunStatus run
                            pure (Right updatedSubmission)

persistAndSubmitPreview ::
    (?modelContext :: ModelContext) =>
    Id User ->
    XeroClient ->
    Text ->
    XeroConnection ->
    XeroTimesheetReadinessRequest ->
    XeroTimesheetReadiness ->
    Aeson.Value ->
    XeroTimesheetPreviewRun ->
    IO (Either Text XeroSubmissionRun)
persistAndSubmitPreview submittedByUserId xeroClient accessToken connection request readiness duplicateSnapshot previewRun = do
    run <-
        newRecord @XeroSubmissionRun
            |> set #venueId (unpackId request.readinessVenueId)
            |> set #xeroConnectionId (unpackId connection.id)
            |> set #submittedByUserId (unpackId submittedByUserId)
            |> set #payPeriodStart request.readinessPeriodStart
            |> set #payPeriodEnd request.readinessPeriodEnd
            |> set #status (if readiness.xeroTimesheetReady then "pending" else "blocked" :: Text)
            |> set #previewPayloadJson (xeroTimesheetPreviewRunJson previewRun)
            |> set #readinessSnapshotJson (xeroReadinessSnapshotJson readiness)
            |> set #xeroDuplicateCheckJson duplicateSnapshot
            |> set #errorSummary (if readiness.xeroTimesheetReady then Nothing else Just (blockedReadinessSummary readiness))
            |> createRecord
    if not readiness.xeroTimesheetReady
        then pure (Right run)
        else do
            submitted <- mapM (submitOnePreview xeroClient accessToken connection run) previewRun.previewRunTimesheets
            completedAt <- getCurrentTime
            let finalStatus = runStatusFromSubmissions submitted
                errorSummary = submissionErrorSummary submitted
            updatedRun <-
                run
                    |> set #status finalStatus
                    |> set #submittedAt (Just completedAt)
                    |> set #completedAt (Just completedAt)
                    |> set #errorSummary errorSummary
                    |> updateRecord
            pure (Right updatedRun)

submitOnePreview ::
    (?modelContext :: ModelContext) =>
    XeroClient ->
    Text ->
    XeroConnection ->
    XeroSubmissionRun ->
    XeroTimesheetPreview ->
    IO XeroTimesheetSubmission
submitOnePreview xeroClient accessToken connection run preview = do
    let requestJson = xeroTimesheetSubmissionRequestJson preview
        idempotencyKey = submissionIdempotencyKey run preview
        staffId = case preview.previewStaffIds of
            staffIdValue : _ -> staffIdValue
            []              -> error "Xero timesheet preview has no source staff id."
    submission <-
        newRecord @XeroTimesheetSubmission
            |> set #xeroSubmissionRunId (unpackId run.id)
            |> set #venueId run.venueId
            |> set #xeroConnectionId run.xeroConnectionId
            |> set #staffId staffId
            |> set #xeroEmployeeId preview.previewXeroEmployeeId
            |> set #payPeriodStart preview.previewPayPeriodStart
            |> set #payPeriodEnd preview.previewPayPeriodEnd
            |> set #status ("pending" :: Text)
            |> set #idempotencyKey idempotencyKey
            |> set #requestPayloadJson requestJson
            |> createRecord
    sourceEntries <- fetchPreviewSourceEntries preview
    forM_ sourceEntries (insertSubmissionEntry submission)
    submitExistingSubmission xeroClient accessToken connection submission

submitExistingSubmission ::
    (?modelContext :: ModelContext) =>
    XeroClient ->
    Text ->
    XeroConnection ->
    XeroTimesheetSubmission ->
    IO XeroTimesheetSubmission
submitExistingSubmission xeroClient accessToken connection submission = do
    now <- getCurrentTime
    createTimesheet xeroClient accessToken connection.tenantId submission.idempotencyKey submission.requestPayloadJson >>= \case
        Right refs -> markSubmissionSubmitted submission now refs
        Left err   -> markSubmissionFailed submission now (xeroClientErrorText err)

xeroTimesheetSubmissionRequestJson :: XeroTimesheetPreview -> Aeson.Value
xeroTimesheetSubmissionRequestJson preview =
    Aeson.Array (Vector.fromList [preview.previewRequestObjectJson])

submissionIdempotencyKey :: XeroSubmissionRun -> XeroTimesheetPreview -> Text
submissionIdempotencyKey run preview =
    Text.take 128 ("xero-timesheet:" <> tshow (unpackId run.id) <> ":" <> preview.previewXeroEmployeeId)

fetchPreviewSourceEntries :: (?modelContext :: ModelContext) => XeroTimesheetPreview -> IO [TimesheetEntry]
fetchPreviewSourceEntries preview =
    query @TimesheetEntry
        |> filterWhereIn (#id, map Id preview.previewSourceEntryIds)
        |> fetch

insertSubmissionEntry :: (?modelContext :: ModelContext) => XeroTimesheetSubmission -> TimesheetEntry -> IO ()
insertSubmissionEntry submission entry =
    case (entry.staffPayVersionId, entry.shiftTypePayVersionId, entry.approvedAt) of
        (Just staffVersionId, Just shiftTypeVersionId, Just approvedAt) ->
            void $
                newRecord @XeroTimesheetSubmissionEntry
                    |> set #xeroTimesheetSubmissionId (unpackId submission.id)
                    |> set #timesheetEntryId (unpackId entry.id)
                    |> set #staffPayVersionId staffVersionId
                    |> set #shiftTypePayVersionId shiftTypeVersionId
                    |> set #entryUpdatedAtAtPreview entry.updatedAt
                    |> set #entryApprovedAtAtPreview approvedAt
                    |> createRecord
        _ -> pure ()

markSubmissionSubmitted :: (?modelContext :: ModelContext) => XeroTimesheetSubmission -> UTCTime -> [XeroTimesheetRef] -> IO XeroTimesheetSubmission
markSubmissionSubmitted submission now refs = do
    let maybeRef = List.find (\ref -> ref.xeroTimesheetEmployeeId == submission.xeroEmployeeId) refs <|> listToMaybe refs
    submission
        |> set #status ("submitted" :: Text)
        |> set #responsePayloadJson (xeroTimesheetRefsResponseJson refs)
        |> set #xeroTimesheetId (maybeRef >>= (.xeroTimesheetId))
        |> set #xeroTimesheetStatus (maybeRef >>= (.xeroTimesheetStatus))
        |> set #attemptCount (submission.attemptCount + 1)
        |> set #lastError Nothing
        |> set #submittedAt (Just now)
        |> updateRecord

markSubmissionFailed :: (?modelContext :: ModelContext) => XeroTimesheetSubmission -> UTCTime -> Text -> IO XeroTimesheetSubmission
markSubmissionFailed submission now message =
    submission
        |> set #status ("failed" :: Text)
        |> set #responsePayloadJson (Aeson.object ["error" Aeson..= message])
        |> set #attemptCount (submission.attemptCount + 1)
        |> set #lastError (Just message)
        |> set #submittedAt (Just now)
        |> updateRecord

markSubmissionBlocked :: (?modelContext :: ModelContext) => XeroTimesheetSubmission -> Text -> IO XeroTimesheetSubmission
markSubmissionBlocked submission message =
    submission
        |> set #status ("blocked" :: Text)
        |> set #responsePayloadJson (Aeson.object ["error" Aeson..= message])
        |> set #lastError (Just message)
        |> updateRecord

refreshRunStatus :: (?modelContext :: ModelContext) => XeroSubmissionRun -> IO XeroSubmissionRun
refreshRunStatus run = do
    submissions <-
        query @XeroTimesheetSubmission
            |> filterWhere (#xeroSubmissionRunId, unpackId run.id)
            |> fetch
    now <- getCurrentTime
    run
        |> set #status (runStatusFromSubmissions submissions)
        |> set #submittedAt (Just now)
        |> set #completedAt (Just now)
        |> set #errorSummary (submissionErrorSummary submissions)
        |> updateRecord

runStatusFromSubmissions :: [XeroTimesheetSubmission] -> Text
runStatusFromSubmissions submissions
    | null submissions = "failed"
    | all ((== "submitted") . (.status)) submissions = "submitted"
    | all ((== "blocked") . (.status)) submissions = "blocked"
    | all ((== "failed") . (.status)) submissions = "failed"
    | otherwise = "partially_failed"

submissionErrorSummary :: [XeroTimesheetSubmission] -> Maybe Text
submissionErrorSummary submissions =
    submissions
        |> mapMaybe (.lastError)
        |> List.nub
        |> \case
            []     -> Nothing
            errors -> Just (Text.intercalate "\n" errors)

blockedReadinessSummary :: XeroTimesheetReadiness -> Text
blockedReadinessSummary readiness =
    readiness.xeroReadinessBlockers
        |> map (.xeroBlockerMessage)
        |> List.nub
        |> Text.intercalate "\n"

fetchRemoteTimesheetsForDuplicateCheck :: XeroClient -> Text -> Text -> IO (Either Text [XeroTimesheetRef])
fetchRemoteTimesheetsForDuplicateCheck xeroClient accessToken tenantId =
    fetchPage 1 []
    where
        fetchPage page acc = do
            let query =
                    XeroTimesheetQuery
                        { xeroTimesheetIfModifiedSince = Nothing
                        , xeroTimesheetWhere = Just "EmployeeID!=Guid(\"00000000-0000-0000-0000-000000000000\")"
                        , xeroTimesheetOrder = Just "StartDate DESC"
                        , xeroTimesheetPage = Just page
                        }
            fetchTimesheets xeroClient accessToken tenantId query >>= \case
                Left err -> pure (Left ("Xero duplicate check failed: " <> xeroClientErrorText err))
                Right refs ->
                    let nextAcc = acc <> refs
                     in if length refs < 100
                            then pure (Right nextAcc)
                            else fetchPage (page + 1) nextAcc

duplicateCheckSnapshotJson :: [XeroTimesheetRef] -> Aeson.Value
duplicateCheckSnapshotJson refs =
    Aeson.object
        [ "remoteTimesheetCount" Aeson..= length refs
        , "remoteTimesheets" Aeson..= map xeroTimesheetRefJson refs
        ]

xeroTimesheetRefsResponseJson :: [XeroTimesheetRef] -> Aeson.Value
xeroTimesheetRefsResponseJson refs =
    Aeson.object ["Timesheets" Aeson..= map xeroTimesheetRefJson refs]

xeroTimesheetRefJson :: XeroTimesheetRef -> Aeson.Value
xeroTimesheetRefJson ref =
    Aeson.object
        [ "TimesheetID" Aeson..= ref.xeroTimesheetId
        , "EmployeeID" Aeson..= ref.xeroTimesheetEmployeeId
        , "StartDate" Aeson..= ref.xeroTimesheetStartDate
        , "EndDate" Aeson..= ref.xeroTimesheetEndDate
        , "Status" Aeson..= ref.xeroTimesheetStatus
        , "Hours" Aeson..= ref.xeroTimesheetHours
        , "Raw" Aeson..= ref.xeroTimesheetRaw
        ]

fetchActiveSubmissionXeroConnection :: (?modelContext :: ModelContext) => Id Venue -> IO (Maybe XeroConnection)
fetchActiveSubmissionXeroConnection venueId =
    query @XeroConnection
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#connectionStatus, "active" :: Text)
        |> orderByDesc #connectedAt
        |> fetchOneOrNothing
