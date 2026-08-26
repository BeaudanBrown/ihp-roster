module Application.FwcMapd.Sync
    ( module Application.FwcMapd.Curation
    , module Application.FwcMapd.Payload
    , module Application.FwcMapd.Projection
    , module Application.FwcMapd.RawStore
    , module Application.FwcMapd.Validation
    , runConfiguredMapdSync
    , runMapdSync
    , runMapdSyncWith
    ) where

import Application.Error.ExternalRuntime (throwExternalRuntime)
import Application.FwcMapd.Config
import Application.FwcMapd.Curation
import Application.FwcMapd.Error
import Application.FwcMapd.Payload
import Application.FwcMapd.Projection
import Application.FwcMapd.RawStore
import Application.FwcMapd.Validation
import Application.WageSourceNotifications (emitLatestAwardDriftNotifications)
import qualified Control.Exception as Exception
import qualified Control.Exception.Safe as SafeException
import Control.Monad (void)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude

runConfiguredMapdSync :: (?modelContext :: ModelContext) => IO (Either Text MapdSyncSummary)
runConfiguredMapdSync = do
    maybeConfig <- liftIO loadMapdConfig
    case maybeConfig of
        Nothing     -> pure (Left "FWC_MAPD_KEY is not configured.")
        Just config -> Right <$> runMapdSync config

runMapdSync :: (?modelContext :: ModelContext) => MapdConfig -> IO MapdSyncSummary
runMapdSync config =
    runMapdSyncWith config.awardFixedIds (fetchAndStore config)

runMapdSyncWith :: (?modelContext :: ModelContext) => [Int] -> IO MapdSyncSummary -> IO MapdSyncSummary
runMapdSyncWith requestedAwardFixedIds syncAction = do
    startedAt <- getCurrentTime
    syncRun <-
        newRecord @FwcMapdSyncRun
            |> set #status ("running" :: Text)
            |> set #requestedAwardFixedIds requestedAwardFixedIds
            |> set #syncedAwardFixedIds ([] :: [Int])
            |> set #startedAt startedAt
            |> createRecord
    syncResult <- trySynchronousMapdAction syncAction
    finishedAt <- getCurrentTime
    case syncResult of
        Left syncError -> do
            let errorMessage =
                    maybe
                        "FWC MAPD synchronization failed."
                        mapdSyncErrorSafeMessage
                        (Exception.fromException syncError)
            void
                ( syncRun
                    |> set #status ("failed" :: Text)
                    |> set #errorMessage (Just errorMessage)
                    |> set #finishedAt (Just finishedAt)
                    |> updateRecord
                )
            throwExternalRuntime syncError
        Right summary -> do
            void
                ( syncRun
                    |> set #status ("succeeded" :: Text)
                    |> set #syncedAwardFixedIds summary.syncedAwardFixedIds
                    |> set #fetchedAwardCount summary.fetchedAwardCount
                    |> set #fetchedClassificationCount summary.fetchedClassificationCount
                    |> set #fetchedPayRateCount summary.fetchedPayRateCount
                    |> set #fetchedPenaltyRateCount summary.fetchedPenaltyRateCount
                    |> set #fetchedWageAllowanceCount summary.fetchedWageAllowanceCount
                    |> set #finishedAt (Just finishedAt)
                    |> updateRecord
                )
            void emitLatestAwardDriftNotifications
            pure summary

trySynchronousMapdAction :: IO value -> IO (Either Exception.SomeException value)
trySynchronousMapdAction action =
    Exception.try action >>= \case
        Left exception
            | SafeException.isAsyncException exception -> Exception.throwIO (exception :: Exception.SomeException)
            | otherwise -> pure (Left exception)
        Right value -> pure (Right value)

