module Test.LiveUpdateSpec where

import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate
import Application.Support.LiveUpdates
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "LiveUpdate runtime types" do
    it "round-trips roster, admin, leave, timesheet, and support scopes through JSON" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let scopes =
                [ RosterWeekScope { venueId, rosterGroupId, weekOffset = 0 }
                , AdminShiftTypesScope { venueId }
                , AdminRosterGroupsScope { venueId }
                , AdminInvitesScope { venueId }
                , AdminXeroScope { venueId }
                , LeaveRequestsScope { venueId }
                , TimesheetWeekScope { venueId, weekOffset = 2 }
                , SupportPlatformScope
                ]

        forM_ scopes \scope ->
            Aeson.decode (Aeson.encode scope) `shouldBe` Just scope

    it "round-trips roster, admin, profile, leave, timesheet, and support fragment keys through JSON" do
        let rosterDayId = expectUuid "22222222-2222-2222-2222-222222222222"
        let fragmentKeys =
                [ RosterContentFragment
                , RosterStaffPanelFragment
                , RosterRowFragment { rosterDayId, rowIndex = 1 }
                , LeaveRequestsContentFragment
                , TimesheetDaySectionFragment { dayOffset = 4 }
                , AdminInvitesFragment
                , AdminShiftTypesFragment
                , AdminRosterGroupsFragment
                , AdminXeroFragment
                , AdminXeroStaffMappingsFragment
                , AdminXeroPayItemsFragment
                , AdminXeroTimesheetsFragment
                , ProfileLeaveRequestsContentFragment
                , SupportAwardRatesSectionFragment
                , SupportPublicHolidaysSectionFragment
                ]

        forM_ fragmentKeys \fragmentKey ->
            Aeson.decode (Aeson.encode fragmentKey) `shouldBe` Just fragmentKey

    it "uses stable live scope keys for client/server subscription matching" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"

        liveUpdateScopeKey RosterWeekScope { venueId, rosterGroupId, weekOffset = -1 }
            `shouldBe` "roster_week:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:-1"
        liveUpdateScopeKey AdminShiftTypesScope { venueId }
            `shouldBe` "admin_shift_types:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey AdminRosterGroupsScope { venueId }
            `shouldBe` "admin_roster_groups:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey AdminInvitesScope { venueId }
            `shouldBe` "admin_invites:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey AdminXeroScope { venueId }
            `shouldBe` "admin_xero:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey LeaveRequestsScope { venueId }
            `shouldBe` "leave_requests:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey TimesheetWeekScope { venueId, weekOffset = 2 }
            `shouldBe` "timesheet_week:11111111-1111-1111-1111-111111111111:2"
        liveUpdateScopeKey SupportPlatformScope
            `shouldBe` "support_platform"

    it "round-trips commands and encodes subscribed, invalidation, and error payloads as JSON" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let scope = RosterWeekScope { venueId, rosterGroupId, weekOffset = 0 }
        let fragment =
                LiveFragmentRef
                    { fragmentKey = RosterStaffPanelFragment
                    , targetId = "roster-staff-panel"
                    , url = "/ShowRosterStaffPanelFragment?weekOffset=0"
                    , deferUntilBlur = False
                    , protectionPolicy = NoProtection
                    }
        let commands =
                [ SubscribeLiveUpdates { scope, clientId = "client-1", lastSeenVersion = Nothing }
                , SubscribeLiveUpdates { scope, clientId = "client-1", lastSeenVersion = Just 4 }
                , UnsubscribeLiveUpdates { scope }
                ]
        let messages =
                [ LiveUpdatesSubscribed { scope, scopeKey = liveUpdateScopeKey scope, currentVersion = 4, resync = False }
                , LiveUpdatesSubscribed { scope, scopeKey = liveUpdateScopeKey scope, currentVersion = 5, resync = True }
                , LiveUpdatesInvalidated { scope, scopeKey = liveUpdateScopeKey scope, version = 6, fragments = [fragment], sourceClientId = Just "client-1" }
                , LiveUpdatesInvalidated { scope, scopeKey = liveUpdateScopeKey scope, version = 7, fragments = [], sourceClientId = Nothing }
                , LiveUpdatesError { message = "Not authorized for requested live update scope" }
                ]

        forM_ commands \command ->
            Aeson.decode (Aeson.encode command) `shouldBe` Just command
        forM_ messages \message ->
            (Aeson.decode (Aeson.encode message) :: Maybe Aeson.Value) `shouldSatisfy` isJust

        let encodedSubscribed = cs (LBS.toStrict (Aeson.encode (LiveUpdatesSubscribed { scope, scopeKey = liveUpdateScopeKey scope, currentVersion = 4, resync = False }))) :: Text
        let encodedInvalidated = cs (LBS.toStrict (Aeson.encode (LiveUpdatesInvalidated { scope, scopeKey = liveUpdateScopeKey scope, version = 6, fragments = [fragment], sourceClientId = Nothing }))) :: Text
        encodedSubscribed `shouldSatisfy` Text.isInfixOf "\"scopeKey\":\"roster_week:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:0\""
        encodedInvalidated `shouldSatisfy` Text.isInfixOf "\"scopeKey\":\"roster_week:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:0\""

    it "exposes active live scopes without leaking websocket subscription internals" do
        activeLiveUpdateScopes `shouldReturn` []
        activeLiveUpdateScopeMatches supportScopeLabel `shouldReturn` []
        activeRosterWeekScopes `shouldReturn` []

    it "reports broadcast fanout counts for profiling hooks" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let scope = LeaveRequestsScope { venueId }
        let fragment =
                LiveFragmentRef
                    { fragmentKey = LeaveRequestsContentFragment
                    , targetId = "leave-requests-content"
                    , url = "/ShowLeaveRequestsContentFragment"
                    , deferUntilBlur = False
                    , protectionPolicy = NoProtection
                    }

        result <- broadcastLiveInvalidationDetailedWithoutContext scope Nothing [fragment]

        result.broadcastVersion `shouldSatisfy` (> 0)
        result.broadcastSubscriberCount `shouldBe` 0
        result.broadcastFragmentCount `shouldBe` 1
        result.broadcastDroppedSubscriptions `shouldBe` 0

    it "encodes support live surface config with stable JSON" do
        let surface =
                mkLiveSurface
                    "support"
                    SupportPlatformScope
                    [ supportAwardRatesSectionFragmentRef
                    , supportPublicHolidaysSectionFragmentRef
                    ]

        liveSurfaceConfigJson surface
            `shouldBe` "{\"decorateRequestsWithin\":[],\"feature\":\"support\",\"resyncFragments\":[{\"deferUntilBlur\":false,\"fragmentKey\":{\"kind\":\"support_award_rates_section\"},\"protectionPolicy\":null,\"targetId\":\"support-award-rates-section\",\"url\":\"/ShowFwcMapdAwardRatesSection\"},{\"deferUntilBlur\":false,\"fragmentKey\":{\"kind\":\"support_public_holidays_section\"},\"protectionPolicy\":null,\"targetId\":\"support-public-holidays-section\",\"url\":\"/ShowPublicHolidaysSection\"}],\"scope\":{\"kind\":\"support_platform\"},\"scopeKey\":\"support_platform\",\"socketPath\":\"/live-updates\"}"

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

supportScopeLabel :: LiveUpdateScope -> Maybe Text
supportScopeLabel SupportPlatformScope = Just "support"
supportScopeLabel _                    = Nothing
