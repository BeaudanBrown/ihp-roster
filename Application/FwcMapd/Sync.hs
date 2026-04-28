module Application.FwcMapd.Sync where

import Application.FwcMapd.Client
import Application.FwcMapd.Config
import Control.Monad (foldM, void)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.Types as Aeson
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Set as Set
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
    , fetchedPenaltyRateCount :: !Int
    , fetchedWageAllowanceCount :: !Int
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

data PenaltyRatePayload = PenaltyRatePayload
    { penaltyClassificationFixedId :: !(Maybe Int)
    , penaltyClassification :: !Text
    , penaltyClassificationLevel :: !(Maybe Text)
    , penaltyParentClassificationName :: !(Maybe Text)
    , penaltyClauseDescription :: !(Maybe Text)
    , penaltyEmployeeRateTypeCode :: !(Maybe Text)
    , penaltyBasePayRateId :: !(Maybe Text)
    , penaltyFixedId :: !(Maybe Int)
    , penaltyDescription :: !(Maybe Text)
    , penaltyText :: !(Maybe Text)
    , penaltyRate :: !(Maybe Scientific)
    , penaltyRateUnit :: !(Maybe Text)
    , penaltyCalculatedValue :: !(Maybe Scientific)
    , penaltyOperativeFrom :: !(Maybe Day)
    , penaltyOperativeTo :: !(Maybe Day)
    , penaltyPublishedYear :: !(Maybe Int)
    , penaltyVersionNumber :: !(Maybe Int)
    , penaltyLastModifiedDatetime :: !(Maybe UTCTime)
    }
    deriving (Eq, Show)

data WageAllowancePayload = WageAllowancePayload
    { wageAllowanceFixedId :: !(Maybe Int)
    , wageAllowanceClauseFixedId :: !(Maybe Int)
    , wageAllowanceClauses :: !(Maybe Text)
    , wageAllowance :: !(Maybe Text)
    , wageAllowanceType :: !(Maybe Text)
    , wageAllowanceIsAllPurpose :: !(Maybe Bool)
    , wageAllowanceRate :: !(Maybe Scientific)
    , wageAllowanceBaseRate :: !(Maybe Scientific)
    , wageAllowanceBasePayRateId :: !(Maybe Text)
    , wageAllowanceRateUnit :: !(Maybe Text)
    , wageAllowanceAmount :: !(Maybe Scientific)
    , wageAllowancePaymentFrequency :: !(Maybe Text)
    , wageAllowanceOperativeFrom :: !(Maybe Day)
    , wageAllowanceOperativeTo :: !(Maybe Day)
    , wageAllowancePublishedYear :: !(Maybe Int)
    , wageAllowanceVersionNumber :: !(Maybe Int)
    , wageAllowanceLastModifiedDatetime :: !(Maybe UTCTime)
    }
    deriving (Eq, Show)

data AwardYearScope
    = AllAwardYears
    | LatestActiveAwardYear
    deriving (Eq, Show)

data MapdCurationProfile = MapdCurationProfile
    { awardYearScope         :: !AwardYearScope
    , employeeRateTypeCodes  :: ![Text]
    , requireHourlyRate      :: !Bool
    , excludedKeywords       :: ![Text]
    , includedKeywords       :: ![Text]
    }
    deriving (Eq, Show)

barVenueCurationProfile :: MapdCurationProfile
barVenueCurationProfile =
    MapdCurationProfile
        { awardYearScope = LatestActiveAwardYear
        , employeeRateTypeCodes = ["AD"]
        , requireHourlyRate = True
        , excludedKeywords =
            [ "apprentice"
            , "apprenticeship"
            , "trainee"
            , "training"
            , "junior"
            , "years of age"
            , "casino"
            , "gaming"
            , "surveillance"
            , "airport catering"
            , "loadedrates"
            ]
        , includedKeywords =
            [ "introductory level"
            , "food and beverage attendant"
            , "food and beverage supervisor"
            , "bar attendant"
            , "bar"
            ]
        }

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

instance Aeson.FromJSON PenaltyRatePayload where
    parseJSON = Aeson.withObject "PenaltyRatePayload" \object ->
        PenaltyRatePayload
            <$> object Aeson..:? "classification_fixed_id"
            <*> (fromMaybe "" <$> object Aeson..:? "classification")
            <*> parseOptionalTextishField object "classification_level"
            <*> object Aeson..:? "parent_classification_name"
            <*> object Aeson..:? "clause_description"
            <*> object Aeson..:? "employee_rate_type_code"
            <*> parseOptionalTextishField object "base_pay_rate_id"
            <*> object Aeson..:? "penalty_fixed_id"
            <*> object Aeson..:? "penalty_description"
            <*> parseOptionalTextishField object "penalty_text"
            <*> object Aeson..:? "rate"
            <*> object Aeson..:? "penalty_rate_unit"
            <*> object Aeson..:? "penalty_calculated_value"
            <*> object Aeson..:? "operative_from"
            <*> object Aeson..:? "operative_to"
            <*> object Aeson..:? "published_year"
            <*> object Aeson..:? "version_number"
            <*> object Aeson..:? "last_modified_datetime"

instance Aeson.FromJSON WageAllowancePayload where
    parseJSON = Aeson.withObject "WageAllowancePayload" \object ->
        WageAllowancePayload
            <$> object Aeson..:? "wage_allowance_fixed_id"
            <*> object Aeson..:? "clause_fixed_id"
            <*> parseOptionalTextishField object "clauses"
            <*> object Aeson..:? "allowance"
            <*> object Aeson..:? "type"
            <*> object Aeson..:? "is_all_purpose"
            <*> object Aeson..:? "rate"
            <*> object Aeson..:? "base_rate"
            <*> parseOptionalTextishField object "base_pay_rate_id"
            <*> object Aeson..:? "rate_unit"
            <*> object Aeson..:? "allowance_amount"
            <*> object Aeson..:? "payment_frequency"
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
                    |> set #fetchedPenaltyRateCount summary.fetchedPenaltyRateCount
                    |> set #fetchedWageAllowanceCount summary.fetchedWageAllowanceCount
                    |> set #finishedAt (Just finishedAt)
                    |> updateRecord
                )
            pure summary

