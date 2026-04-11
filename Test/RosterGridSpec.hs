module Test.RosterGridSpec where

import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude (newRecord)
import IHP.Prelude
import Test.Hspec
import Web.RosterWeeks.Rows (impactedRowKeysForSlotUpdate)
import Web.View.RosterWeeks.Grid (lastRowIndexForRows, rowsForDay)

tests :: Spec
tests = describe "Roster grid row grouping" do
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

    it "locks closed days to exactly three visible rows" do
        let closedDay = newRecord @RosterDay |> set #isClosed True
        let mkSlot rowIndex =
                (newRecord @RosterSlot)
                    |> set #rowIndex rowIndex
        let rows = rowsForDay closedDay [mkSlot 0, mkSlot 4]
        map fst rows `shouldBe` [0, 1, 2]

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
