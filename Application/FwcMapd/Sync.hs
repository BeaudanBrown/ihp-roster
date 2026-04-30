module Application.FwcMapd.Sync
    ( module Application.FwcMapd.Curation
    , module Application.FwcMapd.Payload
    , module Application.FwcMapd.Projection
    , module Application.FwcMapd.RawStore
    , runConfiguredMapdSync
    , runMapdSync
    ) where

import Application.FwcMapd.Config
import Application.FwcMapd.Curation
import Application.FwcMapd.Payload
import Application.FwcMapd.Projection
import Application.FwcMapd.RawStore
import qualified Control.Exception as Exception
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
runMapdSync config = do
    startedAt <- getCurrentTime
    syncRun <-
        newRecord @FwcMapdSyncRun
            |> set #status ("running" :: Text)
            |> set #requestedAwardFixedIds config.awardFixedIds
            |> set #syncedAwardFixedIds ([] :: [Int])
            |> set #startedAt startedAt
            |> createRecord
    syncResult <- Exception.try (fetchAndStore config) :: (?modelContext :: ModelContext) => IO (Either Exception.SomeException MapdSyncSummary)
    finishedAt <- getCurrentTime
    case syncResult of
        Left syncError -> do
            let errorMessage = cs (Exception.displayException syncError)
            void
                ( syncRun
                    |> set #status ("failed" :: Text)
                    |> set #errorMessage (Just errorMessage)
                    |> set #finishedAt (Just finishedAt)
                    |> updateRecord
                )
            Exception.throwIO syncError
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
            pure summary