fetchAndStore :: (?modelContext :: ModelContext) => MapdConfig -> IO MapdSyncSummary
fetchAndStore config = do
    asOfDate <- utctDay <$> getCurrentTime
    fetchedAwards <- forM config.awardFixedIds \awardFixedId -> do
        awardValues <- liftIO (fetchAwardValues config awardFixedId)
        classificationValues <- liftIO (fetchClassificationValues config awardFixedId)
        payRateValues <- liftIO (fetchPayRateValues config awardFixedId)
        wageAllowanceValues <- liftIO (fetchWageAllowanceValues config awardFixedId)
        awards <- decodePayloads "awards" awardValues :: IO [(AwardPayload, Aeson.Value)]
        classifications <- decodePayloads "classifications" classificationValues :: IO [(ClassificationPayload, Aeson.Value)]
        payRates <- decodePayloads "pay rates" payRateValues :: IO [(PayRatePayload, Aeson.Value)]
        wageAllowances <- decodePayloads "wage allowances" wageAllowanceValues :: IO [(WageAllowancePayload, Aeson.Value)]
        let (_, _, _, retainedPayRatesForPenaltyFetch, _) =
                curateAwardData barVenueCurationProfile asOfDate (awardFixedId, awards, classifications, payRates, [])
            retainedBasePayRateIds =
                retainedPayRatesForPenaltyFetch
                    |> mapMaybe (\(payload, _) -> payload.basePayRateId)
                    |> Set.fromList
                    |> Set.toList
        penaltyRateValues <- liftIO (concat <$> forM retainedBasePayRateIds (fetchPenaltyRateValuesForBasePayRateId config awardFixedId))
        penaltyRates <- decodePayloads "penalty rates" penaltyRateValues :: IO [(PenaltyRatePayload, Aeson.Value)]
        let curatedAwardData = curateAwardData barVenueCurationProfile asOfDate (awardFixedId, awards, classifications, payRates, penaltyRates)
            retainedWageAllowances = curateWageAllowances barVenueCurationProfile asOfDate wageAllowances
        pure (curatedAwardData, retainedWageAllowances)

    withTransaction do
        let requestedAwardIds = map (\((awardFixedId, _, _, _, _), _) -> awardFixedId) fetchedAwards
        clearExistingCache requestedAwardIds
        syncedAt <- getCurrentTime
        forM_ fetchedAwards \((awardFixedId, awards, classifications, payRates, penaltyRates), wageAllowances) -> do
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
            forM_ penaltyRates \(payload, rawValue) ->
                void
                    ( newRecord @FwcMapdPenaltyRate
                        |> set #awardFixedId awardFixedId
                        |> set #classificationFixedId payload.penaltyClassificationFixedId
                        |> set #classification payload.penaltyClassification
                        |> set #classificationLevel payload.penaltyClassificationLevel
                        |> set #parentClassificationName payload.penaltyParentClassificationName
                        |> set #clauseDescription payload.penaltyClauseDescription
                        |> set #employeeRateTypeCode payload.penaltyEmployeeRateTypeCode
                        |> set #basePayRateId payload.penaltyBasePayRateId
                        |> set #penaltyFixedId payload.penaltyFixedId
                        |> set #penaltyDescription payload.penaltyDescription
                        |> set #penaltyText payload.penaltyText
                        |> set #rate payload.penaltyRate
                        |> set #penaltyRateUnit payload.penaltyRateUnit
                        |> set #penaltyCalculatedValue payload.penaltyCalculatedValue
                        |> set #operativeFrom payload.penaltyOperativeFrom
                        |> set #operativeTo payload.penaltyOperativeTo
                        |> set #publishedYear payload.penaltyPublishedYear
                        |> set #versionNumber payload.penaltyVersionNumber
                        |> set #lastModifiedDatetime payload.penaltyLastModifiedDatetime
                        |> set #rawJson rawValue
                        |> set #syncedAt syncedAt
                        |> createRecord
                    )
            forM_ wageAllowances \(payload, rawValue) ->
                void
                    ( newRecord @FwcMapdWageAllowance
                        |> set #awardFixedId awardFixedId
                        |> set #wageAllowanceFixedId payload.wageAllowanceFixedId
                        |> set #clauseFixedId payload.wageAllowanceClauseFixedId
                        |> set #clauses payload.wageAllowanceClauses
                        |> set #allowance payload.wageAllowance
                        |> set #allowanceType payload.wageAllowanceType
                        |> set #isAllPurpose payload.wageAllowanceIsAllPurpose
                        |> set #rate payload.wageAllowanceRate
                        |> set #baseRate payload.wageAllowanceBaseRate
                        |> set #basePayRateId payload.wageAllowanceBasePayRateId
                        |> set #rateUnit payload.wageAllowanceRateUnit
                        |> set #allowanceAmount payload.wageAllowanceAmount
                        |> set #paymentFrequency payload.wageAllowancePaymentFrequency
                        |> set #operativeFrom payload.wageAllowanceOperativeFrom
                        |> set #operativeTo payload.wageAllowanceOperativeTo
                        |> set #publishedYear payload.wageAllowancePublishedYear
                        |> set #versionNumber payload.wageAllowanceVersionNumber
                        |> set #lastModifiedDatetime payload.wageAllowanceLastModifiedDatetime
                        |> set #rawJson rawValue
                        |> set #syncedAt syncedAt
                        |> createRecord
                    )
            populateAwardLevelProjection awardFixedId syncedAt

        let fetchedAwardCount = sum (map (\((_, awards, _, _, _), _) -> length awards) fetchedAwards)
        let fetchedClassificationCount = sum (map (\((_, _, classifications, _, _), _) -> length classifications) fetchedAwards)
        let fetchedPayRateCount = sum (map (\((_, _, _, payRates, _), _) -> length payRates) fetchedAwards)
        let fetchedPenaltyRateCount = sum (map (\((_, _, _, _, penaltyRates), _) -> length penaltyRates) fetchedAwards)
        let fetchedWageAllowanceCount = sum (map (\(_, wageAllowances) -> length wageAllowances) fetchedAwards)
        pure
            MapdSyncSummary
                { syncedAwardFixedIds = requestedAwardIds
                , fetchedAwardCount = fetchedAwardCount
                , fetchedClassificationCount = fetchedClassificationCount
                , fetchedPayRateCount = fetchedPayRateCount
                , fetchedPenaltyRateCount = fetchedPenaltyRateCount
                , fetchedWageAllowanceCount = fetchedWageAllowanceCount
                }

