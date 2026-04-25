module Application.PublicHolidays.Job
    ( performPublicHolidayRefreshJob
    , publicHolidayRefreshJobDedupeKey
    , publicHolidayRefreshJobKind
    ) where

import Application.PublicHolidays.Sync
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude

publicHolidayRefreshJobKind :: Text
publicHolidayRefreshJobKind = "public_holiday_refresh"

publicHolidayRefreshJobDedupeKey :: Text
publicHolidayRefreshJobDedupeKey = "public-holiday-refresh-vic"

performPublicHolidayRefreshJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performPublicHolidayRefreshJob appJob = do
    summary <- runDataVicPublicHolidaySync
    let resultPayload =
            Aeson.object
                [ "fetchedCount" Aeson..= summary.fetchedCount
                , "importedCount" Aeson..= summary.importedCount
                , "insertedCount" Aeson..= summary.insertedCount
                , "updatedCount" Aeson..= summary.updatedCount
                , "skippedCount" Aeson..= summary.skippedCount
                ]
    void
        ( appJob
            |> set #result resultPayload
            |> updateRecord
        )
