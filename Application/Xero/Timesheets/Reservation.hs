{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

-- | Atomic local reservation boundary for Xero timesheet writes.
-- Provider calls must happen only after this module returns a created outcome.
module Application.Xero.Timesheets.Reservation
    ( XeroTimesheetReservation (..)
    , XeroTimesheetReservationOutcome (..)
    , failAbandonedXeroTimesheetSubmissionsForPeriod
    , reserveXeroTimesheetSubmissionRun
    , reviewXeroTimesheetReservations
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..),
                                  externalRuntimeInvariantFailure,
                                  throwExternalRuntime)
import Application.Helper.Hasql (isUniqueViolation)
import Application.Helper.Xero.Types (XeroTimesheetRef (..))
import Application.Xero.Timesheets.ProviderWrite
import Application.Xero.Timesheets.Reconciliation
import Application.Xero.Timesheets.ReconciliationReview
import Application.Xero.WorkflowState (xeroSubmissionIsInProgress,
                                       xeroSubmissionIsSuperseded,
                                       xeroSubmissionRunStatusFromStatuses)
import qualified Control.Exception as Exception
import Control.Monad (guard, void)
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Traversable (traverse)
import qualified Data.UUID.V4 as UUIDv4
import qualified Database.PostgreSQL.Simple as PG
import Generated.Types
import IHP.ControllerPrelude

data XeroTimesheetReservation = XeroTimesheetReservation
    { reservationConnectionId       :: !UUID
    , reservationStaffId            :: !UUID
    , reservationXeroEmployeeId     :: !Text
    , reservationPayPeriodStart     :: !Day
    , reservationPayPeriodEnd       :: !Day
    , reservationRequestPayloadJson :: !Aeson.Value
    , reservationSourceEntries      :: ![TimesheetEntry]
    }
    deriving (Eq, Show)

data XeroTimesheetReservationOutcome
    = XeroTimesheetReservationsCreated !XeroSubmissionRun ![XeroTimesheetSubmission]
    | XeroTimesheetReservationsInProgress ![Id XeroSubmissionRun]
    | XeroTimesheetReservationBlocked !XeroTimesheetReconciliationDecision
    | XeroTimesheetReservationInvalid !Text
    deriving (Eq, Show)

reviewXeroTimesheetReservations ::
    (?modelContext :: ModelContext) =>
    [XeroTimesheetReservation] ->
    [XeroTimesheetRef] ->
    IO [XeroTimesheetReconciliationReview]
reviewXeroTimesheetReservations reservations remoteTimesheets = do
    reconciliations <- mapM (reconcileReservation remoteTimesheets) reservations
    pure $ map toReview reconciliations
  where
    toReview (reservation, _, decision) =
        XeroTimesheetReconciliationReview
            { reconciliationReviewEmployeeId = reservation.reservationXeroEmployeeId
            , reconciliationReviewDecision = decision
            }

reserveXeroTimesheetSubmissionRun ::
    (?modelContext :: ModelContext) =>
    XeroSubmissionRun ->
    [XeroTimesheetReservation] ->
    [XeroTimesheetRef] ->
    IO XeroTimesheetReservationOutcome
reserveXeroTimesheetSubmissionRun runTemplate reservations remoteTimesheets =
    case validateReservations runTemplate reservations of
        Just message -> pure (XeroTimesheetReservationInvalid message)
        Nothing -> do
            result :: Either HasqlSessionError XeroTimesheetReservationOutcome <-
                Exception.try $ withTransaction do
                    lockReservationSourceEntries reservations >>= \case
                        Left message -> pure (XeroTimesheetReservationInvalid message)
                        Right lockedReservations -> do
                            mapM_ lockReservation (List.sortOn reservationLockKey lockedReservations)
                            reserveInCurrentTransaction runTemplate lockedReservations remoteTimesheets
            case result of
                Right outcome -> pure outcome
                Left sessionError
                    | isUniqueViolation sessionError -> recoverExpectedUniqueRace sessionError reservations
                    | otherwise -> throwExternalRuntime sessionError

lockReservationSourceEntries ::
    (?modelContext :: ModelContext) =>
    [XeroTimesheetReservation] ->
    IO (Either Text [XeroTimesheetReservation])
