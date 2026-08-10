{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Xero.Timesheets.Submission
    ( XeroTimesheetReviewedSubmissionOutcome (..)
    , duplicateCheckSnapshotJson
    , fetchRemoteTimesheetsForDuplicateCheck
    , reviewXeroDraftTimesheets
    , retryXeroDraftTimesheetSubmission
    , submitReviewedXeroDraftTimesheetsForPreparation
    , submitXeroDraftTimesheets
    , xeroTimesheetSubmissionRequestJson
    )
where

import Application.Helper.Xero
import Application.Helper.XeroTimesheetReadiness
import Application.WageSourceEnforcement (enforceFinalWageEntries,
                                          renderWageEntryFailures)
import Application.Xero.Connection
import Application.Xero.Timesheets.Preview
import Application.Xero.Timesheets.ProviderWrite
import Application.Xero.Timesheets.Reconciliation (XeroTimesheetReconciliationDecision (..),
                                                   reconcileXeroTimesheet)
import Application.Xero.Timesheets.ReconciliationReview
import Application.Xero.Timesheets.Reservation
import Application.Xero.WorkflowState (xeroSubmissionIsInProgress,
                                       xeroSubmissionIsSubmitted,
                                       xeroSubmissionIsSuperseded,
                                       xeroSubmissionRunStatusFromStatuses)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.Bifunctor as Bifunctor
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Clock (UTCTime)
import qualified Data.Vector as Vector
import Generated.Types
import IHP.ControllerPrelude

data XeroTimesheetReviewedSubmissionOutcome
    = XeroTimesheetReviewedSubmissionCompleted !XeroSubmissionRun
    | XeroTimesheetReviewedStateChanged !Aeson.Value
    deriving (Eq, Show)

data XeroTimesheetSubmissionPersistenceOutcome
    = XeroTimesheetSubmissionPersisted !XeroSubmissionRun
    | XeroTimesheetSubmissionReservationInProgress ![Id XeroSubmissionRun]
    | XeroTimesheetSubmissionReservationBlocked !XeroTimesheetReconciliationDecision

data FreshSubmissionPlan = FreshSubmissionPlan
    { freshPlanRequest           :: !XeroTimesheetReadinessRequest
    , freshPlanReadiness         :: !XeroTimesheetReadiness
    , freshPlanDuplicateSnapshot :: !Aeson.Value
    , freshPlanPreviewRun        :: !XeroTimesheetPreviewRun
    , freshPlanReservations      :: ![XeroTimesheetReservation]
    , freshPlanReviewSnapshot    :: !Aeson.Value
    }

reviewXeroDraftTimesheets ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetReadinessRequest ->
    IO (Either Text Aeson.Value)
reviewXeroDraftTimesheets request =
    withFreshRemoteTimesheets request \_ _ connection remoteTimesheets ->
        fmap (.freshPlanReviewSnapshot) <$> buildFreshSubmissionPlan request connection remoteTimesheets

submitXeroDraftTimesheets ::
    (?modelContext :: ModelContext) =>
    Id User ->
    XeroTimesheetReadinessRequest ->
    IO (Either Text XeroSubmissionRun)
submitXeroDraftTimesheets submittedByUserId request =
    submitXeroDraftTimesheetsWithPreparation submittedByUserId Nothing Nothing request >>= \case
        Left message -> pure (Left message)
        Right (XeroTimesheetReviewedSubmissionCompleted run) -> pure (Right run)
        Right (XeroTimesheetReviewedStateChanged _) -> pure (Left "Xero reconciliation state changed unexpectedly.")

submitReviewedXeroDraftTimesheetsForPreparation ::
    (?modelContext :: ModelContext) =>
    Id User ->
    Id XeroTimesheetPreparationRun ->
    Aeson.Value ->
    XeroTimesheetReadinessRequest ->
    IO (Either Text XeroTimesheetReviewedSubmissionOutcome)
submitReviewedXeroDraftTimesheetsForPreparation submittedByUserId preparationRunId reviewedSnapshot =
    submitXeroDraftTimesheetsWithPreparation submittedByUserId (Just preparationRunId) (Just reviewedSnapshot)

submitXeroDraftTimesheetsWithPreparation ::
    (?modelContext :: ModelContext) =>
    Id User ->
    Maybe (Id XeroTimesheetPreparationRun) ->
    Maybe Aeson.Value ->
    XeroTimesheetReadinessRequest ->
    IO (Either Text XeroTimesheetReviewedSubmissionOutcome)
submitXeroDraftTimesheetsWithPreparation submittedByUserId maybePreparationRunId maybeReviewedSnapshot request =
    withFreshRemoteTimesheets request \xeroClient accessToken connection remoteTimesheets -> do
        buildFreshSubmissionPlan request connection remoteTimesheets >>= \case
            Left message -> pure (Left message)
            Right plan
                | Just reviewedSnapshot <- maybeReviewedSnapshot
                , reviewedSnapshot /= plan.freshPlanReviewSnapshot ->
                    pure (Right (XeroTimesheetReviewedStateChanged plan.freshPlanReviewSnapshot))
                | otherwise ->
                    persistAndSubmitPreview
                        submittedByUserId
                        maybePreparationRunId
                        xeroClient
                        accessToken
                        connection
                        plan.freshPlanRequest
                        plan.freshPlanReadiness
                        plan.freshPlanDuplicateSnapshot
                        plan.freshPlanPreviewRun
                        plan.freshPlanReservations
                        >>= \case
                            Left message -> pure (Left message)
                            Right (XeroTimesheetSubmissionPersisted run) ->
                                pure (Right (XeroTimesheetReviewedSubmissionCompleted run))
                            Right (XeroTimesheetSubmissionReservationInProgress runIds) ->
                                case maybeReviewedSnapshot of
                                    Just _ -> pure (Right (reservationStateChanged plan XeroSubmissionInProgress))
                                    Nothing -> case runIds of
                                        [runId] -> Right . XeroTimesheetReviewedSubmissionCompleted <$> fetch runId
                                        _ -> pure (Left "Xero timesheet submission is already in progress in more than one run.")
                            Right (XeroTimesheetSubmissionReservationBlocked decision) ->
                                case maybeReviewedSnapshot of
                                    Just _ -> pure (Right (reservationStateChanged plan decision))
                                    Nothing -> pure (Left (reconciliationBlockedMessage decision))
  where
    reservationStateChanged plan decision =
        XeroTimesheetReviewedStateChanged
            ( reconciliationReviewSnapshotJson
                ( map
                    (\reservation -> XeroTimesheetReconciliationReview reservation.reservationXeroEmployeeId decision)
                    plan.freshPlanReservations
                )
            )

withFreshRemoteTimesheets ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetReadinessRequest ->
    (XeroClient -> Text -> XeroConnection -> [XeroTimesheetRef] -> IO (Either Text a)) ->
    IO (Either Text a)
withFreshRemoteTimesheets request action =
    readXeroConfig >>= \case
        Left message -> pure (Left message)
        Right xeroConfig ->
            fetchActiveSubmissionXeroConnection request.readinessVenueId >>= \case
                Nothing -> pure (Left "Active Xero connection was not found.")
                Just connection ->
                    refreshXeroConnectionAccess xeroConfig connection >>= \case
                        Left message -> pure (Left message)
                        Right (refreshedConnection, accessToken) -> do
                            xeroClient <- currentXeroClient
                            fetchRemoteTimesheetsForDuplicateCheck
                                xeroClient
                                accessToken
                                refreshedConnection.tenantId
                                request.readinessPayrollCalendarId
                                request.readinessPeriodStart
                                request.readinessPeriodEnd >>= \case
                                    Left message -> pure (Left message)
                                    Right remoteTimesheets -> action xeroClient accessToken refreshedConnection remoteTimesheets

buildFreshSubmissionPlan ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetReadinessRequest ->
    XeroConnection ->
    [XeroTimesheetRef] ->
    IO (Either Text FreshSubmissionPlan)
buildFreshSubmissionPlan request connection remoteTimesheets = do
    let readinessRequest = request { readinessRemoteTimesheets = remoteTimesheets }
    readiness <- validateXeroTimesheetReadiness readinessRequest
    previewInput <- fetchPreviewInput readinessRequest connection
    enforceFinalWageEntries previewInput.previewTimesheetEntries >>= \case
        Left failures -> pure (Left (renderWageEntryFailures "Xero submission blocked: " failures))
        Right _ -> case buildXeroTimesheetPreviewRun previewInput of
            Left message -> pure (Left message)
            Right previewRun -> do
                reservations <- mapM (previewReservation connection) previewRun.previewRunTimesheets
                reviews <- reviewXeroTimesheetReservations reservations remoteTimesheets
                let reviewSnapshot = reconciliationReviewSnapshotJson reviews
                pure $ Right FreshSubmissionPlan
                    { freshPlanRequest = readinessRequest
                    , freshPlanReadiness = readiness
                    , freshPlanDuplicateSnapshot = duplicateSnapshotWithReview remoteTimesheets reviewSnapshot
                    , freshPlanPreviewRun = previewRun
                    , freshPlanReservations = reservations
                    , freshPlanReviewSnapshot = reviewSnapshot
                    }

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
            | xeroSubmissionIsSubmitted submission.status -> pure (Left "Xero timesheet submission has already been submitted.")
            | xeroSubmissionIsSuperseded submission.status -> pure (Left "Xero timesheet submission has been superseded by a newer attempt.")
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
                    fetchRemoteTimesheetsForDuplicateCheck
                        xeroClient
                        accessToken
                        refreshedConnection.tenantId
                        run.selectedPayrollCalendarId
                        run.payPeriodStart
                        run.payPeriodEnd >>= \case
                            Left message -> pure (Left message)
                            Right remoteTimesheets -> do
                                let readinessRequest =
                                        XeroTimesheetReadinessRequest
                                            { readinessVenueId = Id run.venueId
                                            , readinessPayrollCalendarId = run.selectedPayrollCalendarId
                                            , readinessPayrollCalendarName = run.selectedPayrollCalendarName
                                            , readinessSelectedPeriodKey = run.selectedPeriodKey
                                            , readinessPeriodStart = run.payPeriodStart
                                            , readinessPeriodEnd = run.payPeriodEnd
                                            , readinessPaymentDate = run.paymentDate
                                            , readinessXeroPayRunId = run.xeroPayRunId
                                            , readinessXeroPayRunStatus = run.xeroPayRunStatus
                                            , readinessRemoteTimesheets = remoteTimesheets
                                            , readinessSkippedStaffIds = []
                                            }
                                    duplicateSnapshot = duplicateCheckSnapshotJson remoteTimesheets
                                readiness <- validateXeroTimesheetReadiness readinessRequest
                                sourceEntries <- fetchRetrySubmissionSourceEntries submission
                                let scopedReadiness = scopeRetryReadinessToEntries sourceEntries readiness
                                _ <-
                                    run
                                        |> set #readinessSnapshotJson (xeroReadinessSnapshotJson scopedReadiness)
                                        |> set #xeroDuplicateCheckJson duplicateSnapshot
                                        |> updateRecord
                                retrySourceCheck <- enforceRetrySubmissionSources sourceEntries
                                updatedSubmission <-
                                    if not scopedReadiness.xeroTimesheetReady
                                        then markSubmissionBlocked submission (blockedReadinessSummary scopedReadiness)
                                        else case retrySourceCheck of
                                            Left message -> markSubmissionBlocked submission message
                                            Right () -> retrySubmissionAfterReconciliation xeroClient accessToken refreshedConnection submission remoteTimesheets
                                refreshRunStatus run
                                pure (Right updatedSubmission)

retrySubmissionAfterReconciliation ::
    (?modelContext :: ModelContext) =>
    XeroClient ->
    Text ->
    XeroConnection ->
    XeroTimesheetSubmission ->
    [XeroTimesheetRef] ->
    IO XeroTimesheetSubmission
retrySubmissionAfterReconciliation xeroClient accessToken connection submission remoteTimesheets =
    case persistedWriteOperation submission of
        Left message -> do
            now <- getCurrentTime
            markSubmissionFailed submission now message
        Right operation ->
            let scopedRemote = remoteTimesheetsForSubmission submission remoteTimesheets
                decision = reconcileXeroTimesheet Nothing scopedRemote
             in retryDecision operation scopedRemote decision
  where
    retryDecision operation scopedRemote decision =
        case decision of
            CreateXeroTimesheet ->
                case operation of
                    UpdateXeroTimesheetDraft priorTimesheetId -> continueWith (ReplaceMissingXeroTimesheetDraft priorTimesheetId)
                    InitialXeroTimesheetCreate -> execute operation
                    ReplaceMissingXeroTimesheetDraft _ -> execute operation
            UpdateXeroDraft timesheetId
                | xeroSubmissionIsInProgress submission.status
                , xeroTimesheetOperationCreatesTimesheet operation -> execute operation
                | otherwise -> continueWith (UpdateXeroTimesheetDraft timesheetId)
            blocked@BlockXeroNonDraft {} -> markSubmissionBlocked submission (reconciliationBlockedMessage blocked)
            blocked@BlockDistinctXeroTimesheets {} -> markSubmissionBlocked submission (reconciliationBlockedMessage blocked)
            blocked@BlockUnknownXeroStatus {} -> markSubmissionBlocked submission (reconciliationBlockedMessage blocked)
            blocked@BlockMissingXeroTimesheetId {} -> markSubmissionBlocked submission (reconciliationBlockedMessage blocked)
            ReplaceMissingXeroDraft _ -> markSubmissionBlocked submission "Xero retry reconciliation produced an invalid replacement decision."
            XeroSubmissionInProgress -> markSubmissionBlocked submission "Xero retry reconciliation produced an invalid in-progress decision."
      where
        execute selectedOperation = executeXeroTimesheetWrite initialWriteRecoveries xeroClient accessToken connection submission selectedOperation
        continueWith nextOperation = do
            transitioned <- transitionSubmissionOperation submission nextOperation
            executeXeroTimesheetWrite initialWriteRecoveries xeroClient accessToken connection transitioned nextOperation

fetchRetrySubmissionSourceEntries :: (?modelContext :: ModelContext) => XeroTimesheetSubmission -> IO [TimesheetEntry]
fetchRetrySubmissionSourceEntries submission = do
    links <- query @XeroTimesheetSubmissionEntry
        |> filterWhere (#xeroTimesheetSubmissionId, unpackId submission.id)
        |> fetch
    query @TimesheetEntry
        |> filterWhereIn (#id, map (Id . (.timesheetEntryId)) links)
        |> fetch

enforceRetrySubmissionSources :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Either Text ())
enforceRetrySubmissionSources entries = do
    let missingOrIneligible =
            null entries || any (\entry -> not entry.isApproved || isJust entry.deletedAt) entries
    if missingOrIneligible
        then pure (Left "Xero retry blocked: a recorded source entry is missing, unapproved, or deleted.")
        else enforceFinalWageEntries entries >>= \case
            Left failures -> pure (Left (renderWageEntryFailures "Xero retry blocked: " failures))
            Right _       -> pure (Right ())

scopeRetryReadinessToEntries :: [TimesheetEntry] -> XeroTimesheetReadiness -> XeroTimesheetReadiness
scopeRetryReadinessToEntries entries readiness =
    readiness
        { xeroTimesheetReady = null relevantBlockers
        , xeroReadinessBlockers = relevantBlockers
        , xeroReadinessWarnings = filter relevant readiness.xeroReadinessWarnings
        , xeroReadinessStaffCount = length (List.nub staffIds)
        , xeroReadinessEntryCount = length entries
        }
  where
    entryIds = map (unpackId . (.id)) entries
    staffIds = map (.staffId) entries
    relevant blocker =
        maybe True (`elem` entryIds) blocker.xeroBlockerTimesheetEntryId
            && maybe True (`elem` staffIds) blocker.xeroBlockerAffectedStaffId
    relevantBlockers = filter relevant readiness.xeroReadinessBlockers

persistAndSubmitPreview ::
    (?modelContext :: ModelContext) =>
    Id User ->
    Maybe (Id XeroTimesheetPreparationRun) ->
    XeroClient ->
    Text ->
    XeroConnection ->
    XeroTimesheetReadinessRequest ->
    XeroTimesheetReadiness ->
    Aeson.Value ->
    XeroTimesheetPreviewRun ->
    [XeroTimesheetReservation] ->
    IO (Either Text XeroTimesheetSubmissionPersistenceOutcome)
persistAndSubmitPreview submittedByUserId maybePreparationRunId xeroClient accessToken connection request readiness duplicateSnapshot previewRun reservations = do
    let runTemplate =
            newRecord @XeroSubmissionRun
                |> set #venueId (unpackId request.readinessVenueId)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #submittedByUserId (unpackId submittedByUserId)
                |> set #payPeriodStart request.readinessPeriodStart
                |> set #payPeriodEnd request.readinessPeriodEnd
                |> set #xeroTimesheetPreparationRunId maybePreparationRunId
                |> set #selectedPayrollCalendarId request.readinessPayrollCalendarId
                |> set #selectedPayrollCalendarName request.readinessPayrollCalendarName
                |> set #selectedPeriodKey request.readinessSelectedPeriodKey
                |> set #paymentDate request.readinessPaymentDate
                |> set #xeroPayRunId request.readinessXeroPayRunId
                |> set #xeroPayRunStatus request.readinessXeroPayRunStatus
                |> set #sourceKind ApprovedTimesheets
                |> set #status (if readiness.xeroTimesheetReady then XeroSubmissionRunStatusEnumPending else XeroSubmissionRunStatusEnumBlocked)
                |> set #previewPayloadJson (xeroTimesheetPreviewRunJson previewRun)
                |> set #readinessSnapshotJson (xeroReadinessSnapshotJson readiness)
                |> set #xeroDuplicateCheckJson duplicateSnapshot
                |> set #errorSummary (if readiness.xeroTimesheetReady then Nothing else Just (blockedReadinessSummary readiness))
    if not readiness.xeroTimesheetReady
        then Right . XeroTimesheetSubmissionPersisted <$> createRecord runTemplate
        else do
            reserveXeroTimesheetSubmissionRun runTemplate reservations request.readinessRemoteTimesheets >>= \case
                XeroTimesheetReservationsCreated run reservedSubmissions -> do
                    submitted <- mapM (submitExistingSubmission xeroClient accessToken connection) reservedSubmissions
                    completedAt <- getCurrentTime
                    let finalStatus = runStatusFromSubmissions submitted
                        errorSummary = submissionErrorSummary submitted
                        hasPendingSubmission = any (xeroSubmissionIsInProgress . (.status)) submitted
                    updatedRun <-
                        run
                            |> set #status finalStatus
                            |> set #submittedAt (Just completedAt)
                            |> set #completedAt (if hasPendingSubmission then Nothing else Just completedAt)
                            |> set #errorSummary errorSummary
                            |> updateRecord
                    pure (Right (XeroTimesheetSubmissionPersisted updatedRun))
                XeroTimesheetReservationsInProgress runIds -> pure (Right (XeroTimesheetSubmissionReservationInProgress runIds))
                XeroTimesheetReservationBlocked decision -> pure (Right (XeroTimesheetSubmissionReservationBlocked decision))
                XeroTimesheetReservationInvalid message -> pure (Left message)

previewReservation ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    XeroTimesheetPreview ->
    IO XeroTimesheetReservation
previewReservation connection preview = do
    sourceEntries <- fetchPreviewSourceEntries preview
    let staffId = case preview.previewStaffIds of
            staffIdValue : _ -> staffIdValue
            []              -> error "Xero timesheet preview has no source staff id."
    pure
        XeroTimesheetReservation
            { reservationConnectionId = unpackId connection.id
            , reservationStaffId = staffId
            , reservationXeroEmployeeId = preview.previewXeroEmployeeId
            , reservationPayPeriodStart = preview.previewPayPeriodStart
            , reservationPayPeriodEnd = preview.previewPayPeriodEnd
            , reservationRequestPayloadJson = xeroTimesheetSubmissionRequestJson preview
            , reservationSourceEntries = sourceEntries
            }

submitExistingSubmission ::
    (?modelContext :: ModelContext) =>
    XeroClient ->
    Text ->
    XeroConnection ->
    XeroTimesheetSubmission ->
    IO XeroTimesheetSubmission
submitExistingSubmission xeroClient accessToken connection submission =
    case persistedWriteOperation submission of
        Left message -> do
            now <- getCurrentTime
            markSubmissionFailed submission now message
        Right operation -> executeXeroTimesheetWrite initialWriteRecoveries xeroClient accessToken connection submission operation

persistedWriteOperation :: XeroTimesheetSubmission -> Either Text XeroTimesheetWriteOperation
persistedWriteOperation submission =
    xeroTimesheetWriteOperationFromPersistence
        submission.xeroEmployeeId
        submission.payPeriodStart
        submission.payPeriodEnd
        submission.idempotencyKey
        submission.requestPayloadJson

initialWriteRecoveries :: [XeroTimesheetWriteFailureAction]
initialWriteRecoveries = [RefetchAfterMissingUpdate, RefetchAfterCreateConflict]

executeXeroTimesheetWrite ::
    (?modelContext :: ModelContext) =>
    [XeroTimesheetWriteFailureAction] ->
    XeroClient ->
    Text ->
    XeroConnection ->
    XeroTimesheetSubmission ->
    XeroTimesheetWriteOperation ->
    IO XeroTimesheetSubmission
executeXeroTimesheetWrite allowedRecoveries xeroClient accessToken connection submission operation = do
    now <- getCurrentTime
    performXeroTimesheetWrite xeroClient accessToken connection submission operation >>= \case
        Right refs -> markSubmissionSubmitted submission now refs
        Left err ->
            case xeroTimesheetWriteFailureAction operation err of
                PreservePendingXeroTimesheetWrite -> markSubmissionPending submission now err
                FailXeroTimesheetWrite -> markSubmissionFailed submission now (xeroClientErrorText err)
                recoveryAction@RefetchAfterMissingUpdate
                    | recoveryAction `elem` allowedRecoveries -> recover recoveryAction err now
                    | otherwise -> markSubmissionFailed submission now (xeroClientErrorText err)
                recoveryAction@RefetchAfterCreateConflict
                    | recoveryAction `elem` allowedRecoveries -> recover recoveryAction err now
                    | otherwise -> markSubmissionFailed submission now (xeroClientErrorText err)
  where
    recover recoveryAction err now =
        recoverAfterProviderResponse
            (List.delete recoveryAction allowedRecoveries)
            xeroClient
            accessToken
            connection
            submission
            operation
            now
            err

performXeroTimesheetWrite ::
    XeroClient ->
    Text ->
    XeroConnection ->
    XeroTimesheetSubmission ->
    XeroTimesheetWriteOperation ->
    IO (Either XeroClientError [XeroTimesheetRef])
performXeroTimesheetWrite xeroClient accessToken connection submission operation =
    case operation of
        InitialXeroTimesheetCreate -> create
        UpdateXeroTimesheetDraft timesheetId ->
            updateTimesheet xeroClient accessToken connection.tenantId submission.idempotencyKey timesheetId submission.requestPayloadJson
        ReplaceMissingXeroTimesheetDraft _ -> create
  where
    create = createTimesheet xeroClient accessToken connection.tenantId submission.idempotencyKey submission.requestPayloadJson

recoverAfterProviderResponse ::
    (?modelContext :: ModelContext) =>
    [XeroTimesheetWriteFailureAction] ->
    XeroClient ->
    Text ->
    XeroConnection ->
    XeroTimesheetSubmission ->
    XeroTimesheetWriteOperation ->
    UTCTime ->
    XeroClientError ->
    IO XeroTimesheetSubmission
recoverAfterProviderResponse remainingRecoveries xeroClient accessToken connection submission operation now writeError = do
    run <- fetch (Id submission.xeroSubmissionRunId :: Id XeroSubmissionRun)
    fetchRemoteTimesheetsForDuplicateCheckResult
        xeroClient
        accessToken
        connection.tenantId
        run.selectedPayrollCalendarId
        submission.payPeriodStart
        submission.payPeriodEnd >>= \case
            Left fetchError ->
                markSubmissionFailed
                    submission
                    now
                    (xeroClientErrorText writeError <> " Reconciliation fetch failed: " <> xeroClientErrorText fetchError)
            Right remoteTimesheets ->
                recoverFromReconciliation
                    remainingRecoveries
                    xeroClient
                    accessToken
                    connection
                    submission
                    operation
                    now
                    writeError
                    (reconcileSubmissionRemoteState submission remoteTimesheets)

recoverFromReconciliation ::
    (?modelContext :: ModelContext) =>
    [XeroTimesheetWriteFailureAction] ->
    XeroClient ->
    Text ->
    XeroConnection ->
    XeroTimesheetSubmission ->
    XeroTimesheetWriteOperation ->
    UTCTime ->
    XeroClientError ->
    XeroTimesheetReconciliationDecision ->
    IO XeroTimesheetSubmission
recoverFromReconciliation remainingRecoveries xeroClient accessToken connection submission operation now writeError decision =
    case (operation, decision) of
        (UpdateXeroTimesheetDraft priorTimesheetId, CreateXeroTimesheet) ->
            continueWith (ReplaceMissingXeroTimesheetDraft priorTimesheetId)
        (_, UpdateXeroDraft timesheetId) -> continueWith (UpdateXeroTimesheetDraft timesheetId)
        (_, blocked@BlockXeroNonDraft {}) -> block blocked
        (_, blocked@BlockDistinctXeroTimesheets {}) -> block blocked
        (_, blocked@BlockUnknownXeroStatus {}) -> block blocked
        (_, blocked@BlockMissingXeroTimesheetId {}) -> block blocked
        (InitialXeroTimesheetCreate, CreateXeroTimesheet) -> failOriginal
        (ReplaceMissingXeroTimesheetDraft _, CreateXeroTimesheet) -> failOriginal
        (_, ReplaceMissingXeroDraft _) -> failOriginal
        (_, XeroSubmissionInProgress) -> failOriginal
  where
    continueWith nextOperation = do
        transitioned <- transitionSubmissionOperationAfterAttempt submission now writeError nextOperation
        executeXeroTimesheetWrite remainingRecoveries xeroClient accessToken connection transitioned nextOperation
    block blockedDecision = markSubmissionBlockedAfterAttempt submission writeError (reconciliationBlockedMessage blockedDecision)
    failOriginal = markSubmissionFailed submission now (xeroClientErrorText writeError)

reconcileSubmissionRemoteState :: XeroTimesheetSubmission -> [XeroTimesheetRef] -> XeroTimesheetReconciliationDecision
reconcileSubmissionRemoteState submission remoteTimesheets =
    reconcileXeroTimesheet Nothing (remoteTimesheetsForSubmission submission remoteTimesheets)

remoteTimesheetsForSubmission :: XeroTimesheetSubmission -> [XeroTimesheetRef] -> [XeroTimesheetRef]
remoteTimesheetsForSubmission submission = filter matches
  where
    matches remote =
        remote.xeroTimesheetEmployeeId == submission.xeroEmployeeId
            && remote.xeroTimesheetStartDate == submission.payPeriodStart
            && remote.xeroTimesheetEndDate == submission.payPeriodEnd

transitionSubmissionOperation ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetSubmission ->
    XeroTimesheetWriteOperation ->
    IO XeroTimesheetSubmission
transitionSubmissionOperation submission operation =
    submission
        |> set #status XeroTimesheetSubmissionStatusEnumPending
        |> set #idempotencyKey (operationIdempotencyKey submission operation)
        |> set #requestPayloadJson (xeroTimesheetRequestForOperation operation submission.requestPayloadJson)
        |> set #lastError Nothing
        |> updateRecord

transitionSubmissionOperationAfterAttempt ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetSubmission ->
    UTCTime ->
    XeroClientError ->
    XeroTimesheetWriteOperation ->
    IO XeroTimesheetSubmission
transitionSubmissionOperationAfterAttempt submission now writeError operation =
    submission
        |> set #status XeroTimesheetSubmissionStatusEnumPending
        |> set #idempotencyKey (operationIdempotencyKey submission operation)
        |> set #requestPayloadJson (xeroTimesheetRequestForOperation operation submission.requestPayloadJson)
        |> set #responsePayloadJson (Aeson.object ["error" Aeson..= xeroClientErrorText writeError])
        |> set #attemptCount (submission.attemptCount + 1)
        |> set #lastError (Just (xeroClientErrorText writeError))
        |> set #submittedAt (Just now)
        |> updateRecord

operationIdempotencyKey :: XeroTimesheetSubmission -> XeroTimesheetWriteOperation -> Text
operationIdempotencyKey submission =
    xeroTimesheetWriteIdempotencyKey submission.xeroEmployeeId submission.payPeriodStart submission.payPeriodEnd

xeroTimesheetSubmissionRequestJson :: XeroTimesheetPreview -> Aeson.Value
xeroTimesheetSubmissionRequestJson preview =
    Aeson.Array (Vector.fromList [preview.previewRequestObjectJson])

fetchPreviewSourceEntries :: (?modelContext :: ModelContext) => XeroTimesheetPreview -> IO [TimesheetEntry]
fetchPreviewSourceEntries preview =
    query @TimesheetEntry
        |> filterWhereIn (#id, map Id preview.previewSourceEntryIds)
        |> fetch

markSubmissionSubmitted :: (?modelContext :: ModelContext) => XeroTimesheetSubmission -> UTCTime -> [XeroTimesheetRef] -> IO XeroTimesheetSubmission
markSubmissionSubmitted submission now refs = do
    let maybeRef = List.find (\ref -> ref.xeroTimesheetEmployeeId == submission.xeroEmployeeId) refs <|> listToMaybe refs
    submission
        |> set #status XeroTimesheetSubmissionStatusEnumSubmitted
        |> set #responsePayloadJson (xeroTimesheetRefsResponseJson refs)
        |> set #xeroTimesheetId (maybeRef >>= (.xeroTimesheetId))
        |> set #xeroTimesheetStatus (maybeRef >>= (.xeroTimesheetStatus))
        |> set #attemptCount (submission.attemptCount + 1)
        |> set #lastError Nothing
        |> set #submittedAt (Just now)
        |> updateRecord

markSubmissionPending :: (?modelContext :: ModelContext) => XeroTimesheetSubmission -> UTCTime -> XeroClientError -> IO XeroTimesheetSubmission
markSubmissionPending submission now err =
    submission
        |> set #status XeroTimesheetSubmissionStatusEnumPending
        |> set #responsePayloadJson (Aeson.object ["error" Aeson..= xeroClientErrorText err, "outcome" Aeson..= ("indeterminate" :: Text)])
        |> set #attemptCount (submission.attemptCount + 1)
        |> set #lastError (Just (xeroClientErrorText err))
        |> set #submittedAt (Just now)
        |> updateRecord

markSubmissionFailed :: (?modelContext :: ModelContext) => XeroTimesheetSubmission -> UTCTime -> Text -> IO XeroTimesheetSubmission
markSubmissionFailed submission now message =
    submission
        |> set #status XeroTimesheetSubmissionStatusEnumFailed
        |> set #responsePayloadJson (Aeson.object ["error" Aeson..= message])
        |> set #attemptCount (submission.attemptCount + 1)
        |> set #lastError (Just message)
        |> set #submittedAt (Just now)
        |> updateRecord

markSubmissionBlockedAfterAttempt :: (?modelContext :: ModelContext) => XeroTimesheetSubmission -> XeroClientError -> Text -> IO XeroTimesheetSubmission
markSubmissionBlockedAfterAttempt submission writeError message =
    submission
        |> set #status XeroTimesheetSubmissionStatusEnumBlocked
        |> set #responsePayloadJson (Aeson.object ["error" Aeson..= message, "providerError" Aeson..= xeroClientErrorText writeError])
        |> set #attemptCount (submission.attemptCount + 1)
        |> set #lastError (Just message)
        |> updateRecord

markSubmissionBlocked :: (?modelContext :: ModelContext) => XeroTimesheetSubmission -> Text -> IO XeroTimesheetSubmission
markSubmissionBlocked submission message =
    submission
        |> set #status XeroTimesheetSubmissionStatusEnumBlocked
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
    let hasPendingSubmission = any (xeroSubmissionIsInProgress . (.status)) submissions
    run
        |> set #status (runStatusFromSubmissions submissions)
        |> set #submittedAt (Just now)
        |> set #completedAt (if hasPendingSubmission then Nothing else Just now)
        |> set #errorSummary (submissionErrorSummary submissions)
        |> updateRecord

runStatusFromSubmissions :: [XeroTimesheetSubmission] -> XeroSubmissionRunStatusEnum
runStatusFromSubmissions = xeroSubmissionRunStatusFromStatuses . map (.status)

submissionErrorSummary :: [XeroTimesheetSubmission] -> Maybe Text
submissionErrorSummary submissions =
    submissions
        |> filter (not . xeroSubmissionIsSuperseded . (.status))
        |> mapMaybe (.lastError)
        |> List.nub
        |> \case
            []     -> Nothing
            errors -> Just (Text.intercalate "\n" errors)

reconciliationBlockedMessage :: XeroTimesheetReconciliationDecision -> Text
reconciliationBlockedMessage CreateXeroTimesheet = "Xero timesheet reconciliation unexpectedly requested creation."
reconciliationBlockedMessage (UpdateXeroDraft _) = "Xero timesheet reconciliation unexpectedly requested an update."
reconciliationBlockedMessage (ReplaceMissingXeroDraft _) = "Xero timesheet reconciliation unexpectedly requested replacement."
reconciliationBlockedMessage XeroSubmissionInProgress = "Xero timesheet submission is already in progress."
reconciliationBlockedMessage (BlockXeroNonDraft _ status) = "Xero timesheet submission blocked because the provider status is " <> status <> "."
reconciliationBlockedMessage (BlockDistinctXeroTimesheets timesheetIds) = "Xero timesheet submission blocked because multiple provider timesheets matched: " <> Text.intercalate ", " timesheetIds <> "."
reconciliationBlockedMessage (BlockUnknownXeroStatus _ maybeStatus) = "Xero timesheet submission blocked because the provider status is unknown: " <> fromMaybe "missing" maybeStatus <> "."
reconciliationBlockedMessage (BlockMissingXeroTimesheetId _) = "Xero timesheet submission blocked because the provider timesheet id is missing."

blockedReadinessSummary :: XeroTimesheetReadiness -> Text
blockedReadinessSummary readiness =
    readiness.xeroReadinessBlockers
        |> map (.xeroBlockerMessage)
        |> List.nub
        |> Text.intercalate "\n"

fetchRemoteTimesheetsForDuplicateCheck :: XeroClient -> Text -> Text -> Maybe Text -> Day -> Day -> IO (Either Text [XeroTimesheetRef])
fetchRemoteTimesheetsForDuplicateCheck xeroClient accessToken tenantId maybeCalendarId periodStart periodEnd =
    fetchRemoteTimesheetsForDuplicateCheckResult xeroClient accessToken tenantId maybeCalendarId periodStart periodEnd
        |> fmap (Bifunctor.first (("Xero duplicate check failed: " <>) . xeroClientErrorText))

fetchRemoteTimesheetsForDuplicateCheckResult :: XeroClient -> Text -> Text -> Maybe Text -> Day -> Day -> IO (Either XeroClientError [XeroTimesheetRef])
fetchRemoteTimesheetsForDuplicateCheckResult xeroClient accessToken tenantId maybeCalendarId periodStart periodEnd =
    fetchTimesheetsForPeriod xeroClient accessToken tenantId maybeCalendarId periodStart periodEnd

duplicateCheckSnapshotJson :: [XeroTimesheetRef] -> Aeson.Value
duplicateCheckSnapshotJson refs =
    Aeson.object
        [ "remoteTimesheetCount" Aeson..= length refs
        , "remoteTimesheets" Aeson..= map xeroTimesheetRefJson refs
        ]

duplicateSnapshotWithReview :: [XeroTimesheetRef] -> Aeson.Value -> Aeson.Value
duplicateSnapshotWithReview refs reviewSnapshot =
    case duplicateCheckSnapshotJson refs of
        Aeson.Object object -> Aeson.Object (AesonKeyMap.insert "reconciliationReview" reviewSnapshot object)
        value -> value

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
