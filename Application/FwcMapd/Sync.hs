module Application.FwcMapd.Sync where

import Application.FwcMapd.Client
import Application.FwcMapd.Config
import Control.Monad (void)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.Types as Aeson
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import qualified Data.Vector as Vector
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (withTransaction)
import IHP.Prelude

data MapdSyncSummary = MapdSyncSummary
    { syncedAwardFixedIds     :: ![Int]
    , fetchedAwardCount       :: !Int
    , fetchedClassificationCount :: !Int
    , fetchedPayRateCount     :: !Int
    }
    deriving (Eq, Show)

data AwardPayload = AwardPayload
    { awardFixedId         :: !Int
    , awardId              :: !Int
    , code                 :: !Text
    , name                 :: !Text
    , awardOperativeFrom   :: !(Maybe Day)
    , awardOperativeTo     :: !(Maybe Day)
    , publishedYear        :: !(Maybe Int)
    , versionNumber        :: !(Maybe Int)
    , lastModifiedDatetime :: !(Maybe UTCTime)
    }
    deriving (Eq, Show)

data ClassificationPayload = ClassificationPayload
    { classificationFixedId         :: !Int
    , classification                :: !Text
    , classificationLevel           :: !(Maybe Text)
    , parentClassificationName      :: !(Maybe Text)
    , clauseFixedId                 :: !(Maybe Int)
    , clauseDescription             :: !(Maybe Text)
    , clauses                       :: !Aeson.Value
    , nextDownClassificationFixedId :: !(Maybe Int)
    , nextUpClassificationFixedId   :: !(Maybe Int)
    , operativeFrom                 :: !(Maybe Day)
    , operativeTo                   :: !(Maybe Day)
    , publishedYear                 :: !(Maybe Int)
    , versionNumber                 :: !(Maybe Int)
    , lastModifiedDatetime          :: !(Maybe UTCTime)
    }
    deriving (Eq, Show)

data PayRatePayload = PayRatePayload
    { classificationFixedId    :: !(Maybe Int)
    , classification           :: !Text
    , classificationLevel      :: !(Maybe Text)
    , parentClassificationName :: !(Maybe Text)
    , employeeRateTypeCode     :: !(Maybe Text)
    , basePayRateId            :: !(Maybe Text)
    , baseRate                 :: !(Maybe Scientific)
    , baseRateType             :: !(Maybe Text)
    , calculatedPayRateId      :: !(Maybe Text)
    , calculatedRate           :: !(Maybe Scientific)
    , calculatedRateType       :: !(Maybe Text)
    , operativeFrom            :: !(Maybe Day)
    , operativeTo              :: !(Maybe Day)
    , publishedYear            :: !(Maybe Int)
    , versionNumber            :: !(Maybe Int)
    , lastModifiedDatetime     :: !(Maybe UTCTime)
    }
    deriving (Eq, Show)

instance Aeson.FromJSON AwardPayload where
    parseJSON = Aeson.withObject "AwardPayload" \object ->
        AwardPayload
            <$> object Aeson..: "award_fixed_id"
            <*> object Aeson..: "award_id"
            <*> object Aeson..: "code"
            <*> object Aeson..: "name"
            <*> object Aeson..:? "award_operative_from"
            <*> object Aeson..:? "award_operative_to"
            <*> object Aeson..:? "published_year"
            <*> object Aeson..:? "version_number"
            <*> object Aeson..:? "last_modified_datetime"

instance Aeson.FromJSON ClassificationPayload where
    parseJSON = Aeson.withObject "ClassificationPayload" \object ->
        ClassificationPayload
            <$> object Aeson..: "classification_fixed_id"
            <*> object Aeson..: "classification"
            <*> parseOptionalTextishField object "classification_level"
            <*> object Aeson..:? "parent_classification_name"
            <*> object Aeson..:? "clause_fixed_id"
            <*> object Aeson..:? "clause_description"
            <*> object Aeson..:? "clauses" Aeson..!= Aeson.Array mempty
            <*> object Aeson..:? "next_down_classification_fixed_id"
            <*> object Aeson..:? "next_up_classification_fixed_id"
            <*> object Aeson..:? "operative_from"
            <*> object Aeson..:? "operative_to"
            <*> object Aeson..:? "published_year"
            <*> object Aeson..:? "version_number"
            <*> object Aeson..:? "last_modified_datetime"

