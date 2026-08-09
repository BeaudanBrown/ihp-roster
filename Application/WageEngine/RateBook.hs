module Application.WageEngine.RateBook
    ( AwardClassification (..)
    , awardClassificationFixedId
    , awardClassificationFromFixedId
    , supportedAwardClassifications
    , ResolvedAwardLevel (..)
    , EmploymentBasis (..)
    , BaseRateKind (..)
    , TimeAdditionKind (..)
    , CandidateRateKey (..)
    , ValidatedRateKey (..)
    , RateSourceIdentity (..)
    , ProjectionRateSource (..)
    , projectionRateSourceIdentity
    , rateSourceIdentityReferencesProjection
    , RateSourceOwner (..)
    , EffectivePeriod (..)
    , CandidateRate (..)
    , RateBookCandidate (..)
    , RateBookVersion (..)
    , ValidatedRateBook
    , AwardRateContext (..)
    , RateBookError (..)
    , mkValidatedRateBook
    , validatedRateBookVersion
    , validatedRateBookEffectivePeriod
    , validatedRateCount
    , lookupValidatedRate
    , lookupValidatedRateWithSource
    )
where

import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import qualified Data.UUID as UUID
import IHP.Prelude

data AwardClassification
    = HospitalityIntroductory
    | HospitalityLevel1
    | HospitalityLevel2
    | HospitalityLevel3
    | HospitalityLevel4
    | HospitalityLevel5
    | HospitalityLevel6
    deriving (Eq, Ord, Show, Enum, Bounded)

supportedAwardClassifications :: [AwardClassification]
supportedAwardClassifications = [minBound .. maxBound]

awardClassificationFixedId :: AwardClassification -> Int
awardClassificationFixedId = \case
    HospitalityIntroductory -> 242
    HospitalityLevel1       -> 243
    HospitalityLevel2       -> 246
    HospitalityLevel3       -> 257
    HospitalityLevel4       -> 268
    HospitalityLevel5       -> 276
    HospitalityLevel6       -> 282

awardClassificationFromFixedId :: Int -> Maybe AwardClassification
awardClassificationFromFixedId fixedId =
    List.find ((== fixedId) . awardClassificationFixedId) supportedAwardClassifications

data ResolvedAwardLevel = ResolvedAwardLevel
    { resolvedAwardClassification :: !AwardClassification
    , resolvedAwardLevelId        :: !Text
    , resolvedAwardLevelName      :: !Text
    }
    deriving (Eq, Show)

data EmploymentBasis
    = PermanentPartTime
    | CasualEmployment
    deriving (Eq, Ord, Show, Enum, Bounded)

data BaseRateKind
    = OrdinaryRate
    | SaturdayRate
    | SundayRate
    | PublicHolidayRate
    deriving (Eq, Ord, Show, Enum, Bounded)

data TimeAdditionKind
    = EveningAddition
    | EarlyMorningAddition
    deriving (Eq, Ord, Show, Enum, Bounded)

data CandidateRateKey
    = CandidateClassificationRate !Int !EmploymentBasis !BaseRateKind
    | CandidateAwardAddition !TimeAdditionKind
    deriving (Eq, Ord, Show)

data ValidatedRateKey
    = ClassificationRate !AwardClassification !EmploymentBasis !BaseRateKind
    | AwardAddition !TimeAdditionKind
    deriving (Eq, Ord, Show)

newtype RateSourceIdentity = RateSourceIdentity Text
    deriving (Eq, Ord, Show)

data ProjectionRateSource
    = AwardLevelBaseRateSource !UUID !UUID
    | AwardLevelPenaltyRateSource !UUID !UUID
    | AwardTimePenaltyAllowanceSource !UUID !UUID
    deriving (Eq, Show)

projectionRateSourceIdentity :: ProjectionRateSource -> RateSourceIdentity
projectionRateSourceIdentity source =
    RateSourceIdentity $ case source of
        AwardLevelBaseRateSource projectionId sourceId ->
            render "award_level_base_rates" projectionId "fwc_mapd_pay_rates" sourceId
        AwardLevelPenaltyRateSource projectionId sourceId ->
            render "award_level_penalty_rates" projectionId "fwc_mapd_penalty_rates" sourceId
        AwardTimePenaltyAllowanceSource projectionId sourceId ->
            render "award_time_penalty_allowances" projectionId "fwc_mapd_wage_allowances" sourceId
  where
    render projectionTable projectionId sourceTable sourceId =
        "bepis-projection:" <> projectionTable <> ":" <> tshow projectionId <> "/source:" <> sourceTable <> ":" <> tshow sourceId

