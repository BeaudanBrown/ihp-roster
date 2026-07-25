module Application.WageEngine.Types
    ( CalculationEntryId (..)
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
    , FinalEarningsBucketKey (..)
    , FinalEarningsLine (..)
    , FinalEarningsSummary (..)
    , WageCalculation (..)
    , PaidIntervalError (..)
    , UnsupportedInput (..)
    , WageCalculationError (..)
    )
where

import Application.VenueTime (AwardSegment)
import Application.WageEngine.RateBook (AwardRateContext, EmploymentBasis,
                                        RateBookVersion, RateSourceIdentity)
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Clock (UTCTime, diffUTCTime)
import IHP.Prelude

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
    deriving (Eq, Ord, Show)

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
    deriving (Eq, Ord, Show)

data CalculationSource
    = HospitalityAward
    | ExternalImportedPayItem
    deriving (Eq, Ord, Show)

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

data FinalEarningsBucketKey = FinalEarningsBucketKey
    { finalEarningsBucketUnitType           :: !EarningsUnit
    , finalEarningsBucketSourceCondition    :: !SourceCondition
    , finalEarningsBucketCalculationSource  :: !CalculationSource
    , finalEarningsBucketRatePerUnit        :: !Scientific
    , finalEarningsBucketSourceRateIdentity :: !(Maybe RateSourceIdentity)
    }
    deriving (Eq, Ord, Show)

data FinalEarningsLine = FinalEarningsLine
    { finalEarningsLineBucketKey     :: !FinalEarningsBucketKey
    , finalEarningsLineQuantity      :: !Rational
    , finalEarningsLineExactAmount   :: !Rational
    , finalEarningsLineRoundedAmount :: !Rational
    }
    deriving (Eq, Show)

data FinalEarningsSummary = FinalEarningsSummary
    { finalEarningsLines       :: ![FinalEarningsLine]
    , finalEarningsTotalAmount :: !Rational
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
    deriving (Eq, Show)

data WageCalculationError
    = InvalidPaidInterval !PaidIntervalError
    | UnsupportedCalculationInput !UnsupportedInput
    deriving (Eq, Show)

selectedImportedPayItem :: ImportedOverrideContext -> Maybe ImportedPayItem
selectedImportedPayItem importedOverrides =
    importedOverrides.shiftImportedPayItem <|> importedOverrides.staffImportedPayItem
