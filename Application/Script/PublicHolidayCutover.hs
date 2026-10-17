module Application.Script.PublicHolidayCutover where

import Application.Async.Boundary (throwAppJobError)
import Application.Async.Error (AppJobError (..))
import Application.Helper.Controller.Input (parseUUIDText)
import Application.PublicHolidays.ActiveImport (cutoverPublicHolidayCalendars)
import Application.PublicHolidays.Client (fetchDataVicYears)
import Application.PublicHolidays.Policy (targetPublicHolidayYears)
import Application.Script.Prelude
import qualified System.Environment as Environment
import qualified Data.Text.IO as TextIO

requireCutoverDatabase :: (?modelContext :: ModelContext) => Text -> IO ()
requireCutoverDatabase expectedDatabase = do
    -- PostgreSQL returns `name` (OID 19), not the `text` expected by Hasql.
    actualDatabase :: Text <- unsafeSqlQueryScalar "SELECT current_database()::text" ()
    unless (actualDatabase == expectedDatabase) (throwAppJobError JobValidationRejected)

-- Operator-only, explicitly targeted database and platform reviewer. Never run
-- automatically from migrations, startup, timers, or ordinary refresh jobs.
run :: Script
run = do
    args <- Environment.getArgs
    case args of
        ["--apply", "--database", expectedDatabase, "--reviewer", rawReviewer] -> do
            requireCutoverDatabase (cs expectedDatabase)
            reviewerId <- maybe (throwAppJobError JobValidationRejected) pure (parseUUIDText (cs rawReviewer))
            actor <- fetch (Id reviewerId :: Id User)
            unless (actor.platformRole == Just SuperAdmin && isNothing actor.deactivatedAt)
                (throwAppJobError JobValidationRejected)
            startedAt <- getCurrentTime
            let years = targetPublicHolidayYears (utctDay startedAt)
            calendars <- fetchDataVicYears years >>= either (const (throwAppJobError JobValidationRejected)) pure
            _ <- cutoverPublicHolidayCalendars actor startedAt years calendars
            TextIO.putStrLn "DataVic cutover committed; reviewed override retired and all requested years imported."
        _ -> do
            TextIO.putStrLn "Usage: PublicHolidayCutover --apply --database DATABASE --reviewer PLATFORM_SUPER_ADMIN_UUID"
            throwAppJobError JobValidationRejected