-- | Matches the immutable projection-row part of a sealed source identity.
-- MAPD refreshes append raw source rows and may repoint the projection row;
-- approved ledgers retain the original raw source UUID and rate.
rateSourceIdentityReferencesProjection :: ProjectionRateSource -> RateSourceIdentity -> Bool
rateSourceIdentityReferencesProjection source (RateSourceIdentity identity) =
    case Text.stripPrefix expectedPrefix identity of
        Just sourceId -> isJust (UUID.fromText sourceId)
        Nothing       -> False
  where
    expectedPrefix = case source of
        AwardLevelBaseRateSource projectionId _ ->
            prefix "award_level_base_rates" projectionId "fwc_mapd_pay_rates"
        AwardLevelPenaltyRateSource projectionId _ ->
            prefix "award_level_penalty_rates" projectionId "fwc_mapd_penalty_rates"
        AwardTimePenaltyAllowanceSource projectionId _ ->
            prefix "award_time_penalty_allowances" projectionId "fwc_mapd_wage_allowances"

    prefix projectionTable projectionId sourceTable =
        "bepis-projection:" <> projectionTable <> ":" <> tshow projectionId <> "/source:" <> sourceTable <> ":"

data RateSourceOwner
    = ClassificationOwner !Int
    | AwardOwner !Int
    deriving (Eq, Ord, Show)

data EffectivePeriod = EffectivePeriod
    { effectiveFrom :: !(Maybe Day)
    , effectiveTo   :: !(Maybe Day)
    }
    deriving (Eq, Ord, Show)

data CandidateRate = CandidateRate
    { candidateRateKey             :: !CandidateRateKey
    , candidateRatePerUnit         :: !Scientific
    , candidateRateSourceIdentity  :: !RateSourceIdentity
    , candidateRateSourceOwner     :: !RateSourceOwner
    , candidateRateEffectivePeriod :: !EffectivePeriod
    }
    deriving (Eq, Show)

data RateBookCandidate = RateBookCandidate
    { candidateAwardFixedId    :: !Int
    , candidateVersion         :: !Text
    , candidateEffectivePeriod :: !EffectivePeriod
    , candidateRates           :: ![CandidateRate]
    }
    deriving (Eq, Show)

newtype RateBookVersion = RateBookVersion Text
    deriving (Eq, Ord, Show)

data ValidatedRate = ValidatedRate
    { validatedRatePerUnit        :: !Scientific
    , validatedRateSourceIdentity :: !RateSourceIdentity
    }
    deriving (Eq, Show)

data ValidatedRateBook = ValidatedRateBook
    { rateBookVersion         :: !RateBookVersion
    , rateBookEffectivePeriod :: !EffectivePeriod
    , rateBookRates           :: !(Map.Map ValidatedRateKey ValidatedRate)
    }
    deriving (Eq, Show)

data AwardRateContext = AwardRateContext
    { awardRateLevel :: !ResolvedAwardLevel
    , awardRateBook  :: !ValidatedRateBook
    }
    deriving (Eq, Show)

data RateBookError
    = MissingRequiredRate !ValidatedRateKey
    | ConflictingRequiredRate !ValidatedRateKey
    | InconsistentRateEffectivePeriod !ValidatedRateKey !EffectivePeriod !EffectivePeriod
    | UnsupportedClassificationFixedId !Int
    | InvalidRateSourceOwnership !ValidatedRateKey !RateSourceOwner
    | InvalidRateSourceIdentity !CandidateRateKey
    | InvalidRateAmount !CandidateRateKey !Scientific
    | UnsupportedAwardFixedId !Int
    | InvalidRateBookVersion
    | InvalidRateBookEffectivePeriod !EffectivePeriod
    deriving (Eq, Show)

