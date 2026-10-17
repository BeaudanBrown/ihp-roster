module Application.PublicHolidays.ActiveImport
    ( refreshPublicHolidaysWith
    , importPublicHolidayCalendars
    , cutoverPublicHolidayCalendars
    , activeImportEnabled
    ) where

import Application.Async.Boundary (throwAppJobError)
import Application.Async.Error (AppJobError (..))
import Application.Helper.FrontendContract.Surface.Support.Resource (supportPublicHolidaysResource)
import Application.Helper.LiveUpdate.BackgroundMutation (withDurableLiveMutationWithoutContext)
import Application.Helper.SurfaceResource (LiveMutationResult (..), liveMutationResult)
import Application.PublicHolidays.Client
import Application.PublicHolidays.Override
import Application.PublicHolidays.OverrideIncident (retirePublicHolidayOverrideInCurrentTransaction)
import qualified Application.PublicHolidays.Policy as Policy
import Application.PublicHolidays.Sync (PublicHolidaySyncSummary (..))
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import qualified System.Environment as Environment

-- Deployment gate: legacy queued jobs must not turn into writes merely because
-- new code was deployed. Cutover is a separate explicit operator operation.
activeImportEnabled :: IO Bool
activeImportEnabled = (== Just "true") <$> Environment.lookupEnv "DATAVIC_ACTIVE_IMPORT"

refreshPublicHolidaysWith :: (?modelContext :: ModelContext) => ((?modelContext :: ModelContext) => PublicHolidaySyncSummary -> UTCTime -> IO ()) -> IO PublicHolidaySyncSummary
refreshPublicHolidaysWith complete = do
    enabled <- activeImportEnabled
    unless enabled (throwAppJobError JobConfigurationUnavailable)
    now <- getCurrentTime
    let years = Policy.targetPublicHolidayYears (utctDay now)
    candidate <- fetchDataVicYears years >>= either (throwAppJobError . clientError) pure
    acceptCalendars Nothing now years candidate complete

-- Caller supplies the request start time: a slow older fetch cannot replace a
-- newer accepted batch. Both normal and cutover paths share this transaction.
importPublicHolidayCalendars :: (?modelContext :: ModelContext) => UTCTime -> [Integer] -> [(Integer, [DataVicDate])] -> IO PublicHolidaySyncSummary
importPublicHolidayCalendars startedAt years calendars =
    acceptCalendars Nothing startedAt years calendars (\_ _ -> pure ())

cutoverPublicHolidayCalendars :: (?modelContext :: ModelContext) => User -> UTCTime -> [Integer] -> [(Integer, [DataVicDate])] -> IO PublicHolidaySyncSummary
cutoverPublicHolidayCalendars actor startedAt years calendars =
    acceptCalendars (Just actor) startedAt years calendars (\_ _ -> pure ())

