module Test.LiveUpdateSpec where

import Application.Helper.LiveUpdate
import Application.Helper.LiveSurface
import Application.Support.LiveUpdates
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
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

    it "encodes support live surface config with stable JSON" do
        let surface =
                mkLiveSurface
                    "support"
                    SupportPlatformScope
                    [ supportAwardRatesSectionFragmentRef
                    , supportPublicHolidaysSectionFragmentRef
                    ]

        liveSurfaceConfigJson surface
            `shouldBe` "{\"decorateRequestsWithin\":[],\"feature\":\"support\",\"resyncFragments\":[{\"deferUntilBlur\":false,\"fragmentKey\":{\"kind\":\"support_award_rates_section\"},\"protectionPolicy\":null,\"targetId\":\"support-award-rates-section\",\"url\":\"/ShowFwcMapdAwardRatesSection\"},{\"deferUntilBlur\":false,\"fragmentKey\":{\"kind\":\"support_public_holidays_section\"},\"protectionPolicy\":null,\"targetId\":\"support-public-holidays-section\",\"url\":\"/ShowPublicHolidaysSection\"}],\"scope\":{\"kind\":\"support_platform\"},\"socketPath\":\"/live-updates\"}"

    it "round-trips leave, timesheet, and protected roster surface configs through JSON" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let surfaces =
                [ mkLiveSurface
                    "leave-requests"
                    LeaveRequestsScope { venueId }
                    [ LiveFragmentRef
                        { fragmentKey = LeaveRequestsContentFragment
                        , targetId = "leave-requests-content"
                        , url = "/ShowLeaveRequestsContentFragment"
                        , deferUntilBlur = False
                        , protectionPolicy = NoProtection
                        }
                    ]
                , mkLiveSurface
                    "timesheets"
                    TimesheetWeekScope { venueId, weekOffset = 1 }
                    [ LiveFragmentRef
                        { fragmentKey = TimesheetDaySectionFragment { dayOffset = 2 }
                        , targetId = "timesheet-day-2"
                        , url = "/ShowTimesheetDaySectionFragment?weekOffset=1&dayOffset=2"
                        , deferUntilBlur = False
                        , protectionPolicy = NoProtection
                        }
                    ]
                , mkLiveSurface
                    "roster"
                    RosterWeekScope { venueId, rosterGroupId, weekOffset = 0 }
                    [ LiveFragmentRef
                        { fragmentKey = RosterContentFragment
                        , targetId = "roster-content"
                        , url = "/ShowRosterWeekContentFragment?weekOffset=0"
                        , deferUntilBlur = True
                        , protectionPolicy =
                            FocusedFieldProtection
                                FocusedFieldProtectionConfig
                                    { activeSelector = ".slot-note-input:focus"
                                    , fieldKeyAttr = "data-roster-field-key"
                                    , fieldNameFallback = True
                                    , containerSelector = Just "tr[data-roster-row]"
                                    }
                        }
                    ]
                ]

        forM_ surfaces \surface ->
            Aeson.decode (LBS.fromStrict (cs (liveSurfaceConfigJson surface))) `shouldBe` Just surface

expectUuid :: Text -> UUID.UUID
expectUuid value =
    fromMaybe (error ("Invalid UUID fixture: " <> cs value)) (UUID.fromText value)
