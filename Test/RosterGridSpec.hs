module Test.RosterGridSpec where

import Application.VenueTime.Model (authoritativeBoundariesFromInstants,
                                    decodeRosterShiftTiming)
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude (newRecord, unpackId)
import IHP.Prelude
import Test.Hspec
import Test.Support (setTestEndTime, setTestStartTime)
import Web.RosterWeeks.DateRange (RosterWindowDay (..), laneForOperationalDate,
                                  projectRosterWindow, projectedRosterDay,
                                  rosterWindowLaneName, rosterWindowLanes,
                                  rosterWindowProjectedDays)
import Web.RosterWeeks.Projection (RosterMutationProjection (..),
                                   rosterMutationProjectionFragments)
import Web.RosterWeeks.Rows (impactedRowKeysForSlotUpdate)
import Web.RosterWeeks.TimelineScale
import Web.RosterWeeks.Types (RosterProjectionFragment (..))
import Web.View.RosterWeeks.Grid (compactDayColumnSlots, lastRowIndexForRows,
                                  rowsForDay)

tests :: Spec
tests = describe "Roster grid row grouping" do
    it "uses a 23-hour elapsed timeline on the spring transition" do
        case timelineScaleForDay (fromGregorian 2026 10 3) 360 345 [] of
            Left failure -> expectationFailure (cs (tshow failure))
            Right scale -> do
                scale.scaleMinutes `shouldBe` 23 * 60
                timelineClockLabel (timelineInstantAt scale (19 * 60)) `shouldBe` "01:00"
                timelineClockLabel (timelineInstantAt scale (20 * 60)) `shouldBe` "03:00"

    it "labels both occurrences on the 25-hour autumn timeline" do
        case timelineScaleForDay (fromGregorian 2026 4 4) 360 345 [] of
            Left failure -> expectationFailure (cs (tshow failure))
            Right scale -> do
                scale.scaleMinutes `shouldBe` 25 * 60
                timelineClockLabel (timelineInstantAt scale (20 * 60)) `shouldBe` "02:00 (first)"
                timelineClockLabel (timelineInstantAt scale (21 * 60)) `shouldBe` "02:00 (second)"
                timelineClockLabel (timelineInstantAt scale (22 * 60)) `shouldBe` "03:00"

    it "expands for saved boundaries and shrinks when they move inward" do
        case timelineScaleForDay (fromGregorian 2026 10 5) 540 1020 [] of
            Left failure -> expectationFailure (cs (tshow failure))
            Right base -> do
                let early = timelineInstantAt base (-90)
                    late = timelineInstantAt base (base.scaleMinutes + 120)
                case timelineScaleForDay (fromGregorian 2026 10 5) 540 1020 [(early, late)] of
                    Left failure -> expectationFailure (cs (tshow failure))
                    Right expanded -> do
                        expanded.scaleStartsAt `shouldBe` early
                        expanded.scaleEndsAt `shouldBe` late
                        timelineOffsetMinutes expanded early `shouldBe` 0
                timelineScaleForDay (fromGregorian 2026 10 5) 540 1020 [(base.scaleStartsAt, base.scaleEndsAt)] `shouldBe` Right base

    it "advances display-only gap boundaries without inventing a saved clock" do
        case timelineScaleForDay (fromGregorian 2026 10 3) 120 240 [] of
            Left failure -> expectationFailure (cs (tshow failure))
            Right scale -> timelineClockLabel scale.scaleStartsAt `shouldBe` "03:00"

    it "snaps to five-minute instants independently of a fractional expanded origin" do
        let start = posixSecondsToUTCTime 1775316600.5
            end = posixSecondsToUTCTime 1775317500
            scale = TimelineScale start end (899.5 / 60)
        timelineSnapInstants scale `shouldBe` map posixSecondsToUTCTime [1775316900, 1775317200, 1775317500]

    it "keeps repeated clock targets distinct and omits spring gap targets" do
        case (timelineScaleForDay (fromGregorian 2026 4 4) 360 345 [], timelineScaleForDay (fromGregorian 2026 10 3) 360 345 []) of
            (Right autumn, Right spring) -> do
                let repeated = filter (\instant -> timelineClockLabel instant `elem` ["02:30 (first)", "02:30 (second)"]) (timelineSnapInstants autumn)
                length repeated `shouldBe` 2
                length (nub repeated) `shouldBe` 2
                map timelineClockLabel (timelineSnapInstants spring) `shouldNotContain` ["02:30"]
            _ -> expectationFailure "Expected valid transition scales"

    it "offers only whole-interval timeline moves with exact second-precision labels" do
        let day = fromGregorian 2026 10 5
        case timelineScaleForDay day 540 1020 [] of
            Left failure -> expectationFailure (cs (tshow failure))
            Right scale -> do
                let start = scale.scaleStartsAt
                case authoritativeBoundariesFromInstants "Australia/Melbourne" start (addUTCTime 7230.5 start) Nothing Nothing of
                    Left failure -> expectationFailure (cs (tshow failure))
                    Right boundaries -> do
                        let choices = timelineMoveChoices scale day boundaries
                        fmap snd (headMay choices) `shouldBe` Just "09:00–11:00:30.5"
                        fmap snd (lastMay choices) `shouldBe` Just "15:10–17:10:30.5"
                        all (\(instant, _) -> instant >= scale.scaleStartsAt && addUTCTime 7230.5 instant <= scale.scaleEndsAt) choices `shouldBe` True

    it "sorts day-column slots by start time" do
        let slotA = newRecord @RosterLane
            slotB = newRecord @RosterLane
            slotC = newRecord @RosterLane

            mkSlot daySlot startTime endTime staffId =
                newRecord @RosterSlot
                    |> set #rosterLaneId (unpackId daySlot.id)
                    |> setTestStartTime (Just startTime)
                    |> setTestEndTime (Just endTime)
                    |> set #staffId staffId

            first = mkSlot slotA (TimeOfDay 10 0 0) (TimeOfDay 11 0 0) (Just (UUID.nil))
            second = mkSlot slotB (TimeOfDay 8 0 0) (TimeOfDay 9 0 0) (Just (UUID.nil))
            third = mkSlot slotC (TimeOfDay 12 0 0) (TimeOfDay 13 0 0) (Just (UUID.nil))
            sorted = compactDayColumnSlots [] [(slot, decodeRosterShiftTiming slot) | slot <- [first, second, third]]
        map (get #rosterLaneId) sorted `shouldBe`
            [unpackId slotB.id, unpackId slotA.id, unpackId slotC.id]

    it "puts untimed visible slots after timed ones" do
        let slotA = newRecord @RosterLane
            slotB = newRecord @RosterLane

            mkTimedSlot startTime endTime =
                newRecord @RosterSlot
                    |> set #rosterLaneId (unpackId slotA.id)
                    |> setTestStartTime (Just startTime)
                    |> setTestEndTime (Just endTime)
                    |> set #staffId (Just UUID.nil)

            mkUntimedSlot =
                newRecord @RosterSlot
                    |> set #rosterLaneId (unpackId slotB.id)
                    |> setTestStartTime Nothing
                    |> setTestEndTime (Just $ TimeOfDay 9 0 0)
                    |> set #staffId Nothing

            first = mkTimedSlot (TimeOfDay 9 0 0) (TimeOfDay 10 0 0)
            second = mkUntimedSlot
            sorted = compactDayColumnSlots [] [(slot, decodeRosterShiftTiming slot) | slot <- [second, first]]
        map (get #rosterLaneId) sorted `shouldBe`
            [unpackId slotA.id, unpackId slotB.id]

    it "returns two visible rows when an open day has no slots" do
        rowsForDay (newRecord @RosterDay) [] `shouldBe` [(0, []), (1, [])]

    it "groups slots by row_index in ascending order" do
        let mkSlot rowIndex =
                (newRecord @RosterSlot)
                    |> set #rowIndex rowIndex
        let rows = rowsForDay (newRecord @RosterDay) [mkSlot 2, mkSlot 0, mkSlot 2, mkSlot 1]
        map fst rows `shouldBe` [0, 1, 2]
        map (length . snd) rows `shouldBe` [1, 1, 2]

    it "returns the highest row index for the day-level remove control" do
        let mkSlot rowIndex =
                (newRecord @RosterSlot)
                    |> set #rowIndex rowIndex
        lastRowIndexForRows (rowsForDay (newRecord @RosterDay) [mkSlot 4, mkSlot 1, mkSlot 4, mkSlot 2])
            `shouldBe` 4

    it "locks closed days to exactly two visible rows" do
        let closedDay = newRecord @RosterDay |> set #isClosed True
        let mkSlot rowIndex =
                (newRecord @RosterSlot)
                    |> set #rowIndex rowIndex
        let rows = rowsForDay closedDay [mkSlot 0, mkSlot 4]
        map fst rows `shouldBe` [0, 1]

    it "includes the edited row and all rows assigned to old/new staff" do
        let Just staffA = UUID.fromText "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let Just staffB = UUID.fromText "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        let Just day1 = UUID.fromText "11111111-1111-1111-1111-111111111111"
        let Just day2 = UUID.fromText "22222222-2222-2222-2222-222222222222"
        let Just day3 = UUID.fromText "33333333-3333-3333-3333-333333333333"

        let editedSlot =
                newRecord @RosterSlot
                    |> set #rosterDayId day1
                    |> set #rowIndex 0
                    |> set #staffId (Just staffB)

        let relatedSlots =
                [ newRecord @RosterSlot |> set #rosterDayId day2 |> set #rowIndex 1 |> set #staffId (Just staffA)
                , newRecord @RosterSlot |> set #rosterDayId day3 |> set #rowIndex 2 |> set #staffId (Just staffB)
                , newRecord @RosterSlot |> set #rosterDayId day3 |> set #rowIndex 9 |> set #staffId Nothing
                ]

        impactedRowKeysForSlotUpdate (Just staffA) editedSlot relatedSlots
            `shouldMatchList` [(day1, 0), (day2, 1), (day3, 2)]

    it "projects an unmaterialized roster day with two rows" do
        let venueId = "10000000-0000-0000-0000-000000000001" :: Id Venue
            rosterGroupId = "20000000-0000-0000-0000-000000000001" :: Id RosterGroup
            windowDay = RosterWindowDay (fromGregorian 2026 8 3) Nothing

        (projectedRosterDay venueId rosterGroupId windowDay).rowCount `shouldBe` 2

    it "projects sparse roster days and a deterministic case-insensitive lane union" do
        let startDate = fromGregorian 2026 8 3
            day0 = newRecord @RosterDay
                |> set #id "10000000-0000-0000-0000-000000000001"
                |> set #operationalDate startDate
            day2 = newRecord @RosterDay
                |> set #id "10000000-0000-0000-0000-000000000003"
                |> set #operationalDate (addDays 2 startDate)
            lane id day name sortOrder = newRecord @RosterLane
                |> set #id id
                |> set #rosterDayId (unpackId day.id)
                |> set #name name
                |> set #sortOrder sortOrder
            lanes =
                [ lane "20000000-0000-0000-0000-000000000001" day0 " Floor " 1
                , lane "20000000-0000-0000-0000-000000000002" day0 "Bar" 0
                , lane "20000000-0000-0000-0000-000000000003" day2 "floor" 0
                , lane "20000000-0000-0000-0000-000000000004" day2 "Kitchen" 1
                ]
            window = projectRosterWindow startDate [day2, day0] lanes

        map (.operationalDate) window.rosterWindowProjectedDays
            `shouldBe` map (`addDays` startDate) [0 .. 6]
        map (isJust . (.persistedRosterDay)) window.rosterWindowProjectedDays
            `shouldBe` [True, False, True, False, False, False, False]
        map rosterWindowLaneName window.rosterWindowLanes
            `shouldBe` ["Bar", "Floor", "Kitchen"]
        fmap (.id) (laneForOperationalDate startDate (window.rosterWindowLanes !! 1))
            `shouldBe` Just ("20000000-0000-0000-0000-000000000001" :: Id RosterLane)
        fmap (.id) (laneForOperationalDate (addDays 2 startDate) (window.rosterWindowLanes !! 1))
            `shouldBe` Just ("20000000-0000-0000-0000-000000000003" :: Id RosterLane)

    it "projects roster mutations through the mounted layout" do
        let dayId = UUID.nil
        let gridAndStaff =
                [ RosterProjectionDayColumns
                , RosterProjectionDayRail
                , RosterProjectionWageRail
                , RosterProjectionSlotsGrid
                , RosterProjectionStaffPanel
                , RosterProjectionSettings
                ]

        rosterMutationProjectionFragments DayRows (RosterDayMutation dayId)
            `shouldBe` gridAndStaff <> [RosterProjectionDaySection dayId]
        rosterMutationProjectionFragments DayColumns (RosterDayMutation dayId)
            `shouldBe` gridAndStaff
        rosterMutationProjectionFragments DayRows (RosterRowsMutation [(dayId, 2), (dayId, 2)])
            `shouldBe` gridAndStaff <> [RosterProjectionRow dayId 2]
        rosterMutationProjectionFragments DayColumns (RosterRowsMutation [(dayId, 2)])
            `shouldBe` gridAndStaff
        rosterMutationProjectionFragments DayColumns RosterTimelineMutation
            `shouldBe`
                [ RosterProjectionGridToolbar
                , RosterProjectionGridFrame
                , RosterProjectionStaffPanel
                , RosterProjectionSettings
                ]