lockReservationSourceEntries reservations = do
    let expectedEntries = concatMap (.reservationSourceEntries) reservations
        entryIds = List.sort (List.nub (map (unpackId . (.id)) expectedEntries))
    lockedIds <- fmap concat $ forM entryIds \entryId ->
        unsafeSqlQuery
            "SELECT id FROM timesheet_entries WHERE id = ? FOR UPDATE"
            (PG.Only entryId)
    lockedEntries <- if null lockedIds
        then pure []
        else query @TimesheetEntry
            |> filterWhereIn (#id, [Id entryId | PG.Only entryId <- lockedIds])
            |> fetch
    let lockedById = Map.fromList [(unpackId entry.id, entry) | entry <- lockedEntries]
        identityMatches expected current =
            current.isApproved
                && current.activePayCalculationId == expected.activePayCalculationId
                && current.approvedAt == expected.approvedAt
                && current.staffPayVersionId == expected.staffPayVersionId
                && current.shiftTypePayVersionId == expected.shiftTypePayVersionId
        replaceExpected expected = do
            current <- Map.lookup (unpackId expected.id) lockedById
            guard (identityMatches expected current)
            pure current
        replaceReservation reservation = do
            lockedSources <- traverse replaceExpected reservation.reservationSourceEntries
            pure reservation { reservationSourceEntries = lockedSources }
    pure case traverse replaceReservation reservations of
        Nothing -> Left "A Timesheet approval changed before Xero submission reservation. Refresh preparation and review it again."
        Just lockedReservations -> Right lockedReservations

validateReservations :: XeroSubmissionRun -> [XeroTimesheetReservation] -> Maybe Text
validateReservations runTemplate reservations
    | null reservations = Just "Xero submission requires at least one timesheet reservation."
    | any (null . (.reservationSourceEntries)) reservations = Just "Every Xero timesheet reservation requires source entries."
    | any ((/= runTemplate.xeroConnectionId) . (.reservationConnectionId)) reservations = Just "Xero timesheet reservation connection does not match its run."
    | any ((/= runTemplate.payPeriodStart) . (.reservationPayPeriodStart)) reservations = Just "Xero timesheet reservation start date does not match its run."
    | any ((/= runTemplate.payPeriodEnd) . (.reservationPayPeriodEnd)) reservations = Just "Xero timesheet reservation end date does not match its run."
    | length lockKeys /= length (List.nub lockKeys) = Just "Xero submission contains duplicate employee-period reservations."
    | otherwise = Nothing
  where
    lockKeys = map reservationLockKey reservations

reserveInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    XeroSubmissionRun ->
    [XeroTimesheetReservation] ->
    [XeroTimesheetRef] ->
    IO XeroTimesheetReservationOutcome
reserveInCurrentTransaction runTemplate reservations remoteTimesheets = do
    reconciliations <- mapM (reconcileReservation remoteTimesheets) reservations
    case inProgressRunIds reconciliations of
        runIds@(_ : _)
            | allReservationsInProgress reconciliations -> pure (XeroTimesheetReservationsInProgress runIds)
            | otherwise -> pure (XeroTimesheetReservationInvalid "Xero submission contains a mix of pending and unreserved employee periods.")
        [] ->
            case firstBlockedDecision reconciliations of
                Just decision -> pure (XeroTimesheetReservationBlocked decision)
                Nothing -> do
                    run <- runTemplate |> createRecord
                    submissions <- mapM (persistReservation run) reconciliations
                    pure (XeroTimesheetReservationsCreated run submissions)

allReservationsInProgress ::
    [(XeroTimesheetReservation, Maybe XeroTimesheetSubmission, XeroTimesheetReconciliationDecision)] ->
    Bool
allReservationsInProgress = all (\(_, _, decision) -> decision == XeroSubmissionInProgress)

reconcileReservation ::
    (?modelContext :: ModelContext) =>
    [XeroTimesheetRef] ->
    XeroTimesheetReservation ->
    IO (XeroTimesheetReservation, Maybe XeroTimesheetSubmission, XeroTimesheetReconciliationDecision)
reconcileReservation remoteTimesheets reservation = do
    active <- fetchActiveReservation reservation
    existing <- mapM failAbandonedPendingSubmission active
    let local = existingSubmission <$> existing
        scopedRemote = filter (remoteMatchesReservation reservation) remoteTimesheets
        decision = reconcileXeroTimesheet local scopedRemote
    pure (reservation, existing, decision)

stalePendingTimeout :: NominalDiffTime
stalePendingTimeout = 120

failAbandonedXeroTimesheetSubmissionsForPeriod ::
    (?modelContext :: ModelContext) =>
    UUID ->
    Day ->
    Day ->
    IO ()
failAbandonedXeroTimesheetSubmissionsForPeriod connectionId periodStart periodEnd = do
    pendingSubmissions <-
        query @XeroTimesheetSubmission
            |> filterWhere (#xeroConnectionId, connectionId)
            |> filterWhere (#payPeriodStart, periodStart)
            |> filterWhere (#payPeriodEnd, periodEnd)
            |> filterWhere (#status, XeroTimesheetSubmissionStatusEnumPending)
            |> fetch
    void (mapM failAbandonedPendingSubmission pendingSubmissions)

abandonedPendingMessage :: Text
abandonedPendingMessage =
    "Bepis could not confirm whether Xero received this timesheet because the submission was interrupted. Check Xero, then start a fresh preparation to retry."

failAbandonedPendingSubmission ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetSubmission ->
    IO XeroTimesheetSubmission
failAbandonedPendingSubmission submission
    | not (xeroSubmissionIsInProgress submission.status) = pure submission
    | otherwise = do
        now <- getCurrentTime
        if diffUTCTime now submission.updatedAt < stalePendingTimeout
            then pure submission
            else do
                failed <-
                    submission
                        |> set #status XeroTimesheetSubmissionStatusEnumFailed
                        |> set #responsePayloadJson (Aeson.object ["error" Aeson..= abandonedPendingMessage, "outcome" Aeson..= ("uncertain" :: Text)])
                        |> set #lastError (Just abandonedPendingMessage)
                        |> set #submittedAt (Just now)
                        |> updateRecord
                refreshAbandonedSubmissionRun now failed
                pure failed

refreshAbandonedSubmissionRun ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    XeroTimesheetSubmission ->
    IO ()
refreshAbandonedSubmissionRun now failedSubmission = do
    let runId = Id failedSubmission.xeroSubmissionRunId :: Id XeroSubmissionRun
    run <- fetch runId
    submissions <-
        query @XeroTimesheetSubmission
            |> filterWhere (#xeroSubmissionRunId, failedSubmission.xeroSubmissionRunId)
            |> fetch
    let activeSubmissions = filter (not . xeroSubmissionIsSuperseded . (.status)) submissions
        hasPending = any (xeroSubmissionIsInProgress . (.status)) activeSubmissions
        errors = List.nub (mapMaybe (.lastError) activeSubmissions)
    void $
        run
            |> set #status (xeroSubmissionRunStatusFromStatuses (map (.status) submissions))
            |> set #completedAt (if hasPending then Nothing else Just now)
            |> set #errorSummary (if null errors then Nothing else Just (Text.intercalate "\n" errors))
            |> updateRecord

existingSubmission :: XeroTimesheetSubmission -> ExistingXeroTimesheetSubmission
existingSubmission submission =
    ExistingXeroTimesheetSubmission
        { existingSubmissionStatus = submission.status
        , existingSubmissionTimesheetId = submission.xeroTimesheetId
        , existingSubmissionTimesheetStatus = submission.xeroTimesheetStatus
        }

remoteMatchesReservation :: XeroTimesheetReservation -> XeroTimesheetRef -> Bool
remoteMatchesReservation reservation remote =
    remote.xeroTimesheetEmployeeId == reservation.reservationXeroEmployeeId
        && remote.xeroTimesheetStartDate == reservation.reservationPayPeriodStart
        && remote.xeroTimesheetEndDate == reservation.reservationPayPeriodEnd

inProgressRunIds ::
    [(XeroTimesheetReservation, Maybe XeroTimesheetSubmission, XeroTimesheetReconciliationDecision)] ->
    [Id XeroSubmissionRun]
inProgressRunIds reconciliations =
    reconciliations
        |> mapMaybe (\(_, existing, decision) -> inProgressRunId existing decision)
        |> List.nub
        |> List.sort

inProgressRunId ::
    Maybe XeroTimesheetSubmission ->
    XeroTimesheetReconciliationDecision ->
    Maybe (Id XeroSubmissionRun)
inProgressRunId (Just submission) XeroSubmissionInProgress =
    Just (Id submission.xeroSubmissionRunId)
inProgressRunId _ _ = Nothing

firstBlockedDecision ::
    [(XeroTimesheetReservation, Maybe XeroTimesheetSubmission, XeroTimesheetReconciliationDecision)] ->
    Maybe XeroTimesheetReconciliationDecision
firstBlockedDecision reconciliations =
    listToMaybe $ mapMaybe (\(_, _, decision) -> classify decision) reconciliations
  where
    classify decision =
        case decision of
            CreateXeroTimesheet                    -> Nothing
            UpdateXeroDraft _                      -> Nothing
            ReplaceMissingXeroDraft _              -> Nothing
            XeroSubmissionInProgress               -> Nothing
            blocked@BlockXeroNonDraft {}           -> Just blocked
            blocked@BlockDistinctXeroTimesheets {} -> Just blocked
            blocked@BlockUnknownXeroStatus {}      -> Just blocked
            blocked@BlockMissingXeroTimesheetId {} -> Just blocked

persistReservation ::
    (?modelContext :: ModelContext) =>
    XeroSubmissionRun ->
    (XeroTimesheetReservation, Maybe XeroTimesheetSubmission, XeroTimesheetReconciliationDecision) ->
    IO XeroTimesheetSubmission
persistReservation run (reservation, existing, decision) = do
    operation <-
        case xeroTimesheetOperationForDecision decision of
            Just value -> pure value
            Nothing -> externalRuntimeInvariantFailure ProviderRuntimeInvariant "Non-write Xero reconciliation decision reached reservation persistence"
    supersedeExisting existing
    submissionId <- UUIDv4.nextRandom
    let idempotencyKey = xeroTimesheetWriteIdempotencyKey submissionId 0 operation
        requestPayload = xeroTimesheetRequestForOperation operation reservation.reservationRequestPayloadJson
    submission <-
        newRecord @XeroTimesheetSubmission
            |> set #id (Id submissionId)
            |> set #xeroSubmissionRunId (unpackId run.id)
            |> set #venueId run.venueId
            |> set #xeroConnectionId run.xeroConnectionId
            |> set #staffId reservation.reservationStaffId
            |> set #xeroEmployeeId reservation.reservationXeroEmployeeId
            |> set #payPeriodStart reservation.reservationPayPeriodStart
            |> set #payPeriodEnd reservation.reservationPayPeriodEnd
            |> set #status XeroTimesheetSubmissionStatusEnumPending
            |> set #idempotencyKey idempotencyKey
            |> set #requestPayloadJson requestPayload
            |> createRecord
    mapM_ (insertSubmissionEntry submission) reservation.reservationSourceEntries
    pure submission

supersedeExisting ::
    (?modelContext :: ModelContext) =>
    Maybe XeroTimesheetSubmission ->
    IO ()
supersedeExisting Nothing = pure ()
supersedeExisting (Just submission) =
    void (submission |> set #status XeroTimesheetSubmissionStatusEnumSuperseded |> updateRecord)

insertSubmissionEntry ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetSubmission ->
    TimesheetEntry ->
    IO ()
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
        _ -> externalRuntimeInvariantFailure ProviderRuntimeInvariant "Xero reservation source entry is not approval-version locked"

fetchActiveReservation ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetReservation ->
    IO (Maybe XeroTimesheetSubmission)
fetchActiveReservation reservation =
    query @XeroTimesheetSubmission
        |> filterWhere (#xeroConnectionId, reservation.reservationConnectionId)
        |> filterWhere (#xeroEmployeeId, reservation.reservationXeroEmployeeId)
        |> filterWhere (#payPeriodStart, reservation.reservationPayPeriodStart)
        |> filterWhere (#payPeriodEnd, reservation.reservationPayPeriodEnd)
        |> filterWhereNot (#status, XeroTimesheetSubmissionStatusEnumSuperseded)
        |> fetchOneOrNothing

lockReservation ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetReservation ->
    IO ()
lockReservation reservation = do
    locked :: [PG.Only Bool] <-
        unsafeSqlQuery
            "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS xero_timesheet_reservation_lock"
            (PG.Only (reservationLockKey reservation))
    unless (locked == [PG.Only True]) do
        externalRuntimeInvariantFailure ProviderRuntimeInvariant "Unable to lock Xero timesheet reservation"

reservationLockKey :: XeroTimesheetReservation -> Text
reservationLockKey reservation =
    Text.intercalate
        ":"
        [ "xero-timesheet-reservation"
        , tshow reservation.reservationConnectionId
        , Text.take 128 (Text.toCaseFold reservation.reservationXeroEmployeeId)
        , tshow reservation.reservationPayPeriodStart
        , tshow reservation.reservationPayPeriodEnd
        ]

recoverExpectedUniqueRace ::
    (?modelContext :: ModelContext) =>
    HasqlSessionError ->
    [XeroTimesheetReservation] ->
    IO XeroTimesheetReservationOutcome
recoverExpectedUniqueRace sessionError reservations = do
    active <- mapM fetchActiveReservation reservations
    let pendingRunIds =
            active
                |> mapMaybe (\submission -> submission >>= pendingRunId)
                |> List.nub
                |> List.sort
    case pendingRunIds of
        _ : _ -> pure (XeroTimesheetReservationsInProgress pendingRunIds)
        []    -> throwExternalRuntime sessionError
  where
    pendingRunId submission
        | xeroSubmissionIsInProgress submission.status = Just (Id submission.xeroSubmissionRunId)
        | otherwise = Nothing
