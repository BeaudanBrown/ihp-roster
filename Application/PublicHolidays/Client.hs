-- Read-only v2 candidate client. Deliberately not wired to the refresh job until
-- the separately approved calendar cutover; never imports or retires overrides.
module Application.PublicHolidays.Client
    ( DataVicDate (..)
    , DataVicClientError (..)
    , fetchDataVicYears
    , fetchDataVicYearsWith
    , decodeDataVicYear
    ) where

import IHP.Prelude
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Data.Traversable (traverse)
import Data.Time.Calendar (toGregorian)
import Data.Time.Calendar.WeekDate (toWeekDate)
import Data.Time.Format (defaultTimeLocale, formatTime, parseTimeM)
import qualified Network.HTTP.Client as HTTP
import Network.HTTP.Client.TLS (getGlobalManager)
import Network.HTTP.Simple (setRequestQueryString)
import Network.HTTP.Types.Status (statusCode)
import qualified System.Environment as Environment

data DataVicDate = DataVicDate
    { date :: !Day
    , name :: !Text
    , sourceId :: !(Maybe Text)
    , description :: !(Maybe Text)
    , sourceUrl :: !Text
    } deriving (Eq, Show)

-- No requests, credentials, provider bodies or exception text in errors.
data DataVicClientError
    = DataVicMissingKey
    | DataVicInvalidYear
    | DataVicTransportUnavailable
    | DataVicHttpStatus Int
    | DataVicResponseTooLarge
    | DataVicMalformedResponse
    | DataVicIncompleteResponse
    | DataVicInvalidCalendar
    deriving (Eq, Show)

data DateRow = DateRow Text Text Text (Maybe Text) (Maybe Text)
data YearResponse = YearResponse Int Int Int [DateRow]

instance Aeson.FromJSON DateRow where
    parseJSON = Aeson.withObject "DataVic v2 date" \o ->
        DateRow <$> o Aeson..: "date" <*> o Aeson..: "name" <*> o Aeson..: "type"
            <*> o Aeson..:? "uuid" <*> o Aeson..:? "description"

instance Aeson.FromJSON YearResponse where
    parseJSON = Aeson.withObject "DataVic v2 response" \o -> do
        meta <- o Aeson..: "_meta"
        YearResponse <$> meta Aeson..: "total_records" <*> meta Aeson..: "page"
            <*> meta Aeson..: "limit" <*> o Aeson..: "dates"

endpoint :: String
endpoint = "https://wovg-community.gateway.prod.api.vic.gov.au/vicgov/v2.0/dates"

-- Exact request URI is retained as provenance: the collection does not return
-- publisher/source, and contemporary rows have empty UUIDs. Never fabricate IDs.
yearQuery :: Integer -> [(BS.ByteString, Maybe BS.ByteString)]
yearQuery year =
    [ ("type", Just "PUBLIC_HOLIDAY")
    , ("from_date", Just (Text.encodeUtf8 (tshow year <> "-01-01")))
    , ("to_date", Just (Text.encodeUtf8 (tshow year <> "-12-31")))
    , ("limit", Just "100")
    , ("page", Just "1")
    , ("sort", Just "date:asc")
    ]

-- Small pure/injectable boundary for request and multi-year failure tests.
-- Returns no partial candidate if any requested year fails validation.
fetchDataVicYearsWith :: (HTTP.Request -> IO (Either DataVicClientError (Int, LBS.ByteString))) -> Text -> [Integer] -> IO (Either DataVicClientError [(Integer, [DataVicDate])])
fetchDataVicYearsWith send key years
    | Text.null (Text.strip key) || Text.any (\c -> c < ' ' || c > '~') key = pure (Left DataVicMissingKey)
    | null years || any (\year -> year < 1900 || year > 9999) years || length (nub years) > 4 = pure (Left DataVicInvalidYear)
    | otherwise = go (sort (nub years))
  where
    go [] = pure (Right [])
    go (year : remaining) = do
        base <- HTTP.parseRequest endpoint
        let request = (setRequestQueryString (yearQuery year) base)
                { HTTP.requestHeaders = [("apikey", Text.encodeUtf8 key), ("Accept", "application/json")]
                , HTTP.redirectCount = 0
                , HTTP.responseTimeout = HTTP.responseTimeoutMicro (30 * 1000000)
                , HTTP.checkResponse = \_ _ -> pure ()
                }
        response <- send request
        case response >>= \(status, body) ->
                if status /= 200 then Left (DataVicHttpStatus status)
                else decodeDataVicYear year body of
            Left err -> pure (Left err)
            Right dates -> fmap ((year, dates) :) <$> go remaining

