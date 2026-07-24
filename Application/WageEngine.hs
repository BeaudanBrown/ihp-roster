module Application.WageEngine
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
    , CalculationEntryId (..)
    , WageCalculationVersion (..)
    , currentWageCalculationVersion
    , VenueTimeZone (..)
    , StatewideHolidayJurisdiction (..)
    , VenueAwardContext (..)
    , resolveVenueAwardContext
    , ImportedPayItem (..)
    , ImportedOverrideContext (..)
    , selectedImportedPayItem
    , UnsupportedEmploymentKind (..)
    , EmploymentArrangement (..)
    , UnsupportedFeature (..)
    , WageCalculationInput (..)
    , PaidTimeKind (..)
    , paidTimeKindValue
    , SourceCondition (..)
    , sourceConditionValue
    , PaidTimeSegment (..)
    , paidTimeDurationSeconds
    , EarningsUnit (..)
    , CalculationSource (..)
    , calculationSourceValue
    , EarningsComponent (..)
    , WageCalculation (..)
    , PaidIntervalError (..)
    , UnsupportedInput (..)
    , WageCalculationError (..)
    , calculateTimesheetPay
    )
where

import Application.VenueTime (AwardSegment, LocalDayKind (..),
                              LocalTimeWindow (..), awardSegmentEnd,
                              awardSegmentLocalDate, awardSegmentLocalDayKind,
                              awardSegmentLocalWindow, awardSegmentStart,
                              resolvedInstantUTC)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Clock (UTCTime, diffUTCTime)
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

lookupValidatedRateWithSource :: ValidatedRateKey -> ValidatedRateBook -> ValidatedRate
lookupValidatedRateWithSource key rateBook =
    fromMaybe
        (error ("ValidatedRateBook invariant broken: missing " <> show key))
        (Map.lookup key rateBook.rateBookRates)

newtype CalculationEntryId = CalculationEntryId Text
    deriving (Eq, Ord, Show)

newtype WageCalculationVersion = WageCalculationVersion Text
    deriving (Eq, Ord, Show)

currentWageCalculationVersion :: WageCalculationVersion
currentWageCalculationVersion = WageCalculationVersion "hospitality-award-v1"

data VenueTimeZone = AustraliaMelbourne
    deriving (Eq, Show)

data StatewideHolidayJurisdiction = VictoriaStatewide
    deriving (Eq, Show)

data VenueAwardContext = VenueAwardContext
    { venueTimeZone             :: !VenueTimeZone
    , publicHolidayJurisdiction :: !StatewideHolidayJurisdiction
    }
    deriving (Eq, Show)

resolveVenueAwardContext :: Text -> Text -> Either UnsupportedInput VenueAwardContext
resolveVenueAwardContext rawTimeZone rawJurisdiction = do
    timeZone <-
        if rawTimeZone == "Australia/Melbourne"
            then Right AustraliaMelbourne
            else Left (UnsupportedVenueTimeZone rawTimeZone)
    jurisdiction <-
        if rawJurisdiction == "VIC"
            then Right VictoriaStatewide
            else Left (UnsupportedPublicHolidayJurisdiction rawJurisdiction)
    pure (VenueAwardContext timeZone jurisdiction)

data ImportedPayItem = ImportedPayItem
    { importedPayItemId   :: !Text
    , importedPayItemName :: !Text
    , importedHourlyRate  :: !Scientific
    }
    deriving (Eq, Show)

data ImportedOverrideContext = ImportedOverrideContext
    { shiftImportedPayItem :: !(Maybe ImportedPayItem)
    , staffImportedPayItem :: !(Maybe ImportedPayItem)
    }
    deriving (Eq, Show)

data UnsupportedEmploymentKind
    = FullTimeEmployment
    | ManagerialSalaryEmployment
    | JuniorEmployment
    | ApprenticeEmployment
    | TraineeEmployment
    | SupportedWageEmployment
    | AnnualisedSalaryEmployment
    deriving (Eq, Ord, Show)

