module Application.PublicHolidays.Sync
    ( DataVicHolidayRecord (..)
    , PublicHolidayImport (..)
    , PublicHolidaySyncSummary (..)
    , dataVicImportantDatesResourceId
    , fetchDataVicPublicHolidayRecords
    , importDataVicPublicHolidayRecords
    , importDataVicPublicHolidayRecordsForYear
    , parseDataVicDate
    , publicHolidayImportFromDataVic
    , runDataVicPublicHolidaySync
    ) where

import qualified Control.Exception as Exception
import Control.Monad (guard)
import qualified Data.Aeson as Aeson
import Data.Aeson.Key (Key)
import Data.Aeson.Types (Parser)
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, fromGregorianValid, toGregorian)
import Data.Time.LocalTime (getZonedTime, localDay, zonedTimeToLocalTime)
import Data.Traversable (traverse)
import Generated.Types
import IHP.ControllerPrelude
import Network.HTTP.Simple
import Text.Read (readMaybe)

data DataVicHolidayRecord = DataVicHolidayRecord
    { arun          :: !(Maybe Text)
    , dateType      :: !Text
    , name          :: !Text
    , importantDate :: !Text
    , publisher     :: !(Maybe Text)
    , description   :: !(Maybe Text)
    , source        :: !(Maybe Text)
    }
    deriving (Eq, Show)

data PublicHolidayImport = PublicHolidayImport
    { jurisdiction :: !Text
    , holidayDate  :: !Day
    , name         :: !Text
    , region       :: !(Maybe Text)
    , isRegional   :: !Bool
    , source       :: !(Maybe Text)
    , sourceId     :: !(Maybe Text)
    , sourceUrl    :: !(Maybe Text)
    , description  :: !(Maybe Text)
    }
    deriving (Eq, Show)

data PublicHolidaySyncSummary = PublicHolidaySyncSummary
    { targetYear    :: !Integer
    , fetchedCount  :: !Int
    , importedCount :: !Int
    , insertedCount :: !Int
    , updatedCount  :: !Int
    , skippedCount  :: !Int
    , invalidCount  :: !Int
    , prunedCount   :: !Int
    }
    deriving (Eq, Show)

data DataVicSearchResponse = DataVicSearchResponse
    { success :: !Bool
    , result  :: !DataVicSearchResult
    }
    deriving (Eq, Show)

newtype DataVicSearchResult = DataVicSearchResult
    { records :: [DataVicHolidayRecord]
    }
    deriving (Eq, Show)

instance Aeson.FromJSON DataVicHolidayRecord where
    parseJSON = Aeson.withObject "DataVicHolidayRecord" \object ->
        DataVicHolidayRecord
            <$> optionalText object "arun"
            <*> object Aeson..: "dateType"
            <*> object Aeson..: "name"
            <*> object Aeson..: "important_date"
            <*> optionalText object "publisher"
            <*> optionalText object "description"
            <*> optionalText object "source"

instance Aeson.FromJSON DataVicSearchResponse where
    parseJSON = Aeson.withObject "DataVicSearchResponse" \object ->
        DataVicSearchResponse
            <$> object Aeson..: "success"
            <*> object Aeson..: "result"

instance Aeson.FromJSON DataVicSearchResult where
    parseJSON = Aeson.withObject "DataVicSearchResult" \object ->
        DataVicSearchResult
            <$> object Aeson..: "records"

dataVicImportantDatesResourceId :: ByteString.ByteString
dataVicImportantDatesResourceId = "caaa47de-8626-46a6-aa28-3d948c15c5d9"

runDataVicPublicHolidaySync ::
    (?modelContext :: ModelContext) =>
    IO PublicHolidaySyncSummary
runDataVicPublicHolidaySync = do
    records <- fetchDataVicPublicHolidayRecords
    importDataVicPublicHolidayRecords records

fetchDataVicPublicHolidayRecords :: IO [DataVicHolidayRecord]
fetchDataVicPublicHolidayRecords = do
    request <- parseRequest "https://discover.data.vic.gov.au/api/3/action/datastore_search"
    let requestWithQuery =
            request
                |> setRequestMethod "GET"
                |> setRequestQueryString
                    [ ("resource_id", Just dataVicImportantDatesResourceId)
                    , ("filters", Just "{\"dateType\":\"PUBLIC_HOLIDAY\"}")
                    , ("limit", Just "500")
                    ]
    response <- httpLBS requestWithQuery
    let statusCode = getResponseStatusCode response
    when (statusCode < 200 || statusCode >= 300) do
        Exception.throwIO (userError ("DataVic public holiday request failed with status " <> cs (tshow statusCode)))
    case Aeson.eitherDecode (getResponseBody response) :: Either String DataVicSearchResponse of
        Left err ->
            Exception.throwIO (userError ("DataVic public holiday response decode failed: " <> err))
        Right decoded
            | decoded.success -> pure decoded.result.records
            | otherwise -> Exception.throwIO (userError "DataVic public holiday response was not successful")

importDataVicPublicHolidayRecords ::
    (?modelContext :: ModelContext) =>
    [DataVicHolidayRecord] ->
    IO PublicHolidaySyncSummary
importDataVicPublicHolidayRecords records = do
    currentYear <- currentLocalYear
    importDataVicPublicHolidayRecordsForYear currentYear records

importDataVicPublicHolidayRecordsForYear ::
    (?modelContext :: ModelContext) =>
    Integer ->
    [DataVicHolidayRecord] ->
    IO PublicHolidaySyncSummary
