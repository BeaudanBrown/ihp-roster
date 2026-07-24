module Test.WageEngine.RulesSpec where

import Application.WageEngine
import qualified Data.Set as Set
import Data.Time.Calendar (fromGregorian)
import IHP.Prelude
import Test.Hspec
import Test.WageEngine.Fixture

tests :: Spec
tests = do
    describe "pure unchanged Award rule subset" do
        it "HIGA-29.2-WEEKDAY-ORDINARY pays permanent part-time worked time at O" do
            let calculation = calculateOrFail testCalculationInput

            calculation.calculatedEntryId `shouldBe` CalculationEntryId "entry-1"
            calculation.calculationVersion `shouldBe` WageCalculationVersion "hospitality-award-v1"
            calculation.calculationRateBookVersion `shouldBe` Just (RateBookVersion "fixture-2025")
            calculationSourceValue HospitalityAward `shouldBe` "hospitality_award"
            calculationSourceValue ExternalImportedPayItem `shouldBe` "external_imported_pay_item"
            calculation.paidTimeSegments
                `shouldBe`
                    [ PaidTimeSegment
                        { paidTimeKind = Worked
                        , paidTimeStart = utcAt 0
                        , paidTimeEnd = utcAt 7200
                        , paidTimeLocalDate = fromGregorian 2026 1 5
                        , paidTimeSourceCondition = OrdinaryCondition
                        }
                    ]
            calculation.earningsComponents
                `shouldBe`
                    [ EarningsComponent
                        { quantity = 2
                        , unitType = Hours
                        , ratePerUnit = 100
                        , amount = 200
                        , sourceCondition = OrdinaryCondition
                        , calculationSource = HospitalityAward
                        , sourceRateIdentity = Just (RateSourceIdentity "source-243-PermanentPartTime-OrdinaryRate")
                        }
                    ]

        it "HIGA-11.1-CASUAL-LOADING pays casual ordinary time at 1.25O" do
            let calculation =
                    calculateOrFail
                        (testCalculationInput { calculationArrangement = AwardHourlyEmployment CasualEmployment })

            rateFor calculation `shouldBe` 125
            amountFor calculation `shouldBe` 250

        it "HIGA-29.2-SATURDAY and SUNDAY select one basis-specific day rate" do
            let saturday = twoHourOrdinaryInterval { paidIntervalLocalDayKind = LocalSaturday }
                sunday = twoHourOrdinaryInterval { paidIntervalLocalDayKind = LocalSunday }
                permanentSaturday = calculateOrFail (testCalculationInput { calculationPaidIntervals = [saturday] })
                casualSunday =
                    calculateOrFail
                        ( testCalculationInput
                            { calculationArrangement = AwardHourlyEmployment CasualEmployment
                            , calculationPaidIntervals = [sunday]
                            }
                        )

            rateFor permanentSaturday `shouldBe` 125
            fmap (.sourceCondition) permanentSaturday.earningsComponents `shouldBe` [SaturdayCondition]
            rateFor casualSunday `shouldBe` 175
            fmap (.sourceCondition) casualSunday.earningsComponents `shouldBe` [SundayCondition]

        it "HIGA-29.2-PUBLIC-HOLIDAY uses statewide dates and takes priority over Saturday" do
            let holidayDate = fromGregorian 2026 1 10
                holidayInterval =
                    twoHourOrdinaryInterval
                        { paidIntervalLocalDate = holidayDate
                        , paidIntervalLocalDayKind = LocalSaturday
                        }
                calculation =
                    calculateOrFail
                        ( testCalculationInput
                            { calculationStatewidePublicHolidayDates = Set.singleton holidayDate
                            , calculationPaidIntervals = [holidayInterval]
                            }
                        )

            rateFor calculation `shouldBe` 225
            fmap (.sourceCondition) calculation.earningsComponents `shouldBe` [PublicHolidayCondition]
            calculation.paidTimeSegments `shouldSatisfy` all ((== Worked) . (.paidTimeKind))

        it "HIGA-POLICY-IMPORTED-OVERRIDE prefers shift over staff and bypasses Award conditions" do
            let staffItem = ImportedPayItem "staff-item" "Staff imported" 55
                shiftItem = ImportedPayItem "shift-item" "Shift imported" 70
                saturdayEvening =
                    twoHourOrdinaryInterval
                        { paidIntervalLocalDayKind = LocalSaturday
                        , paidIntervalLocalWindow = EveningWindow
                        }
                calculation =
                    calculateOrFail
                        ( testCalculationInput
                            { calculationImportedOverrides = ImportedOverrideContext (Just shiftItem) (Just staffItem)
                            , calculationPaidIntervals = [saturdayEvening]
                            }
                        )

            calculation.calculationRateBookVersion `shouldBe` Nothing
            calculation.earningsComponents
                `shouldBe`
                    [ EarningsComponent
                        { quantity = 2
                        , unitType = Hours
                        , ratePerUnit = 70
                        , amount = 140
                        , sourceCondition = ImportedFlatRateCondition "shift-item"
                        , calculationSource = ExternalImportedPayItem
                        , sourceRateIdentity = Nothing
                        }
                    ]

        it "HIGA-POLICY-WEEK-ROLLOVER retains the selected version in each result" do
            let oldBook = validatedBookOrFail (completeRateBookCandidate 100)
                newCandidate =
                    (completeRateBookCandidate 110)
                        { candidateVersion = "fixture-2026"
                        , candidateEffectivePeriod = EffectivePeriod (Just (fromGregorian 2026 7 1)) Nothing
                        , candidateRates =
                            map
                                (\rate -> rate { candidateRateEffectivePeriod = EffectivePeriod (Just (fromGregorian 2026 7 1)) Nothing })
                                (candidateRates (completeRateBookCandidate 110))
                        }
                newBook = validatedBookOrFail newCandidate
                oldCalculation = calculateOrFail (withRateBook oldBook testCalculationInput)
                newCalculation = calculateOrFail (withRateBook newBook testCalculationInput)

            rateFor oldCalculation `shouldBe` 100
            oldCalculation.calculationRateBookVersion `shouldBe` Just (RateBookVersion "fixture-2025")
            rateFor newCalculation `shouldBe` 110
            newCalculation.calculationRateBookVersion `shouldBe` Just (RateBookVersion "fixture-2026")

        it "orders resolved intervals deterministically" do
            let firstHour = twoHourOrdinaryInterval { paidIntervalEnd = utcAt 3600 }
                secondHour = twoHourOrdinaryInterval { paidIntervalStart = utcAt 3600 }
                forward = calculateTimesheetPay (testCalculationInput { calculationPaidIntervals = [firstHour, secondHour] })
                backward = calculateTimesheetPay (testCalculationInput { calculationPaidIntervals = [secondHour, firstHour] })

            backward `shouldBe` forward

        it "HIGA-POLICY-GENERIC-TIME preserves non-quarter-hour elapsed quantities" do
            let thirtySevenMinutes = twoHourOrdinaryInterval { paidIntervalEnd = utcAt (37 * 60) }
                calculation = calculateOrFail (testCalculationInput { calculationPaidIntervals = [thirtySevenMinutes] })

            fmap (.quantity) calculation.earningsComponents `shouldBe` [37 / 60]
            amountFor calculation `shouldBe` 100 * 37 / 60

withRateBook :: ValidatedRateBook -> WageCalculationInput -> WageCalculationInput
withRateBook rateBook calculationInput =
    calculationInput
        { calculationAwardRateContext =
            (\awardContext -> awardContext { awardRateBook = rateBook })
                <$> calculationInput.calculationAwardRateContext
        }

validatedBookOrFail :: RateBookCandidate -> ValidatedRateBook
validatedBookOrFail candidate =
    case mkValidatedRateBook candidate of
        Left validationError -> error (show validationError)
        Right rateBook       -> rateBook