decodePayloads :: Aeson.FromJSON a => Text -> [Aeson.Value] -> IO [(a, Aeson.Value)]
decodePayloads label rawValues =
    forM rawValues \rawValue ->
        case Aeson.parseEither Aeson.parseJSON rawValue of
            Left errorMessage -> Exception.throwIO (userError ("FWC MAPD " <> cs label <> " decode failed: " <> errorMessage))
            Right payload -> pure (payload, rawValue)

populateAwardLevelProjection :: (?modelContext :: ModelContext) => Int -> UTCTime -> IO ()
populateAwardLevelProjection awardFixedId syncedAt = do
    classifications <-
        query @FwcMapdClassification
            |> filterWhere (#awardFixedId, awardFixedId)
            |> filterWhere (#syncedAt, syncedAt)
            |> orderByAsc #classification
            |> fetch
    markMissingAwardLevelsInactive awardFixedId (Set.fromList (map (.classificationFixedId) classifications))
    awardLevels <- forM classifications (upsertAwardLevel syncedAt)

    let awardLevelByClassificationFixedId =
            Map.fromList
                (map (\awardLevel -> (awardLevel.classificationFixedId, awardLevel)) awardLevels)

    payRates <-
        query @FwcMapdPayRate
            |> filterWhere (#awardFixedId, awardFixedId)
            |> filterWhere (#syncedAt, syncedAt)
            |> orderByAsc #classification
            |> fetch
    let awardLevelByBasePayRateId =
            payRates
                |> mapMaybe
                    ( \payRate -> do
                        basePayRateId <- payRate.basePayRateId
                        awardLevel <- payRate.classificationFixedId >>= (`Map.lookup` awardLevelByClassificationFixedId)
                        pure (basePayRateId, awardLevel)
                    )
                |> Map.fromList
        payRateByBasePayRateId =
            payRates
                |> mapMaybe
                    ( \payRate -> do
                        basePayRateId <- payRate.basePayRateId
                        pure (basePayRateId, payRate)
                    )
                |> Map.fromList
    baseRateSeen <-
        foldM
            (createBaseRateIfNew awardLevelByClassificationFixedId)
            Set.empty
            payRates

    penaltyRates <-
        query @FwcMapdPenaltyRate
            |> filterWhere (#awardFixedId, awardFixedId)
            |> filterWhere (#syncedAt, syncedAt)
            |> orderByAsc #classification
            |> fetch
    void $
        foldM
            (createCasualBaseRateIfNew awardLevelByBasePayRateId payRateByBasePayRateId)
            baseRateSeen
            penaltyRates
    void $
        foldM
            (createPenaltyRateIfNew awardLevelByClassificationFixedId awardLevelByBasePayRateId)
            Set.empty
            penaltyRates
    populateTimePenaltyAllowances awardFixedId syncedAt

markMissingAwardLevelsInactive :: (?modelContext :: ModelContext) => Int -> Set.Set Int -> IO ()
markMissingAwardLevelsInactive awardFixedId currentClassificationFixedIds = do
    existingAwardLevels <-
        query @AwardLevel
            |> filterWhere (#awardFixedId, awardFixedId)
            |> fetch
    forM_ existingAwardLevels \awardLevel ->
        when (awardLevel.isActive && not (Set.member awardLevel.classificationFixedId currentClassificationFixedIds)) do
            void (awardLevel |> set #isActive False |> updateRecord)

upsertAwardLevel :: (?modelContext :: ModelContext) => UTCTime -> FwcMapdClassification -> IO AwardLevel
upsertAwardLevel syncedAt classification = do
    existingAwardLevel <-
        query @AwardLevel
            |> filterWhere (#awardFixedId, classification.awardFixedId)
            |> filterWhere (#classificationFixedId, classification.classificationFixedId)
            |> fetchOneOrNothing
    case existingAwardLevel of
        Just awardLevel ->
            awardLevel
                |> set #classification classification.classification
                |> set #classificationLevel classification.classificationLevel
                |> set #parentClassificationName classification.parentClassificationName
                |> set #clauseDescription classification.clauseDescription
                |> set #operativeFrom classification.operativeFrom
                |> set #operativeTo classification.operativeTo
                |> set #publishedYear classification.publishedYear
                |> set #isActive True
                |> set #rawJson classification.rawJson
                |> set #syncedAt syncedAt
                |> updateRecord
        Nothing ->
            newRecord @AwardLevel
                |> set #awardFixedId classification.awardFixedId
                |> set #classificationFixedId classification.classificationFixedId
                |> set #classification classification.classification
                |> set #classificationLevel classification.classificationLevel
                |> set #parentClassificationName classification.parentClassificationName
                |> set #clauseDescription classification.clauseDescription
                |> set #operativeFrom classification.operativeFrom
                |> set #operativeTo classification.operativeTo
                |> set #publishedYear classification.publishedYear
                |> set #isActive True
                |> set #rawJson classification.rawJson
                |> set #syncedAt syncedAt
                |> createRecord

createBaseRateIfNew ::
    (?modelContext :: ModelContext) =>
    Map.Map Int AwardLevel ->
    Set.Set (UUID, StaffEmploymentBasisEnum, Maybe Day, Maybe Day) ->
    FwcMapdPayRate ->
    IO (Set.Set (UUID, StaffEmploymentBasisEnum, Maybe Day, Maybe Day))
createBaseRateIfNew awardLevelByClassificationFixedId seen payRate =
    case (payRate.classificationFixedId >>= (`Map.lookup` awardLevelByClassificationFixedId), ordinaryHourlyRate payRate) of
        (Just awardLevel, Just (employmentBasis, hourlyRate, rateLabel)) -> do
            let key = (unpackId awardLevel.id, employmentBasis, payRate.operativeFrom, payRate.operativeTo)
            if Set.member key seen
                then pure seen
                else do
                    upsertBaseRate
                        awardLevel
                        employmentBasis
                        (unpackId payRate.id)
                        hourlyRate
                        rateLabel
                        payRate.operativeFrom
                        payRate.operativeTo
                        payRate.publishedYear
                    pure (Set.insert key seen)
        _ -> pure seen

createCasualBaseRateIfNew ::
    (?modelContext :: ModelContext) =>
    Map.Map Text AwardLevel ->
    Map.Map Text FwcMapdPayRate ->
    Set.Set (UUID, StaffEmploymentBasisEnum, Maybe Day, Maybe Day) ->
    FwcMapdPenaltyRate ->
    IO (Set.Set (UUID, StaffEmploymentBasisEnum, Maybe Day, Maybe Day))
createCasualBaseRateIfNew awardLevelByBasePayRateId payRateByBasePayRateId seen penaltyRate =
    case (penaltyRate.basePayRateId, penaltyRate.penaltyCalculatedValue) of
        (Just basePayRateId, Just hourlyRate)
            | isCasualOrdinaryPenaltyRate penaltyRate ->
                case (Map.lookup basePayRateId awardLevelByBasePayRateId, Map.lookup basePayRateId payRateByBasePayRateId) of
                    (Just awardLevel, Just sourcePayRate) -> do
                        let key = (unpackId awardLevel.id, Casual, penaltyRate.operativeFrom, penaltyRate.operativeTo)
                        if Set.member key seen
                            then pure seen
                            else do
                                upsertBaseRate
                                    awardLevel
                                    Casual
                                    (unpackId sourcePayRate.id)
                                    hourlyRate
                                    "Casual ordinary hours"
                                    penaltyRate.operativeFrom
                                    penaltyRate.operativeTo
                                    penaltyRate.publishedYear
                                pure (Set.insert key seen)
                    _ -> pure seen
        _ -> pure seen

createPenaltyRateIfNew ::
    (?modelContext :: ModelContext) =>
    Map.Map Int AwardLevel ->
    Map.Map Text AwardLevel ->
    Set.Set (UUID, StaffEmploymentBasisEnum, AwardPenaltyKindEnum, Maybe Day, Maybe Day) ->
    FwcMapdPenaltyRate ->
    IO (Set.Set (UUID, StaffEmploymentBasisEnum, AwardPenaltyKindEnum, Maybe Day, Maybe Day))
createPenaltyRateIfNew awardLevelByClassificationFixedId awardLevelByBasePayRateId seen penaltyRate =
    case (resolvePenaltyAwardLevel awardLevelByClassificationFixedId awardLevelByBasePayRateId penaltyRate, normalisePenaltyKindFromRecord penaltyRate, penaltyRate.penaltyCalculatedValue) of
        (Just awardLevel, Just penaltyKind, Just hourlyRate) -> do
            let employmentBasis = penaltyEmploymentBasisFromRecord penaltyRate
                key = (unpackId awardLevel.id, employmentBasis, penaltyKind, penaltyRate.operativeFrom, penaltyRate.operativeTo)
            if Set.member key seen
                then pure seen
                else do
                    upsertPenaltyRate
                        awardLevel
                        employmentBasis
                        penaltyKind
                        (unpackId penaltyRate.id)
                        hourlyRate
                        penaltyRate.operativeFrom
                        penaltyRate.operativeTo
                        penaltyRate.publishedYear
                    pure (Set.insert key seen)
        _ -> pure seen

upsertBaseRate ::
    (?modelContext :: ModelContext) =>
    AwardLevel ->
    StaffEmploymentBasisEnum ->
    UUID ->
    Scientific ->
    Text ->
    Maybe Day ->
    Maybe Day ->
    Maybe Int ->
    IO ()
upsertBaseRate awardLevel employmentBasis fwcMapdPayRateId hourlyRate rateLabel operativeFrom operativeTo publishedYear = do
    existingBaseRate <-
        query @AwardLevelBaseRate
            |> filterWhere (#awardLevelId, unpackId awardLevel.id)
            |> filterWhere (#employmentBasis, employmentBasis)
            |> filterWhere (#operativeFrom, operativeFrom)
            |> filterWhere (#operativeTo, operativeTo)
            |> fetchOneOrNothing
    void case existingBaseRate of
        Just baseRate ->
            baseRate
                |> set #fwcMapdPayRateId fwcMapdPayRateId
                |> set #hourlyRate hourlyRate
                |> set #rateLabel rateLabel
                |> set #publishedYear publishedYear
                |> updateRecord
        Nothing ->
            newRecord @AwardLevelBaseRate
                |> set #awardLevelId (unpackId awardLevel.id)
                |> set #employmentBasis employmentBasis
                |> set #fwcMapdPayRateId fwcMapdPayRateId
                |> set #hourlyRate hourlyRate
                |> set #rateLabel rateLabel
                |> set #operativeFrom operativeFrom
                |> set #operativeTo operativeTo
                |> set #publishedYear publishedYear
                |> createRecord

upsertPenaltyRate ::
    (?modelContext :: ModelContext) =>
    AwardLevel ->
    StaffEmploymentBasisEnum ->
    AwardPenaltyKindEnum ->
    UUID ->
    Scientific ->
    Maybe Day ->
    Maybe Day ->
    Maybe Int ->
    IO ()
upsertPenaltyRate awardLevel employmentBasis penaltyKind fwcMapdPenaltyRateId hourlyRate operativeFrom operativeTo publishedYear = do
    existingPenaltyRate <-
        query @AwardLevelPenaltyRate
            |> filterWhere (#awardLevelId, unpackId awardLevel.id)
            |> filterWhere (#employmentBasis, employmentBasis)
            |> filterWhere (#penaltyKind, penaltyKind)
            |> filterWhere (#operativeFrom, operativeFrom)
            |> filterWhere (#operativeTo, operativeTo)
            |> fetchOneOrNothing
    void case existingPenaltyRate of
        Just penaltyRate ->
            penaltyRate
                |> set #fwcMapdPenaltyRateId fwcMapdPenaltyRateId
                |> set #hourlyRate hourlyRate
                |> set #startsAtTime (penaltyWindowStart penaltyKind)
                |> set #endsAtTime (penaltyWindowEnd penaltyKind)
                |> set #publishedYear publishedYear
                |> updateRecord
        Nothing ->
            newRecord @AwardLevelPenaltyRate
                |> set #awardLevelId (unpackId awardLevel.id)
                |> set #employmentBasis employmentBasis
                |> set #penaltyKind penaltyKind
                |> set #fwcMapdPenaltyRateId fwcMapdPenaltyRateId
                |> set #hourlyRate hourlyRate
                |> set #startsAtTime (penaltyWindowStart penaltyKind)
                |> set #endsAtTime (penaltyWindowEnd penaltyKind)
                |> set #operativeFrom operativeFrom
                |> set #operativeTo operativeTo
                |> set #publishedYear publishedYear
                |> createRecord

populateTimePenaltyAllowances :: (?modelContext :: ModelContext) => Int -> UTCTime -> IO ()
populateTimePenaltyAllowances awardFixedId syncedAt = do
    wageAllowances <-
        query @FwcMapdWageAllowance
            |> filterWhere (#awardFixedId, awardFixedId)
            |> filterWhere (#syncedAt, syncedAt)
            |> orderByAsc #createdAt
            |> fetch
    void $
        foldM
            createTimePenaltyAllowanceIfNew
            Set.empty
            wageAllowances

createTimePenaltyAllowanceIfNew ::
    (?modelContext :: ModelContext) =>
    Set.Set (Int, AwardPenaltyKindEnum, Maybe Day, Maybe Day) ->
    FwcMapdWageAllowance ->
    IO (Set.Set (Int, AwardPenaltyKindEnum, Maybe Day, Maybe Day))
createTimePenaltyAllowanceIfNew seen wageAllowance =
    case (normaliseTimePenaltyKindFromWageAllowance wageAllowance, wageAllowance.allowanceAmount) of
        (Just penaltyKind, Just hourlyAmount) -> do
            let key = (wageAllowance.awardFixedId, penaltyKind, wageAllowance.operativeFrom, wageAllowance.operativeTo)
            if Set.member key seen
                then pure seen
                else do
                    upsertTimePenaltyAllowance wageAllowance penaltyKind hourlyAmount
                    pure (Set.insert key seen)
        _ -> pure seen

upsertTimePenaltyAllowance ::
    (?modelContext :: ModelContext) =>
    FwcMapdWageAllowance ->
    AwardPenaltyKindEnum ->
    Scientific ->
    IO ()
upsertTimePenaltyAllowance wageAllowance penaltyKind hourlyAmount = do
    existingAllowance <-
        query @AwardTimePenaltyAllowance
            |> filterWhere (#awardFixedId, wageAllowance.awardFixedId)
            |> filterWhere (#penaltyKind, penaltyKind)
            |> filterWhere (#operativeFrom, wageAllowance.operativeFrom)
            |> filterWhere (#operativeTo, wageAllowance.operativeTo)
            |> fetchOneOrNothing
    void case existingAllowance of
        Just allowance ->
            allowance
                |> set #fwcMapdWageAllowanceId (unpackId wageAllowance.id)
                |> set #ratePercent wageAllowance.rate
                |> set #hourlyAmount hourlyAmount
                |> set #startsAtTime (penaltyWindowStart penaltyKind)
                |> set #endsAtTime (penaltyWindowEnd penaltyKind)
                |> set #publishedYear wageAllowance.publishedYear
                |> updateRecord
        Nothing ->
            newRecord @AwardTimePenaltyAllowance
                |> set #awardFixedId wageAllowance.awardFixedId
                |> set #penaltyKind penaltyKind
                |> set #fwcMapdWageAllowanceId (unpackId wageAllowance.id)
                |> set #ratePercent wageAllowance.rate
                |> set #hourlyAmount hourlyAmount
                |> set #startsAtTime (penaltyWindowStart penaltyKind)
                |> set #endsAtTime (penaltyWindowEnd penaltyKind)
                |> set #operativeFrom wageAllowance.operativeFrom
                |> set #operativeTo wageAllowance.operativeTo
                |> set #publishedYear wageAllowance.publishedYear
                |> createRecord

resolvePenaltyAwardLevel :: Map.Map Int AwardLevel -> Map.Map Text AwardLevel -> FwcMapdPenaltyRate -> Maybe AwardLevel
resolvePenaltyAwardLevel awardLevelByClassificationFixedId awardLevelByBasePayRateId penaltyRate =
    case penaltyRate.basePayRateId >>= (`Map.lookup` awardLevelByBasePayRateId) of
        Just awardLevel -> Just awardLevel
        Nothing         -> penaltyRate.classificationFixedId >>= (`Map.lookup` awardLevelByClassificationFixedId)

ordinaryHourlyRate :: FwcMapdPayRate -> Maybe (StaffEmploymentBasisEnum, Scientific, Text)
ordinaryHourlyRate payRate
    | isHourlyRateType payRate.calculatedRateType =
        fmap
            (\hourlyRate -> (basisFromRateType payRate.calculatedRateType, hourlyRate, fromMaybe "Hourly" payRate.calculatedRateType))
            payRate.calculatedRate
    | isHourlyRateType payRate.baseRateType =
        fmap
            (\hourlyRate -> (basisFromRateType payRate.baseRateType, hourlyRate, fromMaybe "Hourly" payRate.baseRateType))
            payRate.baseRate
    | otherwise = Nothing

basisFromRateType :: Maybe Text -> StaffEmploymentBasisEnum
basisFromRateType maybeRateType =
    if maybe False (Text.isInfixOf "casual" . Text.toLower) maybeRateType
        then Casual
        else Permanent

normalisePenaltyKindFromRecord :: FwcMapdPenaltyRate -> Maybe AwardPenaltyKindEnum
normalisePenaltyKindFromRecord penaltyRate =
    normalisePenaltyKindText
        (Text.intercalate " " [fromMaybe "" penaltyRate.penaltyDescription, fromMaybe "" penaltyRate.penaltyText, fromMaybe "" penaltyRate.clauseDescription])

normalisePenaltyKind :: PenaltyRatePayload -> Maybe AwardPenaltyKindEnum
normalisePenaltyKind penaltyRate =
    normalisePenaltyKindText
        (Text.intercalate " " [fromMaybe "" penaltyRate.penaltyDescription, fromMaybe "" penaltyRate.penaltyText])

normaliseTimePenaltyKindFromWageAllowance :: FwcMapdWageAllowance -> Maybe AwardPenaltyKindEnum
normaliseTimePenaltyKindFromWageAllowance wageAllowance =
    case normalisePenaltyKindText (searchableWageAllowanceRecordText wageAllowance) of
        Just EveningAfter7Pm -> Just EveningAfter7Pm
        Just LateNightAfterMidnight -> Just LateNightAfterMidnight
        _ -> Nothing

normaliseTimePenaltyKind :: WageAllowancePayload -> Maybe AwardPenaltyKindEnum
normaliseTimePenaltyKind wageAllowance =
    case normalisePenaltyKindText (searchableWageAllowanceText wageAllowance) of
        Just EveningAfter7Pm -> Just EveningAfter7Pm
        Just LateNightAfterMidnight -> Just LateNightAfterMidnight
        _ -> Nothing

normalisePenaltyKindText :: Text -> Maybe AwardPenaltyKindEnum
normalisePenaltyKindText rawText
    | containsAny ["public holiday", "public holidays"] text = Just PublicHolidayPenalty
    | containsAny ["saturday"] text = Just SaturdayPenalty
    | containsAny ["sunday"] text = Just SundayPenalty
    | containsAny ["7.00 pm", "7pm", "after 7", "evening"] text = Just EveningAfter7Pm
    | containsAny ["midnight", "after 12", "after midnight"] text = Just LateNightAfterMidnight
    | otherwise = Nothing
    where
        text = Text.toLower rawText

containsAny :: [Text] -> Text -> Bool
containsAny needles haystack =
    any (`Text.isInfixOf` haystack) needles

penaltyEmploymentBasisFromRecord :: FwcMapdPenaltyRate -> StaffEmploymentBasisEnum
penaltyEmploymentBasisFromRecord penaltyRate =
    if containsAny ["casual"] (Text.toLower (Text.intercalate " " [fromMaybe "" penaltyRate.penaltyDescription, fromMaybe "" penaltyRate.penaltyText, fromMaybe "" penaltyRate.clauseDescription]))
        then Casual
        else Permanent

isCasualOrdinaryPenaltyRate :: FwcMapdPenaltyRate -> Bool
isCasualOrdinaryPenaltyRate penaltyRate =
    containsAny ["casual"] searchableText
        && containsAny ["ordinary hours"] searchableText
        && not (containsAny ["overtime"] searchableText)
    where
        searchableText =
            Text.toLower
                (Text.intercalate " " [fromMaybe "" penaltyRate.penaltyDescription, fromMaybe "" penaltyRate.penaltyText, fromMaybe "" penaltyRate.clauseDescription])

penaltyWindowStart :: AwardPenaltyKindEnum -> Maybe TimeOfDay
penaltyWindowStart EveningAfter7Pm = Just (TimeOfDay 19 0 0)
penaltyWindowStart LateNightAfterMidnight = Just (TimeOfDay 0 0 0)
penaltyWindowStart _ = Nothing

penaltyWindowEnd :: AwardPenaltyKindEnum -> Maybe TimeOfDay
penaltyWindowEnd EveningAfter7Pm = Just (TimeOfDay 0 0 0)
penaltyWindowEnd LateNightAfterMidnight = Just (TimeOfDay 7 0 0)
penaltyWindowEnd _ = Nothing

clearExistingCache :: (?modelContext :: ModelContext) => [Int] -> IO ()
clearExistingCache _awardFixedIds = do
    -- FWC projections reference raw MAPD rows. Keep both append-only so historical
    -- award rates and staff/shift award-level references survive refreshes.
    pure ()

curateAwardData ::
    MapdCurationProfile ->
    Day ->
    (Int, [(AwardPayload, Aeson.Value)], [(ClassificationPayload, Aeson.Value)], [(PayRatePayload, Aeson.Value)], [(PenaltyRatePayload, Aeson.Value)]) ->
    (Int, [(AwardPayload, Aeson.Value)], [(ClassificationPayload, Aeson.Value)], [(PayRatePayload, Aeson.Value)], [(PenaltyRatePayload, Aeson.Value)])
curateAwardData profile asOfDate (awardFixedId, awards, classifications, payRates, penaltyRates) =
    (awardFixedId, retainedAwards, retainedClassifications, retainedPayRates, retainedPenaltyRates)
    where
        activeAwards = filter (isActiveAwardOn asOfDate . fst) awards
        activeClassifications = filter (isActiveClassificationOn asOfDate . fst) classifications
        activePayRates = filter (isActivePayRateOn asOfDate . fst) payRates
        activePenaltyRates = filter (isActivePenaltyRateOn asOfDate . fst) penaltyRates
        scopedAwards = applyAwardYearScope profile.awardYearScope (.publishedYear) activeAwards
        scopedClassifications = applyAwardYearScope profile.awardYearScope (.publishedYear) activeClassifications
        scopedPayRates = applyAwardYearScope profile.awardYearScope (.publishedYear) activePayRates
        scopedPenaltyRates = applyAwardYearScope profile.awardYearScope (.penaltyPublishedYear) activePenaltyRates
        relevantClassificationIds =
            scopedClassifications
                |> filter (isRelevantClassification profile . fst)
                |> map (classificationPayloadFixedId . fst)
                |> Set.fromList
        retainedPayRates =
            scopedPayRates
                |> filter (\(payload, _) -> maybe False (`Set.member` relevantClassificationIds) (payRatePayloadClassificationFixedId payload))
                |> filter (isRelevantPayRate profile . fst)
        retainedBasePayRateIds =
            retainedPayRates
                |> mapMaybe (\(payload, _) -> payload.basePayRateId)
                |> Set.fromList
        retainedPenaltyRates =
            scopedPenaltyRates
                |> filter (\(payload, _) -> maybe False (`Set.member` retainedBasePayRateIds) payload.penaltyBasePayRateId)
                |> filter (\(payload, _) -> isRelevantPenaltyRate profile payload || isRelevantCasualOrdinaryPenaltyRate profile payload)
        retainedClassificationIds =
            mapMaybe (\(payload, _) -> payRatePayloadClassificationFixedId payload) retainedPayRates
                |> Set.fromList
        retainedClassifications =
            scopedClassifications
                |> filter (\(payload, _) -> Set.member (classificationPayloadFixedId payload) retainedClassificationIds)
        retainedAwards = scopedAwards

classificationPayloadFixedId :: ClassificationPayload -> Int
classificationPayloadFixedId payload = payload.classificationFixedId

payRatePayloadClassificationFixedId :: PayRatePayload -> Maybe Int
payRatePayloadClassificationFixedId payload = payload.classificationFixedId

applyAwardYearScope :: AwardYearScope -> (a -> Maybe Int) -> [(a, Aeson.Value)] -> [(a, Aeson.Value)]
applyAwardYearScope AllAwardYears _ values = values
applyAwardYearScope LatestActiveAwardYear yearOf values =
    case maximumMaybe (mapMaybe (yearOf . fst) values) of
        Nothing -> values
        Just latestYear ->
            filter (\(payload, _) -> yearOf payload == Just latestYear) values

maximumMaybe :: Ord a => [a] -> Maybe a
maximumMaybe [] = Nothing
maximumMaybe values = Just (maximum values)

isRelevantPayRate :: MapdCurationProfile -> PayRatePayload -> Bool
isRelevantPayRate profile payRate =
    isIncludedRateType
        && hourlyOk
        && matchesCurationText profile searchableText
    where
        isIncludedRateType = payRate.employeeRateTypeCode `elem` map Just profile.employeeRateTypeCodes
        hourlyOk = not profile.requireHourlyRate || hasHourlyAmount payRate
        searchableText = searchablePayRateText payRate

isRelevantPenaltyRate :: MapdCurationProfile -> PenaltyRatePayload -> Bool
isRelevantPenaltyRate profile penaltyRate =
    isIncludedRateType
        && hasPayablePenaltyAmount penaltyRate
        && not (hasAnyKeyword profile.excludedKeywords searchableText)
        && isJust (normalisePenaltyKind penaltyRate)
    where
        isIncludedRateType = penaltyRate.penaltyEmployeeRateTypeCode `elem` map Just profile.employeeRateTypeCodes
        searchableText = searchablePenaltyRateText penaltyRate

isRelevantCasualOrdinaryPenaltyRate :: MapdCurationProfile -> PenaltyRatePayload -> Bool
isRelevantCasualOrdinaryPenaltyRate profile penaltyRate =
    isIncludedRateType
        && hasPayablePenaltyAmount penaltyRate
        && containsAny ["casual"] searchableText
        && containsAny ["ordinary hours"] searchableText
        && not (containsAny ["overtime"] searchableText)
        && not (hasAnyKeyword profile.excludedKeywords searchableText)
    where
        isIncludedRateType = penaltyRate.penaltyEmployeeRateTypeCode `elem` map Just profile.employeeRateTypeCodes
        searchableText = searchablePenaltyRateText penaltyRate

curateWageAllowances :: MapdCurationProfile -> Day -> [(WageAllowancePayload, Aeson.Value)] -> [(WageAllowancePayload, Aeson.Value)]
curateWageAllowances profile asOfDate wageAllowances =
    wageAllowances
        |> filter (isActiveWageAllowanceOn asOfDate . fst)
        |> applyAwardYearScope profile.awardYearScope (.wageAllowancePublishedYear)
        |> filter (isRelevantWageAllowance profile . fst)

isRelevantWageAllowance :: MapdCurationProfile -> WageAllowancePayload -> Bool
isRelevantWageAllowance profile wageAllowance =
    hasPayableWageAllowanceAmount wageAllowance
        && not (hasAnyKeyword profile.excludedKeywords searchableText)
        && isJust (normaliseTimePenaltyKind wageAllowance)
    where
        searchableText = searchableWageAllowanceText wageAllowance

isRelevantClassification :: MapdCurationProfile -> ClassificationPayload -> Bool
isRelevantClassification profile classification =
    matchesCurationText profile (searchableClassificationText classification)

matchesCurationText :: MapdCurationProfile -> Text -> Bool
matchesCurationText profile searchableText =
    not (hasAnyKeyword profile.excludedKeywords searchableText)
        && hasAnyKeyword profile.includedKeywords searchableText

hasHourlyAmount :: PayRatePayload -> Bool
hasHourlyAmount payRate =
    (isHourlyRateType payRate.calculatedRateType && isJust payRate.calculatedRate)
        || (isHourlyRateType payRate.baseRateType && isJust payRate.baseRate)

isHourlyRateType :: Maybe Text -> Bool
isHourlyRateType =
    maybe False (\rateType -> Text.toLower rateType `elem` ["hourly", "casual hourly"])

hasPayablePenaltyAmount :: PenaltyRatePayload -> Bool
hasPayablePenaltyAmount penaltyRate =
    isJust penaltyRate.penaltyCalculatedValue

hasPayableWageAllowanceAmount :: WageAllowancePayload -> Bool
hasPayableWageAllowanceAmount wageAllowance =
    isJust wageAllowance.wageAllowanceAmount

isActiveAwardOn :: Day -> AwardPayload -> Bool
isActiveAwardOn asOfDate award =
    startsOnOrBefore asOfDate award.awardOperativeFrom && endsOnOrAfter asOfDate award.awardOperativeTo

isActiveClassificationOn :: Day -> ClassificationPayload -> Bool
isActiveClassificationOn asOfDate classification =
    startsOnOrBefore asOfDate classification.operativeFrom && endsOnOrAfter asOfDate classification.operativeTo

isActivePayRateOn :: Day -> PayRatePayload -> Bool
isActivePayRateOn asOfDate payRate =
    startsOnOrBefore asOfDate payRate.operativeFrom && endsOnOrAfter asOfDate payRate.operativeTo

isActivePenaltyRateOn :: Day -> PenaltyRatePayload -> Bool
isActivePenaltyRateOn asOfDate penaltyRate =
    startsOnOrBefore asOfDate penaltyRate.penaltyOperativeFrom && endsOnOrAfter asOfDate penaltyRate.penaltyOperativeTo

isActiveWageAllowanceOn :: Day -> WageAllowancePayload -> Bool
isActiveWageAllowanceOn asOfDate wageAllowance =
    startsOnOrBefore asOfDate wageAllowance.wageAllowanceOperativeFrom && endsOnOrAfter asOfDate wageAllowance.wageAllowanceOperativeTo

startsOnOrBefore :: Day -> Maybe Day -> Bool
startsOnOrBefore asOfDate = maybe True (<= asOfDate)

endsOnOrAfter :: Day -> Maybe Day -> Bool
endsOnOrAfter asOfDate = maybe True (>= asOfDate)

searchablePayRateText :: PayRatePayload -> Text
searchablePayRateText payRate =
    Text.toLower
        ( Text.intercalate
            " "
            ( filter
                (not . Text.null)
                [ payRate.classification
                , fromMaybe "" payRate.classificationLevel
                , fromMaybe "" payRate.parentClassificationName
                , fromMaybe "" payRate.employeeRateTypeCode
                , fromMaybe "" payRate.baseRateType
                , fromMaybe "" payRate.calculatedRateType
                ]
            )
        )

searchableClassificationText :: ClassificationPayload -> Text
searchableClassificationText classification =
    Text.toLower
        ( Text.intercalate
            " "
            ( filter
                (not . Text.null)
                [ classification.classification
                , fromMaybe "" classification.classificationLevel
                , fromMaybe "" classification.parentClassificationName
                , fromMaybe "" classification.clauseDescription
                ]
            )
        )

searchablePenaltyRateText :: PenaltyRatePayload -> Text
searchablePenaltyRateText penaltyRate =
    Text.toLower
        ( Text.intercalate
            " "
            ( filter
                (not . Text.null)
                [ penaltyRate.penaltyClassification
                , fromMaybe "" penaltyRate.penaltyClassificationLevel
                , fromMaybe "" penaltyRate.penaltyParentClassificationName
                , fromMaybe "" penaltyRate.penaltyClauseDescription
                , fromMaybe "" penaltyRate.penaltyEmployeeRateTypeCode
                , fromMaybe "" penaltyRate.penaltyDescription
                , fromMaybe "" penaltyRate.penaltyText
                ]
            )
        )

searchableWageAllowanceText :: WageAllowancePayload -> Text
searchableWageAllowanceText wageAllowance =
    Text.toLower
        ( Text.intercalate
            " "
            ( filter
                (not . Text.null)
                [ fromMaybe "" wageAllowance.wageAllowanceClauses
                , fromMaybe "" wageAllowance.wageAllowance
                , fromMaybe "" wageAllowance.wageAllowanceType
                , fromMaybe "" wageAllowance.wageAllowanceRateUnit
                , fromMaybe "" wageAllowance.wageAllowancePaymentFrequency
                ]
            )
        )

searchableWageAllowanceRecordText :: FwcMapdWageAllowance -> Text
searchableWageAllowanceRecordText wageAllowance =
    Text.toLower
        ( Text.intercalate
            " "
            ( filter
                (not . Text.null)
                [ fromMaybe "" wageAllowance.clauses
                , fromMaybe "" wageAllowance.allowance
                , fromMaybe "" wageAllowance.allowanceType
                , fromMaybe "" wageAllowance.rateUnit
                , fromMaybe "" wageAllowance.paymentFrequency
                ]
            )
        )

hasAnyKeyword :: [Text] -> Text -> Bool
hasAnyKeyword keywords searchableText =
    any (`Text.isInfixOf` searchableText) (map Text.toLower keywords)
