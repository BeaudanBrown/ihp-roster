{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.TimesheetApproval
    ( ApprovalEngineMode (..)
    , ApprovalEngineResult (..)
    , ExpectedApprovalIdentity (..)
    , TimesheetApprovalError (..)
    , refreshProblemApproval
    , refreshProblemApprovalWithAudit
    , runApprovalEngineInCurrentTransaction
    ) where

import Application.Error.Domain (projectDomainError)
import Application.Error.ExternalRuntime (throwExternalRuntime)
import Application.Error.Types (AppResult)
import Application.Helper.Audit (recordAuditEvent, recordTimesheetEntryVersion,
                                 timesheetEntrySnapshot)
import Application.Helper.Audit.Vocabulary (AuditEventType (TimesheetApprovedAudit),
                                            AuditSourceChannel (WebAuditSource))
import Application.Helper.Pay (ensurePayVersionsForTimesheetApproval,
                               lockPayVersionsForApproval,
                               payVersionManifestForEntry)
import Application.Helper.TimesheetPayLedger (persistApprovedTimesheetPayCalculation)
import Application.TimesheetApproval.Error (TimesheetApprovalError (..))
import Application.VenueTime.Model (decodeTimesheetTiming)
import Application.WageSourceEnforcement (enforceFinalWageEntries)
import qualified Control.Exception as Exception
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as AesonKeyMap
import Data.Time.Clock (UTCTime, getCurrentTime)
import Data.Tuple.Only (Only (..))
import Data.UUID (UUID)
import Generated.Types
import qualified Hasql.Errors as Hasql
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlExecDiscardResult, sqlQuery)
import IHP.ModelSupport.Types (HasqlSessionError (..))

-- The expected identity is rendered into each entry-specific Xero blocker.
data ExpectedApprovalIdentity = ExpectedApprovalIdentity
    { expectedActiveCalculationId :: !UUID
    , expectedApprovedAt          :: !UTCTime
    }
    deriving (Eq, Show)

data ApprovalEngineMode
    = InitialApproval
    | RefreshProblemApproval !ExpectedApprovalIdentity
    deriving (Eq, Show)

data ApprovalEngineResult = ApprovalEngineResult
    { approvalEngineEntry              :: !TimesheetEntry
    , approvalEnginePriorCalculationId :: !(Maybe UUID)
    , approvalEngineNewCalculationId   :: !UUID
    , approvalEngineChanged            :: !Bool
    }
    deriving (Eq, Show)

newtype ApprovalEngineException = ApprovalEngineException TimesheetApprovalError
    deriving (Show)

instance Exception.Exception ApprovalEngineException

refreshProblemApproval ::
    (?modelContext :: ModelContext) =>
    Id User ->
    Id Venue ->
    Id TimesheetEntry ->
    ExpectedApprovalIdentity ->
    IO (AppResult ApprovalEngineResult)
refreshProblemApproval actorUserId venueId entryId expected =
    refreshProblemApprovalWithAudit actorUserId venueId entryId expected (\payload -> payload) WebAuditSource

refreshProblemApprovalWithAudit ::
    (?modelContext :: ModelContext) =>
    Id User ->
    Id Venue ->
    Id TimesheetEntry ->
    ExpectedApprovalIdentity ->
    (Aeson.Value -> Aeson.Value) ->
    AuditSourceChannel ->
    IO (AppResult ApprovalEngineResult)
