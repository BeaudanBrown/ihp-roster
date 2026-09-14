module Test.VenueTimeSpec where

import Application.VenueTime
import Application.VenueTime.Model
import qualified Data.Map.Strict as Map
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime, diffUTCTime,
                        secondsToDiffTime)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay (..))
import Generated.Types
import IHP.HaskellSupport (set)
import IHP.ModelSupport (newRecord)
import IHP.Prelude
import Test.Hspec
import Test.QuickCheck (NonNegative (..), Positive (..), property)


tests :: Spec
tests =
    describe "Melbourne civil-time authority" do
        it "normal: resolves a unique Melbourne civil time automatically" do
            let civilTime =
                    MelbourneCivilTime
                        { civilDate = fromGregorian 2026 1 5
                        , civilTimeOfDay = TimeOfDay 9 15 37
                        , repeatedTimeOccurrence = Nothing
                        }

            resolved <- expectRight (resolveCivilTime civilTime)

            melbourneTimeZoneName `shouldBe` "Australia/Melbourne"
            resolvedInstantUTC resolved
                `shouldBe` UTCTime (fromGregorian 2026 1 4) (secondsToDiffTime (22 * 60 * 60 + 15 * 60 + 37))
            resolvedInstantLocalTime resolved
                `shouldBe` LocalTime civilTime.civilDate civilTime.civilTimeOfDay
            resolvedInstantOccurrence resolved `shouldBe` Nothing

        it "spring-forward: rejects nonexistent input and conserves the shortened elapsed interval" do
            let localTime = LocalTime (fromGregorian 2026 10 4) (TimeOfDay 2 30 0)

            resolveCivilTime (civilTime localTime Nothing)
                `shouldBe` Left (NonexistentCivilTime localTime)
            interval <- expectRight
                ( resolveInterval
                    (civilTime (LocalTime (fromGregorian 2026 10 4) (TimeOfDay 1 30 0)) Nothing)
                    (civilTime (LocalTime (fromGregorian 2026 10 4) (TimeOfDay 3 30 0)) Nothing)
                )
            segments <- expectRight (awardSegments interval)
            resolvedIntervalElapsedSeconds interval `shouldBe` 60 * 60
            map awardSegmentLocalWindow segments `shouldBe` [EarlyMorningWindow]
            sum (map awardSegmentElapsedSeconds segments) `shouldBe` 60 * 60

        it "autumn-first: requires and resolves the first repeated-time occurrence" do
            let localTime = LocalTime (fromGregorian 2026 4 5) (TimeOfDay 2 30 0)

            resolveCivilTime (civilTime localTime Nothing)
                `shouldBe` Left (RepeatedCivilTimeRequiresOccurrence localTime)
            first <- expectRight (resolveCivilTime (civilTime localTime (Just FirstOccurrence)))
            resolvedInstantUTC first
                `shouldBe` UTCTime (fromGregorian 2026 4 4) (secondsToDiffTime (15 * 60 * 60 + 30 * 60))
            resolvedInstantOccurrence first `shouldBe` Just FirstOccurrence
            interval <- expectRight
                ( resolveInterval
                    (civilTime localTime (Just FirstOccurrence))
                    (civilTime (LocalTime (fromGregorian 2026 4 5) (TimeOfDay 3 30 0)) Nothing)
                )
            segments <- expectRight (awardSegments interval)
            resolvedIntervalElapsedSeconds interval `shouldBe` 2 * 60 * 60
            sum (map awardSegmentElapsedSeconds segments) `shouldBe` 2 * 60 * 60

        it "autumn-second: resolves the second repeated-time occurrence one elapsed hour later" do
            let localTime = LocalTime (fromGregorian 2026 4 5) (TimeOfDay 2 30 0)

            second <- expectRight (resolveCivilTime (civilTime localTime (Just SecondOccurrence)))

            resolvedInstantUTC second
                `shouldBe` UTCTime (fromGregorian 2026 4 4) (secondsToDiffTime (16 * 60 * 60 + 30 * 60))
            resolvedInstantLocalTime second `shouldBe` localTime
            resolvedInstantOccurrence second `shouldBe` Just SecondOccurrence
            interval <- expectRight
                ( resolveInterval
                    (civilTime localTime (Just SecondOccurrence))
                    (civilTime (LocalTime (fromGregorian 2026 4 5) (TimeOfDay 3 30 0)) Nothing)
                )
            segments <- expectRight (awardSegments interval)
            resolvedIntervalElapsedSeconds interval `shouldBe` 60 * 60
            sum (map awardSegmentElapsedSeconds segments) `shouldBe` 60 * 60

        it "rejects a repeated-time occurrence attached to a unique civil time" do
            let localTime = LocalTime (fromGregorian 2026 4 5) (TimeOfDay 4 0 0)

            resolveCivilTime (civilTime localTime (Just FirstOccurrence))
                `shouldBe` Left (RepeatedTimeOccurrenceNotApplicable localTime FirstOccurrence)

        it "applies Melbourne's IANA recurring rule beyond the TZif transition table" do
            winter <- expectRight
                (resolveCivilTime (civilTime (LocalTime (fromGregorian 2040 7 1) (TimeOfDay 9 0 0)) Nothing))
            summer <- expectRight
                (resolveCivilTime (civilTime (LocalTime (fromGregorian 2040 1 1) (TimeOfDay 9 0 0)) Nothing))
            let repeated = LocalTime (fromGregorian 2040 4 1) (TimeOfDay 2 30 0)
                skipped = LocalTime (fromGregorian 2040 10 7) (TimeOfDay 2 30 0)

            resolvedInstantUTC winter
                `shouldBe` UTCTime (fromGregorian 2040 6 30) (secondsToDiffTime (23 * 60 * 60))
            resolvedInstantUTC summer
                `shouldBe` UTCTime (fromGregorian 2039 12 31) (secondsToDiffTime (22 * 60 * 60))
            resolveCivilTime (civilTime repeated Nothing)
                `shouldBe` Left (RepeatedCivilTimeRequiresOccurrence repeated)
            first <- expectRight (resolveCivilTime (civilTime repeated (Just FirstOccurrence)))
            second <- expectRight (resolveCivilTime (civilTime repeated (Just SecondOccurrence)))
            diffUTCTime (resolvedInstantUTC second) (resolvedInstantUTC first) `shouldBe` 60 * 60
            resolvedInstantOccurrence first `shouldBe` Just FirstOccurrence
            resolvedInstantOccurrence second `shouldBe` Just SecondOccurrence
            resolveCivilTime (civilTime skipped Nothing)
                `shouldBe` Left (NonexistentCivilTime skipped)
            resolvedInstantLocalTime winter
                `shouldBe` LocalTime (fromGregorian 2040 7 1) (TimeOfDay 9 0 0)
            resolvedInstantLocalTime summer
                `shouldBe` LocalTime (fromGregorian 2040 1 1) (TimeOfDay 9 0 0)

        it "rejects malformed civil clocks and non-positive intervals with typed errors" do
            let invalidClock = TimeOfDay 24 0 0
                validLocal = LocalTime (fromGregorian 2026 1 5) (TimeOfDay 9 0 0)
                validCivil = civilTime validLocal Nothing
            instant <- expectRight (resolveCivilTime validCivil)

            resolveCivilTime (MelbourneCivilTime (fromGregorian 2026 1 5) invalidClock Nothing)
                `shouldBe` Left (InvalidCivilTimeOfDay invalidClock)
            resolveInterval validCivil validCivil
                `shouldBe` Left (NonPositiveResolvedInterval (resolvedInstantUTC instant) (resolvedInstantUTC instant))

        it "preserves fractional elapsed seconds without quarter-hour normalization" do
            let day = fromGregorian 2026 1 5
            interval <- expectRight
                ( resolveInterval
                    (MelbourneCivilTime day (TimeOfDay 9 0 0.125) Nothing)
                    (MelbourneCivilTime day (TimeOfDay 9 0 1.875) Nothing)
                )
            segments <- expectRight (awardSegments interval)

            resolvedIntervalElapsedSeconds interval `shouldBe` 1.75
            map awardSegmentElapsedSeconds segments `shouldBe` [1.75]

        it "ambiguous-endpoint: requires the end occurrence and preserves its elapsed meaning" do
            let start = civilTime (LocalTime (fromGregorian 2026 4 5) (TimeOfDay 1 30 0)) Nothing
                ambiguousEnd = LocalTime (fromGregorian 2026 4 5) (TimeOfDay 2 30 0)

            resolveInterval start (civilTime ambiguousEnd Nothing)
                `shouldBe` Left (RepeatedCivilTimeRequiresOccurrence ambiguousEnd)
            firstEnd <- expectRight (resolveInterval start (civilTime ambiguousEnd (Just FirstOccurrence)))
            secondEnd <- expectRight (resolveInterval start (civilTime ambiguousEnd (Just SecondOccurrence)))

            resolvedIntervalElapsedSeconds firstEnd `shouldBe` 60 * 60
            resolvedIntervalElapsedSeconds secondEnd `shouldBe` 2 * 60 * 60
            resolvedInstantOccurrence (resolvedIntervalEnd firstEnd) `shouldBe` Just FirstOccurrence
            resolvedInstantOccurrence (resolvedIntervalEnd secondEnd) `shouldBe` Just SecondOccurrence

        it "overnight: splits exact elapsed time at local 19:00, 00:00 and 07:00 boundaries" do
            interval <- expectRight
                ( resolveInterval
                    (civilTime (LocalTime (fromGregorian 2026 7 10) (TimeOfDay 18 30 15)) Nothing)
                    (civilTime (LocalTime (fromGregorian 2026 7 11) (TimeOfDay 8 0 45)) Nothing)
                )
            segments <- expectRight (awardSegments interval)

            map awardSegmentLocalDate segments
                `shouldBe`
                    [ fromGregorian 2026 7 10
                    , fromGregorian 2026 7 10
                    , fromGregorian 2026 7 11
                    , fromGregorian 2026 7 11
                    ]
            map awardSegmentLocalDayKind segments
                `shouldBe` [LocalWeekday, LocalWeekday, LocalSaturday, LocalSaturday]
            map awardSegmentLocalWindow segments
                `shouldBe` [OrdinaryWindow, EveningWindow, EarlyMorningWindow, OrdinaryWindow]
            map (resolvedInstantLocalTime . awardSegmentStart) segments
                `shouldBe`
                    [ LocalTime (fromGregorian 2026 7 10) (TimeOfDay 18 30 15)
                    , LocalTime (fromGregorian 2026 7 10) (TimeOfDay 19 0 0)
                    , LocalTime (fromGregorian 2026 7 11) (TimeOfDay 0 0 0)
                    , LocalTime (fromGregorian 2026 7 11) (TimeOfDay 7 0 0)
                    ]
            map awardSegmentElapsedSeconds segments
                `shouldBe` [29 * 60 + 45, 5 * 60 * 60, 7 * 60 * 60, 60 * 60 + 45]
            sum (map awardSegmentElapsedSeconds segments)
                `shouldBe` resolvedIntervalElapsedSeconds interval

        it "copy preserves local clock times on the target date instead of adding UTC duration" do
            source <- expectRight
                ( resolveInterval
                    (civilTime (LocalTime (fromGregorian 2026 9 27) (TimeOfDay 1 30 0)) Nothing)
                    (civilTime (LocalTime (fromGregorian 2026 9 27) (TimeOfDay 3 30 0)) Nothing)
                )

            copied <- expectRight
                ( copyIntervalToDate
                    (fromGregorian 2026 10 4)
                    (CopyOccurrenceSelections Nothing Nothing)
                    source
                )

            resolvedInstantLocalTime (resolvedIntervalStart copied)
                `shouldBe` LocalTime (fromGregorian 2026 10 4) (TimeOfDay 1 30 0)
            resolvedInstantLocalTime (resolvedIntervalEnd copied)
                `shouldBe` LocalTime (fromGregorian 2026 10 4) (TimeOfDay 3 30 0)
            resolvedIntervalElapsedSeconds source `shouldBe` 2 * 60 * 60
            resolvedIntervalElapsedSeconds copied `shouldBe` 60 * 60

        it "copy preserves an overnight end date and requires an ambiguous target occurrence" do
            source <- expectRight
                ( resolveInterval
                    (civilTime (LocalTime (fromGregorian 2026 3 28) (TimeOfDay 22 30 0)) Nothing)
                    (civilTime (LocalTime (fromGregorian 2026 3 29) (TimeOfDay 2 30 0)) Nothing)
                )
            let targetDate = fromGregorian 2026 4 4
                ambiguousEnd = LocalTime (fromGregorian 2026 4 5) (TimeOfDay 2 30 0)

            copyIntervalToDate targetDate (CopyOccurrenceSelections Nothing Nothing) source
                `shouldBe` Left (RepeatedCivilTimeRequiresOccurrence ambiguousEnd)
            first <- expectRight
                (copyIntervalToDate targetDate (CopyOccurrenceSelections Nothing (Just FirstOccurrence)) source)
            second <- expectRight
                (copyIntervalToDate targetDate (CopyOccurrenceSelections Nothing (Just SecondOccurrence)) source)

            resolvedInstantLocalTime (resolvedIntervalEnd first) `shouldBe` ambiguousEnd
            resolvedInstantOccurrence (resolvedIntervalEnd first) `shouldBe` Just FirstOccurrence
            resolvedInstantOccurrence (resolvedIntervalEnd second) `shouldBe` Just SecondOccurrence
            resolvedIntervalElapsedSeconds first `shouldBe` 4 * 60 * 60
            resolvedIntervalElapsedSeconds second `shouldBe` 5 * 60 * 60

        it "applies copy occurrence choices only to target endpoints that repeat" do
            source <- expectRight (resolveShiftBoundaries melbourneTimeZoneName ShiftBoundaryInput
                { shiftBoundaryDate = fromGregorian 2026 3 29
                , shiftBoundaryStartTime = TimeOfDay 9 0 0
                , shiftBoundaryStartOccurrence = Nothing
                , shiftBoundaryEndTime = TimeOfDay 17 0 0
                , shiftBoundaryEndOccurrence = Nothing
                , shiftBoundaryBreak = Nothing
                })
            copied <- expectRight (copyAuthoritativeBoundariesToDate
                (fromGregorian 2026 4 5)
                noShiftCopyOccurrenceSelections
                    { copyShiftStartOccurrence = Just SecondOccurrence
                    , copyShiftEndOccurrence = Just SecondOccurrence
                    }
                source)

            authoritativeStartLocalTime copied
                `shouldBe` LocalTime (fromGregorian 2026 4 5) (TimeOfDay 9 0 0)
            authoritativeEndLocalTime copied
                `shouldBe` LocalTime (fromGregorian 2026 4 5) (TimeOfDay 17 0 0)
            authoritativeStartOccurrence copied `shouldBe` Nothing
            authoritativeEndOccurrence copied `shouldBe` Nothing

        it "integrates a repeated-time shift and contained break into exact persisted boundaries" do
            let day = fromGregorian 2026 4 5
                input = ShiftBoundaryInput
                    { shiftBoundaryDate = day
                    , shiftBoundaryStartTime = TimeOfDay 1 30 0
                    , shiftBoundaryStartOccurrence = Nothing
                    , shiftBoundaryEndTime = TimeOfDay 2 30 0
                    , shiftBoundaryEndOccurrence = Just SecondOccurrence
                    , shiftBoundaryBreak = Just BreakBoundaryInput
                        { breakBoundaryStartTime = TimeOfDay 2 0 0
                        , breakBoundaryStartOccurrence = Just FirstOccurrence
                        , breakBoundaryEndTime = TimeOfDay 2 15 0
                        , breakBoundaryEndOccurrence = Just FirstOccurrence
                        }
                    }

            boundaries <- expectRight (resolveShiftBoundaries melbourneTimeZoneName input)

            authoritativeStartsAt boundaries
                `shouldBe` UTCTime (fromGregorian 2026 4 4) (secondsToDiffTime (14 * 60 * 60 + 30 * 60))
            authoritativeEndsAt boundaries
                `shouldBe` UTCTime (fromGregorian 2026 4 4) (secondsToDiffTime (16 * 60 * 60 + 30 * 60))
            authoritativeBreakStartsAt boundaries
                `shouldBe` Just (UTCTime (fromGregorian 2026 4 4) (secondsToDiffTime (15 * 60 * 60)))
            authoritativeBreakEndsAt boundaries
                `shouldBe` Just (UTCTime (fromGregorian 2026 4 4) (secondsToDiffTime (15 * 60 * 60 + 15 * 60)))
            authoritativeElapsedSeconds boundaries `shouldBe` 2 * 60 * 60
            authoritativeBreakElapsedSeconds boundaries `shouldBe` 15 * 60
            authoritativePaidElapsedSeconds boundaries `shouldBe` 105 * 60

        it "resolves equal repeated shift clocks from the first to second occurrence" do
            let day = fromGregorian 2026 4 5
            boundaries <- expectRight (resolveShiftBoundaries melbourneTimeZoneName ShiftBoundaryInput
                { shiftBoundaryDate = day
                , shiftBoundaryStartTime = TimeOfDay 2 30 0
                , shiftBoundaryStartOccurrence = Just FirstOccurrence
                , shiftBoundaryEndTime = TimeOfDay 2 30 0
                , shiftBoundaryEndOccurrence = Just SecondOccurrence
                , shiftBoundaryBreak = Nothing
                })

            authoritativeStartLocalTime boundaries `shouldBe` LocalTime day (TimeOfDay 2 30 0)
            authoritativeEndLocalTime boundaries `shouldBe` LocalTime day (TimeOfDay 2 30 0)
            authoritativeStartOccurrence boundaries `shouldBe` Just FirstOccurrence
            authoritativeEndOccurrence boundaries `shouldBe` Just SecondOccurrence
            authoritativeElapsedSeconds boundaries `shouldBe` 60 * 60

        it "resolves equal repeated break clocks from the first to second occurrence" do
            let day = fromGregorian 2026 4 5
            boundaries <- expectRight (resolveShiftBoundaries melbourneTimeZoneName ShiftBoundaryInput
                { shiftBoundaryDate = day
                , shiftBoundaryStartTime = TimeOfDay 1 30 0
                , shiftBoundaryStartOccurrence = Nothing
                , shiftBoundaryEndTime = TimeOfDay 3 30 0
                , shiftBoundaryEndOccurrence = Nothing
                , shiftBoundaryBreak = Just BreakBoundaryInput
                    { breakBoundaryStartTime = TimeOfDay 2 30 0
                    , breakBoundaryStartOccurrence = Just FirstOccurrence
                    , breakBoundaryEndTime = TimeOfDay 2 30 0
                    , breakBoundaryEndOccurrence = Just SecondOccurrence
                    }
                })

            authoritativeBreakStartLocalTime boundaries `shouldBe` Just (LocalTime day (TimeOfDay 2 30 0))
            authoritativeBreakEndLocalTime boundaries `shouldBe` Just (LocalTime day (TimeOfDay 2 30 0))
            authoritativeBreakStartOccurrence boundaries `shouldBe` Just FirstOccurrence
            authoritativeBreakEndOccurrence boundaries `shouldBe` Just SecondOccurrence
            authoritativeBreakElapsedSeconds boundaries `shouldBe` 60 * 60

        it "decodes persisted Timesheet timing into an opaque validated value" do
            let entry =
                    newRecord @TimesheetEntry
                        |> set #startsAt (UTCTime (fromGregorian 2026 1 5) (secondsToDiffTime 0))
                        |> set #endsAt (UTCTime (fromGregorian 2026 1 5) (secondsToDiffTime (60 * 60)))
                        |> set #timezone melbourneTimeZoneName

            timing <- expectRight (decodeTimesheetTiming entry)

            timesheetTimingStartTime timing `shouldBe` TimeOfDay 11 0 0
            timesheetTimingEndTime timing `shouldBe` TimeOfDay 12 0 0
            timesheetTimingElapsedSeconds timing `shouldBe` 60 * 60

        it "reports corrupt persisted Timesheet timing without throwing" do
            let start = UTCTime (fromGregorian 2026 1 5) (secondsToDiffTime 0)
                invalidZoneEntry =
                    newRecord @TimesheetEntry
                        |> set #startsAt start
                        |> set #endsAt (addUTCTime (60 * 60) start)
                        |> set #timezone "not-a-zone"
                reversedEntry =
                    invalidZoneEntry
                        |> set #timezone melbourneTimeZoneName
                        |> set #endsAt start

            decodeTimesheetTiming invalidZoneEntry
                `shouldBe` Left (TimesheetTimingInvalid (BoundaryUnsupportedTimezone "not-a-zone"))
            decodeTimesheetTiming reversedEntry
                `shouldBe` Left (TimesheetTimingInvalid (BoundaryCivilTimeError (NonPositiveResolvedInterval start start)))
            recoverStoredInstantLocalTime invalidZoneEntry.timezone (Just start) `shouldBe` Nothing

        it "decodes complete roster timing and reports missing or corrupt persisted boundaries" do
            let start = UTCTime (fromGregorian 2026 1 5) (secondsToDiffTime 0)
                completeSlot =
                    newRecord @RosterSlot
                        |> set #startsAt (Just start)
                        |> set #endsAt (Just (addUTCTime (60 * 60) start))
                        |> set #timezone melbourneTimeZoneName
                missingSlot = completeSlot |> set #startsAt Nothing
                invalidZoneSlot = completeSlot |> set #timezone "not-a-zone"

            timing <- expectRight (decodeRosterShiftTiming completeSlot)
            rosterShiftTimingElapsedSeconds timing `shouldBe` 60 * 60
            decodeRosterShiftTiming missingSlot `shouldBe` Left (RosterShiftTimingInvalid BoundaryShiftShapeInvalid)
            decodeRosterShiftTiming invalidZoneSlot
                `shouldBe` Left (RosterShiftTimingInvalid (BoundaryUnsupportedTimezone "not-a-zone"))
            rosterSlotStartTime invalidZoneSlot `shouldBe` Nothing

        it "integration rejects a nonexistent spring boundary instead of normalizing it" do
            let skipped = LocalTime (fromGregorian 2026 10 4) (TimeOfDay 2 30 0)
                input = ShiftBoundaryInput
                    { shiftBoundaryDate = skipped.localDay
                    , shiftBoundaryStartTime = skipped.localTimeOfDay
                    , shiftBoundaryStartOccurrence = Nothing
                    , shiftBoundaryEndTime = TimeOfDay 4 0 0
                    , shiftBoundaryEndOccurrence = Nothing
                    , shiftBoundaryBreak = Nothing
                    }

            resolveShiftBoundaries melbourneTimeZoneName input
                `shouldBe` Left (BoundaryCivilTimeError (NonexistentCivilTime skipped))

        it "property: Award segmentation conserves every exact elapsed second" $
            property propElapsedConservation

        it "property: segmentation is deterministic through civil and instant entry paths" $
            property propDeterministicSegmentation

        it "property: an artificial instant split does not change classified elapsed totals" $
            property propSplitInvariance