data EmploymentArrangement
    = AwardHourlyEmployment !EmploymentBasis
    | UnsupportedEmployment !UnsupportedEmploymentKind
    deriving (Eq, Show)

data UnsupportedFeature
    = AirportCateringArrangement
    | LoadedRateArrangement
    | AllowancePayments
    | HigherDutiesSelection
    | LeaveCalculation
    | SuperannuationCalculation
    | TerminationCalculation
    | GuaranteedHoursTopUp
    | SubstitutedHolidayArrangement
    | PublicHolidayPaidTimeAlternative
    deriving (Eq, Ord, Show)

data WageCalculationInput = WageCalculationInput
    { calculationEntryId                     :: !CalculationEntryId
    , calculationVenueContext                :: !VenueAwardContext
    , calculationArrangement                 :: !EmploymentArrangement
    , calculationAwardRateContext            :: !(Maybe AwardRateContext)
    , calculationStatewidePublicHolidayDates :: !(Set.Set Day)
    , calculationImportedOverrides           :: !ImportedOverrideContext
    , calculationUnsupportedFeatures         :: !(Set.Set UnsupportedFeature)
    , calculationPaidIntervals               :: ![AwardSegment]
    }
    deriving (Eq, Show)

data PaidTimeKind
    = Worked
    | CasualMinimumEngagementTopUp
    | PublicHolidayMinimumTopUp
    deriving (Eq, Show)

paidTimeKindValue :: PaidTimeKind -> Text
paidTimeKindValue = \case
    Worked                         -> "worked"
    CasualMinimumEngagementTopUp   -> "casual_minimum_engagement_top_up"
    PublicHolidayMinimumTopUp      -> "public_holiday_minimum_top_up"

data SourceCondition
    = OrdinaryCondition
    | SaturdayCondition
    | SundayCondition
    | PublicHolidayCondition
    | EveningAdditionCondition
    | EarlyMorningAdditionCondition
    | MissedMealBreakAdditionCondition
    | ImportedFlatRateCondition !Text
    deriving (Eq, Show)

sourceConditionValue :: SourceCondition -> Text
sourceConditionValue = \case
    OrdinaryCondition                  -> "ordinary"
    SaturdayCondition                  -> "saturday"
    SundayCondition                    -> "sunday"
    PublicHolidayCondition             -> "public_holiday"
    EveningAdditionCondition           -> "evening_after_7pm_addition"
    EarlyMorningAdditionCondition      -> "late_night_after_midnight_addition"
    MissedMealBreakAdditionCondition   -> "missed_meal_break_addition"
    ImportedFlatRateCondition itemId   -> "external_imported_pay_item:" <> itemId

data PaidTimeSegment = PaidTimeSegment
    { paidTimeKind            :: !PaidTimeKind
    , paidTimeStart           :: !UTCTime
    , paidTimeEnd             :: !UTCTime
    , paidTimeLocalDate       :: !Day
    , paidTimeSourceCondition :: !SourceCondition
    }
    deriving (Eq, Show)

paidTimeDurationSeconds :: PaidTimeSegment -> Rational
paidTimeDurationSeconds segment = toRational (diffUTCTime segment.paidTimeEnd segment.paidTimeStart)

data EarningsUnit
    = Hours
    | CommencedHours
    deriving (Eq, Show)

data CalculationSource
    = HospitalityAward
    | ExternalImportedPayItem
    deriving (Eq, Show)

calculationSourceValue :: CalculationSource -> Text
calculationSourceValue = \case
    HospitalityAward        -> "hospitality_award"
    ExternalImportedPayItem -> "external_imported_pay_item"

data EarningsComponent = EarningsComponent
    { quantity           :: !Rational
    , unitType           :: !EarningsUnit
    , ratePerUnit        :: !Scientific
    , amount             :: !Rational
    , sourceCondition    :: !SourceCondition
    , calculationSource  :: !CalculationSource
    , sourceRateIdentity :: !(Maybe RateSourceIdentity)
    }
    deriving (Eq, Show)

