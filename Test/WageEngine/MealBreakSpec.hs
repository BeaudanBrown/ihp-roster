module Test.WageEngine.MealBreakSpec where

import Application.VenueTime
import Application.WageEngine
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import Data.Time.Calendar (Day, fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime, secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import IHP.Prelude
import Test.Hspec
import Test.QuickCheck (NonNegative (..), Positive (..), property)
import Test.WageEngine.Fixture

tests :: Spec
tests =
    describe "WageEngine unpaid meal breaks" do
        it "HIGA-16.6-BREAK-NOT-RECORDED and HIGA-EXCL-BREAK-OFFERED-WORKFLOW keep worked time and add the exact 50% ordinary-rate component after six elapsed hours from recorded facts" do
            let day = fromGregorian 2026 1 5
                calculation = calculationFor day (TimeOfDay 9 0 0) day (TimeOfDay 17 0 0) Nothing

            sum (map paidTimeDurationSeconds calculation.paidTimeSegments) `shouldBe` 8 * 60 * 60
            calculation.earningsComponents
                `shouldBe`
                    [ EarningsComponent
                        { quantity = 8
                        , unitType = Hours
                        , ratePerUnit = 100
                        , amount = 800
                        , sourceCondition = OrdinaryCondition
                        , calculationSource = HospitalityAward
                        , sourceRateIdentity = Just (RateSourceIdentity "source-243-PermanentPartTime-OrdinaryRate")
                        }
                    , EarningsComponent
                        { quantity = 2
                        , unitType = Hours
                        , ratePerUnit = 50
                        , amount = 100
                        , sourceCondition = MissedMealBreakAdditionCondition
                        , calculationSource = HospitalityAward
                        , sourceRateIdentity = Just (RateSourceIdentity "source-243-PermanentPartTime-OrdinaryRate")
                        }
                    ]

        it "HIGA-16.2-BREAK-5H and HIGA-16.2-BREAK-5-6H keep recorded breaks elective while deducting them exactly once" do
            let day = fromGregorian 2026 1 5
                exactlyFiveHours = calculationFor day (TimeOfDay 9 0 0) day (TimeOfDay 14 0 0) Nothing
                fiveAndAHalfWithoutBreak = calculationFor day (TimeOfDay 9 0 0) day (TimeOfDay 14 30 0) Nothing
                fiveAndAHalfWithBreak =
                    calculationFor
                        day
                        (TimeOfDay 9 0 0)
                        day
                        (TimeOfDay 14 30 0)
                        (Just (mealBreakFor day (TimeOfDay 12 0 0) day (TimeOfDay 12 30 0)))

            paidSeconds exactlyFiveHours `shouldBe` 5 * 60 * 60
            paidSeconds fiveAndAHalfWithoutBreak `shouldBe` 5 * 60 * 60 + 30 * 60
            paidSeconds fiveAndAHalfWithBreak `shouldBe` 5 * 60 * 60
            map missedQuantity [exactlyFiveHours, fiveAndAHalfWithoutBreak, fiveAndAHalfWithBreak]
                `shouldBe` [0, 0, 0]

        it "HIGA-16.2-BREAK-6H keeps exactly six hours outside the missed-break addition" do
            let day = fromGregorian 2026 1 5
                withoutBreak = calculationFor day (TimeOfDay 9 0 0) day (TimeOfDay 15 0 0) Nothing
                withBreak =
                    calculationFor
                        day
                        (TimeOfDay 9 0 0)
                        day
                        (TimeOfDay 15 0 0)
                        (Just (mealBreakFor day (TimeOfDay 12 0 0) day (TimeOfDay 12 30 0)))

            paidSeconds withoutBreak `shouldBe` 6 * 60 * 60
            paidSeconds withBreak `shouldBe` 5 * 60 * 60 + 30 * 60
            map missedQuantity [withoutBreak, withBreak] `shouldBe` [0, 0]

        it "HIGA-16.2-BREAK-29M and HIGA-16.2-BREAK-30M distinguish deduction from qualification" do
            let day = fromGregorian 2026 1 5
                twentyNineMinutes =
                    calculationFor
                        day
                        (TimeOfDay 9 0 0)
                        day
                        (TimeOfDay 17 0 0)
                        (Just (mealBreakFor day (TimeOfDay 12 0 0) day (TimeOfDay 12 29 0)))
                lateTwentyNineMinutes =
                    calculationFor
                        day
                        (TimeOfDay 9 0 0)
                        day
                        (TimeOfDay 17 0 0)
                        (Just (mealBreakFor day (TimeOfDay 15 30 0) day (TimeOfDay 15 59 0)))
                thirtyMinutes =
                    calculationFor
                        day
                        (TimeOfDay 9 0 0)
                        day
                        (TimeOfDay 17 0 0)
                        (Just (mealBreakFor day (TimeOfDay 12 0 0) day (TimeOfDay 12 30 0)))

            map paidSeconds [twentyNineMinutes, lateTwentyNineMinutes] `shouldBe` replicate 2 (8 * 60 * 60 - 29 * 60)
            paidSeconds thirtyMinutes `shouldBe` 8 * 60 * 60 - 30 * 60
            map missedQuantity [twentyNineMinutes, lateTwentyNineMinutes, thirtyMinutes] `shouldBe` [2, 2, 0]

        it "HIGA-16.2-BREAK-BEFORE-2H, HIGA-16.2-BREAK-AT-2H, HIGA-16.2-BREAK-AT-6H and HIGA-16.5-BREAK-LATE-STOP apply inclusive timing and stop late additions" do
            let day = fromGregorian 2026 1 5
                early = mealBreakFor day (TimeOfDay 10 0 0) day (TimeOfDay 10 30 0)
                atTwoHours = mealBreakFor day (TimeOfDay 11 0 0) day (TimeOfDay 11 30 0)
                atSixHours = mealBreakFor day (TimeOfDay 15 0 0) day (TimeOfDay 15 30 0)
                late = mealBreakFor day (TimeOfDay 15 30 0) day (TimeOfDay 16 0 0)
                calculations =
                    map
                        (calculationFor day (TimeOfDay 9 0 0) day (TimeOfDay 17 0 0) . Just)
                        [early, atTwoHours, atSixHours, late]

            map paidSeconds calculations `shouldBe` replicate 4 (8 * 60 * 60 - 30 * 60)
            map missedQuantity calculations `shouldBe` [2, 0, 0, 1 / 2]

        it "HIGA-POLICY-BREAK-BUCKET deducts an overnight unpaid meal break from its actual next-day condition" do
            let friday = fromGregorian 2026 1 9
                saturday = fromGregorian 2026 1 10
                mealBreak = mealBreakFor saturday (TimeOfDay 0 15 0) saturday (TimeOfDay 0 45 0)
                calculation = calculationFor friday (TimeOfDay 22 0 0) saturday (TimeOfDay 6 0 0) (Just mealBreak)

            paidSeconds calculation `shouldBe` 7 * 60 * 60 + 30 * 60
            map (.sourceCondition) (baseHourlyComponents calculation)
                `shouldBe` [OrdinaryCondition, SaturdayCondition, SaturdayCondition]
            baseHourlyQuantityFor OrdinaryCondition calculation `shouldBe` 2
            baseHourlyQuantityFor SaturdayCondition calculation `shouldBe` 11 / 2
            missedQuantity calculation `shouldBe` 0

        it "HIGA-16.2-PAID-REST leaves all elapsed time payable when no unpaid meal break is recorded" do
            let day = fromGregorian 2026 1 5
                calculation = calculationFor day (TimeOfDay 9 0 0) day (TimeOfDay 14 0 0) Nothing

            paidSeconds calculation `shouldBe` 5 * 60 * 60
            baseHourlyQuantity calculation `shouldBe` 5

        it "HIGA-16.6-BREAK-CASUAL-O uses 50% of part-time ordinary O rather than casual O" do
            let day = fromGregorian 2026 1 5
                calculation =
                    calculateOrFail
                        ( (calculationInputFor day (TimeOfDay 9 0 0) day (TimeOfDay 17 0 0) Nothing)
                            { calculationArrangement = AwardHourlyEmployment CasualEmployment
                            }
                        )

            baseHourlyQuantity calculation `shouldBe` 8
            map (.ratePerUnit) (baseHourlyComponents calculation) `shouldBe` [125]
            missedComponents calculation
                `shouldBe`
                    [ EarningsComponent
                        { quantity = 2
                        , unitType = Hours
                        , ratePerUnit = 50
                        , amount = 100
                        , sourceCondition = MissedMealBreakAdditionCondition
                        , calculationSource = HospitalityAward
                        , sourceRateIdentity = Just (RateSourceIdentity "source-243-PermanentPartTime-OrdinaryRate")
                        }
                    ]

        it "HIGA-16.2-BREAK-OVER-6H, HIGA-16.6-BREAK-CONDITION-MATRIX and HIGA-29.3-BREAK-CUMULATIVE retain each part-time/casual base wage, weekday addition and 50% meal-break addition" do
            let monday = fromGregorian 2026 1 5
                saturday = fromGregorian 2026 1 10
                sunday = fromGregorian 2026 1 11
                publicHolidayInput =
                    (calculationInputFor saturday (TimeOfDay 9 0 0) saturday (TimeOfDay 17 0 0) Nothing)
                        { calculationStatewidePublicHolidayDates = Set.singleton saturday
                        }
                cases =
                    [ ( "ordinary"
                      , calculationInputFor monday (TimeOfDay 9 0 0) monday (TimeOfDay 17 0 0) Nothing
                      , 100
                      , 125
                      , []
                      )
                    , ( "evening"
                      , calculationInputFor monday (TimeOfDay 15 0 0) monday (TimeOfDay 23 0 0) Nothing
                      , 100
                      , 125
                      , [fixedComponent 4 10 EveningAdditionCondition]
                      )
                    , ( "early-morning"
                      , calculationInputFor monday (TimeOfDay 20 0 0) (fromGregorian 2026 1 6) (TimeOfDay 4 0 0) Nothing
                      , 100
                      , 125
                      , [ fixedComponent 4 10 EveningAdditionCondition
                        , fixedComponent 4 15 EarlyMorningAdditionCondition
                        ]
                      )
                    , ( "saturday"
                      , calculationInputFor saturday (TimeOfDay 9 0 0) saturday (TimeOfDay 17 0 0) Nothing
                      , 125
                      , 150
                      , []
                      )
                    , ( "sunday"
                      , calculationInputFor sunday (TimeOfDay 9 0 0) sunday (TimeOfDay 17 0 0) Nothing
                      , 150
                      , 175
                      , []
                      )
                    , ("public-holiday", publicHolidayInput, 225, 250, [])
                    ]

            forM_ cases \(_, input, permanentRate, casualRate, expectedFixed) ->
                forM_ [(PermanentPartTime, permanentRate), (CasualEmployment, casualRate)] \(basis, expectedBaseRate) -> do
                    let calculation = calculateOrFail (input { calculationArrangement = AwardHourlyEmployment basis })

                    baseHourlyQuantity calculation `shouldBe` 8
                    map (.ratePerUnit) (baseHourlyComponents calculation) `shouldSatisfy` all (== expectedBaseRate)
                    fixedEarningsComponents calculation `shouldBe` expectedFixed
                    missedComponents calculation `shouldBe` [hourlyComponent 2 50 MissedMealBreakAdditionCondition]
                    paidSeconds calculation `shouldBe` 8 * 60 * 60

        it "HIGA-29.3-HIGHEST-PENALTY gives public holidays precedence and prevents weekday additions from stacking on weekend or holiday bases" do
            let saturday = fromGregorian 2026 1 10
                sunday = fromGregorian 2026 1 11
                saturdayEvening = calculationFor saturday (TimeOfDay 19 0 0) saturday (TimeOfDay 21 0 0) Nothing
                sundayEarly = calculationFor sunday (TimeOfDay 1 0 0) sunday (TimeOfDay 3 0 0) Nothing
                publicHolidaySaturdayEvening =
                    calculateOrFail
                        ( (calculationInputFor saturday (TimeOfDay 19 0 0) saturday (TimeOfDay 21 0 0) Nothing)
                            { calculationStatewidePublicHolidayDates = Set.singleton saturday
                            }
                        )
                publicHolidaySundayEarly =
                    calculateOrFail
                        ( (calculationInputFor sunday (TimeOfDay 1 0 0) sunday (TimeOfDay 3 0 0) Nothing)
                            { calculationStatewidePublicHolidayDates = Set.singleton sunday
                            }
                        )

            baseHourlyComponents saturdayEvening `shouldBe` [hourlyComponent 2 125 SaturdayCondition]
            baseHourlyComponents sundayEarly `shouldBe` [hourlyComponent 2 150 SundayCondition]
            map baseHourlyComponents [publicHolidaySaturdayEvening, publicHolidaySundayEarly]
                `shouldBe` replicate 2 [hourlyComponent 2 225 PublicHolidayCondition]
            map fixedEarningsComponents [saturdayEvening, sundayEarly, publicHolidaySaturdayEvening, publicHolidaySundayEarly] `shouldBe` [[], [], [], []]

        it "HIGA-POLICY-MELBOURNE-ELAPSED applies missed-break thresholds and recorded-break deductions to exact autumn and spring Sunday elapsed time" do
            let autumnSunday = fromGregorian 2026 4 5
                springSunday = fromGregorian 2026 10 4
                autumnBreak =
                    mealBreakForCivil
                        (MelbourneCivilTime autumnSunday (TimeOfDay 2 30 0) (Just FirstOccurrence))
                        (MelbourneCivilTime autumnSunday (TimeOfDay 2 30 0) (Just SecondOccurrence))
                springBreak = mealBreakFor springSunday (TimeOfDay 1 30 0) springSunday (TimeOfDay 3 30 0)
                autumn = calculationFor autumnSunday (TimeOfDay 0 0 0) autumnSunday (TimeOfDay 7 0 0) Nothing
                spring = calculationFor springSunday (TimeOfDay 0 0 0) springSunday (TimeOfDay 8 0 0) Nothing
                autumnWithBreak = calculationFor autumnSunday (TimeOfDay 0 0 0) autumnSunday (TimeOfDay 7 0 0) (Just autumnBreak)
                springWithBreak = calculationFor springSunday (TimeOfDay 0 0 0) springSunday (TimeOfDay 8 0 0) (Just springBreak)

            map resolvedIntervalElapsedSeconds [autumnBreak, springBreak] `shouldBe` [60 * 60, 60 * 60]
            map paidSeconds [autumn, spring, autumnWithBreak, springWithBreak]
                `shouldBe` [8 * 60 * 60, 7 * 60 * 60, 7 * 60 * 60, 6 * 60 * 60]
            map baseHourlyQuantity [autumn, spring, autumnWithBreak, springWithBreak] `shouldBe` [8, 7, 7, 6]
            map missedQuantity [autumn, spring, autumnWithBreak, springWithBreak] `shouldBe` [2, 1, 0, 1]
            map fixedEarningsComponents [autumn, spring, autumnWithBreak, springWithBreak] `shouldBe` [[], [], [], []]

        it "HIGA-POLICY-IMPORTED-OVERRIDE keeps the imported rate flat while still deducting an unpaid meal break" do
            let day = fromGregorian 2026 1 5
                imported = ImportedPayItem "imported-item" "Imported item" 70
                mealBreak = mealBreakFor day (TimeOfDay 12 0 0) day (TimeOfDay 12 30 0)
                calculation =
                    calculateOrFail
                        ( (calculationInputFor day (TimeOfDay 9 0 0) day (TimeOfDay 17 0 0) (Just mealBreak))
                            { calculationImportedOverrides = ImportedOverrideContext (Just imported) Nothing
                            }
                        )

            paidSeconds calculation `shouldBe` 7 * 60 * 60 + 30 * 60
            map (.sourceCondition) calculation.earningsComponents `shouldSatisfy` all (== ImportedFlatRateCondition "imported-item")
            map (.ratePerUnit) calculation.earningsComponents `shouldSatisfy` all (== 70)
            sum (map (.quantity) calculation.earningsComponents) `shouldBe` 15 / 2
            missedComponents calculation `shouldBe` []

        it "HIGA-16.6-COMMENCED-SPLIT keeps weekday commenced-hour units correct when the six-hour threshold falls inside evening work" do
            let day = fromGregorian 2026 1 5
                calculation = calculationFor day (TimeOfDay 15 0 0) day (TimeOfDay 23 0 0) Nothing

            fixedEarningsComponents calculation `shouldBe` [fixedComponent 4 10 EveningAdditionCondition]
            missedComponents calculation `shouldBe` [hourlyComponent 2 50 MissedMealBreakAdditionCondition]
            baseHourlyQuantity calculation `shouldBe` 8

        it "HIGA-POLICY-FINAL-LINE-ROUNDING reconciles separate base, commenced-hour and missed-break exact components" do
            let day = fromGregorian 2026 1 5
                calculation = calculationFor day (TimeOfDay 15 0 0) day (TimeOfDay 23 0 0) Nothing
                summary = deriveFinalEarnings calculation.earningsComponents

            sum (map (.finalEarningsLineExactAmount) summary.finalEarningsLines)
                `shouldBe` sum (map (.amount) calculation.earningsComponents)
            summary.finalEarningsTotalAmount `shouldBe` 940
            filter ((== MissedMealBreakAdditionCondition) . (.finalEarningsBucketSourceCondition)) (map (.finalEarningsLineBucketKey) summary.finalEarningsLines)
                `shouldBe`
                    [ FinalEarningsBucketKey
                        { finalEarningsBucketUnitType = Hours
                        , finalEarningsBucketSourceCondition = MissedMealBreakAdditionCondition
                        , finalEarningsBucketCalculationSource = HospitalityAward
                        , finalEarningsBucketRatePerUnit = 50
                        , finalEarningsBucketSourceRateIdentity = Just (RateSourceIdentity "source-243-PermanentPartTime-OrdinaryRate")
                        }
                    ]

        it "property: exact elapsed paid time and base hourly quantities conserve every recorded unpaid meal break exactly once" $
            property propBreakDeductionConservation

        it "property: highest base-penalty selection is unique for Saturday, Sunday and public-holiday evening work" $
            property propHighestBasePenaltyUniqueness

        it "property: an artificial split across the six-hour threshold preserves final earnings, paid elapsed time and commenced evening units" $
            property propSixHourSplitInvariance

calculationFor :: Day -> TimeOfDay -> Day -> TimeOfDay -> Maybe ResolvedInterval -> WageCalculation
calculationFor startDay startTime endDay endTime mealBreak =
    calculateOrFail (calculationInputFor startDay startTime endDay endTime mealBreak)

calculationInputFor :: Day -> TimeOfDay -> Day -> TimeOfDay -> Maybe ResolvedInterval -> WageCalculationInput
calculationInputFor startDay startTime endDay endTime mealBreak =
    testCalculationInput
        { calculationShiftSegments = awardSegmentsFor startDay startTime endDay endTime
        , calculationUnpaidMealBreak = mealBreak
        }

awardSegmentsFor :: Day -> TimeOfDay -> Day -> TimeOfDay -> [AwardSegment]
awardSegmentsFor startDay startTime endDay endTime =
    case resolveInterval startCivil endCivil >>= awardSegments of
        Left failure   -> error (show failure)
        Right segments -> segments
  where
    startCivil = MelbourneCivilTime startDay startTime Nothing
    endCivil = MelbourneCivilTime endDay endTime Nothing

mealBreakFor :: Day -> TimeOfDay -> Day -> TimeOfDay -> ResolvedInterval
mealBreakFor startDay startTime endDay endTime =
    mealBreakForCivil
        (MelbourneCivilTime startDay startTime Nothing)
        (MelbourneCivilTime endDay endTime Nothing)

mealBreakForCivil :: MelbourneCivilTime -> MelbourneCivilTime -> ResolvedInterval
mealBreakForCivil startCivil endCivil =
    case resolveInterval startCivil endCivil of
        Left failure   -> error (show failure)
        Right interval -> interval

paidSeconds :: WageCalculation -> Rational
paidSeconds = sum . map paidTimeDurationSeconds . (.paidTimeSegments)

missedQuantity :: WageCalculation -> Rational
missedQuantity = sum . map (.quantity) . missedComponents

missedComponents :: WageCalculation -> [EarningsComponent]
missedComponents =
    filter ((== MissedMealBreakAdditionCondition) . (.sourceCondition))
        . (.earningsComponents)

baseHourlyQuantity :: WageCalculation -> Rational
baseHourlyQuantity = sum . map (.quantity) . baseHourlyComponents

baseHourlyQuantityFor :: SourceCondition -> WageCalculation -> Rational
baseHourlyQuantityFor condition =
    sum
        . map (.quantity)
        . filter ((== condition) . (.sourceCondition))
        . baseHourlyComponents

baseHourlyComponents :: WageCalculation -> [EarningsComponent]
baseHourlyComponents =
    filter
        (\component ->
            component.unitType == Hours
                && component.sourceCondition /= MissedMealBreakAdditionCondition
        )
        . (.earningsComponents)

fixedEarningsComponents :: WageCalculation -> [EarningsComponent]
fixedEarningsComponents = filter ((== CommencedHours) . (.unitType)) . (.earningsComponents)

hourlyComponent :: Rational -> Scientific -> SourceCondition -> EarningsComponent
hourlyComponent componentQuantity componentRate condition =
    EarningsComponent
        { quantity = componentQuantity
        , unitType = Hours
        , ratePerUnit = componentRate
        , amount = componentQuantity * toRational componentRate
        , sourceCondition = condition
        , calculationSource = HospitalityAward
        , sourceRateIdentity = Just (RateSourceIdentity (hourlySource condition))
        }

hourlySource :: SourceCondition -> Text
hourlySource = \case
    OrdinaryCondition                 -> "source-243-PermanentPartTime-OrdinaryRate"
    SaturdayCondition                 -> "source-243-PermanentPartTime-SaturdayRate"
    SundayCondition                   -> "source-243-PermanentPartTime-SundayRate"
    PublicHolidayCondition            -> "source-243-PermanentPartTime-PublicHolidayRate"
    MissedMealBreakAdditionCondition  -> "source-243-PermanentPartTime-OrdinaryRate"
    unexpected -> error ("Expected an Award hourly condition, got " <> show unexpected)

fixedComponent :: Rational -> Scientific -> SourceCondition -> EarningsComponent
fixedComponent componentQuantity componentRate condition =
    EarningsComponent
        { quantity = componentQuantity
        , unitType = CommencedHours
        , ratePerUnit = componentRate
        , amount = componentQuantity * toRational componentRate
        , sourceCondition = condition
        , calculationSource = HospitalityAward
        , sourceRateIdentity = Just (RateSourceIdentity (additionSource condition))
        }

additionSource :: SourceCondition -> Text
additionSource = \case
    EveningAdditionCondition      -> "source-addition-EveningAddition"
    EarlyMorningAdditionCondition -> "source-addition-EarlyMorningAddition"
    unexpected -> error ("Expected a weekday addition condition, got " <> show unexpected)

propBreakDeductionConservation :: Positive Integer -> NonNegative Integer -> Positive Integer -> Bool
propBreakDeductionConservation (Positive durationSeed) (NonNegative breakStartSeed) (Positive breakDurationSeed) =
    case (shiftSegments, breakInterval) of
        (Right segments, Right mealBreak) ->
            case calculateTimesheetPay input of
                Right calculation ->
                    paidSeconds calculation == expectedPaidSeconds
                        && baseHourlyQuantity calculation * 3600 == expectedPaidSeconds
                Left _ -> False
        _ -> False
  where
    shiftDurationSeconds = 2 + durationSeed `mod` (12 * 60 * 60 - 1)
    breakStartSeconds = 1 + breakStartSeed `mod` (shiftDurationSeconds - 1)
    breakDurationSeconds = 1 + breakDurationSeed `mod` (shiftDurationSeconds - breakStartSeconds)
    expectedPaidSeconds = toRational (shiftDurationSeconds - breakDurationSeconds)
    start = resolvedInstantFromUTC (UTCTime (fromGregorian 2026 1 4) (secondsToDiffTime (22 * 60 * 60)))
    breakStart = resolvedInstantFromUTC (addUTCTime (fromInteger breakStartSeconds) (resolvedInstantUTC start))
    breakEnd = resolvedInstantFromUTC (addUTCTime (fromInteger breakDurationSeconds) (resolvedInstantUTC breakStart))
    shiftEnd = resolvedInstantFromUTC (addUTCTime (fromInteger shiftDurationSeconds) (resolvedInstantUTC start))
    shiftSegments = resolvedIntervalFromInstants start shiftEnd >>= awardSegments
    breakInterval = resolvedIntervalFromInstants breakStart breakEnd
    input =
        testCalculationInput
            { calculationShiftSegments = either (const []) id shiftSegments
            , calculationUnpaidMealBreak = either (const Nothing) Just breakInterval
            }

propHighestBasePenaltyUniqueness :: NonNegative Integer -> Bool
propHighestBasePenaltyUniqueness (NonNegative seed) =
    case calculateTimesheetPay input of
        Right calculation ->
            baseHourlyComponents calculation == [hourlyComponent 1 expectedRate expectedCondition]
                && fixedEarningsComponents calculation == []
        Left _ -> False
  where
    (day, holidayDates, expectedRate, expectedCondition) =
        [ (fromGregorian 2026 1 10, Set.empty, 125, SaturdayCondition)
        , (fromGregorian 2026 1 11, Set.empty, 150, SundayCondition)
        , (fromGregorian 2026 1 10, Set.singleton (fromGregorian 2026 1 10), 225, PublicHolidayCondition)
        ] !! fromInteger (seed `mod` 3)
    input =
        (calculationInputFor day (TimeOfDay 19 0 0) day (TimeOfDay 20 0 0) Nothing)
            { calculationStatewidePublicHolidayDates = holidayDates
            }

propSixHourSplitInvariance :: Positive Integer -> NonNegative Integer -> Bool
propSixHourSplitInvariance (Positive durationSeed) (NonNegative splitSeed) =
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
                            && paidSeconds directCalculation == paidSeconds splitCalculation
                            && missedQuantity directCalculation == missedQuantity splitCalculation
                            && fixedQuantity directCalculation == expectedEveningUnits
                            && fixedQuantity splitCalculation == expectedEveningUnits
                    _ -> False
        _ -> False
  where
    durationSeconds = 6 * 60 * 60 + 2 + durationSeed `mod` (3 * 60 * 60 - 2)
    splitSeconds = 1 + splitSeed `mod` (durationSeconds - 1)
    start = resolvedInstantFromUTC (UTCTime (fromGregorian 2026 1 5) (secondsToDiffTime (4 * 60 * 60)))
    split = resolvedInstantFromUTC (addUTCTime (fromInteger splitSeconds) (resolvedInstantUTC start))
    end = resolvedInstantFromUTC (addUTCTime (fromInteger durationSeconds) (resolvedInstantUTC start))
    directSegments = resolvedIntervalFromInstants start end >>= awardSegments
    splitSegments = do
        left <- resolvedIntervalFromInstants start split >>= awardSegments
        right <- resolvedIntervalFromInstants split end >>= awardSegments
        pure (left <> right)
    expectedEveningUnits =
        fromInteger
            ( ceiling (toRational (durationSeconds - 4 * 60 * 60) / 3600)
                :: Integer
            )

fixedQuantity :: WageCalculation -> Rational
fixedQuantity = sum . map (.quantity) . fixedEarningsComponents