fetchDataVicYears :: [Integer] -> IO (Either DataVicClientError [(Integer, [DataVicDate])])
fetchDataVicYears years = do
    key <- maybe "" Text.pack <$> Environment.lookupEnv "DATAVIC_KEY"
    fetchDataVicYearsWith send key years
  where
    send request = do
        -- Catch only HTTP exceptions, not cancellation. HTTP exceptions contain
        -- the request (including apikey), so discard them at this boundary.
        result <- Exception.try @HTTP.HttpException do
            manager <- getGlobalManager
            HTTP.withResponse request manager \response -> do
                let status = statusCode (HTTP.responseStatus response)
                if status /= 200 then pure (Right (status, ""))
                else fmap ((status,) <$>) (readBounded (HTTP.responseBody response) 0 [])
        pure (either (const (Left DataVicTransportUnavailable)) (\value -> value) result)
    readBounded reader size chunks = do
        chunk <- HTTP.brRead reader
        let newSize = size + BS.length chunk
        if newSize > 1024 * 1024 then pure (Left DataVicResponseTooLarge)
        else if BS.null chunk then pure (Right (LBS.fromChunks (reverse chunks)))
        else readBounded reader newSize (chunk : chunks)

decodeDataVicYear :: Integer -> LBS.ByteString -> Either DataVicClientError [DataVicDate]
decodeDataVicYear year body = do
    when (year < 1900 || year > 9999) (Left DataVicInvalidYear)
    when (LBS.length body > 1024 * 1024) (Left DataVicResponseTooLarge)
    YearResponse total page limit rows <- either (const (Left DataVicMalformedResponse)) Right (Aeson.eitherDecode body)
    -- Annual statewide calendars fit within 100 rows. Do not blindly follow
    -- provider links: live unfiltered pages repeated the entire collection.
    unless (page == 1 && limit == 100 && total == length rows && total > 0 && total <= 100)
        (Left DataVicIncompleteResponse)
    dates <- traverse decodeRow rows
    let pairs = map (\entry -> (entry.date, entry.name)) dates
        ids = mapMaybe (.sourceId) dates
    unless (length pairs == Set.size (Set.fromList pairs) && length ids == Set.size (Set.fromList ids))
        (Left DataVicInvalidCalendar)
    pure dates
  where
    decodeRow (DateRow rawDate rawName kind uuid description) = do
        day <- maybe (Left DataVicInvalidCalendar) Right (parseTimeM True defaultTimeLocale "%Y-%m-%d" (Text.unpack rawDate) :: Maybe Day)
        let (actualYear, _, _) = toGregorian day
            (_, _, weekday) = toWeekDate day
            name = Text.strip rawName
        unless (actualYear == year && Text.pack (formatTime defaultTimeLocale "%Y-%m-%d" day) == rawDate
            && kind == "PUBLIC_HOLIDAY" && not (Text.null name)) (Left DataVicInvalidCalendar)
        -- Observed upstream defect: Easter Monday 2027 is published as Sunday
        -- 28 March. Fail closed; do not silently correct government data.
        when (Text.toCaseFold name == "easter monday" && weekday /= 1) (Left DataVicInvalidCalendar)
        pure DataVicDate
            { date = day, name, sourceId = nonBlank uuid, description = nonBlank description
            , sourceUrl = Text.pack endpoint <> "?type=PUBLIC_HOLIDAY&from_date=" <> tshow year <> "-01-01&to_date=" <> tshow year <> "-12-31&limit=100&page=1&sort=date:asc"
            }
    nonBlank value = case Text.strip <$> value of
        Just text | not (Text.null text) -> Just text
        _ -> Nothing
