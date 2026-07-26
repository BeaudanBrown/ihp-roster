module Test.RosterAwardDurationSpec where

import Application.Helper.RosterAwardDuration
import Application.VenueTime (melbourneTimeZoneName)
import Application.VenueTime.Model
import Data.Time.Calendar (Day, addDays, fromGregorian)
import Data.Time.Clock (NominalDiffTime, UTCTime (..), addUTCTime)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay (..))
import Generated.Types (StaffEmploymentBasisEnum (Casual, Permanent))
import IHP.Prelude
import Test.Hspec
import Test.QuickCheck (NonNegative (..), property)

tests :: Spec
tests =
    describe "Roster Award shift duration" do
        it "HIGA-15.2-PART-TIME-SHIFT-MIN, HIGA-15.2-PART-TIME-SHIFT-MAX and HIGA-11.2-CASUAL-SHIFT-MAX accept exact limits" do
            let partTimeMinimum = boundariesForElapsedSeconds (3 * hours)
                partTimeMaximum = boundariesForElapsedSeconds (12 * hours)
                casualMaximum = boundariesForElapsedSeconds (12 * hours + 30 * minutes)

            projectedRosterWorkingSeconds partTimeMinimum `shouldBe` 3 * hours
            projectedRosterWorkingSeconds partTimeMaximum `shouldBe` 11 * hours + 30 * minutes
            projectedRosterWorkingSeconds casualMaximum `shouldBe` 12 * hours
            rosterAwardDurationViolation Permanent partTimeMinimum `shouldBe` Nothing
            rosterAwardDurationViolation Permanent partTimeMaximum `shouldBe` Nothing
            rosterAwardDurationViolation Casual casualMaximum `shouldBe` Nothing

        it "deducts the existing automatic unpaid meal break at its elapsed-time threshold" do
            let beforeBreakThreshold = boundariesForElapsedSeconds (6 * hours + 15 * minutes - 1)
                atBreakThreshold = boundariesForElapsedSeconds (6 * hours + 15 * minutes)

            projectedRosterWorkingSeconds beforeBreakThreshold `shouldBe` 6 * hours + 15 * minutes - 1
            projectedRosterWorkingSeconds atBreakThreshold `shouldBe` 5 * hours + 45 * minutes

        it "HIGA-15.2-PART-TIME-SHIFT-MIN, HIGA-15.2-PART-TIME-SHIFT-MAX and HIGA-11.2-CASUAL-SHIFT-MAX reject one second beyond limits" do
            let partTimeTooShort = boundariesForElapsedSeconds (3 * hours - 1)
                partTimeTooLong = boundariesForElapsedSeconds (12 * hours + 1)
                casualTooLong = boundariesForElapsedSeconds (12 * hours + 30 * minutes + 1)

            rosterAwardDurationViolation Permanent partTimeTooShort `shouldSatisfy` isJust
            rosterAwardDurationViolation Permanent partTimeTooLong `shouldSatisfy` isJust
            rosterAwardDurationViolation Casual casualTooLong `shouldSatisfy` isJust
            rosterAwardDurationViolation Permanent partTimeTooLong
                |> fmap rosterAwardDurationViolationMessage
                `shouldBe` Just "Part-time roster shifts must project between 3 and 11.5 working hours after the automatic unpaid meal break."

        it "uses authoritative elapsed Melbourne instants for overnight and DST shifts" do
            overnight <- resolvedBoundaries (fromGregorian 2026 7 10) (TimeOfDay 22 0 0) (TimeOfDay 2 0 0)
            autumn <- resolvedBoundaries (fromGregorian 2026 4 5) (TimeOfDay 1 30 0) (TimeOfDay 3 30 0)
            spring <- resolvedBoundaries (fromGregorian 2026 10 4) (TimeOfDay 1 30 0) (TimeOfDay 3 30 0)

            projectedRosterWorkingSeconds overnight `shouldBe` 4 * hours
            projectedRosterWorkingSeconds autumn `shouldBe` 3 * hours
            projectedRosterWorkingSeconds spring `shouldBe` hours
            rosterAwardDurationViolation Permanent overnight `shouldBe` Nothing
            rosterAwardDurationViolation Permanent autumn `shouldBe` Nothing
            rosterAwardDurationViolation Permanent spring `shouldSatisfy` isJust

        it "re-evaluates copied Part-time shifts with the target date's DST elapsed time" do
            source <- resolvedBoundaries (fromGregorian 2026 3 28) (TimeOfDay 17 45 0) (TimeOfDay 5 45 0)
            copied <- expectRight (copyAuthoritativeBoundariesToDate (fromGregorian 2026 4 4) noShiftCopyOccurrenceSelections source)

            authoritativeStartLocalTime copied `shouldBe` LocalTime (fromGregorian 2026 4 4) (TimeOfDay 17 45 0)
            authoritativeEndLocalTime copied `shouldBe` LocalTime (fromGregorian 2026 4 5) (TimeOfDay 5 45 0)
            projectedRosterWorkingSeconds source `shouldBe` 11 * hours + 30 * minutes
            projectedRosterWorkingSeconds copied `shouldBe` 12 * hours + 30 * minutes
            rosterAwardDurationViolation Permanent source `shouldBe` Nothing
            rosterAwardDurationViolation Permanent copied `shouldSatisfy` isJust

        it "property: projected working time derives from every exact elapsed-second value" $
            property propProjectedWorkingSeconds

        it "property: copies retain target local clocks and recalculate from target instants" $
            property propCopiedIntervalsUseTargetInstants

hours :: NominalDiffTime
hours = 60 * 60

minutes :: NominalDiffTime
minutes = 60

boundariesForElapsedSeconds :: NominalDiffTime -> AuthoritativeBoundaries
boundariesForElapsedSeconds elapsedSeconds =
    either (error . show) id $
        authoritativeBoundariesFromInstants melbourneTimeZoneName start (addUTCTime elapsedSeconds start) Nothing Nothing
  where
    start = UTCTime (fromGregorian 2026 1 5) 0

resolvedBoundaries :: Day -> TimeOfDay -> TimeOfDay -> IO AuthoritativeBoundaries
resolvedBoundaries day startTime endTime =
    expectRight $
        resolveShiftBoundaries melbourneTimeZoneName ShiftBoundaryInput
            { shiftBoundaryDate = day
            , shiftBoundaryStartTime = startTime
            , shiftBoundaryStartOccurrence = Nothing
            , shiftBoundaryEndTime = endTime
            , shiftBoundaryEndOccurrence = Nothing
            , shiftBoundaryBreak = Nothing
            }

propProjectedWorkingSeconds :: NonNegative Integer -> Bool
propProjectedWorkingSeconds (NonNegative rawSeconds) =
    projectedRosterWorkingSeconds (boundariesForElapsedSeconds elapsedSeconds)
        == referenceProjectedWorkingSeconds elapsedSeconds
  where
    elapsedSeconds = 1 + fromInteger (rawSeconds `mod` (36 * 60 * 60))

propCopiedIntervalsUseTargetInstants :: NonNegative Integer -> Bool
propCopiedIntervalsUseTargetInstants (NonNegative targetSeed) =
    case do
        source <- resolveShiftBoundaries melbourneTimeZoneName ShiftBoundaryInput
            { shiftBoundaryDate = fromGregorian 2026 3 28
            , shiftBoundaryStartTime = TimeOfDay 17 45 0
            , shiftBoundaryStartOccurrence = Nothing
            , shiftBoundaryEndTime = TimeOfDay 5 45 0
            , shiftBoundaryEndOccurrence = Nothing
            , shiftBoundaryBreak = Nothing
            }
        copied <- copyAuthoritativeBoundariesToDate targetDate noShiftCopyOccurrenceSelections source
        pure copied
      of
        Left _ -> False
        Right copied ->
            authoritativeStartLocalTime copied == LocalTime targetDate (TimeOfDay 17 45 0)
                && authoritativeEndLocalTime copied == LocalTime (addDays 1 targetDate) (TimeOfDay 5 45 0)
                && projectedRosterWorkingSeconds copied
                    == referenceProjectedWorkingSeconds (authoritativeElapsedSeconds copied)
  where
    targetDate = addDays (fromInteger (targetSeed `mod` 1095)) (fromGregorian 2026 1 1)

referenceProjectedWorkingSeconds :: NominalDiffTime -> NominalDiffTime
referenceProjectedWorkingSeconds elapsedSeconds
    | elapsedSeconds >= 6 * hours + 15 * minutes = elapsedSeconds - 30 * minutes
    | otherwise = elapsedSeconds

expectRight :: Show error => Either error value -> IO value
expectRight = \case
    Left failure -> expectationFailure (cs (tshow failure)) >> fail "unreachable"
    Right value  -> pure value
