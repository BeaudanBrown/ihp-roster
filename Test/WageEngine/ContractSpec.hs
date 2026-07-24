module Test.WageEngine.ContractSpec where

import Application.VenueTime
import Application.WageEngine
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import IHP.Prelude
import Test.Hspec
import Test.WageEngine.Fixture

tests :: Spec
tests = do
    describe "ValidatedRateBook contract" do
        it "accepts exactly the complete MA000009 semantic set" do
            case mkValidatedRateBook (completeRateBookCandidate 100) of
                Left validationError -> expectationFailure (Text.unpack (tshow validationError))
                Right rateBook -> do
                    validatedRateCount rateBook `shouldBe` 58
                    validatedRateBookVersion rateBook `shouldBe` RateBookVersion "fixture-2025"
                    lookupValidatedRate
                        (ClassificationRate HospitalityLevel3 CasualEmployment SundayRate)
                        rateBook
                        `shouldSatisfy` isJust

        it "fails every required semantic category with its named missing-rate error" do
            let completeCandidate = completeRateBookCandidate 100
            forM_ completeCandidate.candidateRates \requiredRate -> do
                let missingKey = requiredRate.candidateRateKey
                    candidate = removeCandidateRate missingKey completeCandidate

                mkValidatedRateBook candidate
                    `shouldBe` Left (MissingRequiredRate (validatedKey missingKey))

        it "normalizes value-identical duplicates" do
            let candidate = completeRateBookCandidate 100
                Just duplicate = head candidate.candidateRates
                duplicated = candidate { candidateRates = duplicate : candidate.candidateRates }

            fmap validatedRateCount (mkValidatedRateBook duplicated) `shouldBe` Right 58

        it "rejects conflicting duplicates independently of response order" do
            let candidate = completeRateBookCandidate 100
                Just original = head candidate.candidateRates
                conflict = original { candidateRatePerUnit = original.candidateRatePerUnit + 1 }
                forward = candidate { candidateRates = conflict : candidate.candidateRates }
                backward = candidate { candidateRates = reverse forward.candidateRates }
                expectedKey = ClassificationRate HospitalityIntroductory PermanentPartTime OrdinaryRate

            mkValidatedRateBook forward `shouldBe` Left (ConflictingRequiredRate expectedKey)
            mkValidatedRateBook backward `shouldBe` Left (ConflictingRequiredRate expectedKey)

        it "rejects inconsistent effective periods" do
            let candidate = completeRateBookCandidate 100
                targetKey = CandidateClassificationRate 243 PermanentPartTime SaturdayRate
                inconsistentPeriod = EffectivePeriod (Just (fromGregorian 2024 7 1)) (Just (fromGregorian 2025 6 30))
                changed = updateCandidateRate targetKey (\rate -> rate { candidateRateEffectivePeriod = inconsistentPeriod }) candidate

            mkValidatedRateBook changed
                `shouldBe` Left
                    ( InconsistentRateEffectivePeriod
                        (ClassificationRate HospitalityLevel1 PermanentPartTime SaturdayRate)
                        testEffectivePeriod
                        inconsistentPeriod
                    )

        it "rejects unsupported classifications independent of response order" do
            let candidate = completeRateBookCandidate 100
                unsupported999 = candidateLevelRate 999 PermanentPartTime OrdinaryRate 100
                unsupported998 = candidateLevelRate 998 PermanentPartTime OrdinaryRate 100
                unsupportedRates = unsupported999 : unsupported998 : candidate.candidateRates

            mkValidatedRateBook (candidate { candidateRates = unsupportedRates })
                `shouldBe` Left (UnsupportedClassificationFixedId 998)
            mkValidatedRateBook (candidate { candidateRates = reverse unsupportedRates })
                `shouldBe` Left (UnsupportedClassificationFixedId 998)

        it "rejects invalid source ownership" do
            let candidate = completeRateBookCandidate 100
                targetKey = CandidateClassificationRate 246 PermanentPartTime OrdinaryRate
                changed = updateCandidateRate targetKey (\rate -> rate { candidateRateSourceOwner = AwardOwner 9 }) candidate

            mkValidatedRateBook changed
                `shouldBe` Left
                    ( InvalidRateSourceOwnership
                        (ClassificationRate HospitalityLevel2 PermanentPartTime OrdinaryRate)
                        (AwardOwner 9)
                    )

        it "rejects missing stable source identities" do
            let candidate = completeRateBookCandidate 100
                targetKey = CandidateClassificationRate 268 PermanentPartTime OrdinaryRate
                changed = updateCandidateRate targetKey (\rate -> rate { candidateRateSourceIdentity = RateSourceIdentity "" }) candidate

            mkValidatedRateBook changed `shouldBe` Left (InvalidRateSourceIdentity targetKey)

        it "rejects non-positive source rates" do
            let candidate = completeRateBookCandidate 100
                targetKey = CandidateClassificationRate 276 CasualEmployment PublicHolidayRate
                changed = updateCandidateRate targetKey (\rate -> rate { candidateRatePerUnit = 0 }) candidate

            mkValidatedRateBook changed `shouldBe` Left (InvalidRateAmount targetKey 0)

        it "rejects the wrong Award, an empty version and an invalid period with typed errors" do
            let candidate = completeRateBookCandidate 100
                invalidPeriod = EffectivePeriod (Just (fromGregorian 2026 7 1)) (Just (fromGregorian 2025 6 30))

            mkValidatedRateBook (candidate { candidateAwardFixedId = 10 })
                `shouldBe` Left (UnsupportedAwardFixedId 10)
            mkValidatedRateBook (candidate { candidateVersion = "" })
                `shouldBe` Left InvalidRateBookVersion
            mkValidatedRateBook (candidate { candidateEffectivePeriod = invalidPeriod })
                `shouldBe` Left (InvalidRateBookEffectivePeriod invalidPeriod)

    describe "pure calculation input contract" do
        it "rejects missing and overlapping authoritative Award segments" do
            let day = fromGregorian 2026 1 5
                overlap = awardSegmentBetween day (TimeOfDay 9 1 0) day (TimeOfDay 9 2 0)

            calculateTimesheetPay (testCalculationInput { calculationPaidIntervals = [] })
                `shouldBe` Left (InvalidPaidInterval NoPaidIntervals)
            calculateTimesheetPay (testCalculationInput { calculationPaidIntervals = [twoHourOrdinaryInterval, overlap] })
                `shouldBe` Left (InvalidPaidInterval OverlappingPaidIntervals)

        it "rejects unsupported venue, holiday, worker and imported inputs explicitly" do
            resolveVenueAwardContext "Etc/UTC" "VIC"
                `shouldBe` Left (UnsupportedVenueTimeZone "Etc/UTC")
            resolveVenueAwardContext "Australia/Melbourne" "NSW"
                `shouldBe` Left (UnsupportedPublicHolidayJurisdiction "NSW")
            calculateTimesheetPay (testCalculationInput { calculationAwardRateContext = Nothing })
                `shouldBe` Left (UnsupportedCalculationInput MissingAwardRateContext)
            forM_
                [ FullTimeEmployment
                , ManagerialSalaryEmployment
                , JuniorEmployment
                , ApprenticeEmployment
                , TraineeEmployment
                , SupportedWageEmployment
                , AnnualisedSalaryEmployment
                ]
                \unsupportedEmployment ->
                    calculateTimesheetPay
                        (testCalculationInput { calculationArrangement = UnsupportedEmployment unsupportedEmployment })
                        `shouldBe` Left (UnsupportedCalculationInput (UnsupportedEmploymentArrangement unsupportedEmployment))
            forM_
                [ AirportCateringArrangement
                , LoadedRateArrangement
                , AllowancePayments
                , HigherDutiesSelection
                , LeaveCalculation
                , SuperannuationCalculation
                , TerminationCalculation
                , GuaranteedHoursTopUp
                , SubstitutedHolidayArrangement
                , PublicHolidayPaidTimeAlternative
                ]
                \unsupportedFeature ->
                    calculateTimesheetPay
                        (testCalculationInput { calculationUnsupportedFeatures = Set.singleton unsupportedFeature })
                        `shouldBe` Left (UnsupportedCalculationInput (UnsupportedFeatureRequested unsupportedFeature))
            let invalidImportedItem = ImportedPayItem "invalid" "Invalid" 0
            calculateTimesheetPay
                ( testCalculationInput
                    { calculationImportedOverrides = ImportedOverrideContext (Just invalidImportedItem) Nothing
                    }
                )
                `shouldBe` Left (UnsupportedCalculationInput (InvalidImportedPayItem "invalid"))

        it "does not reproduce legacy hourly/stacked commenced-hour additions" do
            let day = fromGregorian 2026 1 5
                eveningInterval = awardSegmentBetween day (TimeOfDay 19 0 0) day (TimeOfDay 21 0 0)

            calculateTimesheetPay (testCalculationInput { calculationPaidIntervals = [eveningInterval] })
                `shouldBe` Left (UnsupportedCalculationInput (PendingCommencedHourRule EveningWindow))
            show CommencedHours `shouldBe` "CommencedHours"
            map paidTimeKindValue [Worked, CasualMinimumEngagementTopUp, PublicHolidayMinimumTopUp]
                `shouldBe` ["worked", "casual_minimum_engagement_top_up", "public_holiday_minimum_top_up"]
            let intendedDifferenceComponents =
                    [ EarningsComponent 1 CommencedHours 10 10 EveningAdditionCondition HospitalityAward Nothing
                    , EarningsComponent 1 CommencedHours 15 15 EarlyMorningAdditionCondition HospitalityAward Nothing
                    , EarningsComponent 2 Hours 50 100 MissedMealBreakAdditionCondition HospitalityAward Nothing
                    ]
            map (.unitType) intendedDifferenceComponents `shouldBe` [CommencedHours, CommencedHours, Hours]
            map (sourceConditionValue . (.sourceCondition)) intendedDifferenceComponents
                `shouldBe` ["evening_after_7pm_addition", "late_night_after_midnight_addition", "missed_meal_break_addition"]

validatedKey :: CandidateRateKey -> ValidatedRateKey
validatedKey = \case
    CandidateClassificationRate fixedId basis rateKind ->
        ClassificationRate (classification fixedId) basis rateKind
    CandidateAwardAddition additionKind -> AwardAddition additionKind
  where
    classification = \case
        242 -> HospitalityIntroductory
        243 -> HospitalityLevel1
        246 -> HospitalityLevel2
        257 -> HospitalityLevel3
        268 -> HospitalityLevel4
        276 -> HospitalityLevel5
        282 -> HospitalityLevel6
        unsupported -> error ("unsupported test classification " <> tshow unsupported)

removeCandidateRate :: CandidateRateKey -> RateBookCandidate -> RateBookCandidate
removeCandidateRate key candidate =
    candidate { candidateRates = filter ((/= key) . (.candidateRateKey)) candidate.candidateRates }

updateCandidateRate :: CandidateRateKey -> (CandidateRate -> CandidateRate) -> RateBookCandidate -> RateBookCandidate
updateCandidateRate key update candidate =
    candidate
        { candidateRates =
            map
                (\rate -> if rate.candidateRateKey == key then update rate else rate)
                candidate.candidateRates
        }