refreshProblemApprovalWithAudit actorUserId venueId entryId expected enrichAuditPayload auditSourceChannel = do
    result <- Exception.try @HasqlSessionError $ Exception.try @ApprovalEngineException $ withTransaction do
        -- A refresh may wait briefly for a concurrent refresh or reservation.
        sqlExecDiscardResult "SET LOCAL lock_timeout = '5s'" ()
        maybeEntry <- query @TimesheetEntry |> filterWhere (#id, entryId) |> fetchOneOrNothing
        entry <- maybe (Exception.throwIO (ApprovalEngineException ApprovalEntryUnavailable)) pure maybeEntry
        when (entry.venueId /= unpackId venueId) (Exception.throwIO (ApprovalEngineException ApprovalEntryUnavailable))
        runApprovalEngineInCurrentTransaction actorUserId (RefreshProblemApproval expected) enrichAuditPayload auditSourceChannel entry >>= \case
            Left approvalError -> Exception.throwIO (ApprovalEngineException approvalError)
            Right approvalResult -> pure approvalResult
    case result of
        Right (Right approvalResult) -> pure (Right approvalResult)
        Right (Left (ApprovalEngineException approvalError)) -> pure (Left (projectDomainError approvalError))
        Left sessionError
            | isLockTimeout sessionError -> pure (Left (projectDomainError ApprovalRefreshLockTimedOut))
            | otherwise -> throwExternalRuntime sessionError

runApprovalEngineInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    Id User ->
    ApprovalEngineMode ->
    (Aeson.Value -> Aeson.Value) ->
    AuditSourceChannel ->
    TimesheetEntry ->
    IO (Either TimesheetApprovalError ApprovalEngineResult)
runApprovalEngineInCurrentTransaction actorUserId mode enrichAuditPayload auditSourceChannel entry = do
    lockedEntryIds :: [Only UUID] <- sqlQuery
        "SELECT id FROM timesheet_entries WHERE id = ? ORDER BY id FOR UPDATE"
        (Only (unpackId entry.id))
    case listToMaybe lockedEntryIds of
        Nothing -> pure (Left ApprovalEntryUnavailable)
        Just (Only lockedEntryId) -> fetch (Id lockedEntryId :: Id TimesheetEntry) >>= runLocked
  where
    runLocked lockedEntry =
        case decodeTimesheetTiming lockedEntry of
            Left _ -> pure (Left ApprovalStillBlocked)
            Right timing ->
                validateMode lockedEntry >>= \case
                    Left approvalError -> pure (Left approvalError)
                    Right (Just healthyResult) -> pure (Right healthyResult)
                    Right Nothing -> do
                        activeWrite <- hasActiveProviderWrite lockedEntry.id
                        if activeWrite
                            then pure (Left ApprovalProviderWriteActive)
                            else replaceValidatedApproval timing lockedEntry

    validateMode lockedEntry = case mode of
        InitialApproval ->
            case (lockedEntry.isApproved, lockedEntry.activePayCalculationId) of
                (True, Just calculationId) -> pure (Right (Just (unchangedResult lockedEntry calculationId)))
                _ -> pure (Right Nothing)
        RefreshProblemApproval expected
            | not lockedEntry.isApproved -> pure (Left ApprovalControlStale)
            | approvalIdentity lockedEntry == Just expected -> pure (Right Nothing)
            | otherwise -> do
                healthy <- (&&) <$> approvalCalculationComplete lockedEntry <*> approvalWasXeroRefreshFrom expected lockedEntry
                pure if healthy
                    then case lockedEntry.activePayCalculationId of
                        Just calculationId -> Right (Just (unchangedResult lockedEntry calculationId))
                        Nothing -> Left ApprovalControlStale
                    else Left ApprovalControlStale

    unchangedResult lockedEntry calculationId = ApprovalEngineResult
        { approvalEngineEntry = lockedEntry
        , approvalEnginePriorCalculationId = Just (unpackId calculationId)
        , approvalEngineNewCalculationId = unpackId calculationId
        , approvalEngineChanged = False
        }

    replaceValidatedApproval timing lockedEntry = do
        now <- getCurrentTime
        (staffPayVersion, shiftTypePayVersion) <- ensurePayVersionsForTimesheetApproval actorUserId timing lockedEntry
        lockPayVersionsForApproval actorUserId now staffPayVersion shiftTypePayVersion
        let approvalEntry = lockedEntry
                |> set #isApproved True
                |> set #staffPayVersionId (Just (unpackId staffPayVersion.id))
                |> set #shiftTypePayVersionId (Just (unpackId shiftTypePayVersion.id))
                |> set #approvedAt (Just now)
                |> set #approvedByUserId (Just (unpackId actorUserId))
                |> set #updatedAt now
            priorCalculationId = fmap unpackId lockedEntry.activePayCalculationId
        enforceFinalWageEntries [approvalEntry |> set #isApproved False] >>= \case
            Left _ -> pure (Left ApprovalStillBlocked)
            Right _ -> persistApprovedTimesheetPayCalculation approvalEntry >>= \case
                Left _ -> pure (Left ApprovalStillBlocked)
                Right calculation -> do
                    complete <- case mode of
                        InitialApproval -> pure True
                        RefreshProblemApproval _ -> replacementXeroMappingComplete calculation.id
                    if not complete
                        then pure (Left ApprovalStillBlocked)
                        else do
                            activeEntry <- approvalEntry
                                |> set #activePayCalculationId (Just calculation.id)
                                |> updateRecord
                            let source = case mode of
                                    InitialApproval -> "initial_approval" :: Text
                                    RefreshProblemApproval _ -> "xero_preparation_refresh"
                                payload = enrichAuditPayload $ Aeson.object
                                    [ "previous" Aeson..= timesheetEntrySnapshot lockedEntry
                                    , "staffId" Aeson..= lockedEntry.staffId
                                    , "startsAt" Aeson..= lockedEntry.startsAt
                                    , "timezone" Aeson..= lockedEntry.timezone
                                    , "wasApproved" Aeson..= lockedEntry.isApproved
                                    , "payConfigVersionManifest" Aeson..= payVersionManifestForEntry activeEntry
                                    , "approvedAt" Aeson..= now
                                    , "priorCalculationId" Aeson..= priorCalculationId
                                    , "priorApprovedAt" Aeson..= lockedEntry.approvedAt
                                    , "newCalculationId" Aeson..= calculation.id
                                    , "source" Aeson..= source
                                    ]
                            void $ recordTimesheetEntryVersion activeEntry.venueId (unpackId actorUserId) EntryVersionActionEnumApproved activeEntry payload
                            void $ recordAuditEvent activeEntry.venueId (unpackId actorUserId) TimesheetApprovedAudit "timesheet_entries" (unpackId activeEntry.id) payload auditSourceChannel
                            pure (Right ApprovalEngineResult
                                { approvalEngineEntry = activeEntry
                                , approvalEnginePriorCalculationId = priorCalculationId
                                , approvalEngineNewCalculationId = unpackId calculation.id
                                , approvalEngineChanged = True
                                })

approvalIdentity :: TimesheetEntry -> Maybe ExpectedApprovalIdentity
approvalIdentity entry = ExpectedApprovalIdentity
    <$> (unpackId <$> entry.activePayCalculationId)
    <*> entry.approvedAt

hasActiveProviderWrite :: (?modelContext :: ModelContext) => Id TimesheetEntry -> IO Bool
hasActiveProviderWrite entryId = do
    sourceLinks <- query @XeroTimesheetSubmissionEntry
        |> filterWhere (#timesheetEntryId, unpackId entryId)
        |> fetch
    if null sourceLinks
        then pure False
        else query @XeroTimesheetSubmission
            |> filterWhereIn (#id, map (Id . (.xeroTimesheetSubmissionId)) sourceLinks)
            |> filterWhere (#status, XeroTimesheetSubmissionStatusEnumPending)
            |> fetchCount
            |> fmap (> 0)

approvalCalculationComplete :: (?modelContext :: ModelContext) => TimesheetEntry -> IO Bool
approvalCalculationComplete entry = case entry.activePayCalculationId of
    Nothing -> pure False
    Just calculationId -> do
        calculation <- query @TimesheetPayCalculation
            |> filterWhere (#id, calculationId)
            |> filterWhere (#timesheetEntryId, unpackId entry.id)
            |> fetchOneOrNothing
        case calculation of
            Nothing -> pure False
            Just row
                | isNothing row.sealedAt -> pure False
                | otherwise -> replacementXeroMappingComplete calculationId

approvalWasXeroRefreshFrom :: (?modelContext :: ModelContext) => ExpectedApprovalIdentity -> TimesheetEntry -> IO Bool
approvalWasXeroRefreshFrom expected entry = case entry.activePayCalculationId of
    Nothing -> pure False
    Just calculationId -> do
        events <- query @AuditEvent
            |> filterWhere (#targetTable, "timesheet_entries" :: Text)
            |> filterWhere (#targetId, unpackId entry.id)
            |> filterWhere (#eventType, "timesheet_approved" :: Text)
            |> fetch
        pure (any (payloadMatches calculationId . (.payload)) events)
  where
    payloadMatches calculationId (Aeson.Object payload) =
        AesonKeyMap.lookup "source" payload == Just (Aeson.String "xero_preparation_refresh")
            && AesonKeyMap.lookup "priorCalculationId" payload == Just (Aeson.toJSON expected.expectedActiveCalculationId)
            && AesonKeyMap.lookup "priorApprovedAt" payload == Just (Aeson.toJSON expected.expectedApprovedAt)
            && AesonKeyMap.lookup "newCalculationId" payload == Just (Aeson.toJSON calculationId)
    payloadMatches _ _ = False

replacementXeroMappingComplete :: (?modelContext :: ModelContext) => Id TimesheetPayCalculation -> IO Bool
replacementXeroMappingComplete calculationId = do
    components <- query @TimesheetPayEarningsComponent
        |> filterWhere (#timesheetPayCalculationId, unpackId calculationId)
        |> fetch
    pure (all componentComplete components)
  where
    componentComplete component =
        component.exactAmount <= 0
            || (isJust component.xeroLocalBucketKey && isJust component.xeroEarningsRateId)

isLockTimeout :: HasqlSessionError -> Bool
isLockTimeout (HasqlSessionError sessionError) = case sessionError of
    Hasql.StatementSessionError _ _ _ _ _ (Hasql.ServerStatementError (Hasql.ServerError code _ _ _ _)) -> code == "55P03"
    Hasql.ScriptSessionError _ (Hasql.ServerError code _ _ _ _) -> code == "55P03"
    _ -> False