acceptCalendars :: (?modelContext :: ModelContext) => Maybe User -> UTCTime -> [Integer] -> [(Integer, [DataVicDate])] -> ((?modelContext :: ModelContext) => PublicHolidaySyncSummary -> UTCTime -> IO ()) -> IO PublicHolidaySyncSummary
acceptCalendars reviewer startedAt years calendars complete = do
    validateCandidate years calendars
    fmap (.liveMutationValue) $ withDurableLiveMutationWithoutContext "support.public_holidays.sync" do
        -- Serialize the guarded cutover with every calendar writer, including
        -- older processes. Order matches override review before holiday writes.
        unsafeSqlExecDiscardResult "SET LOCAL lock_timeout = '5s'" ()
        unsafeSqlExecDiscardResult "LOCK TABLE public_holiday_overrides, public_holidays, public_holiday_import_batches IN EXCLUSIVE MODE" ()
        now <- getCurrentTime
        when (startedAt > now) (throwAppJobError JobValidationRejected)
        receipts <- query @PublicHolidayImportBatch |> filterWhere (#jurisdiction, "VIC" :: Text) |> fetch
        when (any (\receipt -> receipt.acceptedAt > startedAt && any (`elem` map fromIntegral receipt.targetYears) years) receipts)
            (throwAppJobError JobValidationRejected)
        overrides <- fetchActivePublicHolidayOverrides
        holidays <- query @PublicHoliday |> filterWhere (#jurisdiction, "VIC" :: Text) |> filterWhere (#isRegional, False) |> fetch
        case reviewer of
            Nothing -> unless (Set.null (Set.intersection (Set.fromList years) (overriddenYears overrides)))
                (throwAppJobError JobValidationRejected)
            Just suppliedActor -> do
                actor <- fetch suppliedActor.id
                unless (actor.platformRole == Just SuperAdmin && isNothing actor.deactivatedAt)
                    (throwAppJobError JobValidationRejected)
                case overrides of
                    [entry] | entry.snapshotKey == verifiedVic2026Key
                        && entry.targetYear == 2026 && 2026 `elem` years
                        && overrideStatus now holidays entry /= OverrideInvalid -> do
                            retired <- retirePublicHolidayOverrideInCurrentTransaction actor entry.id "datavic_v2_active_import_cutover" now
                            when (isNothing retired) (throwAppJobError JobValidationRejected)
                    _ -> throwAppJobError JobValidationRejected
        let replaced = filter (\holiday -> yearOf holiday.holidayDate `elem` years) holidays
        mapM_ deleteRecord replaced
        forM_ (concatMap snd calendars) \entry -> void $
            newRecord @PublicHoliday
                |> set #jurisdiction "VIC"
                |> set #holidayDate entry.date
                |> set #name entry.name
                |> set #isRegional False
                |> set #source (Just "datavic_v2")
                |> set #sourceId entry.sourceId
                |> set #sourceUrl (Just entry.sourceUrl)
                |> set #description entry.description
                |> set #importedAt (Just now)
                |> createRecord
        void $ newRecord @PublicHolidayImportBatch
            |> set #jurisdiction "VIC"
            |> set #targetYears (map fromIntegral years)
            |> set #acceptedAt now
            |> set #source "datavic_v2"
            |> set #previousCalendar (Aeson.toJSON (map storedDate replaced))
            |> set #acceptedCalendar (Aeson.toJSON (map candidateDate (concatMap snd calendars)))
            |> set #reviewedByUserId (fmap (unpackId . (.id)) reviewer)
            |> createRecord
        let count = length (concatMap snd calendars)
        let summary = PublicHolidaySyncSummary
                { targetYears = years, fetchedCount = count, importedCount = count
                , insertedCount = count, updatedCount = 0, skippedCount = 0
                , invalidCount = 0, prunedCount = length replaced
                }
        complete summary now
        pure (liveMutationResult summary [supportPublicHolidaysResource])

validateCandidate :: [Integer] -> [(Integer, [DataVicDate])] -> IO ()
validateCandidate years calendars = unless valid (throwAppJobError JobValidationRejected)
  where
    valid = not (null years) && length years <= 4 && length (nub years) == length years
        && sort years == sort (map fst calendars)
        && all (\(year, dates) -> not (null dates) && length dates <= 100
            && all (\entry -> yearOf entry.date == year && not (Text.null (Text.strip entry.name))) dates
            && length dates == Set.size (Set.fromList (map (\entry -> (entry.date, entry.name)) dates))) calendars

yearOf :: Day -> Integer
yearOf day = let (year, _, _) = toGregorian day in year

storedDate :: PublicHoliday -> Aeson.Value
storedDate row = Aeson.object
    [ "id" Aeson..= row.id, "date" Aeson..= row.holidayDate, "name" Aeson..= row.name
    , "region" Aeson..= row.region, "source" Aeson..= row.source
    , "sourceId" Aeson..= row.sourceId, "sourceUrl" Aeson..= row.sourceUrl
    , "description" Aeson..= row.description, "importedAt" Aeson..= row.importedAt
    ]

candidateDate :: DataVicDate -> Aeson.Value
candidateDate row = Aeson.object
    [ "date" Aeson..= row.date, "name" Aeson..= row.name, "sourceId" Aeson..= row.sourceId
    , "sourceUrl" Aeson..= row.sourceUrl, "description" Aeson..= row.description ]

clientError :: DataVicClientError -> AppJobError
clientError = \case
    DataVicMissingKey -> JobConfigurationUnavailable
    DataVicInvalidYear -> JobValidationRejected
    DataVicTransportUnavailable -> JobTransportUnavailable
    DataVicHttpStatus 401 -> JobAuthenticationRequired
    DataVicHttpStatus 403 -> JobAuthenticationRequired
    DataVicHttpStatus 429 -> JobRateLimited
    DataVicHttpStatus _ -> JobTransportUnavailable
    DataVicResponseTooLarge -> JobMalformedResponse
    DataVicMalformedResponse -> JobMalformedResponse
    DataVicIncompleteResponse -> JobMalformedResponse
    DataVicInvalidCalendar -> JobValidationRejected
