module Test.WageEngine.ContractSpec where

import Application.VenueTime
import Application.WageEngine
import Application.Xero.PayrollSourceKey (sourceRateSuffix)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.UUID as UUID
import IHP.Prelude
import Test.Hspec
import Test.WageEngine.Fixture

sourceUuid :: String -> UUID
sourceUuid value = fromMaybe (error "invalid source-identity test UUID") (UUID.fromString value)

tests :: Spec
tests = do
    describe "payroll source identity contract" do
        it "renders every current projection/source pair as exact stable bytes" do
            let projectionId = sourceUuid "11111111-1111-1111-1111-111111111111"
                sourceId = sourceUuid "22222222-2222-2222-2222-222222222222"
                cases =
                    [ ( AwardLevelBaseRateSource projectionId sourceId
                      , "bepis-projection:award_level_base_rates:11111111-1111-1111-1111-111111111111/source:fwc_mapd_pay_rates:22222222-2222-2222-2222-222222222222"
                      )
                    , ( AwardLevelPenaltyRateSource projectionId sourceId
                      , "bepis-projection:award_level_penalty_rates:11111111-1111-1111-1111-111111111111/source:fwc_mapd_penalty_rates:22222222-2222-2222-2222-222222222222"
                      )
                    , ( AwardTimePenaltyAllowanceSource projectionId sourceId
                      , "bepis-projection:award_time_penalty_allowances:11111111-1111-1111-1111-111111111111/source:fwc_mapd_wage_allowances:22222222-2222-2222-2222-222222222222"
                      )
                    ]

            forM_ cases \(source, expected) ->
                projectionRateSourceIdentity source `shouldBe` RateSourceIdentity expected

        it "recognizes a sealed source after the same projection row points at a refreshed raw source" do
            let projectionId = sourceUuid "11111111-1111-1111-1111-111111111111"
                sealedSourceId = sourceUuid "22222222-2222-2222-2222-222222222222"
                refreshedSourceId = sourceUuid "33333333-3333-3333-3333-333333333333"
                otherProjectionId = sourceUuid "44444444-4444-4444-4444-444444444444"
                sealedIdentity = projectionRateSourceIdentity (AwardLevelPenaltyRateSource projectionId sealedSourceId)

            rateSourceIdentityReferencesProjection (AwardLevelPenaltyRateSource projectionId refreshedSourceId) sealedIdentity `shouldBe` True
            rateSourceIdentityReferencesProjection (AwardLevelPenaltyRateSource otherProjectionId sealedSourceId) sealedIdentity `shouldBe` False
            rateSourceIdentityReferencesProjection (AwardLevelBaseRateSource projectionId sealedSourceId) sealedIdentity `shouldBe` False
            rateSourceIdentityReferencesProjection (AwardLevelPenaltyRateSource projectionId refreshedSourceId) (RateSourceIdentity "malformed") `shouldBe` False

        it "renders exact source/rate suffix bytes for present and missing identities" do
            sourceRateSuffix (Just (RateSourceIdentity "stable-source")) 31.25
                `shouldBe` ":source:stable-source:rate:31.25"
            sourceRateSuffix Nothing 31.25
                `shouldBe` ":source:missing:rate:31.25"

    describe "ValidatedRateBook contract" do
        it "HIGA-18.1-ADULT-CORE and HIGA-SOURCE-FWC-COVERAGE accept exactly the complete MA000009 semantic set" do
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

            calculateTimesheetPay (testCalculationInput { calculationShiftSegments = [] })
                `shouldBe` Left (InvalidShiftSegments NoShiftSegments)
            calculateTimesheetPay (testCalculationInput { calculationShiftSegments = [twoHourOrdinaryInterval, overlap] })
                `shouldBe` Left (InvalidShiftSegments OverlappingShiftSegments)

        it "rejects non-contiguous shift segments and unpaid meal breaks outside the authoritative shift" do
            let day = fromGregorian 2026 1 5
                firstHour = awardSegmentBetween day (TimeOfDay 9 0 0) day (TimeOfDay 10 0 0)
                thirdHour = awardSegmentBetween day (TimeOfDay 11 0 0) day (TimeOfDay 12 0 0)
                outsideBreak =
                    case
                        resolveInterval
                            (MelbourneCivilTime day (TimeOfDay 8 30 0) Nothing)
                            (MelbourneCivilTime day (TimeOfDay 9 0 0) Nothing)
                        of
                            Left failure   -> error (show failure)
                            Right interval -> interval

            calculateTimesheetPay (testCalculationInput { calculationShiftSegments = [firstHour, thirdHour] })
                `shouldBe` Left (InvalidShiftSegments NonContiguousShiftSegments)
            calculateTimesheetPay (testCalculationInput { calculationUnpaidMealBreak = Just outsideBreak })
                `shouldBe` Left (InvalidShiftSegments UnpaidMealBreakOutsideShift)

        it "HIGA-EXCL-FULL-TIME, HIGA-EXCL-MANAGERIAL-SALARY, HIGA-EXCL-JUNIOR, HIGA-EXCL-APPRENTICE, HIGA-EXCL-TRAINEE and HIGA-EXCL-SUPPORTED-WAGE reject unsupported workers explicitly" do
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
            -- HIGA-EXCL-AIRPORT-CATERING, HIGA-EXCL-LOADED-RATE,
            -- HIGA-EXCL-ALLOWANCES, HIGA-EXCL-HIGHER-DUTIES,
            -- HIGA-EXCL-ANNUALISED-SALARY-RECONCILIATION, HIGA-EXCL-LEAVE,
            -- HIGA-EXCL-SUPERANNUATION, HIGA-EXCL-TERMINATION,
            -- HIGA-EXCL-GUARANTEED-HOURS-TOP-UP, HIGA-EXCL-SUBSTITUTED-HOLIDAY,
            -- and HIGA-EXCL-PH-125-PAID-TIME are typed unsupported features.
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

        it "represents weekday additions as fixed components rather than a combined hourly rate" do
            let day = fromGregorian 2026 1 5
                eveningInterval = awardSegmentBetween day (TimeOfDay 19 0 0) day (TimeOfDay 21 0 0)
                calculation = calculateOrFail (testCalculationInput { calculationShiftSegments = [eveningInterval] })

            map (.unitType) calculation.earningsComponents `shouldBe` [Hours, CommencedHours]
            map (sourceConditionValue . (.sourceCondition)) calculation.earningsComponents
                `shouldBe` ["ordinary", "evening_after_7pm_addition"]
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
