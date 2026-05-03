module Test.RosterGridSpec where

import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude (newRecord, unpackId)
import IHP.Prelude
import Test.Hspec
import Web.RosterWeeks.Rows (impactedRowKeysForSlotUpdate)
import Web.View.RosterWeeks.Grid (compactDayColumnSlots, lastRowIndexForRows,
                                  rowsForDay)

tests :: Spec
tests = describe "Roster grid row grouping" do
    it "sorts day-column slots by start time" do
        let slotA = newRecord @RosterWeekSlotDefinition
            slotB = newRecord @RosterWeekSlotDefinition
            slotC = newRecord @RosterWeekSlotDefinition

            mkSlot daySlot startTime staffId =
                newRecord @RosterSlot
                    |> set #rosterWeekSlotDefinitionId (unpackId daySlot.id)
                    |> set #startTime startTime
                    |> set #staffId staffId

            first = mkSlot slotA (Just $ TimeOfDay 10 0 0) (Just (UUID.nil))
            second = mkSlot slotB (Just $ TimeOfDay 8 0 0) (Just (UUID.nil))
            third = mkSlot slotC (Just $ TimeOfDay 12 0 0) (Just (UUID.nil))
            sorted = compactDayColumnSlots [slotA, slotB, slotC] [first, second, third]
        map (get #rosterWeekSlotDefinitionId) sorted `shouldBe`
            [unpackId slotB.id, unpackId slotA.id, unpackId slotC.id]

    it "puts untimed visible slots after timed ones" do
        let slotA = newRecord @RosterWeekSlotDefinition
            slotB = newRecord @RosterWeekSlotDefinition

            mkTimedSlot startTime =
                newRecord @RosterSlot
                    |> set #rosterWeekSlotDefinitionId (unpackId slotA.id)
                    |> set #startTime (Just startTime)
                    |> set #staffId (Just UUID.nil)

            mkUntimedSlot =
                newRecord @RosterSlot
                    |> set #rosterWeekSlotDefinitionId (unpackId slotB.id)
                    |> set #startTime Nothing
                    |> set #endTime (Just $ TimeOfDay 9 0 0)
                    |> set #staffId Nothing

            first = mkTimedSlot (TimeOfDay 9 0 0)
            second = mkUntimedSlot
            sorted = compactDayColumnSlots [slotA, slotB] [second, first]
        map (get #rosterWeekSlotDefinitionId) sorted `shouldBe`
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
