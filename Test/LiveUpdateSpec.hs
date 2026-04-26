module Test.LiveUpdateSpec where

import Application.Helper.LiveUpdate
import qualified Data.Aeson as Aeson
import qualified Data.UUID as UUID
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "LiveUpdate runtime types" do
    it "round-trips roster, roster-group-config, admin-slot-names, leave, timesheet, and support scopes through JSON" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let scopes =
                [ RosterWeekScope { venueId, rosterGroupId, weekOffset = 0 }
                , RosterGroupConfigScope { venueId, rosterGroupId }
                , AdminSlotNamesScope { venueId, rosterGroupId }
                , LeaveRequestsScope { venueId }
                , TimesheetWeekScope { venueId, weekOffset = 2 }
                , SupportPlatformScope
                ]

        forM_ scopes \scope ->
            Aeson.decode (Aeson.encode scope) `shouldBe` Just scope

    it "round-trips roster, leave, timesheet, and support fragment keys through JSON" do
        let rosterDayId = expectUuid "22222222-2222-2222-2222-222222222222"
        let fragmentKeys =
                [ RosterContentFragment
                , RosterStaffPanelFragment
                , RosterRowFragment { rosterDayId, rowIndex = 1 }
                , LeaveRequestsContentFragment
                , TimesheetDaySectionFragment { dayOffset = 4 }
                , SupportAwardRatesSectionFragment
                , SupportPublicHolidaysSectionFragment
                ]

        forM_ fragmentKeys \fragmentKey ->
            Aeson.decode (Aeson.encode fragmentKey) `shouldBe` Just fragmentKey

expectUuid :: Text -> UUID.UUID
expectUuid value =
    fromMaybe (error ("Invalid UUID fixture: " <> cs value)) (UUID.fromText value)
