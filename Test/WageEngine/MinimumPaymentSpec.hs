module Test.WageEngine.MinimumPaymentSpec where

import Application.PublicHolidays.Sync (importDataVicPublicHolidayRecordsForYears)
import Application.VenueTime
import Application.WageEngine
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import Data.Time.Calendar (Day, fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime, secondsToDiffTime)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.QuickCheck (NonNegative (..), Positive (..), property)
import Test.Support
import Test.Support.DataVicFixture (loadDataVicHolidayFixture)
import Test.WageEngine.Fixture

databaseTests :: Spec
databaseTests = aroundAll withDatabaseTestContext do
    describe "WageEngine minimum-payment DataVic lookup" do
        it "HIGA-SOURCE-DATAVIC-STATEWIDE drives the public-holiday minimum from the dated fixture cache" $ withContext do
            withCleanDb do
                records <- loadDataVicHolidayFixture
                _ <- importDataVicPublicHolidayRecordsForYears [2026] records
                holidays <- query @PublicHoliday
                    |> filterWhere (#jurisdiction, "VIC" :: Text)
                    |> filterWhere (#isRegional, False)
                    |> fetch
                let holidayDates = Set.fromList (map (.holidayDate) holidays)
                    holiday = fromGregorian 2026 11 3
                    additionalStatewideHoliday = fromGregorian 2026 12 28
                    worked = awardSegmentBetween holiday (TimeOfDay 9 0 0) holiday (TimeOfDay 10 0 0)
                    calculation = permanentCalculation holidayDates [worked]

                holidayDates `shouldSatisfy` Set.member holiday
                holidayDates `shouldSatisfy` Set.member additionalStatewideHoliday
                map (.paidTimeKind) (minimumPaidSegments calculation) `shouldBe` [PublicHolidayMinimumTopUp]
                paidSeconds calculation `shouldBe` fourHoursInSeconds
                hourlyDetails calculation
                    `shouldBe`
                        [ (PublicHolidayCondition, 1, 225)
                        , (PublicHolidayCondition, 3, 225)
                        ]

pureTests :: Spec
pureTests =
    describe "WageEngine minimum payments" do
        it "HIGA-11.3-CASUAL-MINIMUM tops an Award-calculated weekday entry up to two payable hours with auditable non-worked time" do
            let day = fromGregorian 2026 1 5
                worked = awardSegmentBetween day (TimeOfDay 9 0 0) day (TimeOfDay 10 0 0)
                topUp = awardSegmentBetween day (TimeOfDay 10 0 0) day (TimeOfDay 11 0 0)
                calculation =
                    calculateOrFail
                        ( testCalculationInput
                            { calculationArrangement = AwardHourlyEmployment CasualEmployment
                            , calculationShiftSegments = [worked]
                            }
                        )

            calculation.paidTimeSegments
                `shouldBe`
                    [ expectedPaidSegment Worked OrdinaryCondition worked
                    , expectedPaidSegment CasualMinimumEngagementTopUp OrdinaryCondition topUp
                    ]
            calculation.earningsComponents
                `shouldBe`
                    [ casualOrdinaryComponent 1
                    , casualOrdinaryComponent 1
                    ]

        it "HIGA-29.4-PH-MIN-PERMANENT pays a part-time public-holiday entry up to four hours at the public-holiday rate" do
            let day = fromGregorian 2026 1 5
                worked = awardSegmentBetween day (TimeOfDay 9 0 0) day (TimeOfDay 10 0 0)
                topUp = awardSegmentBetween day (TimeOfDay 10 0 0) day (TimeOfDay 13 0 0)
                calculation =
                    calculateOrFail
                        ( testCalculationInput
                            { calculationStatewidePublicHolidayDates = Set.singleton day
                            , calculationShiftSegments = [worked]
                            }
                        )

            calculation.paidTimeSegments
                `shouldBe`
                    [ expectedPaidSegment Worked PublicHolidayCondition worked
                    , expectedPaidSegment PublicHolidayMinimumTopUp PublicHolidayCondition topUp
                    ]
            calculation.earningsComponents
                `shouldBe`
                    [ permanentPublicHolidayComponent 1
                    , permanentPublicHolidayComponent 3
                    ]

        it "HIGA-29.4-PH-MIN-CASUAL and HIGA-POLICY-MINIMUM-PRECEDENCE retain public-holiday provenance instead of stacking a casual top-up" do
            let day = fromGregorian 2026 1 5
                worked = awardSegmentBetween day (TimeOfDay 9 0 0) day (TimeOfDay 10 0 0)
                topUp = awardSegmentBetween day (TimeOfDay 10 0 0) day (TimeOfDay 11 0 0)
                calculation = casualCalculation (Set.singleton day) [worked]

            minimumPaidSegments calculation
                `shouldBe` [expectedPaidSegment PublicHolidayMinimumTopUp PublicHolidayCondition topUp]
            minimumPaidSegments calculation
                `shouldSatisfy` all ((/= CasualMinimumEngagementTopUp) . (.paidTimeKind))
            hourlyDetails calculation
                `shouldBe`
                    [ (PublicHolidayCondition, 1, 250)
                    , (PublicHolidayCondition, 1, 250)
                    ]
            paidSeconds calculation `shouldBe` twoHoursInSeconds

        it "HIGA-29.4-PH-CONTINUOUS counts ordinary adjacent time only within the same cross-midnight entry and rates the shortfall as public-holiday time" do
            let sunday = fromGregorian 2026 1 11
                holiday = fromGregorian 2026 1 12
                worked = awardSegmentsBetween sunday (TimeOfDay 23 0 0) holiday (TimeOfDay 2 0 0)
                topUp = awardSegmentBetween holiday (TimeOfDay 2 0 0) holiday (TimeOfDay 3 0 0)
                calculation = permanentCalculation (Set.singleton holiday) worked

            minimumPaidSegments calculation
                `shouldBe` [expectedPaidSegment PublicHolidayMinimumTopUp PublicHolidayCondition topUp]
            hourlyDetails calculation
                `shouldBe`
                    [ (SundayCondition, 1, 150)
                    , (PublicHolidayCondition, 2, 225)
                    , (PublicHolidayCondition, 1, 225)
                    ]
            paidSeconds calculation `shouldBe` fourHoursInSeconds

        it "HIGA-29.4-PH-CONTINUOUS also counts ordinary adjacent time after the holiday within one entry while retaining the public-holiday top-up rate" do
            let holiday = fromGregorian 2026 1 12
                tuesday = fromGregorian 2026 1 13
                worked = awardSegmentsBetween holiday (TimeOfDay 23 0 0) tuesday (TimeOfDay 2 0 0)
                topUp = awardSegmentBetween tuesday (TimeOfDay 2 0 0) tuesday (TimeOfDay 3 0 0)
                calculation = permanentCalculation (Set.singleton holiday) worked

            minimumPaidSegments calculation
                `shouldBe` [expectedPaidSegment PublicHolidayMinimumTopUp PublicHolidayCondition topUp]
            hourlyDetails calculation
                `shouldBe`
                    [ (PublicHolidayCondition, 1, 225)
                    , (OrdinaryCondition, 2, 100)
                    , (PublicHolidayCondition, 1, 225)
                    ]
            paidSeconds calculation `shouldBe` fourHoursInSeconds

        it "HIGA-POLICY-ENTRY-INDEPENDENT leaves adjacent and overlapping casual entries as separately payable engagements" do
            let day = fromGregorian 2026 1 5
                first = awardSegmentBetween day (TimeOfDay 9 0 0) day (TimeOfDay 10 0 0)
                adjacent = awardSegmentBetween day (TimeOfDay 10 0 0) day (TimeOfDay 11 0 0)
                overlapping = awardSegmentBetween day (TimeOfDay 9 30 0) day (TimeOfDay 10 30 0)
                calculate entryId interval =
                    calculateOrFail
                        ( (minimumInput CasualEmployment Set.empty [interval])
                            { calculationEntryId = CalculationEntryId entryId
                            }
                        )
                calculations =
                    [ calculate "entry-1" first
                    , calculate "entry-2" adjacent
                    , calculate "entry-3" overlapping
                    ]

            map paidSeconds calculations `shouldBe` replicate 3 twoHoursInSeconds
            map (map (.paidTimeKind) . minimumPaidSegments) calculations
                `shouldBe` replicate 3 [CasualMinimumEngagementTopUp]

        it "HIGA-11.3-CASUAL-MINIMUM continues from the actual end across midnight and applies the Saturday condition only to the hypothetical Saturday portion" do
            let friday = fromGregorian 2026 1 9
                saturday = fromGregorian 2026 1 10
                worked = awardSegmentsBetween friday (TimeOfDay 23 30 0) saturday (TimeOfDay 0 30 0)
                topUp = awardSegmentBetween saturday (TimeOfDay 0 30 0) saturday (TimeOfDay 1 30 0)
                calculation = casualCalculation Set.empty worked

            minimumPaidSegments calculation
                `shouldBe` [expectedPaidSegment CasualMinimumEngagementTopUp SaturdayCondition topUp]
            hourlyDetails calculation
                `shouldBe`
                    [ (OrdinaryCondition, 1 / 2, 125)
                    , (SaturdayCondition, 1 / 2, 150)
                    , (SaturdayCondition, 1, 150)
                    ]
            fixedComponents calculation `shouldBe` [eveningAdditionComponent 1]

        it "HIGA-11.3-CASUAL-MINIMUM uses authoritative continuation across a public-holiday midnight without turning non-worked time into a commenced-hour addition" do
            let monday = fromGregorian 2026 1 5
                holiday = fromGregorian 2026 1 6
                worked = awardSegmentBetween monday (TimeOfDay 22 30 0) monday (TimeOfDay 23 30 0)
                (topUpBeforeHoliday, topUpOnHoliday) =
                    case awardSegmentsBetween monday (TimeOfDay 23 30 0) holiday (TimeOfDay 0 30 0) of
                        [beforeHoliday, onHoliday] -> (beforeHoliday, onHoliday)
                        unexpected -> error ("Expected two hypothetical continuation segments, got " <> show unexpected)
                calculation = casualCalculation (Set.singleton holiday) [worked]

            minimumPaidSegments calculation
                `shouldBe`
                    [ expectedPaidSegment CasualMinimumEngagementTopUp OrdinaryCondition topUpBeforeHoliday
                    , expectedPaidSegment CasualMinimumEngagementTopUp PublicHolidayCondition topUpOnHoliday
                    ]
            hourlyDetails calculation
                `shouldBe`
                    [ (OrdinaryCondition, 1, 125)
                    , (OrdinaryCondition, 1 / 2, 125)
                    , (PublicHolidayCondition, 1 / 2, 250)
                    ]
            fixedComponents calculation `shouldBe` [eveningAdditionComponent 1]

        it "HIGA-11.3-CASUAL-MINIMUM measures payable rather than gross time when an actual unpaid meal break is recorded" do
            let day = fromGregorian 2026 1 5
                grossShift = awardSegmentBetween day (TimeOfDay 9 0 0) day (TimeOfDay 11 0 0)
                mealBreak = intervalBetween day (TimeOfDay 9 30 0) day (TimeOfDay 10 0 0)
                topUp = awardSegmentBetween day (TimeOfDay 11 0 0) day (TimeOfDay 11 30 0)
                calculation =
                    calculateOrFail
                        ( (minimumInput CasualEmployment Set.empty [grossShift])
                            { calculationUnpaidMealBreak = Just mealBreak
                            }
                        )

            workedSeconds calculation `shouldBe` 90 * 60
            minimumPaidSegments calculation
                `shouldBe` [expectedPaidSegment CasualMinimumEngagementTopUp OrdinaryCondition topUp]
            paidSeconds calculation `shouldBe` twoHoursInSeconds

        it "HIGA-POLICY-IMPORTED-OVERRIDE keeps short imported casual and public-holiday entries at actual paid time only" do
            let day = fromGregorian 2026 1 5
                worked = awardSegmentBetween day (TimeOfDay 9 0 0) day (TimeOfDay 10 0 0)
                imported = ImportedPayItem "imported-item" "Imported item" 70
                calculation =
                    calculateOrFail
                        ( (minimumInput CasualEmployment (Set.singleton day) [worked])
                            { calculationImportedOverrides = ImportedOverrideContext (Just imported) Nothing
                            }
                        )

            minimumPaidSegments calculation `shouldBe` []
            paidSeconds calculation `shouldBe` 60 * 60
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

        it "HIGA-POLICY-MELBOURNE-ELAPSED continues a casual minimum through the repeated autumn hour by elapsed time" do
            let day = fromGregorian 2026 4 5
                worked =
                    awardSegmentsForCivil
                        (MelbourneCivilTime day (TimeOfDay 1 30 0) Nothing)
                        (MelbourneCivilTime day (TimeOfDay 2 30 0) (Just FirstOccurrence))
                calculation = casualCalculation Set.empty worked

            paidSeconds calculation `shouldBe` twoHoursInSeconds
            map (resolvedInstantOccurrence . resolvedInstantFromUTC . (.paidTimeEnd)) (minimumPaidSegments calculation)
                `shouldBe` [Just SecondOccurrence]
            hourlyDetails calculation
                `shouldBe`
                    [ (SundayCondition, 1, 175)
                    , (SundayCondition, 1, 175)
                    ]

        it "HIGA-POLICY-MELBOURNE-ELAPSED continues a casual minimum through the skipped spring hour by elapsed time" do
            let day = fromGregorian 2026 10 4
                worked =
                    awardSegmentsForCivil
                        (MelbourneCivilTime day (TimeOfDay 1 0 0) Nothing)
                        (MelbourneCivilTime day (TimeOfDay 1 30 0) Nothing)
                calculation = casualCalculation Set.empty worked

            paidSeconds calculation `shouldBe` twoHoursInSeconds
            map (resolvedInstantLocalTime . resolvedInstantFromUTC . (.paidTimeEnd)) (minimumPaidSegments calculation)
                `shouldBe` [LocalTime day (TimeOfDay 4 0 0)]
            hourlyDetails calculation
                `shouldBe`
                    [ (SundayCondition, 1 / 2, 175)
                    , (SundayCondition, 3 / 2, 175)
                    ]

        it "property: HIGA-11.3-CASUAL-MINIMUM reconciles paid-time and hourly components exactly" $
            property propPaidTimeComponentReconciliation

        it "property: HIGA-POLICY-MINIMUM-PRECEDENCE emits one public-holiday top-up for casual holiday work" $
            property propMinimumPrecedence

        it "property: HIGA-POLICY-ENTRY-INDEPENDENT gives adjacent and overlapping entries their own minimum payment" $
            property propEntryIndependence

        it "property: HIGA-11.3-CASUAL-MINIMUM hypothetical continuation is deterministic across artificial actual-segment splits" $
            property propDeterministicHypotheticalContinuation

expectedPaidSegment :: PaidTimeKind -> SourceCondition -> AwardSegment -> PaidTimeSegment
expectedPaidSegment kind condition segment =
    PaidTimeSegment
        { paidTimeKind = kind
        , paidTimeStart = resolvedInstantUTC (awardSegmentStart segment)
        , paidTimeEnd = resolvedInstantUTC (awardSegmentEnd segment)
        , paidTimeLocalDate = awardSegmentLocalDate segment
        , paidTimeSourceCondition = condition
        }

casualOrdinaryComponent :: Rational -> EarningsComponent
casualOrdinaryComponent hours =
    EarningsComponent
        { quantity = hours
        , unitType = Hours
        , ratePerUnit = 125
        , amount = hours * 125
        , sourceCondition = OrdinaryCondition
        , calculationSource = HospitalityAward
        , sourceRateIdentity = Just (RateSourceIdentity "source-243-CasualEmployment-OrdinaryRate")
        }

permanentPublicHolidayComponent :: Rational -> EarningsComponent
permanentPublicHolidayComponent hours =
    EarningsComponent
        { quantity = hours
        , unitType = Hours
        , ratePerUnit = 225
        , amount = hours * 225
        , sourceCondition = PublicHolidayCondition
        , calculationSource = HospitalityAward
        , sourceRateIdentity = Just (RateSourceIdentity "source-243-PermanentPartTime-PublicHolidayRate")
        }

minimumInput :: EmploymentBasis -> Set.Set Day -> [AwardSegment] -> WageCalculationInput
minimumInput basis holidayDates segments =
    testCalculationInput
        { calculationArrangement = AwardHourlyEmployment basis
        , calculationStatewidePublicHolidayDates = holidayDates
        , calculationShiftSegments = segments
        }

casualCalculation :: Set.Set Day -> [AwardSegment] -> WageCalculation
casualCalculation holidayDates = calculateOrFail . minimumInput CasualEmployment holidayDates

permanentCalculation :: Set.Set Day -> [AwardSegment] -> WageCalculation
permanentCalculation holidayDates = calculateOrFail . minimumInput PermanentPartTime holidayDates

awardSegmentsBetween :: Day -> TimeOfDay -> Day -> TimeOfDay -> [AwardSegment]
awardSegmentsBetween startDay startTime endDay endTime =
    awardSegmentsForCivil
        (MelbourneCivilTime startDay startTime Nothing)
        (MelbourneCivilTime endDay endTime Nothing)

awardSegmentsForCivil :: MelbourneCivilTime -> MelbourneCivilTime -> [AwardSegment]
awardSegmentsForCivil start end =
    case resolveInterval start end >>= awardSegments of
        Left failure   -> error (show failure)
        Right segments -> segments

intervalBetween :: Day -> TimeOfDay -> Day -> TimeOfDay -> ResolvedInterval
intervalBetween startDay startTime endDay endTime =
    case
        resolveInterval
            (MelbourneCivilTime startDay startTime Nothing)
            (MelbourneCivilTime endDay endTime Nothing)
        of
            Left failure   -> error (show failure)
            Right interval -> interval

minimumPaidSegments :: WageCalculation -> [PaidTimeSegment]
minimumPaidSegments = filter ((/= Worked) . (.paidTimeKind)) . (.paidTimeSegments)

workedSegments :: WageCalculation -> [PaidTimeSegment]
workedSegments = filter ((== Worked) . (.paidTimeKind)) . (.paidTimeSegments)

paidSeconds :: WageCalculation -> Rational
paidSeconds = sum . map paidTimeDurationSeconds . (.paidTimeSegments)

workedSeconds :: WageCalculation -> Rational
workedSeconds = sum . map paidTimeDurationSeconds . workedSegments

hourlyDetails :: WageCalculation -> [(SourceCondition, Rational, Scientific)]
hourlyDetails =
    map (\component -> (component.sourceCondition, component.quantity, component.ratePerUnit))
        . filter ((== Hours) . (.unitType))
        . (.earningsComponents)

fixedComponents :: WageCalculation -> [EarningsComponent]
fixedComponents = filter ((== CommencedHours) . (.unitType)) . (.earningsComponents)

eveningAdditionComponent :: Rational -> EarningsComponent
eveningAdditionComponent units =
    EarningsComponent
        { quantity = units
        , unitType = CommencedHours
        , ratePerUnit = 10
        , amount = units * 10
        , sourceCondition = EveningAdditionCondition
        , calculationSource = HospitalityAward
        , sourceRateIdentity = Just (RateSourceIdentity "source-addition-EveningAddition")
        }

twoHoursInSeconds :: Rational
twoHoursInSeconds = 2 * 60 * 60

fourHoursInSeconds :: Rational
fourHoursInSeconds = 4 * 60 * 60

propPaidTimeComponentReconciliation :: Positive Integer -> Bool
propPaidTimeComponentReconciliation (Positive durationSeed) =
    case awardSegmentsFromInstants start durationSeconds of
        Left _ -> False
        Right intervals ->
            let calculation = casualCalculation Set.empty intervals
             in paidSeconds calculation == twoHoursInSeconds
                    && sum [quantity | (_, quantity, _) <- hourlyDetails calculation] == 2
  where
    durationSeconds = 1 + durationSeed `mod` (2 * 60 * 60 - 1)
    start = resolvedInstantFromUTC (UTCTime (fromGregorian 2026 1 4) (secondsToDiffTime (22 * 60 * 60)))

propMinimumPrecedence :: Positive Integer -> Bool
propMinimumPrecedence (Positive durationSeed) =
    case awardSegmentsFromInstants start durationSeconds of
        Left _ -> False
        Right intervals ->
            let calculation = casualCalculation (Set.singleton holiday) intervals
             in map (.paidTimeKind) (minimumPaidSegments calculation) == [PublicHolidayMinimumTopUp]
                    && paidSeconds calculation == twoHoursInSeconds
  where
    holiday = fromGregorian 2026 1 5
    durationSeconds = 1 + durationSeed `mod` (2 * 60 * 60 - 1)
    start = resolvedInstantFromUTC (UTCTime (fromGregorian 2026 1 4) (secondsToDiffTime (22 * 60 * 60)))

propEntryIndependence :: Positive Integer -> NonNegative Integer -> Bool
propEntryIndependence (Positive durationSeed) (NonNegative overlapSeed) =
    case (awardSegmentsFromInstants firstStart durationSeconds, awardSegmentsFromInstants secondStart durationSeconds) of
        (Right firstIntervals, Right secondIntervals) ->
            let firstCalculation =
                    calculateOrFail
                        ( (minimumInput CasualEmployment Set.empty firstIntervals)
                            { calculationEntryId = CalculationEntryId "adjacent-or-overlapping-1"
                            }
                        )
                secondCalculation =
                    calculateOrFail
                        ( (minimumInput CasualEmployment Set.empty secondIntervals)
                            { calculationEntryId = CalculationEntryId "adjacent-or-overlapping-2"
                            }
                        )
             in all ((== twoHoursInSeconds) . paidSeconds) [firstCalculation, secondCalculation]
                    && all ((== 1) . length . minimumPaidSegments) [firstCalculation, secondCalculation]
        _ -> False
  where
    durationSeconds = 1 + durationSeed `mod` (60 * 60 - 1)
    firstStart = resolvedInstantFromUTC (UTCTime (fromGregorian 2026 1 4) (secondsToDiffTime (22 * 60 * 60)))
    secondOffset
        | overlapSeed `mod` 2 == 0 = durationSeconds
        | otherwise = durationSeconds `div` 2
    secondStart = resolvedInstantFromUTC (addUTCTime (fromInteger secondOffset) (resolvedInstantUTC firstStart))

propDeterministicHypotheticalContinuation :: Positive Integer -> NonNegative Integer -> Bool
propDeterministicHypotheticalContinuation (Positive durationSeed) (NonNegative splitSeed) =
    case directIntervals of
        Left _ -> False
        Right direct ->
            case
                ( awardSegmentsFromInstants start splitSeconds
                , awardSegmentsFromInstants split splitTailSeconds
                , calculateTimesheetPay (minimumInput CasualEmployment Set.empty direct)
                )
                of
                    (Right before, Right after, Right directCalculation) ->
                        case calculateTimesheetPay (minimumInput CasualEmployment Set.empty (before <> after)) of
                            Left _ -> False
                            Right splitCalculation ->
                                minimumPaidSegments directCalculation == minimumPaidSegments splitCalculation
                                    && deriveFinalEarnings directCalculation.earningsComponents
                                        == deriveFinalEarnings splitCalculation.earningsComponents
                    _ -> False
  where
    durationSeconds = 2 + durationSeed `mod` (2 * 60 * 60 - 2)
    splitSeconds = 1 + splitSeed `mod` (durationSeconds - 1)
    splitTailSeconds = durationSeconds - splitSeconds
    start = resolvedInstantFromUTC (UTCTime (fromGregorian 2026 1 5) (secondsToDiffTime (8 * 60 * 60)))
    split = resolvedInstantFromUTC (addUTCTime (fromInteger splitSeconds) (resolvedInstantUTC start))
    directIntervals = awardSegmentsFromInstants start durationSeconds

awardSegmentsFromInstants :: ResolvedInstant -> Integer -> Either VenueTimeError [AwardSegment]
awardSegmentsFromInstants start durationSeconds =
    resolvedIntervalFromInstants
        start
        (resolvedInstantFromUTC (addUTCTime (fromInteger durationSeconds) (resolvedInstantUTC start)))
        >>= awardSegments