data WageCalculation = WageCalculation
    { calculatedEntryId          :: !CalculationEntryId
    , calculationVersion         :: !WageCalculationVersion
    , calculationRateBookVersion :: !(Maybe RateBookVersion)
    , paidTimeSegments           :: ![PaidTimeSegment]
    , earningsComponents         :: ![EarningsComponent]
    }
    deriving (Eq, Show)

data PaidIntervalError
    = NoPaidIntervals
    | OverlappingPaidIntervals
    deriving (Eq, Show)

data UnsupportedInput
    = UnsupportedVenueTimeZone !Text
    | UnsupportedPublicHolidayJurisdiction !Text
    | UnsupportedEmploymentArrangement !UnsupportedEmploymentKind
    | MissingAwardRateContext
    | UnsupportedFeatureRequested !UnsupportedFeature
    | InvalidImportedPayItem !Text
    | PendingCommencedHourRule !LocalTimeWindow
    deriving (Eq, Show)

data WageCalculationError
    = InvalidPaidInterval !PaidIntervalError
    | UnsupportedCalculationInput !UnsupportedInput
    deriving (Eq, Show)

calculateTimesheetPay :: WageCalculationInput -> Either WageCalculationError WageCalculation
calculateTimesheetPay calculationInput = do
    validateCalculationContext calculationInput
    intervals <- validatePaidIntervals calculationInput.calculationPaidIntervals
    case selectedImportedPayItem calculationInput.calculationImportedOverrides of
        Just importedPayItem -> calculateImportedPay importedPayItem intervals
        Nothing -> do
            basis <- case calculationInput.calculationArrangement of
                AwardHourlyEmployment employmentBasis -> Right employmentBasis
                UnsupportedEmployment unsupportedEmployment ->
                    Left (UnsupportedCalculationInput (UnsupportedEmploymentArrangement unsupportedEmployment))
            case List.find ((/= OrdinaryWindow) . awardSegmentLocalWindow) intervals of
                Just interval -> Left (UnsupportedCalculationInput (PendingCommencedHourRule (awardSegmentLocalWindow interval)))
                Nothing       -> Right ()
            awardRateContext <- maybe (Left (UnsupportedCalculationInput MissingAwardRateContext)) Right calculationInput.calculationAwardRateContext
            let segmentComponents = map (calculateAwardInterval awardRateContext basis) intervals
            pure
                WageCalculation
                    { calculatedEntryId = calculationInput.calculationEntryId
                    , calculationVersion = currentWageCalculationVersion
                    , calculationRateBookVersion = Just (validatedRateBookVersion awardRateContext.awardRateBook)
                    , paidTimeSegments = map fst segmentComponents
                    , earningsComponents = map snd segmentComponents
                    }
  where
    calculateImportedPay importedPayItem intervals = do
        unless
            ( not (Text.null (Text.strip importedPayItem.importedPayItemId))
                && not (Text.null (Text.strip importedPayItem.importedPayItemName))
                && importedPayItem.importedHourlyRate > 0
            )
            (Left (UnsupportedCalculationInput (InvalidImportedPayItem importedPayItem.importedPayItemId)))
        let condition = ImportedFlatRateCondition importedPayItem.importedPayItemId
            segments = map (paidSegment condition) intervals
            components = map (importedComponent importedPayItem condition) intervals
        pure
            WageCalculation
                { calculatedEntryId = calculationInput.calculationEntryId
                , calculationVersion = currentWageCalculationVersion
                , calculationRateBookVersion = Nothing
                , paidTimeSegments = segments
                , earningsComponents = components
                }

    calculateAwardInterval awardRateContext basis interval =
        let
            (rateKind, condition) = awardCondition calculationInput.calculationStatewidePublicHolidayDates interval
            key = ClassificationRate awardRateContext.awardRateLevel.resolvedAwardClassification basis rateKind
            validatedRate = lookupValidatedRateWithSource key awardRateContext.awardRateBook
            hours = intervalDurationHours interval
         in
            ( paidSegment condition interval
            , EarningsComponent
                { quantity = hours
                , unitType = Hours
                , ratePerUnit = validatedRate.validatedRatePerUnit
                , amount = hours * toRational validatedRate.validatedRatePerUnit
                , sourceCondition = condition
                , calculationSource = HospitalityAward
                , sourceRateIdentity = Just validatedRate.validatedRateSourceIdentity
                }
            )

