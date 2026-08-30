module Application.FwcMapd.Payload where

import Application.Error.Parser (parserFailure)
import Application.Error.Runtime (throwExternalRuntime)
import Application.FwcMapd.Error
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.Types as Aeson
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import qualified Data.Vector as Vector
import IHP.ControllerPrelude
import IHP.Prelude

data MapdSyncSummary = MapdSyncSummary
    { syncedAwardFixedIds        :: ![Int]
    , fetchedAwardCount          :: !Int
    , fetchedClassificationCount :: !Int
    , fetchedPayRateCount        :: !Int
    , fetchedPenaltyRateCount    :: !Int
    , fetchedWageAllowanceCount  :: !Int
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
    { penaltyClassificationFixedId    :: !(Maybe Int)
    , penaltyClassification           :: !Text
    , penaltyClassificationLevel      :: !(Maybe Text)
    , penaltyParentClassificationName :: !(Maybe Text)
    , penaltyClauseDescription        :: !(Maybe Text)
    , penaltyEmployeeRateTypeCode     :: !(Maybe Text)
    , penaltyBasePayRateId            :: !(Maybe Text)
    , penaltyFixedId                  :: !(Maybe Int)
    , penaltyDescription              :: !(Maybe Text)
    , penaltyText                     :: !(Maybe Text)
    , penaltyRate                     :: !(Maybe Scientific)
    , penaltyRateUnit                 :: !(Maybe Text)
    , penaltyCalculatedValue          :: !(Maybe Scientific)
    , penaltyOperativeFrom            :: !(Maybe Day)
    , penaltyOperativeTo              :: !(Maybe Day)
    , penaltyPublishedYear            :: !(Maybe Int)
    , penaltyVersionNumber            :: !(Maybe Int)
    , penaltyLastModifiedDatetime     :: !(Maybe UTCTime)
    }
    deriving (Eq, Show)

data WageAllowancePayload = WageAllowancePayload
    { wageAllowanceFixedId              :: !(Maybe Int)
    , wageAllowanceClauseFixedId        :: !(Maybe Int)
    , wageAllowanceClauses              :: !(Maybe Text)
    , wageAllowance                     :: !(Maybe Text)
    , wageAllowanceType                 :: !(Maybe Text)
    , wageAllowanceIsAllPurpose         :: !(Maybe Bool)
    , wageAllowanceRate                 :: !(Maybe Scientific)
    , wageAllowanceBaseRate             :: !(Maybe Scientific)
    , wageAllowanceBasePayRateId        :: !(Maybe Text)
    , wageAllowanceRateUnit             :: !(Maybe Text)
    , wageAllowanceAmount               :: !(Maybe Scientific)
    , wageAllowancePaymentFrequency     :: !(Maybe Text)
    , wageAllowanceOperativeFrom        :: !(Maybe Day)
    , wageAllowanceOperativeTo          :: !(Maybe Day)
    , wageAllowancePublishedYear        :: !(Maybe Int)
    , wageAllowanceVersionNumber        :: !(Maybe Int)
    , wageAllowanceLastModifiedDatetime :: !(Maybe UTCTime)
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
        Nothing    -> pure Nothing
        Just value -> Just <$> textFromJsonValue value

textFromJsonValue :: Aeson.Value -> Aeson.Parser Text
textFromJsonValue = \case
    Aeson.String value -> pure value
    Aeson.Number value -> pure (cs (show value))
    Aeson.Bool value -> pure (if value then "true" else "false")
    Aeson.Null -> parserFailure "expected non-null JSON value"
    Aeson.Array values -> pure (cs (show (Vector.toList values)))
    Aeson.Object value -> pure (cs (show value))

decodePayloads :: Aeson.FromJSON a => Text -> [Aeson.Value] -> IO [(a, Aeson.Value)]
decodePayloads _label rawValues =
    forM rawValues \rawValue ->
        case Aeson.parseEither Aeson.parseJSON rawValue of
            Left _        -> throwExternalRuntime MapdResponseMalformed
            Right payload -> pure (payload, rawValue)