propElapsedConservation :: NonNegative Integer -> Positive Integer -> Bool
propElapsedConservation startSeed durationSeed =
    case awardSegments interval of
        Left _         -> False
        Right segments -> sum (map awardSegmentElapsedSeconds segments) == resolvedIntervalElapsedSeconds interval
  where
    (interval, _) = generatedInterval startSeed durationSeed

propDeterministicSegmentation :: NonNegative Integer -> Positive Integer -> Bool
propDeterministicSegmentation startSeed durationSeed =
    case (awardSegments interval, resolveInterval startCivil endCivil >>= awardSegments) of
        (Right direct, Right roundTripped) -> direct == roundTripped
        _                                  -> False
  where
    (interval, _) = generatedInterval startSeed durationSeed
    startCivil = civilTimeFromInstant (resolvedIntervalStart interval)
    endCivil = civilTimeFromInstant (resolvedIntervalEnd interval)

propSplitInvariance :: NonNegative Integer -> Positive Integer -> NonNegative Integer -> Bool
propSplitInvariance startSeed durationSeed (NonNegative splitSeed) =
    case (awardSegments interval, splitSegments) of
        (Right direct, Right split) -> classifiedElapsed direct == classifiedElapsed split
        _                           -> False
  where
    (interval, durationSeconds) = generatedInterval startSeed durationSeed
    start = resolvedIntervalStart interval
    splitSeconds = 1 + splitSeed `mod` (durationSeconds - 1)
    split = resolvedInstantFromUTC (addUTCTime (fromInteger splitSeconds) (resolvedInstantUTC start))
    splitSegments = do
        left <- resolvedIntervalFromInstants start split >>= awardSegments
        right <- resolvedIntervalFromInstants split (resolvedIntervalEnd interval) >>= awardSegments
        pure (left <> right)

