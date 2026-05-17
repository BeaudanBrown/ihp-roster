module Test.MutationBoundarySpec where

import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "Mutation boundary guard" do
    it "keeps leave request database writes in the mutation module" do
        source <- Text.readFile "Web/Controller/LeaveRequests.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserLeaveRequestEvent", "recordCurrentUserAuditEvent"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps timesheet database writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Timesheets.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserTimesheetEntryVersion", "recordCurrentUserAuditEvent"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps profile update writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Profiles.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "replaceStaffShiftPreferences", "refreshRosterFragments", "refreshProfileContent"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps staff update writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Staff.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "syncStaffRosterGroupAssignments", "replaceStaffShiftPreferences", "ensureStaffPayVersionForStaff"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []
