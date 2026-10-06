module Test.RosterInteractionWorkflowSpec where

import Application.Helper.TimeRules (defaultShiftTimesForVenueConfig)
import Application.RosterShiftAssignment
import Application.VenueTime (RepeatedTimeOccurrence (..),
                              resolvedInstantFromUTC, resolvedInstantLocalTime)
import Application.VenueTime.Model
import Data.Either (isLeft)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ModelSupport (newRecord, unpackId)
import IHP.ModelSupport.Types (Id' (Id))
import IHP.Prelude
import Test.Hspec
import Web.RosterWeeks.DefaultDuration
import Web.RosterWeeks.DropWorkflow
import Web.RosterWeeks.Service (rosterSlotBlocksPublish)
import Web.RosterWeeks.ShiftWorkflow
import Web.View.RosterWeeks.ShiftDialog (RosterShiftDialogValues (..))

workflowVenueConfig :: VenueConfig
workflowVenueConfig = (newRecord @VenueConfig)
    { defaultRosterShiftDurationMinutes = 480
    , timePickerStartMinuteOfDay = 360
    , timePickerFinalSelectableMinuteOfDay = 345
    }

tests :: Spec
tests = do
    describe "roster interaction workflow tokens" do
        it "prefills timeline creation with the exact repeated occurrence and clips its real end" do
            let config = workflowVenueConfig
                day = fromGregorian 2026 4 4
                first = rosterTimelineCreateDialogValues config day (posixSecondsToUTCTime 1775316600)
                second = rosterTimelineCreateDialogValues config day (posixSecondsToUTCTime 1775320200)
            first.rosterShiftStartTime `shouldBe` "02:30"
            second.rosterShiftStartTime `shouldBe` "02:30"
            first.rosterShiftStartOccurrence `shouldBe` Just FirstOccurrence
            second.rosterShiftStartOccurrence `shouldBe` Just SecondOccurrence
            first.rosterShiftStartIsRepeated `shouldBe` True
            first.rosterShiftEndTime `shouldBe` "05:45"
            second.rosterShiftEndTime `shouldBe` "05:45"
            first.rosterShiftSelectedAssignment `shouldBe` Nothing

        it "retains a repeated end occurrence when elapsed duration crosses the autumn fold" do
            let config = workflowVenueConfig { defaultRosterShiftDurationMinutes = 30 }
                values = rosterTimelineCreateDialogValues config (fromGregorian 2026 4 4) (posixSecondsToUTCTime 1775316600)
            values.rosterShiftStartTime `shouldBe` "02:30"
            values.rosterShiftEndTime `shouldBe` "02:00"
            values.rosterShiftEndOccurrence `shouldBe` Just SecondOccurrence
            values.rosterShiftEndIsRepeated `shouldBe` True

        it "clips a nonexistent spring window endpoint to the final real selectable minute" do
            let policy = RosterCreationDefaults 480 0 150
                day = fromGregorian 2026 10 3
                end precision = do
                    start <- defaultRosterStart policy day
                    instant <- defaultRosterEnd policy day start precision
                    pure (resolvedInstantLocalTime (resolvedInstantFromUTC instant)).localTimeOfDay
            end 5 `shouldBe` Just (TimeOfDay 1 55 0)
            end 15 `shouldBe` Just (TimeOfDay 1 45 0)

        it "validates bounded quarter-hour venue defaults" do
            map validDefaultRosterDuration [15, 480, 1440] `shouldBe` replicate 3 True
            map validDefaultRosterDuration [-1, 0, 1, 14, 16, 1441] `shouldBe` replicate 6 False

        it "clips an eight-hour default at 15:00 to the configured 17:00 end" do
            let config = workflowVenueConfig
                    { timePickerStartMinuteOfDay = 9 * 60
                    , timePickerFinalSelectableMinuteOfDay = 17 * 60
                    }
                start = UTCTime (fromGregorian 2026 6 1) (secondsToDiffTime (5 * 3600))
                values = rosterTimelineCreateDialogValues config (fromGregorian 2026 6 1) start
            values.rosterShiftStartTime `shouldBe` "15:00"
            values.rosterShiftEndTime `shouldBe` "17:00"

        it "uses configured duration in both ordinary and timeline creation" do
            let config = workflowVenueConfig { defaultRosterShiftDurationMinutes = 90 }
                day = fromGregorian 2026 6 1
                Just start = defaultRosterStart (rosterCreationDefaults config) day
                ordinary = defaultRosterShiftDialogValuesForVenue config day
                timeline = rosterTimelineCreateDialogValues config day start
            ordinary.rosterShiftStartTime `shouldBe` "06:00"
            ordinary.rosterShiftEndTime `shouldBe` "07:30"
            timeline.rosterShiftEndTime `shouldBe` ordinary.rosterShiftEndTime
            snd (defaultShiftTimesForVenueConfig config) `shouldBe` TimeOfDay 14 0 0

        it "uses elapsed hours across both DST transitions without inventing clock times" do
            let policy = RosterCreationDefaults 480 (22 * 60) (10 * 60)
                endpoint day = do
                    start <- defaultRosterStart policy day
                    end <- defaultRosterEnd policy day start 15
                    pure (resolvedInstantLocalTime (resolvedInstantFromUTC end)).localTimeOfDay
            endpoint (fromGregorian 2026 10 3) `shouldBe` Just (TimeOfDay 7 0 0)
            endpoint (fromGregorian 2026 4 4) `shouldBe` Just (TimeOfDay 5 0 0)

        it "does not invent a default for a nonexistent start or a window with no remaining room" do
            defaultRosterStart (RosterCreationDefaults 480 150 600) (fromGregorian 2026 10 3) `shouldBe` Nothing
            let policy = RosterCreationDefaults 480 540 1020
                start = UTCTime (fromGregorian 2026 6 1) (secondsToDiffTime (7 * 3600))
            defaultRosterEnd policy (fromGregorian 2026 6 1) start 5 `shouldBe` Nothing

        it "rejects malformed and wrong-kind opaque source tokens" do
            parseRosterDropSourceToken "" `shouldBe` Nothing
            parseRosterDropSourceToken "existing:not-a-uuid" `shouldBe` Nothing
            parseRosterDropSourceToken "staff:11111111-1111-1111-1111-111111111111:extra" `shouldBe` Nothing
            parseRosterDropSourceToken "day:11111111-1111-1111-1111-111111111111" `shouldBe` Nothing

        it "distinguishes existing shifts, staff, placement targets and delete without interpreting browser state" do
            let firstId = workflowUuid "11111111-1111-1111-1111-111111111111"
                secondId = workflowUuid "22222222-2222-2222-2222-222222222222"
            parseRosterDropSourceToken "existing:11111111-1111-1111-1111-111111111111"
                `shouldSatisfy` \case
                    Just (ExistingRosterShiftSource rosterSlotId) -> unpackId rosterSlotId == firstId
                    _ -> False
            parseRosterDropSourceToken "staff:11111111-1111-1111-1111-111111111111"
                `shouldSatisfy` \case
                    Just (RosterStaffSource staffId) -> unpackId staffId == firstId
                    _ -> False
            parseRosterShiftDropDestinationToken "delete"
                `shouldBe` Just DeleteRosterShiftDestination
            parseRosterShiftDropDestinationToken "day:11111111-1111-1111-1111-111111111111"
                `shouldSatisfy` \case
                    Just (PlaceRosterShiftDestination (DayRosterShiftDropTarget rosterDayId)) -> unpackId rosterDayId == firstId
                    _ -> False
            parseRosterShiftDropDestinationToken "new:11111111-1111-1111-1111-111111111111:22222222-2222-2222-2222-222222222222:3"
                `shouldSatisfy` \case
                    Just (PlaceRosterShiftDestination (PreciseRosterShiftDropTarget rosterDayId slotDefinitionId rowIndex)) ->
                        unpackId rosterDayId == firstId && unpackId slotDefinitionId == secondId && rowIndex == 3
                    _ -> False

        it "parses instant timeline targets and rejects malformed or unbounded epochs" do
            let firstId = workflowUuid "11111111-1111-1111-1111-111111111111"
                secondId = workflowUuid "22222222-2222-2222-2222-222222222222"
            parseTimelineShiftDropTargetToken "instant:11111111-1111-1111-1111-111111111111:22222222-2222-2222-2222-222222222222:1775316600"
                `shouldSatisfy` \case
                    Just TimelineShiftDropTarget { timelineTargetRosterDayId, timelineTargetSlotDefinitionId, timelineTargetStartsAt } ->
                        unpackId timelineTargetRosterDayId == firstId
                            && unpackId timelineTargetSlotDefinitionId == secondId
                            && timelineTargetStartsAt == posixSecondsToUTCTime 1775316600
                    _ -> False
            forEach ["not-an-instant", "1.5", "-1", "253402300800", "9999999999999999999999999999999999999999999"] \raw ->
                parseTimelineShiftDropTargetToken ("instant:11111111-1111-1111-1111-111111111111:22222222-2222-2222-2222-222222222222:" <> raw)
                    `shouldBe` Nothing

    describe "explicit roster shift assignment" do
        it "applies Staff and Open as closed assignment variants" do
            let staffId = Id (workflowUuid "33333333-3333-3333-3333-333333333333") :: Id Staff
                assigned = applyRosterShiftAssignment (StaffAssignment staffId) (newRecord @RosterSlot)
                open = applyRosterShiftAssignment OpenAssignment assigned
                copied = copyRosterShiftAssignment open (newRecord @RosterSlot)

            assigned.assignmentState `shouldBe` "staff"
            assigned.staffId `shouldBe` Just (unpackId staffId)
            rosterShiftAssignment assigned `shouldBe` Right (StaffAssignment staffId)
            open.assignmentState `shouldBe` "open"
            open.staffId `shouldBe` Nothing
            rosterShiftAssignment open `shouldBe` Right OpenAssignment
            fmap (\slot -> (slot.assignmentState, slot.staffId)) copied
                `shouldBe` Right ("open", Nothing)

        it "rejects inconsistent or unknown persisted assignment shapes" do
            let invalidStaff = newRecord @RosterSlot |> set #assignmentState "staff" |> set #staffId Nothing
                invalidOpen = newRecord @RosterSlot |> set #assignmentState "open" |> set #staffId (Just (workflowUuid "33333333-3333-3333-3333-333333333333"))
                unknown = newRecord @RosterSlot |> set #assignmentState "unknown" |> set #staffId Nothing

            map (isLeft . rosterShiftAssignment) [invalidStaff, invalidOpen, unknown]
                `shouldBe` replicate 3 True

    describe "roster shift publication" do
        it "blocks structurally incomplete Open shifts" do
            let incompleteOpen = applyRosterShiftAssignment OpenAssignment (newRecord @RosterSlot)
            rosterSlotBlocksPublish incompleteOpen `shouldBe` True

    describe "roster shift workflow application" do
        it "applies one validated typed submission as exact authoritative slot fields" do
            let staffId = workflowUuid "33333333-3333-3333-3333-333333333333"
                shiftTypeId = workflowUuid "44444444-4444-4444-4444-444444444444"
                boundaryInput = ShiftBoundaryInput
                    { shiftBoundaryDate = fromGregorian 2025 1 6
                    , shiftBoundaryStartTime = TimeOfDay 9 0 0
                    , shiftBoundaryStartOccurrence = Nothing
                    , shiftBoundaryEndTime = TimeOfDay 17 0 0
                    , shiftBoundaryEndOccurrence = Nothing
                    , shiftBoundaryBreak = Nothing
                    }
                boundaries = either (error . show) (\value -> value) (resolveShiftBoundaries "Australia/Melbourne" boundaryInput)
                valid = ValidatedRosterShift
                    { validRosterShiftAssignment = StaffAssignment (Id staffId)
                    , validRosterShiftBoundaries = boundaries
                    , validRosterShiftTypeId = shiftTypeId
                    }
                slot = applyValidatedRosterShift valid (newRecord @RosterSlot)

            slot.assignmentState `shouldBe` "staff"
            slot.staffId `shouldBe` Just staffId
            slot.shiftTypeId `shouldBe` Just shiftTypeId
            slot.startsAt `shouldBe` Just (UTCTime (fromGregorian 2025 1 5) (secondsToDiffTime (22 * 60 * 60)))
            slot.endsAt `shouldBe` Just (UTCTime (fromGregorian 2025 1 6) (secondsToDiffTime (6 * 60 * 60)))
            slot.timezone `shouldBe` "Australia/Melbourne"

workflowUuid :: String -> UUID
workflowUuid value = fromMaybe (error "invalid roster workflow test UUID") (UUID.fromString value)