instance Aeson.FromJSON PayRatePayload where
    parseJSON = Aeson.withObject "PayRatePayload" \object ->
        PayRatePayload
            <$> object Aeson..:? "classification_fixed_id"
            <*> object Aeson..: "classification"
            <*> parseOptionalTextishField object "classification_level"
            <*> object Aeson..:? "parent_classification_name"
            <*> object Aeson..:? "employee_rate_type_code"
            <*> parseOptionalTextishField object "base_pay_rate_id"
            <*> object Aeson..:? "base_rate"
            <*> object Aeson..:? "base_rate_type"
            <*> parseOptionalTextishField object "calculated_pay_rate_id"
            <*> object Aeson..:? "calculated_rate"
            <*> object Aeson..:? "calculated_rate_type"
            <*> object Aeson..:? "operative_from"
            <*> object Aeson..:? "operative_to"
            <*> object Aeson..:? "published_year"
            <*> object Aeson..:? "version_number"
            <*> object Aeson..:? "last_modified_datetime"

parseOptionalTextishField :: Aeson.Object -> Text -> Aeson.Parser (Maybe Text)
parseOptionalTextishField object fieldName = do
    maybeValue <- object Aeson..:? AesonKey.fromText fieldName
    case maybeValue of
        Nothing -> pure Nothing
        Just value -> Just <$> textFromJsonValue value

textFromJsonValue :: Aeson.Value -> Aeson.Parser Text
textFromJsonValue = \case
    Aeson.String value -> pure value
    Aeson.Number value -> pure (cs (show value))
    Aeson.Bool value -> pure (if value then "true" else "false")
    Aeson.Null -> fail "expected non-null JSON value"
    Aeson.Array values -> pure (cs (show (Vector.toList values)))
    Aeson.Object value -> pure (cs (show value))

runConfiguredMapdSync :: (?modelContext :: ModelContext) => IO (Either Text MapdSyncSummary)
runConfiguredMapdSync = do
    maybeConfig <- liftIO loadMapdConfig
    case maybeConfig of
        Nothing -> pure (Left "FWC_MAPD_KEY is not configured.")
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
                    |> set #finishedAt (Just finishedAt)
                    |> updateRecord
                )
            pure summary

