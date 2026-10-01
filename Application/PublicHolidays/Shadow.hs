{-# LANGUAGE DeriveGeneric #-}

-- Shadow results are operational evidence, never holiday or freshness authority.
module Application.PublicHolidays.Shadow
    ( enqueuePublicHolidayShadowJob
    , performPublicHolidayShadowJob
    , performPublicHolidayShadowJobWith
    , publicHolidayShadowJobKind
    , publicHolidayShadowJobDedupeKey
    , ShadowResult (..)
    , ShadowYearSummary (..)
    ) where

import Application.Async.Boundary (throwAppJobError, trySynchronousAppJobAction)
import Application.Async.Error (AppJobError (..))
import Application.Async.Payload (decodeAppJobPayloadV1, requireAppJobPayloadV1)
import Application.Async.Queue
import Application.Helper.FrontendContract.Surface.Support.Resource (supportPublicHolidaysResource)
import Application.Helper.LiveUpdate.BackgroundMutation (withDurableLiveMutationWithoutContext)
import Application.Helper.SurfaceResource (liveMutationResult)
import Application.PublicHolidays.Client
import qualified Application.PublicHolidays.Policy as Policy
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.List ((\\))
import Data.Time.Calendar (fromGregorian)
import Generated.Types
import GHC.Generics (Generic)
import IHP.ControllerPrelude

-- Only counts and timestamps cross the persisted/visible boundary, not raw
-- upstream names, descriptions, UUIDs, request headers or exception messages.
data ShadowYearSummary = ShadowYearSummary
    { year              :: Integer
    , fetchedCount      :: Int
    , cachedCount       :: Int
    , providerOnlyCount :: Int
    , cacheOnlyCount    :: Int
    } deriving (Eq, Show, Generic)
instance Aeson.ToJSON ShadowYearSummary
instance Aeson.FromJSON ShadowYearSummary

data ShadowResult = ShadowResult
    { attemptedAt :: UTCTime
    , completedAt :: UTCTime
    , targetYears :: [Integer]
    , failure     :: Maybe Text
    , years       :: [ShadowYearSummary]
    } deriving (Eq, Show, Generic)
instance Aeson.ToJSON ShadowResult
instance Aeson.FromJSON ShadowResult

newtype ShadowPayload = ShadowPayload { jurisdiction :: Text }
instance Aeson.FromJSON ShadowPayload where
    parseJSON = Aeson.withObject "PublicHolidayShadowPayload" \o -> ShadowPayload <$> o Aeson..: "jurisdiction"

publicHolidayShadowJobKind :: Text
publicHolidayShadowJobKind = "public_holiday_shadow"

publicHolidayShadowJobDedupeKey :: Text
publicHolidayShadowJobDedupeKey = "public-holiday-shadow-vic"

enqueuePublicHolidayShadowJob :: (?modelContext :: ModelContext) => Maybe UUID -> IO EnqueueAppJobResult
enqueuePublicHolidayShadowJob requestedByUserId = enqueueAppJob AppJobRequest
    { jobKind = publicHolidayShadowJobKind
    , payload = Aeson.object ["jurisdiction" Aeson..= Policy.publicHolidayJurisdiction]
    , payloadSchemaVersion = 1
    , requestedByUserId
    , venueId = Nothing
    , relatedTable = Just "public_holidays"
    , relatedId = Nothing
    , dedupeKey = Just publicHolidayShadowJobDedupeKey
    , runAt = Nothing
    }

performPublicHolidayShadowJob :: (?modelContext :: ModelContext) => AppJob -> IO ()
performPublicHolidayShadowJob = performPublicHolidayShadowJobWith fetchDataVicYears

performPublicHolidayShadowJobWith
    :: (?modelContext :: ModelContext)
    => ([Integer] -> IO (Either DataVicClientError [(Integer, [DataVicDate])]))
    -> AppJob
    -> IO ()
performPublicHolidayShadowJobWith fetchYears appJob = do
    requireAppJobPayloadV1 appJob
    unless (appJob.jobKind == publicHolidayShadowJobKind && appJob.relatedTable == Just "public_holidays"
        && isNothing appJob.relatedId && isNothing appJob.venueId) (throwAppJobError JobInvalidProvenance)
    payload <- decodeAppJobPayloadV1 @ShadowPayload appJob
    unless (payload.jurisdiction == Policy.publicHolidayJurisdiction) (throwAppJobError JobInvalidProvenance)
    attemptedAt <- getCurrentTime
    let targetYears = Policy.targetPublicHolidayYears (utctDay attemptedAt)
    outcome <- trySynchronousAppJobAction (fetchYears targetYears)
    let candidate = case outcome of
            Left _                  -> Left JobUnexpectedSynchronousFailure
            Right (Left err)        -> Left (shadowClientError err)
            Right (Right calendars) -> Right calendars
    summaries <- case candidate of
        Left _ -> pure []
        Right calendars -> forM calendars \(year, dates) -> do
            cached <- query @PublicHoliday
                |> filterWhere (#jurisdiction, Policy.publicHolidayJurisdiction)
                |> filterWhere (#isRegional, False)
                |> filterWhere (#region, Nothing)
                |> filterWhereGreaterThanOrEqualTo (#holidayDate, fromGregorian year 1 1)
                |> filterWhereLessThan (#holidayDate, fromGregorian (year + 1) 1 1)
                |> fetch
            let providerPairs = map (\entry -> (entry.date, entry.name)) dates
                cachePairs = map (\entry -> (entry.holidayDate, entry.name)) cached
            pure ShadowYearSummary
                { year, fetchedCount = length dates, cachedCount = length cached
                , providerOnlyCount = length (providerPairs \\ cachePairs)
                , cacheOnlyCount = length (cachePairs \\ providerPairs)
                }
    completedAt <- getCurrentTime
    let result = ShadowResult { attemptedAt, completedAt, targetYears, failure = either (Just . tshow) (const Nothing) candidate, years = summaries }
    void $ withDurableLiveMutationWithoutContext "support.public_holidays.shadow" do
        let updated = appJob |> set #result (Aeson.toJSON result)
        _ <- (case candidate of Right _ -> updated |> set #status JobStatusSucceeded |> set #lastError Nothing; Left _ -> updated) |> updateRecord
        pure (liveMutationResult () [supportPublicHolidaysResource])
    -- Throw outside the result transaction: IHP retains retry ownership, and a
    -- failed attempt's sanitized evidence survives. No freshness job is emitted.
    either throwAppJobError (const (pure ())) candidate

shadowClientError :: DataVicClientError -> AppJobError
shadowClientError = \case
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