mkValidatedRateBook :: RateBookCandidate -> Either RateBookError ValidatedRateBook
mkValidatedRateBook candidate = do
    unless (candidate.candidateAwardFixedId == 9)
        (Left (UnsupportedAwardFixedId candidate.candidateAwardFixedId))
    when (Text.null (Text.strip candidate.candidateVersion))
        (Left InvalidRateBookVersion)
    unless (validEffectivePeriod candidate.candidateEffectivePeriod)
        (Left (InvalidRateBookEffectivePeriod candidate.candidateEffectivePeriod))
    keyedRates <- mapM resolveCandidateKey (List.sortOn (.candidateRateKey) candidate.candidateRates)
    normalizedRates <- normalizeCandidateRates keyedRates
    forM_ requiredRateKeys \requiredKey ->
        unless (Map.member requiredKey normalizedRates)
            (Left (MissingRequiredRate requiredKey))
    validatedRates <- Map.traverseWithKey validateRate normalizedRates
    pure
        ValidatedRateBook
            { rateBookVersion = RateBookVersion candidate.candidateVersion
            , rateBookEffectivePeriod = candidate.candidateEffectivePeriod
            , rateBookRates = validatedRates
            }
  where
    resolveCandidateKey rate = do
        validatedKey <- case rate.candidateRateKey of
            CandidateClassificationRate fixedId basis rateKind ->
                case awardClassificationFromFixedId fixedId of
                    Nothing -> Left (UnsupportedClassificationFixedId fixedId)
                    Just classification -> Right (ClassificationRate classification basis rateKind)
            CandidateAwardAddition additionKind -> Right (AwardAddition additionKind)
        pure (validatedKey, rate)

    validateRate validatedKey rate = do
        let RateSourceIdentity sourceIdentity = rate.candidateRateSourceIdentity
        when (Text.null (Text.strip sourceIdentity))
            (Left (InvalidRateSourceIdentity rate.candidateRateKey))
        unless (rate.candidateRatePerUnit > 0)
            (Left (InvalidRateAmount rate.candidateRateKey rate.candidateRatePerUnit))
        unless (validOwner candidate.candidateAwardFixedId validatedKey rate.candidateRateSourceOwner)
            (Left (InvalidRateSourceOwnership validatedKey rate.candidateRateSourceOwner))
        unless (rate.candidateRateEffectivePeriod == candidate.candidateEffectivePeriod)
            ( Left
                ( InconsistentRateEffectivePeriod
                    validatedKey
                    candidate.candidateEffectivePeriod
                    rate.candidateRateEffectivePeriod
                )
            )
        pure
            ValidatedRate
                { validatedRatePerUnit = rate.candidateRatePerUnit
                , validatedRateSourceIdentity = rate.candidateRateSourceIdentity
                }

normalizeCandidateRates :: [(ValidatedRateKey, CandidateRate)] -> Either RateBookError (Map.Map ValidatedRateKey CandidateRate)
normalizeCandidateRates keyedRates =
    Map.traverseWithKey normalizeGroup grouped
  where
    grouped = Map.fromListWith (<>) (map (\(key, rate) -> (key, [rate])) keyedRates)
    normalizeGroup key rates =
        case List.nub rates of
            [rate] -> Right rate
            _      -> Left (ConflictingRequiredRate key)

requiredRateKeys :: [ValidatedRateKey]
requiredRateKeys =
    [ ClassificationRate classification basis rateKind
    | classification <- supportedAwardClassifications
    , basis <- [PermanentPartTime, CasualEmployment]
    , rateKind <- [OrdinaryRate, SaturdayRate, SundayRate, PublicHolidayRate]
    ]
        <> [AwardAddition EveningAddition, AwardAddition EarlyMorningAddition]

validOwner :: Int -> ValidatedRateKey -> RateSourceOwner -> Bool
validOwner awardFixedId key owner =
    case key of
        ClassificationRate classification _ _ ->
            owner == ClassificationOwner (awardClassificationFixedId classification)
        AwardAddition _ -> owner == AwardOwner awardFixedId

validEffectivePeriod :: EffectivePeriod -> Bool
validEffectivePeriod period =
    case period.effectiveFrom of
        Nothing   -> False
        Just from -> maybe True (>= from) period.effectiveTo

validatedRateBookVersion :: ValidatedRateBook -> RateBookVersion
validatedRateBookVersion = (.rateBookVersion)

validatedRateBookEffectivePeriod :: ValidatedRateBook -> EffectivePeriod
validatedRateBookEffectivePeriod = (.rateBookEffectivePeriod)

validatedRateCount :: ValidatedRateBook -> Int
validatedRateCount = Map.size . (.rateBookRates)

lookupValidatedRate :: ValidatedRateKey -> ValidatedRateBook -> Maybe Scientific
lookupValidatedRate key rateBook = (.validatedRatePerUnit) <$> Map.lookup key rateBook.rateBookRates

lookupValidatedRateWithSource :: ValidatedRateKey -> ValidatedRateBook -> (Scientific, RateSourceIdentity)
lookupValidatedRateWithSource key rateBook =
    case Map.lookup key rateBook.rateBookRates of
        Nothing -> error ("ValidatedRateBook invariant broken: missing " <> show key)
        Just validatedRate ->
            (validatedRate.validatedRatePerUnit, validatedRate.validatedRateSourceIdentity)
