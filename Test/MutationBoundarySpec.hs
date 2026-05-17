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

    it "routes leave request live invalidation through touched resources" do
        source <- Text.readFile "Web/LeaveRequests/Mutations.hs"
        let forbiddenTokens = ["broadcastLeaveRequestsInvalidation", "refreshProfileLeaveRequests", "invalidateAffectedRosterWeeksForLeave", "refreshRosterFragments"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps timesheet database writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Timesheets.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserTimesheetEntryVersion", "recordCurrentUserAuditEvent"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes timesheet mutation live invalidation through touched resources" do
        source <- Text.readFile "Web/Timesheets/Mutations.hs"
        let forbiddenTokens = ["refreshTimesheetDay", "refreshMovedTimesheetEntry", "refreshTimesheetFragments", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps profile update writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Profiles.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "replaceStaffShiftPreferences", "refreshRosterFragments", "refreshProfileContent"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes profile mutation live invalidation through touched resources" do
        source <- Text.readFile "Web/Profiles/Mutations.hs"
        let forbiddenTokens = ["refreshProfileContent", "refreshRosterFragments", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps staff update writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Staff.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "syncStaffRosterGroupAssignments", "replaceStaffShiftPreferences", "ensureStaffPayVersionForStaff"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes staff mutation live invalidation through touched resources" do
        mutationSource <- Text.readFile "Web/Staff/Mutations.hs"
        controllerSource <- Text.readFile "Web/Controller/Staff.hs"
        let forbiddenTokens = ["broadcastSurface", "refreshRosterContent", "refreshAdminXero"]
        filter (`Text.isInfixOf` (mutationSource <> controllerSource)) forbiddenTokens `shouldBe` []

    it "keeps staff document writes in the mutation module" do
        source <- Text.readFile "Web/Controller/StaffDocuments.hs"
        let forbiddenTokens = ["createRsaDocument", "reviewRsaDocument", "recordCurrentUserAuditEvent", "createRecord", "updateRecord"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes staff document mutation live invalidation through touched resources" do
        source <- Text.readFile "Web/StaffDocuments/Mutations.hs"
        let forbiddenTokens = ["refreshProfileContent", "refreshStaffCompliance", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps roster week writes in the mutation module" do
        source <- Text.readFile "Web/Controller/RosterWeeks.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "enqueueRosterTimesheetCreationJobsForWeek", "appendRosterWeekSlotDefinition rosterWeek", "deleteRosterWeekSlotDefinition", "repackRosterWeekDays", "removeRosterRowWithPacking"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes roster mutation live invalidation through touched resources" do
        source <- Text.readFile "Web/RosterWeeks/Mutations.hs"
        let forbiddenTokens = ["refreshRosterContent", "refreshRosterContentAndStaffPanel", "refreshRosterFragments", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps admin config writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Admin.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "enqueueVenueInvitationDeliveryJob", "ensureShiftTypePayVersionForShiftType", "createVenueRosterGroupWithDefaults", "ensureDefaultRosterSlots", "syncVenueDefaultRosterGroupToTopActive", "reorderActiveRosterGroups", "reorderActiveShiftTypes"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes admin mutation live invalidation through touched resources" do
        source <- Text.readFile "Web/Admin/Mutations.hs"
        let forbiddenTokens = ["refreshAdminInvites", "refreshAdminRosterGroups", "refreshAdminShiftTypes", "refreshAdminXero", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes venue invitation acceptance through the mutation module" do
        controllerSource <- Text.readFile "Web/Controller/Users.hs"
        mutationSource <- Text.readFile "Web/Users/Mutations.hs"
        let controllerForbiddenTokens = ["broadcastSurfaceFragments", "adminInvitesLiveSurfaceDefinitionForVenue", "AdminInvitesLiveFragment"]
        let mutationForbiddenTokens = ["broadcastSurface", "refreshAdminInvites"]
        filter (`Text.isInfixOf` controllerSource) controllerForbiddenTokens `shouldBe` []
        filter (`Text.isInfixOf` mutationSource) mutationForbiddenTokens `shouldBe` []

    it "keeps export job writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Exports.hs"
        let forbiddenTokens = ["requestFixedExport ", "recordExportDownload ", "createRecord", "updateRecord", "recordCurrentUserAuditEvent"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes export mutation live invalidation through touched resources" do
        source <- Text.readFile "Web/Exports/Mutations.hs"
        let forbiddenTokens = ["refreshAdminExports", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes Xero timesheet mutation live invalidation through touched resources" do
        source <- Text.readFile "Web/Controller/Admin/Xero/Timesheets.hs"
        let forbiddenTokens = ["refreshAdminXero", "refreshAdminXeroTimesheets", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps Xero timesheet service writes behind the mutation wrapper" do
        controllerSource <- Text.readFile "Web/Controller/Admin/Xero/Timesheets.hs"
        connectionSource <- Text.readFile "Application/Xero/Connection.hs"
        keepaliveSource <- Text.readFile "Application/Xero/Keepalive.hs"
        let controllerForbiddenTokens = ["Application.Xero.Timesheets.Preview", "Application.Xero.Timesheets.Submission"]
        let applicationForbiddenTokens = ["broadcastSurface", "LiveSurface", "adminXeroLiveSurfaceDefinition"]
        filter (`Text.isInfixOf` controllerSource) controllerForbiddenTokens `shouldBe` []
        filter (`Text.isInfixOf` (connectionSource <> keepaliveSource)) applicationForbiddenTokens `shouldBe` []

    it "keeps Xero mapping writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Admin/Xero/Mappings.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserAuditEvent", "refreshAdminXero"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps Xero connection writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Admin/Xero/Connection.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserAuditEvent", "refreshAdminXero"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps Xero reference sync writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Admin/Xero/ReferenceSync.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "recordCurrentUserAuditEvent", "refreshAdminXero"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "keeps Xero pay item sync writes in the mutation module" do
        source <- Text.readFile "Web/Controller/Admin/Xero/PayItemMutations.hs"
        let forbiddenTokens = ["createRecord", "updateRecord", "withTransaction", "refreshAdminXeroPayItems"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []

    it "routes Xero pay item sync live invalidation through touched resources" do
        source <- Text.readFile "Web/Admin/Xero/Mutations.hs"
        let forbiddenTokens = ["refreshAdminXeroPayItems", "refreshAdminXero", "broadcastSurface"]
        filter (`Text.isInfixOf` source) forbiddenTokens `shouldBe` []
