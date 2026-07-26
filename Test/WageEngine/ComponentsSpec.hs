module Test.WageEngine.ComponentsSpec where

import Application.VenueTime
import Application.WageEngine
import Application.WagePublication
import qualified Data.Set as Set
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime, secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import IHP.Prelude
import Test.Hspec
import Test.QuickCheck (NonNegative (..), Positive (..), property)
import Test.WageEngine.Fixture

tests :: Spec
tests =
    describe "WageEngine components" do
        it "HIGA-29.2-EVENING-PART-HOUR pays a 15-minute weekday evening interval plus one fixed commenced unit" do
            let day = fromGregorian 2026 1 5
                eveningQuarterHour = awardSegmentBetween day (TimeOfDay 19 0 0) day (TimeOfDay 19 15 0)
                calculation = calculateOrFail (testCalculationInput { calculationShiftSegments = [eveningQuarterHour] })

            calculation.paidTimeSegments `shouldSatisfy` all ((== Worked) . (.paidTimeKind))
            sum (map paidTimeDurationSeconds calculation.paidTimeSegments) `shouldBe` 15 * 60
            calculation.earningsComponents
                `shouldBe`
                    [ EarningsComponent
                        { quantity = 1 / 4
                        , unitType = Hours
                        , ratePerUnit = 100
                        , amount = 25
                        , sourceCondition = OrdinaryCondition
                        , calculationSource = HospitalityAward
                        , sourceRateIdentity = Just (RateSourceIdentity "source-243-PermanentPartTime-OrdinaryRate")
                        }
                    , EarningsComponent
                        { quantity = 1
                        , unitType = CommencedHours
                        , ratePerUnit = 10
                        , amount = 10
                        , sourceCondition = EveningAdditionCondition
                        , calculationSource = HospitalityAward
                        , sourceRateIdentity = Just (RateSourceIdentity "source-addition-EveningAddition")
                        }
                    ]

        it "HIGA-29.2-EVENING-PART-HOUR keeps the fixed addition separate from a casual hourly rate once the engagement minimum is already met" do
            let day = fromGregorian 2026 1 5
                eveningTwoHours = awardSegmentBetween day (TimeOfDay 19 0 0) day (TimeOfDay 21 0 0)
                calculation =
                    calculateOrFail
                        ( testCalculationInput
                            { calculationArrangement = AwardHourlyEmployment CasualEmployment
                            , calculationShiftSegments = [eveningTwoHours]
                            }
                        )

            fmap (\component -> (component.unitType, component.ratePerUnit, component.amount)) calculation.earningsComponents
                `shouldBe` [(Hours, 125, 250), (CommencedHours, 10, 20)]

        it "HIGA-29.2-EVENING-PART-HOUR rounds 15, 60 and 75 exact elapsed minutes up to 1, 1 and 2 units" do
            let day = fromGregorian 2026 1 5
            forM_
                [ (TimeOfDay 19 15 0, 1)
                , (TimeOfDay 20 0 0, 1)
                , (TimeOfDay 20 15 0, 2)
                ]
                \(endTime, expectedUnits) -> do
                    let interval = awardSegmentBetween day (TimeOfDay 19 0 0) day endTime
                        calculation = calculateOrFail (testCalculationInput { calculationShiftSegments = [interval] })

                    commencedQuantity calculation `shouldBe` expectedUnits

        it "HIGA-29.2-EARLY-PART-HOUR keeps weekday evening and early-morning commenced additions separate" do
            let intervals =
                    awardSegmentsBetween
                        (fromGregorian 2026 1 5)
                        (TimeOfDay 18 45 0)
                        (fromGregorian 2026 1 6)
                        (TimeOfDay 0 15 0)
                calculation = calculateOrFail (testCalculationInput { calculationShiftSegments = intervals })

            sum (map paidTimeDurationSeconds calculation.paidTimeSegments) `shouldBe` 5 * 60 * 60 + 30 * 60
            hourlyQuantity calculation `shouldBe` 11 / 2
            fixedComponents calculation
                `shouldBe`
                    [ EarningsComponent
                        { quantity = 5
                        , unitType = CommencedHours
                        , ratePerUnit = 10
                        , amount = 50
                        , sourceCondition = EveningAdditionCondition
                        , calculationSource = HospitalityAward
                        , sourceRateIdentity = Just (RateSourceIdentity "source-addition-EveningAddition")
                        }
                    , EarningsComponent
                        { quantity = 1
                        , unitType = CommencedHours
                        , ratePerUnit = 15
                        , amount = 15
                        , sourceCondition = EarlyMorningAdditionCondition
                        , calculationSource = HospitalityAward
                        , sourceRateIdentity = Just (RateSourceIdentity "source-addition-EarlyMorningAddition")
                        }
                    ]

        it "HIGA-29.2-WEEKDAY additions do not apply to a public-holiday evening once the holiday minimum is already met" do
            let day = fromGregorian 2026 1 5
                evening = awardSegmentBetween day (TimeOfDay 19 0 0) day (TimeOfDay 23 0 0)
                calculation =
                    calculateOrFail
                        ( testCalculationInput
                            { calculationStatewidePublicHolidayDates = Set.singleton day
                            , calculationShiftSegments = [evening]
                            }
                        )

            fixedComponents calculation `shouldBe` []
            fmap (.sourceCondition) calculation.earningsComponents `shouldBe` [PublicHolidayCondition]
            hourlyQuantity calculation `shouldBe` 4

        it "HIGA-POLICY-MELBOURNE-ELAPSED keeps weekday additions out of Sunday DST intervals while preserving elapsed hours" do
            let autumnSunday =
                    awardSegmentsBetween
                        (fromGregorian 2026 4 5)
                        (TimeOfDay 1 30 0)
                        (fromGregorian 2026 4 5)
                        (TimeOfDay 3 30 0)
                springSunday =
                    awardSegmentsBetween
                        (fromGregorian 2026 10 4)
                        (TimeOfDay 1 30 0)
                        (fromGregorian 2026 10 4)
                        (TimeOfDay 3 30 0)

            forM_ [(autumnSunday, 3), (springSunday, 1)] \(intervals, expectedHours) -> do
                let calculation = calculateOrFail (testCalculationInput { calculationShiftSegments = intervals })

                fixedComponents calculation `shouldBe` []
                hourlyQuantity calculation `shouldBe` expectedHours
                sum (map paidTimeDurationSeconds calculation.paidTimeSegments) `shouldBe` expectedHours * 60 * 60

        it "HIGA-POLICY-IMPORTED-OVERRIDE keeps an evening imported pay item flat and addition-free" do
            let day = fromGregorian 2026 1 5
                importedPayItem = ImportedPayItem "imported-item" "Imported item" 70
                evening = awardSegmentBetween day (TimeOfDay 19 0 0) day (TimeOfDay 20 0 0)
                calculation =
                    calculateOrFail
                        ( testCalculationInput
                            { calculationImportedOverrides = ImportedOverrideContext (Just importedPayItem) Nothing
                            , calculationShiftSegments = [evening]
                            }
                        )

            calculation.earningsComponents
                `shouldBe`
                    [ EarningsComponent
                        { quantity = 1
                        , unitType = Hours
                        , ratePerUnit = 70
                        , amount = 70
                        , sourceCondition = ImportedFlatRateCondition "imported-item"
                        , calculationSource = ExternalImportedPayItem
                        , sourceRateIdentity = Nothing
                        }
                    ]

        it "HIGA-16.6-COMMENCED-SPLIT aggregates break-separated paid intervals before deriving an evening unit" do
            let day = fromGregorian 2026 1 5
                evening = awardSegmentBetween day (TimeOfDay 19 0 0) day (TimeOfDay 20 0 0)
                mealBreak =
                    case resolveInterval breakStart breakEnd of
                        Left failure   -> error (show failure)
                        Right interval -> interval
                breakStart = MelbourneCivilTime day (TimeOfDay 19 15 0) Nothing
                breakEnd = MelbourneCivilTime day (TimeOfDay 19 45 0) Nothing
                calculation =
                    calculateOrFail
                        ( testCalculationInput
                            { calculationShiftSegments = [evening]
                            , calculationUnpaidMealBreak = Just mealBreak
                            }
                        )

            sum (map paidTimeDurationSeconds calculation.paidTimeSegments) `shouldBe` 30 * 60
            hourlyQuantity calculation `shouldBe` 1 / 2
            commencedQuantity calculation `shouldBe` 1

        it "HIGA-POLICY-FINAL-LINE-ROUNDING aggregates exact matching components before rounding once to cents" do
            let components = replicate 2 (roundingComponent OrdinaryCondition)
                expectedKey =
                    FinalEarningsBucketKey
                        { finalEarningsBucketUnitType = Hours
                        , finalEarningsBucketSourceCondition = OrdinaryCondition
                        , finalEarningsBucketCalculationSource = HospitalityAward
                        , finalEarningsBucketRatePerUnit = 1
                        , finalEarningsBucketSourceRateIdentity = Just (RateSourceIdentity "rounding-source")
                        }
                expectedLine =
                    FinalEarningsLine
                        { finalEarningsLineBucketKey = expectedKey
                        , finalEarningsLineQuantity = 2 / 250
                        , finalEarningsLineExactAmount = 2 / 250
                        , finalEarningsLineRoundedAmount = 1 / 100
                        }
                summary = deriveFinalEarnings components

            summary `shouldBe` FinalEarningsSummary [expectedLine] (1 / 100)
            deriveFinalEarnings (reverse components) `shouldBe` summary
            sum (map (.finalEarningsLineExactAmount) summary.finalEarningsLines)
                `shouldBe` sum (map (.amount) components)

        it "HIGA-POLICY-FINAL-LINE-ROUNDING sums rounded final lines rather than rounding across buckets" do
            let ordinary = roundingComponent OrdinaryCondition
                saturday = ordinary { sourceCondition = SaturdayCondition }
                summary = deriveFinalEarnings [ordinary, saturday]

            fmap (.finalEarningsLineRoundedAmount) summary.finalEarningsLines `shouldBe` [0, 0]
            summary.finalEarningsTotalAmount `shouldBe` 0

        it "HIGA-POLICY-OUTPUT-ROUNDING aggregates hourly quantities before one quarter-hour half-up transform" do
            let component = (roundingComponent OrdinaryCondition) { quantity = 1 / 16, ratePerUnit = 30, amount = 15 / 8 }
                lines = derivePublishedEarnings [component, component]

            lines `shouldBe`
                [ PublishedEarningsLine
                    { publishedBucketKey = publicationBucketKey component
                    , publishedExactQuantity = 1 / 8
                    , publishedQuantity = 1 / 4
                    , publishedExactAmount = 15 / 4
                    , publishedAmount = 15 / 2
                    }
                ]

        it "HIGA-POLICY-OUTPUT-ROUNDING keeps commenced-hour units whole and rounds their final amount once" do
            let component =
                    EarningsComponent
                        { quantity = 2
                        , unitType = CommencedHours
                        , ratePerUnit = 10.005
                        , amount = 20.01
                        , sourceCondition = EveningAdditionCondition
                        , calculationSource = HospitalityAward
                        , sourceRateIdentity = Just (RateSourceIdentity "fixed-source")
                        }
                [line] = derivePublishedEarnings [component]

            line.publishedQuantity `shouldBe` 2
            line.publishedAmount `shouldBe` 2001 / 100

        it "HIGA-POLICY-OUTPUT-CONSERVATION publishes paid evening time without publishing its fixed addition as hours" do
            let day = fromGregorian 2026 1 5
                calculation = calculateOrFail (testCalculationInput { calculationShiftSegments = [awardSegmentBetween day (TimeOfDay 19 0 0) day (TimeOfDay 19 15 0)] })

            staffHoursContributions calculation `shouldBe` [StaffHoursContribution day StaffHoursEvening (1 / 4)]
            map (\(_, component) -> component.unitType) (datedEarningsComponents calculation) `shouldBe` [Hours, CommencedHours]

        it "HIGA-POLICY-OUTPUT-CONSERVATION keeps an overnight late-break addition on the local day where it applied" do
            let day = fromGregorian 2026 1 5
                nextDay = addDays 1 day
                lateBreak =
                    case resolveInterval (MelbourneCivilTime day (TimeOfDay 23 0 0) Nothing) (MelbourneCivilTime day (TimeOfDay 23 30 0) Nothing) of
                        Left failure   -> error (show failure)
                        Right interval -> interval
                calculation =
                    calculateOrFail
                        ( testCalculationInput
                            { calculationShiftSegments = awardSegmentsBetween day (TimeOfDay 16 0 0) nextDay (TimeOfDay 1 0 0)
                            , calculationUnpaidMealBreak = Just lateBreak
                            }
                        )
                missed =
                    [ (componentDate, component.quantity)
                    | (componentDate, component) <- datedEarningsComponents calculation
                    , component.sourceCondition == MissedMealBreakAdditionCondition
                    ]

            missed `shouldBe` [(day, 1)]

        it "HIGA-POLICY-OUTPUT-CONSERVATION sends non-worked casual minimum top-up time to the ordinary Staff Hours bucket" do
            let day = fromGregorian 2026 1 5
                calculation =
                    calculateOrFail
                        ( testCalculationInput
                            { calculationArrangement = AwardHourlyEmployment CasualEmployment
                            , calculationShiftSegments = [awardSegmentBetween day (TimeOfDay 19 0 0) day (TimeOfDay 19 15 0)]
                            }
                        )
                contributions = staffHoursContributions calculation

            contributions `shouldContain` [StaffHoursContribution day StaffHoursEvening (1 / 4)]
            sum [quantity | StaffHoursContribution _ StaffHoursOrdinary quantity <- contributions] `shouldBe` 7 / 4

        it "property: artificial weekday-evening splitting preserves final wages and commenced units" $
            property propArtificialSplitInvariance

        it "property: imported overrides remain flat, deterministic and split-invariant" $
            property propImportedOverrideDeterminism

        it "property: export-only quarter-hour rounding is deterministic, split-invariant and internally reconciled" $
            property propPublishedEarningsReconciliation

propImportedOverrideDeterminism :: Positive Integer -> NonNegative Integer -> Bool
propImportedOverrideDeterminism (Positive durationSeed) (NonNegative splitSeed) =
    case (directSegments, splitSegments) of
        (Right direct, Right split) ->
            case (calculate direct, calculate split) of
                (Right directCalculation, Right splitCalculation) ->
                    deriveFinalEarnings directCalculation.earningsComponents
                        == deriveFinalEarnings splitCalculation.earningsComponents
                        && directCalculation == calculateOrFail (input direct)
                        && all isFlatImported (directCalculation.earningsComponents <> splitCalculation.earningsComponents)
                        && sum (map (.quantity) directCalculation.earningsComponents) * 3600 == toRational durationSeconds
                _ -> False
        _ -> False
  where
    durationSeconds = 2 + durationSeed `mod` (12 * 60 * 60 - 1)
    splitSeconds = 1 + splitSeed `mod` (durationSeconds - 1)
    start = resolvedInstantFromUTC (UTCTime (fromGregorian 2026 1 5) (secondsToDiffTime (8 * 60 * 60)))
    split = resolvedInstantFromUTC (addUTCTime (fromInteger splitSeconds) (resolvedInstantUTC start))
    end = resolvedInstantFromUTC (addUTCTime (fromInteger durationSeconds) (resolvedInstantUTC start))
    directSegments = resolvedIntervalFromInstants start end >>= awardSegments
    splitSegments = do
        left <- resolvedIntervalFromInstants start split >>= awardSegments
        right <- resolvedIntervalFromInstants split end >>= awardSegments
        pure (left <> right)
    imported = ImportedPayItem "property-imported" "Property imported" 73
    input segments =
        testCalculationInput
            { calculationImportedOverrides = ImportedOverrideContext (Just imported) Nothing
            , calculationShiftSegments = segments
            }
    calculate = calculateTimesheetPay . input
    isFlatImported component =
        component.unitType == Hours
            && component.ratePerUnit == 73
            && component.sourceCondition == ImportedFlatRateCondition "property-imported"
            && component.calculationSource == ExternalImportedPayItem
            && isNothing component.sourceRateIdentity

propPublishedEarningsReconciliation :: Positive Integer -> NonNegative Integer -> Positive Integer -> Bool
propPublishedEarningsReconciliation (Positive durationSeed) (NonNegative splitSeed) (Positive rateSeed) =
    direct == splitPublished
        && direct == derivePublishedEarnings (reverse splitComponents)
        && case direct of
            [line] ->
                line.publishedExactQuantity == quantity
                    && line.publishedExactAmount == quantity * toRational rate
                    && (floor (line.publishedQuantity * 4) :: Integer) == ceiling (line.publishedQuantity * 4)
                    && line.publishedAmount == roundCents (line.publishedQuantity * toRational rate)
            _ -> False
  where
    elapsedSeconds = 2 + durationSeed `mod` (24 * 60 * 60 - 1)
    firstSeconds = 1 + splitSeed `mod` (elapsedSeconds - 1)
    quantity = toRational elapsedSeconds / 3600
    firstQuantity = toRational firstSeconds / 3600
    secondQuantity = quantity - firstQuantity
    rate = fromInteger (1 + rateSeed `mod` 10000) / 100
    component componentQuantity =
        EarningsComponent
            { quantity = componentQuantity
            , unitType = Hours
            , ratePerUnit = rate
            , amount = componentQuantity * toRational rate
            , sourceCondition = OrdinaryCondition
            , calculationSource = HospitalityAward
            , sourceRateIdentity = Just (RateSourceIdentity "publication-property-source")
            }
    splitComponents = [component firstQuantity, component secondQuantity]
    direct = derivePublishedEarnings [component quantity]
    splitPublished = derivePublishedEarnings splitComponents
    roundCents value = fromInteger (floor (value * 100 + 1 / 2)) / 100

