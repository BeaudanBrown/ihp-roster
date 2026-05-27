module Application.PublicHolidays.Sync
    ( DataVicHolidayRecord (..)
    , PublicHolidayImport (..)
    , PublicHolidaySyncSummary (..)
    , dataVicImportantDatesResourceId
    , fetchDataVicPublicHolidayRecords
    , importDataVicPublicHolidayRecords
    , importDataVicPublicHolidayRecordsForYears
    , parseDataVicDate
    , publicHolidayImportFromDataVic
    , runDataVicPublicHolidaySync
    , runDataVicPublicHolidaySyncForYears
    ) where

import Application.PublicHolidays.Policy (targetPublicHolidayYears)
import qualified Application.PublicHolidays.Policy as PublicHolidayPolicy
import qualified Control.Exception as Exception
import Control.Monad (guard, void)
import qualified Data.Aeson as Aeson
import Data.Aeson.Key (Key)
import Data.Aeson.Types (Parser)
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, fromGregorianValid, toGregorian)
import Data.Traversable (traverse)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (withTransaction)
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
    { targetYears   :: ![Integer]
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
    today <- utctDay <$> getCurrentTime
    runDataVicPublicHolidaySyncForYears (targetPublicHolidayYears today)

runDataVicPublicHolidaySyncForYears ::
    (?modelContext :: ModelContext) =>
    [Integer] ->
    IO PublicHolidaySyncSummary
runDataVicPublicHolidaySyncForYears years = do
    records <- fetchDataVicPublicHolidayRecords
    importDataVicPublicHolidayRecordsForYears years records

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
    today <- utctDay <$> getCurrentTime
    importDataVicPublicHolidayRecordsForYears (targetPublicHolidayYears today) records

importDataVicPublicHolidayRecordsForYears ::
    (?modelContext :: ModelContext) =>
    [Integer] ->
    [DataVicHolidayRecord] ->
    IO PublicHolidaySyncSummary
importDataVicPublicHolidayRecordsForYears years records = do
    now <- getCurrentTime
    let targetYears = nub (sort years)
    parsedImports <- forM records \record ->
        case publicHolidayImportFromDataVic record of
            Left reason -> do
                TextIO.putStrLn ("public_holiday_sync_invalid_record: " <> reason)
                pure (Left reason)
            Right holidayImport -> pure (Right holidayImport)
    let invalidReasons = [reason | Left reason <- parsedImports]
    unless (null invalidReasons) do
        Exception.throwIO (userError (cs ("DataVic public holiday import contains invalid records: " <> Text.intercalate "; " invalidReasons)))

    let validImports = [holidayImport | Right holidayImport <- parsedImports]
    let targetImports = filter (\holidayImport -> dayYear holidayImport.holidayDate `elem` targetYears) validImports
    prunedCount <- withTransaction do
        deletedCount <- deleteTargetPublicHolidays targetYears
        forM_ targetImports \holidayImport ->
            void
                ( newRecord @PublicHoliday
                    |> applyPublicHolidayImport now holidayImport
                    |> createRecord
                )
        pure deletedCount
    pure
        PublicHolidaySyncSummary
            { targetYears
            , fetchedCount = length records
            , importedCount = length targetImports
            , insertedCount = length targetImports
            , updatedCount = 0
            , skippedCount = length records - length targetImports
            , invalidCount = length invalidReasons
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

deleteTargetPublicHolidays ::
    (?modelContext :: ModelContext) =>
    [Integer] ->
    IO Int
deleteTargetPublicHolidays targetYears = do
    existingHolidays <-
        query @PublicHoliday
            |> filterWhere (#jurisdiction, PublicHolidayPolicy.publicHolidayJurisdiction)
            |> filterWhere (#isRegional, False)
            |> fetch
    let holidaysToDelete =
            filter
                (\publicHoliday -> dayYear publicHoliday.holidayDate `elem` targetYears)
                existingHolidays
    mapM_ deleteRecord holidaysToDelete
    pure (length holidaysToDelete)

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
