module Test.WageEngine.Fixture where

import Application.WageEngine
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import IHP.Prelude

testEffectivePeriod :: EffectivePeriod
testEffectivePeriod =
    EffectivePeriod
        { effectiveFrom = Just (fromGregorian 2025 7 1)
        , effectiveTo = Just (fromGregorian 2026 6 30)
        }

completeRateBookCandidate :: Scientific -> RateBookCandidate
completeRateBookCandidate ordinaryRate =
    RateBookCandidate
        { candidateAwardFixedId = 9
        , candidateVersion = "fixture-2025"
        , candidateEffectivePeriod = testEffectivePeriod
        , candidateRates = concatMap ratesForClassification supportedAwardClassifications <> awardAdditions
        }
  where
    ratesForClassification classification =
        concatMap
            (ratesForBasis (awardClassificationFixedId classification))
            [PermanentPartTime, CasualEmployment]

    ratesForBasis classificationFixedId employmentBasis =
        [ candidateLevelRate classificationFixedId employmentBasis rateKind (ordinaryRate * rateMultiplier employmentBasis rateKind)
        | rateKind <- [OrdinaryRate, SaturdayRate, SundayRate, PublicHolidayRate]
        ]

    rateMultiplier PermanentPartTime OrdinaryRate      = 1
    rateMultiplier PermanentPartTime SaturdayRate      = 1.25
    rateMultiplier PermanentPartTime SundayRate        = 1.5
    rateMultiplier PermanentPartTime PublicHolidayRate = 2.25
    rateMultiplier CasualEmployment OrdinaryRate       = 1.25
    rateMultiplier CasualEmployment SaturdayRate       = 1.5
    rateMultiplier CasualEmployment SundayRate         = 1.75
    rateMultiplier CasualEmployment PublicHolidayRate  = 2.5

    awardAdditions =
        [ candidateAwardAddition EveningAddition 10
        , candidateAwardAddition EarlyMorningAddition 15
        ]

candidateLevelRate :: Int -> EmploymentBasis -> BaseRateKind -> Scientific -> CandidateRate
candidateLevelRate classificationFixedId employmentBasis rateKind ratePerUnit =
    CandidateRate
        { candidateRateKey = CandidateClassificationRate classificationFixedId employmentBasis rateKind
        , candidateRatePerUnit = ratePerUnit
        , candidateRateSourceIdentity = RateSourceIdentity ("source-" <> tshow classificationFixedId <> "-" <> tshow employmentBasis <> "-" <> tshow rateKind)
        , candidateRateSourceOwner = ClassificationOwner classificationFixedId
        , candidateRateEffectivePeriod = testEffectivePeriod
        }

candidateAwardAddition :: TimeAdditionKind -> Scientific -> CandidateRate
candidateAwardAddition additionKind ratePerUnit =
    CandidateRate
        { candidateRateKey = CandidateAwardAddition additionKind
        , candidateRatePerUnit = ratePerUnit
        , candidateRateSourceIdentity = RateSourceIdentity ("source-addition-" <> tshow additionKind)
        , candidateRateSourceOwner = AwardOwner 9
        , candidateRateEffectivePeriod = testEffectivePeriod
        }

validatedTestRateBook :: ValidatedRateBook
validatedTestRateBook =
    case mkValidatedRateBook (completeRateBookCandidate 100) of
        Left validationError -> error (show validationError)
        Right rateBook       -> rateBook

testCalculationInput :: WageCalculationInput
testCalculationInput =
    WageCalculationInput
        { calculationEntryId = CalculationEntryId "entry-1"
        , calculationVenueContext =
            VenueAwardContext
                { venueTimeZone = AustraliaMelbourne
                , publicHolidayJurisdiction = VictoriaStatewide
                }
        , calculationArrangement = AwardHourlyEmployment PermanentPartTime
        , calculationAwardRateContext =
            Just (AwardRateContext (ResolvedAwardLevel HospitalityLevel1 "level-1" "Level 1") validatedTestRateBook)
        , calculationStatewidePublicHolidayDates = Set.empty
        , calculationImportedOverrides = ImportedOverrideContext Nothing Nothing
        , calculationUnsupportedFeatures = Set.empty
        , calculationPaidIntervals = [twoHourOrdinaryInterval]
        }

twoHourOrdinaryInterval :: ResolvedPaidInterval
twoHourOrdinaryInterval =
    ResolvedPaidInterval
        { paidIntervalStart = utcAt 0
        , paidIntervalEnd = utcAt (2 * 60 * 60)
        , paidIntervalLocalDate = fromGregorian 2026 1 5
        , paidIntervalLocalDayKind = LocalWeekday
        , paidIntervalLocalWindow = OrdinaryWindow
        }

utcAt :: Integer -> UTCTime
utcAt seconds = UTCTime (fromGregorian 2026 1 5) (secondsToDiffTime seconds)

calculateOrFail :: WageCalculationInput -> WageCalculation
calculateOrFail calculationInput =
    case calculateTimesheetPay calculationInput of
        Left calculationError -> error (show calculationError)
        Right calculation     -> calculation

rateFor :: WageCalculation -> Scientific
rateFor calculation =
    case calculation.earningsComponents of
        [component] -> component.ratePerUnit
        components -> error ("Expected one earnings component, got " <> show components)

amountFor :: WageCalculation -> Rational
amountFor calculation = sum (map (.amount) calculation.earningsComponents)