fetchAndStore :: (?modelContext :: ModelContext) => MapdConfig -> IO MapdSyncSummary
fetchAndStore config = do
    fetchedAwards <- forM config.awardFixedIds \awardFixedId -> do
        awardValues <- liftIO (fetchAwardValues config awardFixedId)
        classificationValues <- liftIO (fetchClassificationValues config awardFixedId)
        payRateValues <- liftIO (fetchPayRateValues config awardFixedId)
        awards <- decodePayloads "awards" awardValues :: IO [(AwardPayload, Aeson.Value)]
        classifications <- decodePayloads "classifications" classificationValues :: IO [(ClassificationPayload, Aeson.Value)]
        payRates <- decodePayloads "pay rates" payRateValues :: IO [(PayRatePayload, Aeson.Value)]
        pure (awardFixedId, awards, classifications, payRates)

    withTransaction do
        let requestedAwardIds = map (\(awardFixedId, _, _, _) -> awardFixedId) fetchedAwards
        clearExistingCache requestedAwardIds
        syncedAt <- getCurrentTime
        forM_ fetchedAwards \(awardFixedId, awards, classifications, payRates) -> do
            forM_ awards \(payload, rawValue) ->
                void
                    ( newRecord @FwcMapdAward
                        |> set #awardFixedId payload.awardFixedId
                        |> set #awardId payload.awardId
                        |> set #code payload.code
                        |> set #name payload.name
                        |> set #awardOperativeFrom payload.awardOperativeFrom
                        |> set #awardOperativeTo payload.awardOperativeTo
                        |> set #publishedYear payload.publishedYear
                        |> set #versionNumber payload.versionNumber
                        |> set #lastModifiedDatetime payload.lastModifiedDatetime
                        |> set #rawJson rawValue
                        |> set #syncedAt syncedAt
                        |> createRecord
                    )
            forM_ classifications \(payload, rawValue) ->
                void
                    ( newRecord @FwcMapdClassification
                        |> set #awardFixedId awardFixedId
                        |> set #classificationFixedId payload.classificationFixedId
                        |> set #classification payload.classification
                        |> set #classificationLevel payload.classificationLevel
                        |> set #parentClassificationName payload.parentClassificationName
                        |> set #clauseFixedId payload.clauseFixedId
                        |> set #clauseDescription payload.clauseDescription
                        |> set #clauses payload.clauses
                        |> set #nextDownClassificationFixedId payload.nextDownClassificationFixedId
                        |> set #nextUpClassificationFixedId payload.nextUpClassificationFixedId
                        |> set #operativeFrom payload.operativeFrom
                        |> set #operativeTo payload.operativeTo
                        |> set #publishedYear payload.publishedYear
                        |> set #versionNumber payload.versionNumber
                        |> set #lastModifiedDatetime payload.lastModifiedDatetime
                        |> set #rawJson rawValue
                        |> set #syncedAt syncedAt
                        |> createRecord
                    )
            forM_ payRates \(payload, rawValue) ->
                void
                    ( newRecord @FwcMapdPayRate
                        |> set #awardFixedId awardFixedId
                        |> set #classificationFixedId payload.classificationFixedId
                        |> set #classification payload.classification
                        |> set #classificationLevel payload.classificationLevel
                        |> set #parentClassificationName payload.parentClassificationName
                        |> set #employeeRateTypeCode payload.employeeRateTypeCode
                        |> set #basePayRateId payload.basePayRateId
                        |> set #baseRate payload.baseRate
                        |> set #baseRateType payload.baseRateType
                        |> set #calculatedPayRateId payload.calculatedPayRateId
                        |> set #calculatedRate payload.calculatedRate
                        |> set #calculatedRateType payload.calculatedRateType
                        |> set #operativeFrom payload.operativeFrom
                        |> set #operativeTo payload.operativeTo
                        |> set #publishedYear payload.publishedYear
                        |> set #versionNumber payload.versionNumber
                        |> set #lastModifiedDatetime payload.lastModifiedDatetime
                        |> set #rawJson rawValue
                        |> set #syncedAt syncedAt
                        |> createRecord
                    )

        let fetchedAwardCount = sum (map (\(_, awards, _, _) -> length awards) fetchedAwards)
        let fetchedClassificationCount = sum (map (\(_, _, classifications, _) -> length classifications) fetchedAwards)
        let fetchedPayRateCount = sum (map (\(_, _, _, payRates) -> length payRates) fetchedAwards)
        pure
            MapdSyncSummary
                { syncedAwardFixedIds = requestedAwardIds
                , fetchedAwardCount = fetchedAwardCount
                , fetchedClassificationCount = fetchedClassificationCount
                , fetchedPayRateCount = fetchedPayRateCount
                }

decodePayloads :: Aeson.FromJSON a => Text -> [Aeson.Value] -> IO [(a, Aeson.Value)]
decodePayloads label rawValues =
    forM rawValues \rawValue ->
        case Aeson.parseEither Aeson.parseJSON rawValue of
            Left errorMessage -> Exception.throwIO (userError ("FWC MAPD " <> cs label <> " decode failed: " <> errorMessage))
            Right payload -> pure (payload, rawValue)

clearExistingCache :: (?modelContext :: ModelContext) => [Int] -> IO ()
clearExistingCache awardFixedIds = do
    existingPayRates <-
        query @FwcMapdPayRate
            |> filterWhereIn (#awardFixedId, awardFixedIds)
            |> fetch
    mapM_ deleteRecord existingPayRates

    existingClassifications <-
        query @FwcMapdClassification
            |> filterWhereIn (#awardFixedId, awardFixedIds)
            |> fetch
    mapM_ deleteRecord existingClassifications

    existingAwards <-
        query @FwcMapdAward
            |> filterWhereIn (#awardFixedId, awardFixedIds)
            |> fetch
    mapM_ deleteRecord existingAwards