importDataVicPublicHolidayRecordsForYear targetYear records = do
    now <- getCurrentTime
    prunedCount <- prunePublicHolidaysOutsideYear targetYear
    results <- forM records \record ->
        case publicHolidayImportFromDataVic record of
            Left reason -> do
                TextIO.putStrLn ("public_holiday_sync_invalid_record: " <> reason)
                pure (Left reason)
            Right holidayImport
                | dayYear holidayImport.holidayDate == targetYear ->
                    Right . Just <$> upsertPublicHoliday now holidayImport
                | otherwise -> pure (Right Nothing)
    let invalidCount = length [reason | Left reason <- results]
    let importedResults = catMaybes [maybeResult | Right maybeResult <- results]
    pure
        PublicHolidaySyncSummary
            { targetYear
            , fetchedCount = length records
            , importedCount = length importedResults
            , insertedCount = length (filter (== InsertedHoliday) importedResults)
            , updatedCount = length (filter (== UpdatedHoliday) importedResults)
            , skippedCount = length records - length importedResults
            , invalidCount
            , prunedCount
            }

publicHolidayImportFromDataVic :: DataVicHolidayRecord -> Either Text PublicHolidayImport
publicHolidayImportFromDataVic record
    | Text.strip record.dateType /= "PUBLIC_HOLIDAY" =
        Left ("Skipping non-public-holiday date type: " <> record.dateType)
    | Text.null holidayName =
        Left "Public holiday record is missing a name"
    | otherwise = do
        holidayDate <- parseDataVicDate record.importantDate
        Right
            PublicHolidayImport
                { jurisdiction = "VIC"
                , holidayDate
                , name = holidayName
                , region = Nothing
                , isRegional = False
                , source = cleanOptionalText record.publisher
                , sourceId = cleanOptionalText record.arun
                , sourceUrl = cleanOptionalText record.source
                , description = cleanOptionalText record.description
                }
    where
        holidayName = Text.strip record.name

parseDataVicDate :: Text -> Either Text Day
parseDataVicDate rawDate =
    case traverse readPositiveInt (Text.splitOn "/" (Text.strip rawDate)) of
        Just [dayOfMonth, month, year] ->
            case fromGregorianValid (fromIntegral year) month dayOfMonth of
                Just day -> Right day
                Nothing  -> Left ("Invalid DataVic date: " <> rawDate)
        _ -> Left ("Expected DataVic date in D/MM/YYYY format, got: " <> rawDate)

data UpsertResult = InsertedHoliday | UpdatedHoliday
    deriving (Eq, Show)

upsertPublicHoliday ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    PublicHolidayImport ->
    IO UpsertResult
upsertPublicHoliday importedAt holidayImport = do
    existingHoliday <-
        query @PublicHoliday
            |> filterWhere (#jurisdiction, holidayImport.jurisdiction)
            |> filterWhere (#holidayDate, holidayImport.holidayDate)
            |> filterWhere (#name, holidayImport.name)
            |> filterWhere (#region, holidayImport.region)
            |> fetchOneOrNothing

    case existingHoliday of
        Nothing -> do
            _ <-
                newRecord @PublicHoliday
                    |> applyPublicHolidayImport importedAt holidayImport
                    |> createRecord
            pure InsertedHoliday
        Just publicHoliday -> do
            _ <-
                publicHoliday
                    |> applyPublicHolidayImport importedAt holidayImport
                    |> updateRecord
            pure UpdatedHoliday

applyPublicHolidayImport :: UTCTime -> PublicHolidayImport -> PublicHoliday -> PublicHoliday
applyPublicHolidayImport importedAt holidayImport publicHoliday =
    publicHoliday
        |> set #jurisdiction holidayImport.jurisdiction
        |> set #holidayDate holidayImport.holidayDate
        |> set #name holidayImport.name
        |> set #region holidayImport.region
        |> set #isRegional holidayImport.isRegional
        |> set #source holidayImport.source
        |> set #sourceId holidayImport.sourceId
        |> set #sourceUrl holidayImport.sourceUrl
        |> set #description holidayImport.description
        |> set #importedAt (Just importedAt)

prunePublicHolidaysOutsideYear ::
    (?modelContext :: ModelContext) =>
    Integer ->
    IO Int
prunePublicHolidaysOutsideYear targetYear = do
    staleHolidays <-
        query @PublicHoliday
            |> filterWhere (#jurisdiction, "VIC" :: Text)
            |> fetch
    let holidaysToDelete =
            filter
                (\publicHoliday -> dayYear publicHoliday.holidayDate /= targetYear)
                staleHolidays
    mapM_ deleteRecord holidaysToDelete
    pure (length holidaysToDelete)

currentLocalYear :: IO Integer
currentLocalYear = dayYear . localDay . zonedTimeToLocalTime <$> getZonedTime

dayYear :: Day -> Integer
dayYear day =
    let (year, _, _) = toGregorian day
     in year

optionalText :: Aeson.Object -> Key -> Parser (Maybe Text)
optionalText object key = cleanOptionalText <$> object Aeson..:? key

cleanOptionalText :: Maybe Text -> Maybe Text
cleanOptionalText value =
    case Text.strip <$> value of
        Just text | not (Text.null text) -> Just text
        _                                -> Nothing

readPositiveInt :: Text -> Maybe Int
readPositiveInt raw = do
    parsed <- readMaybe (cs (Text.strip raw))
    guard (parsed > 0)
    pure parsed