roundingComponent :: SourceCondition -> EarningsComponent
roundingComponent condition =
    EarningsComponent
        { quantity = 1 / 250
        , unitType = Hours
        , ratePerUnit = 1
        , amount = 1 / 250
        , sourceCondition = condition
        , calculationSource = HospitalityAward
        , sourceRateIdentity = Just (RateSourceIdentity "rounding-source")
        }

fixedComponents :: WageCalculation -> [EarningsComponent]
fixedComponents = filter ((== CommencedHours) . (.unitType)) . (.earningsComponents)

hourlyQuantity :: WageCalculation -> Rational
hourlyQuantity =
    sum
        . map (.quantity)
        . filter ((== Hours) . (.unitType))
        . (.earningsComponents)

commencedQuantity :: WageCalculation -> Rational
commencedQuantity = sum . map (.quantity) . fixedComponents

awardSegmentsBetween :: Day -> TimeOfDay -> Day -> TimeOfDay -> [AwardSegment]
awardSegmentsBetween startDay startTime endDay endTime =
    case resolveInterval startCivil endCivil >>= awardSegments of
        Left failure    -> error (show failure)
        Right intervals -> intervals
  where
    startCivil = MelbourneCivilTime startDay startTime Nothing
    endCivil = MelbourneCivilTime endDay endTime Nothing