generatedInterval :: NonNegative Integer -> Positive Integer -> (ResolvedInterval, Integer)
generatedInterval (NonNegative startSeed) (Positive durationSeed) =
    (interval, durationSeconds)
  where
    base = UTCTime (fromGregorian 2022 1 1) 0
    startSeconds = startSeed `mod` (30 * 366 * 24 * 60 * 60)
    durationSeconds = 2 + durationSeed `mod` (3 * 24 * 60 * 60)
    start = resolvedInstantFromUTC (addUTCTime (fromInteger startSeconds) base)
    end = resolvedInstantFromUTC (addUTCTime (fromInteger durationSeconds) (resolvedInstantUTC start))
    interval =
        case resolvedIntervalFromInstants start end of
            Left failure   -> error (show failure)
            Right resolved -> resolved

civilTimeFromInstant :: ResolvedInstant -> MelbourneCivilTime
civilTimeFromInstant instant =
    civilTime (resolvedInstantLocalTime instant) (resolvedInstantOccurrence instant)

classifiedElapsed :: [AwardSegment] -> Map.Map (Day, LocalDayKind, LocalTimeWindow) NominalDiffTime
classifiedElapsed =
    Map.fromListWith (+)
        . map
            ( \segment ->
                ( ( awardSegmentLocalDate segment
                  , awardSegmentLocalDayKind segment
                  , awardSegmentLocalWindow segment
                  )
                , awardSegmentElapsedSeconds segment
                )
            )

civilTime :: LocalTime -> Maybe RepeatedTimeOccurrence -> MelbourneCivilTime
civilTime LocalTime { localDay, localTimeOfDay } occurrence =
    MelbourneCivilTime
        { civilDate = localDay
        , civilTimeOfDay = localTimeOfDay
        , repeatedTimeOccurrence = occurrence
        }

expectRight :: Show error => Either error value -> IO value
expectRight = \case
    Left failure -> expectationFailure (cs (tshow failure)) >> fail "unreachable"
    Right value  -> pure value
