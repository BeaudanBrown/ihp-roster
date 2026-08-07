{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

-- | Atomic local reservation boundary for Xero timesheet writes.
-- Provider calls must happen only after this module returns a created outcome.
module Application.Xero.Timesheets.Reservation
    ( XeroTimesheetReservation (..)
    , XeroTimesheetReservationOutcome (..)
    , reserveXeroTimesheetSubmissionRun
    ) where

import Application.Helper.Xero.Types (XeroTimesheetRef (..))
import Application.Xero.Timesheets.Reconciliation
import Application.Xero.WorkflowState (xeroSubmissionIsInProgress)
import qualified Control.Exception as Exception
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import qualified Database.PostgreSQL.Simple as PG
import Generated.Types
import qualified Hasql.Errors as Hasql
import IHP.ControllerPrelude
import IHP.ModelSupport.Types (HasqlSessionError (..))

data XeroTimesheetReservation = XeroTimesheetReservation
    { reservationConnectionId       :: !UUID
    , reservationStaffId            :: !UUID
    , reservationXeroEmployeeId     :: !Text
    , reservationPayPeriodStart     :: !Day
    , reservationPayPeriodEnd       :: !Day
    , reservationIdempotencyKey     :: !Text
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
                    mapM_ lockReservation (List.sortOn reservationLockKey reservations)
                    reserveInCurrentTransaction runTemplate reservations remoteTimesheets
            case result of
                Right outcome -> pure outcome
                Left sessionError
                    | isUniqueViolation sessionError -> recoverExpectedUniqueRace sessionError reservations
                    | otherwise -> Exception.throwIO sessionError

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
    existing <- fetchActiveReservation reservation
    let local = existingSubmission <$> existing
        scopedRemote = filter (remoteMatchesReservation reservation) remoteTimesheets
        decision = reconcileXeroTimesheet local scopedRemote
    pure (reservation, existing, decision)

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
    case decision of
        CreateXeroTimesheet       -> supersedeExisting existing
        UpdateXeroDraft _         -> supersedeExisting existing
        ReplaceMissingXeroDraft _ -> supersedeExisting existing
        XeroSubmissionInProgress  -> error "In-progress Xero reservation reached persistence"
        BlockXeroNonDraft {}      -> error "Blocked Xero reservation reached persistence"
        BlockDistinctXeroTimesheets {} -> error "Blocked Xero reservation reached persistence"
        BlockUnknownXeroStatus {} -> error "Blocked Xero reservation reached persistence"
        BlockMissingXeroTimesheetId {} -> error "Blocked Xero reservation reached persistence"
    submission <-
        newRecord @XeroTimesheetSubmission
            |> set #xeroSubmissionRunId (unpackId run.id)
            |> set #venueId run.venueId
            |> set #xeroConnectionId run.xeroConnectionId
            |> set #staffId reservation.reservationStaffId
            |> set #xeroEmployeeId reservation.reservationXeroEmployeeId
            |> set #payPeriodStart reservation.reservationPayPeriodStart
            |> set #payPeriodEnd reservation.reservationPayPeriodEnd
            |> set #status XeroTimesheetSubmissionStatusEnumPending
            |> set #idempotencyKey reservation.reservationIdempotencyKey
            |> set #requestPayloadJson reservation.reservationRequestPayloadJson
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
        _ -> error "Xero reservation source entry is not approval-version locked"

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
        sqlQuery
            "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS xero_timesheet_reservation_lock"
            (PG.Only (reservationLockKey reservation))
    unless (locked == [PG.Only True]) do
        error "Unable to lock Xero timesheet reservation"

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

isUniqueViolation :: HasqlSessionError -> Bool
isUniqueViolation (HasqlSessionError sessionError) =
    case sessionError of
        Hasql.StatementSessionError _ _ _ _ _ statementError -> statementErrorIsUniqueViolation statementError
        Hasql.ScriptSessionError _ serverError -> serverErrorIsUniqueViolation serverError
        Hasql.ConnectionSessionError _ -> False
        Hasql.MissingTypesSessionError _ -> False
        Hasql.DriverSessionError _ -> False
  where
    statementErrorIsUniqueViolation (Hasql.ServerStatementError serverError) = serverErrorIsUniqueViolation serverError
    statementErrorIsUniqueViolation (Hasql.UnexpectedRowCountStatementError _ _ _) = False
    statementErrorIsUniqueViolation (Hasql.UnexpectedColumnCountStatementError _ _) = False
    statementErrorIsUniqueViolation (Hasql.UnexpectedColumnTypeStatementError _ _ _) = False
    statementErrorIsUniqueViolation (Hasql.RowStatementError _ _) = False
    statementErrorIsUniqueViolation (Hasql.UnexpectedResultStatementError _) = False

    serverErrorIsUniqueViolation (Hasql.ServerError code _ _ _ _) = code == "23505"

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
        []    -> Exception.throwIO sessionError
  where
    pendingRunId submission
        | xeroSubmissionIsInProgress submission.status = Just (Id submission.xeroSubmissionRunId)
        | otherwise = Nothing
