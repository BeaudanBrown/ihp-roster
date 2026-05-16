module Application.FwcMapd.Job
    ( fwcMapdRefreshJobDedupeKey
    , fwcMapdRefreshJobKind
    , performFwcMapdRefreshJob
    ) where

import Application.FwcMapd.Sync
import Application.Helper.LiveSurface (broadcastSurfaceFragmentsWithoutContext)
import Application.Support.LiveUpdates
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

fwcMapdRefreshJobKind :: Text
fwcMapdRefreshJobKind = "fwc_mapd_refresh"

fwcMapdRefreshJobDedupeKey :: Text
fwcMapdRefreshJobDedupeKey = "fwc-mapd-refresh"

performFwcMapdRefreshJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performFwcMapdRefreshJob appJob = do
    syncResult <- runConfiguredMapdSync
    case syncResult of
        Left err ->
            fail (Text.unpack err)
        Right summary -> do
            let resultPayload =
                    Aeson.object
                        [ "syncedAwardFixedIds" Aeson..= summary.syncedAwardFixedIds
                        , "fetchedAwardCount" Aeson..= summary.fetchedAwardCount
                        , "fetchedClassificationCount" Aeson..= summary.fetchedClassificationCount
                        , "fetchedPayRateCount" Aeson..= summary.fetchedPayRateCount
                        ]
            void
                ( appJob
                    |> set #result resultPayload
                    |> set #status JobStatusSucceeded
                    |> updateRecord
                )
            void $
                broadcastSurfaceFragmentsWithoutContext
                    supportLiveSurfaceDefinition
                    ()
                    Nothing
                    [SupportAwardRatesLiveFragment]
