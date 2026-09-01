module Application.Xero.ReferenceSyncRequest
    ( runXeroReferenceDataSyncCategoriesRequest
    , runXeroReferenceDataSyncRequest
    , withInlineXeroReferenceSyncRequestsForTest
    , withQueuedXeroReferenceSyncRequestsForTest
    ) where

import Application.Async.Boundary (trySynchronousAppJobAction)
import Application.Async.Queue
import Application.Error.Parser (parserFailure)
import Application.Xero.Admin.ReferenceData (XeroReferenceDataSyncResult (..))
import Application.Xero.ReferenceCategory (allXeroReferenceSyncCategories)
import Application.Xero.ReferenceSyncJob
import qualified Control.Exception as Exception
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.IORef as IORef
import qualified Data.Set as Set
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types
import System.IO.Unsafe (unsafePerformIO)

inlineXeroReferenceSyncRequestsForTestRef :: IORef.IORef Bool
inlineXeroReferenceSyncRequestsForTestRef = unsafePerformIO (IORef.newIORef False)
{-# NOINLINE inlineXeroReferenceSyncRequestsForTestRef #-}

data CompletedReferenceSyncCounts = CompletedReferenceSyncCounts
    { employeeCount        :: !Int
    , earningsRateCount    :: !Int
    , payrollCalendarCount :: !Int
    , accountCount         :: !Int
    }

runXeroReferenceDataSyncRequest ::
    (?modelContext :: ModelContext) =>
    Maybe (Id User) ->
    XeroConnection ->
    IO (Either Text XeroReferenceDataSyncResult)
runXeroReferenceDataSyncRequest maybeActorUserId connection =
    runXeroReferenceDataSyncCategoriesRequest maybeActorUserId connection allXeroReferenceSyncCategories

runXeroReferenceDataSyncCategoriesRequest ::
    (?modelContext :: ModelContext) =>
    Maybe (Id User) ->
    XeroConnection ->
    Set.Set XeroReferenceSyncCategoryEnum ->
    IO (Either Text XeroReferenceDataSyncResult)
runXeroReferenceDataSyncCategoriesRequest maybeActorUserId connection categories
    | connection.connectionStatus /= "active" =
        pure (Left "Reconnect Xero before syncing payroll reference data.")
    | Set.null categories =
        pure (Left "Choose at least one Xero reference category to sync.")
    | otherwise =
        requestXeroReferenceSyncCategories maybeActorUserId connection categories >>= \case
            ExistingActiveAppJob _ ->
                pure (Left "Xero payroll reference data is already syncing in the background.")
            EnqueuedAppJob appJob -> do
                runInline <- IORef.readIORef inlineXeroReferenceSyncRequestsForTestRef
                attempt <- trySynchronousAppJobAction (if runInline then performXeroReferenceSyncJob appJob else pure ())
                case attempt of
                    Left (_ :: Exception.SomeException) -> do
                        let safeMessage = "Xero reference sync failed before completion."
                        markInlineReferenceSyncJobFailed appJob safeMessage
                        updatedConnection <- fetch connection.id
                        pure $
                            Left $
                                if updatedConnection.connectionStatus == "reauthorization_required"
                                    then "Xero needs to be reconnected before sync can continue."
                                    else safeMessage
                    Right () -> referenceSyncResultFromJob appJob connection

withInlineXeroReferenceSyncRequestsForTest :: IO value -> IO value
withInlineXeroReferenceSyncRequestsForTest =
    withInlineXeroReferenceSyncSettingForTest True

withQueuedXeroReferenceSyncRequestsForTest :: IO value -> IO value
withQueuedXeroReferenceSyncRequestsForTest =
    withInlineXeroReferenceSyncSettingForTest False

withInlineXeroReferenceSyncSettingForTest :: Bool -> IO value -> IO value
withInlineXeroReferenceSyncSettingForTest runInline action =
    Exception.bracket
        (IORef.atomicModifyIORef' inlineXeroReferenceSyncRequestsForTestRef (\old -> (runInline, old)))
        (IORef.writeIORef inlineXeroReferenceSyncRequestsForTestRef)
        (const action)

referenceSyncResultFromJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    XeroConnection ->
    IO (Either Text XeroReferenceDataSyncResult)
referenceSyncResultFromJob appJob connection = do
    completedJob <- fetch appJob.id
    case completedReferenceSyncCounts completedJob.result of
        Nothing -> pure (Left "Xero payroll reference data is continuing in the background.")
        Just counts -> do
            maybeSyncRun <-
                query @XeroSyncRun
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#syncStatus, Succeeded)
                    |> orderByDesc #createdAt
                    |> fetchOneOrNothing
            case maybeSyncRun of
                Nothing -> pure (Left "Xero payroll reference data did not produce a complete snapshot.")
                Just syncRun -> do
                    updatedConnection <- fetch connection.id
                    pure $
                        Right
                            XeroReferenceDataSyncResult
                                { referenceDataSyncRun = syncRun
                                , referenceDataSyncConnection = updatedConnection
                                , referenceDataSyncEmployeeCount = counts.employeeCount
                                , referenceDataSyncEarningsRateCount = counts.earningsRateCount
                                , referenceDataSyncPayrollCalendarCount = counts.payrollCalendarCount
                                , referenceDataSyncAccountCount = counts.accountCount
                                }

completedReferenceSyncCounts :: Aeson.Value -> Maybe CompletedReferenceSyncCounts
completedReferenceSyncCounts =
    Aeson.parseMaybe $ Aeson.withObject "completed Xero reference sync result" \object -> do
        status <- object Aeson..: "status"
        if status /= ("succeeded" :: Text)
            then parserFailure "Xero reference sync did not succeed"
            else
                CompletedReferenceSyncCounts
                    <$> object Aeson..: "employeesCount"
                    <*> object Aeson..: "earningsRatesCount"
                    <*> object Aeson..: "payrollCalendarsCount"
                    <*> object Aeson..: "accountsCount"

markInlineReferenceSyncJobFailed ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    Text ->
    IO ()
markInlineReferenceSyncJobFailed appJob message = do
    latestJob <- fetch appJob.id
    void $
        latestJob
            |> set #status JobStatusFailed
            |> set #lastError (Just message)
            |> set #lockedAt Nothing
            |> set #lockedBy Nothing
            |> updateRecord