propArtificialSplitInvariance :: Positive Integer -> NonNegative Integer -> Bool
propArtificialSplitInvariance (Positive durationSeed) (NonNegative splitSeed) =
    case (directSegments, splitSegments) of
        (Right direct, Right split) ->
            case
                ( calculateTimesheetPay (testCalculationInput { calculationShiftSegments = direct })
                , calculateTimesheetPay (testCalculationInput { calculationShiftSegments = split })
                )
                of
                    (Right directCalculation, Right splitCalculation) ->
                        deriveFinalEarnings directCalculation.earningsComponents
                            == deriveFinalEarnings splitCalculation.earningsComponents
                            && sum (map paidTimeDurationSeconds directCalculation.paidTimeSegments)
                                == sum (map paidTimeDurationSeconds splitCalculation.paidTimeSegments)
                            && commencedQuantity directCalculation == expectedUnits
                            && commencedQuantity splitCalculation == expectedUnits
                    _ -> False
        _ -> False
  where
    durationSeconds = 2 + durationSeed `mod` (5 * 60 * 60 - 1)
    splitSeconds = 1 + splitSeed `mod` (durationSeconds - 1)
    start = resolvedInstantFromUTC (UTCTime (fromGregorian 2026 1 5) (secondsToDiffTime (8 * 60 * 60)))
    split = resolvedInstantFromUTC (addUTCTime (fromInteger splitSeconds) (resolvedInstantUTC start))
    end = resolvedInstantFromUTC (addUTCTime (fromInteger durationSeconds) (resolvedInstantUTC start))
    directSegments = resolvedIntervalFromInstants start end >>= awardSegments
    splitSegments = do
        left <- resolvedIntervalFromInstants start split >>= awardSegments
        right <- resolvedIntervalFromInstants split end >>= awardSegments
        pure (left <> right)
    expectedUnits = fromInteger (ceiling (toRational durationSeconds / 3600) :: Integer)
