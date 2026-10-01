module Test.TimesheetFiltersSpec where

import qualified Data.Text as Text
import Data.UUID (fromWords)
import IHP.Prelude
import Test.Hspec
import Web.Timesheets.Filters
import Web.Timesheets.Paths (timesheetWindowUrlWithFilters,
                             withTimesheetFilters)

tests :: Spec
tests = describe "Timesheet multi-selection filters" do
    let alice = fromWords 1 0 0 0
        bob = fromWords 2 0 0 0
        bar = fromWords 3 0 0 0
        kitchen = fromWords 4 0 0 0
        upstairs = fromWords 5 0 0 0
        downstairs = fromWords 6 0 0 0
        other = fromWords 7 0 0 0
        filters = TimesheetViewFilters [alice, bob] [upstairs, downstairs] [bar, kitchen]
    it "uses OR within categories and AND between them" do
        matchesTimesheetFilters filters alice (Just upstairs) bar `shouldBe` True
        matchesTimesheetFilters filters bob (Just downstairs) kitchen `shouldBe` True
        matchesTimesheetFilters filters other (Just upstairs) bar `shouldBe` False
        matchesTimesheetFilters filters alice (Just other) bar `shouldBe` False
        matchesTimesheetFilters filters alice (Just upstairs) other `shouldBe` False
        matchesTimesheetFilters filters alice Nothing bar `shouldBe` False
    it "treats empty categories as All, including historical ungrouped entries" do
        matchesTimesheetFilters emptyTimesheetViewFilters alice Nothing bar `shouldBe` True
        activeTimesheetFilterCount emptyTimesheetViewFilters `shouldBe` 0
        activeTimesheetFilterCount filters `shouldBe` 3
    it "deduplicates, orders and removes unavailable selections" do
        canonicalizeTimesheetFilters True [alice, bob] [upstairs, downstairs] [bar]
            (TimesheetViewFilters [bob, alice, bob, other] [other] [bar, kitchen])
            `shouldBe` TimesheetViewFilters [alice, bob] [] [bar]
    it "removes manager-only filters without removing the worker's shift filter" do
        canonicalizeTimesheetFilters False [alice, bob] [upstairs, downstairs] [bar, kitchen] filters
            `shouldBe` TimesheetViewFilters [] [] [bar, kitchen]
    it "clears the hidden single-group category" do
        canonicalizeTimesheetFilters True [alice, bob] [upstairs] [bar, kitchen] filters
            `shouldBe` filters { filterRosterGroupIds = [] }
    it "replaces all three categories without losing unrelated route context" do
        let original = timesheetWindowUrlWithFilters (fromGregorian 2025 1 6) filters <> "&rosterCalendarRevision=1"
        let cleared = withTimesheetFilters emptyTimesheetViewFilters original
        cleared `shouldBe` "/ShowTimesheetWindow?anchorDate=2025-01-06&rosterCalendarRevision=1"
        Text.count "staffFilterIds=" original `shouldBe` 2