validateCalculationContext :: WageCalculationInput -> Either WageCalculationError ()
validateCalculationContext calculationInput = do
    case calculationInput.calculationArrangement of
        UnsupportedEmployment unsupportedEmployment ->
            Left (UnsupportedCalculationInput (UnsupportedEmploymentArrangement unsupportedEmployment))
        AwardHourlyEmployment _ -> Right ()
    case Set.lookupMin calculationInput.calculationUnsupportedFeatures of
        Nothing -> Right ()
        Just unsupportedFeature -> Left (UnsupportedCalculationInput (UnsupportedFeatureRequested unsupportedFeature))

validatePaidIntervals :: [AwardSegment] -> Either WageCalculationError [AwardSegment]
validatePaidIntervals [] = Left (InvalidPaidInterval NoPaidIntervals)
validatePaidIntervals rawIntervals = do
    let intervals = List.sortOn (resolvedInstantUTC . awardSegmentStart) rawIntervals
        adjacent = zip intervals (drop 1 intervals)
    when
        ( any
            ( \(left, right) ->
                resolvedInstantUTC (awardSegmentEnd left)
                    > resolvedInstantUTC (awardSegmentStart right)
            )
            adjacent
        )
        (Left (InvalidPaidInterval OverlappingPaidIntervals))
    pure intervals

selectedImportedPayItem :: ImportedOverrideContext -> Maybe ImportedPayItem
selectedImportedPayItem importedOverrides =
    importedOverrides.shiftImportedPayItem <|> importedOverrides.staffImportedPayItem

awardCondition :: Set.Set Day -> AwardSegment -> (BaseRateKind, SourceCondition)
awardCondition statewidePublicHolidayDates interval
    | Set.member (awardSegmentLocalDate interval) statewidePublicHolidayDates = (PublicHolidayRate, PublicHolidayCondition)
    | otherwise = case awardSegmentLocalDayKind interval of
        LocalWeekday  -> (OrdinaryRate, OrdinaryCondition)
        LocalSaturday -> (SaturdayRate, SaturdayCondition)
        LocalSunday   -> (SundayRate, SundayCondition)

paidSegment :: SourceCondition -> AwardSegment -> PaidTimeSegment
paidSegment condition interval =
    PaidTimeSegment
        { paidTimeKind = Worked
        , paidTimeStart = resolvedInstantUTC (awardSegmentStart interval)
        , paidTimeEnd = resolvedInstantUTC (awardSegmentEnd interval)
        , paidTimeLocalDate = awardSegmentLocalDate interval
        , paidTimeSourceCondition = condition
        }

importedComponent :: ImportedPayItem -> SourceCondition -> AwardSegment -> EarningsComponent
importedComponent importedPayItem condition interval =
    let hours = intervalDurationHours interval
     in EarningsComponent
            { quantity = hours
            , unitType = Hours
            , ratePerUnit = importedPayItem.importedHourlyRate
            , amount = hours * toRational importedPayItem.importedHourlyRate
            , sourceCondition = condition
            , calculationSource = ExternalImportedPayItem
            , sourceRateIdentity = Nothing
            }

intervalDurationHours :: AwardSegment -> Rational
intervalDurationHours interval =
    toRational
        ( diffUTCTime
            (resolvedInstantUTC (awardSegmentEnd interval))
            (resolvedInstantUTC (awardSegmentStart interval))
        )
        / 3600
