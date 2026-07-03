module Test.LiveUpdateSpec where

import qualified Application.Helper.Frontend.LiveUpdateSchema as Wire
import Application.Helper.LiveSurface
import Application.Helper.LiveSurface.Internal (defaultLiveUpdateScopeAuthorizationRequirement)
import Application.Helper.LiveUpdate.Runtime
import Application.Support.LiveUpdates
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "LiveUpdate runtime types" do
    it "encodes runtime values through the generated live-update wire schema" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let scope = RosterWeekScope { venueId, rosterGroupId, weekOffset = 0 }
        let fragment =
                LiveUpdateWireFragment
                    { fragmentKey = RosterStaffPanelFragment
                    , targetId = "roster-staff-panel"
                    , url = "/ShowRosterStaffPanelFragment?weekOffset=0"
                    , deferUntilBlur = False
                    , protectionPolicy = NoProtection
                    }
        let message =
                LiveUpdatesInvalidated
                    { scope
                    , scopeKey = liveUpdateScopeKey scope
                    , version = 6
                    , fragments = [fragment]
                    , sourceClientId = Just "client-1"
                    }
        let surface =
                testLiveSurfaceConfig
                    "roster"
                    scope
                    [fragment]

        Aeson.toJSON scope `shouldBe` Aeson.toJSON (liveUpdateScopeToWire scope)
        Aeson.toJSON fragment `shouldBe` Aeson.toJSON (liveUpdateWireFragmentToWire fragment)
        Aeson.toJSON message
            `shouldBe`
                Aeson.toJSON
                    (Wire.Invalidate (liveUpdateScopeToWire scope) (liveUpdateScopeKey scope) 6 [liveUpdateWireFragmentToWire fragment] (Just "client-1"))
        Aeson.decode (Aeson.encode surface) `shouldBe` Just surface

    it "round-trips roster, admin, leave, timesheet, and support scopes through JSON" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let staffId = expectUuid "44444444-4444-4444-4444-444444444444"
        let scopes =
                [ RosterWeekScope { venueId, rosterGroupId, weekOffset = 0 }
                , AdminVenueConfigScope { venueId }
                , AdminShiftTypesScope { venueId }
                , AdminRosterGroupsScope { venueId }
                , AdminInvitesScope { venueId }
                , AdminExportsScope { venueId }
                , AdminXeroScope { venueId }
                , BillingScope { venueId }
                , LeaveRequestsScope { venueId }
                , TimesheetWeekScope { venueId, weekOffset = 2 }
                , ProfileScope { venueId, staffId }
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
                , AdminVenueConfigFragment
                , AdminInvitesFragment
                , AdminExportsFragment
                , AdminShiftTypesFragment
                , AdminRosterGroupsFragment
                , AdminXeroFragment
                , AdminXeroStaffMappingsFragment
                , AdminXeroPayItemsFragment
                , AdminXeroTimesheetsFragment
                , BillingStatusFragment
                , ProfileContentFragment
                , ProfileLeaveRequestsContentFragment
                , SupportAwardRatesSectionFragment
                , SupportPublicHolidaysSectionFragment
                ]

        forM_ fragmentKeys \fragmentKey ->
            Aeson.decode (Aeson.encode fragmentKey) `shouldBe` Just fragmentKey

    it "keeps wire fragment payloads self-describing for the browser" do
        let rosterDayId = expectUuid "22222222-2222-2222-2222-222222222222"
        let fragment =
                LiveUpdateWireFragment
                    { fragmentKey = RosterRowFragment { rosterDayId, rowIndex = 2 }
                    , targetId = "roster-row-2"
                    , url = "/ShowRosterWeekRowFragment?weekOffset=0&rowIndex=2"
                    , deferUntilBlur = True
                    , protectionPolicy = NoProtection
                    }

        Aeson.toJSON fragment
            `shouldBe`
                Aeson.object
                    [ "fragmentKey" Aeson..= Aeson.object
                        [ "surface" Aeson..= ("roster" :: Text)
                        , "kind" Aeson..= ("roster-row" :: Text)
                        , "params" Aeson..= Aeson.object
                            [ "rosterDayId" Aeson..= UUID.toText rosterDayId
                            , "rowIndex" Aeson..= (2 :: Int)
                            ]
                        ]
                    , "targetId" Aeson..= ("roster-row-2" :: Text)
                    , "url" Aeson..= ("/ShowRosterWeekRowFragment?weekOffset=0&rowIndex=2" :: Text)
                    , "deferUntilBlur" Aeson..= True
                    , "protectionPolicy" Aeson..= NoProtection
                    ]

    it "uses stable live scope keys for client/server subscription matching" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let staffId = expectUuid "44444444-4444-4444-4444-444444444444"

        liveUpdateScopeKey RosterWeekScope { venueId, rosterGroupId, weekOffset = -1 }
            `shouldBe` "roster:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:-1"
        liveUpdateScopeKey AdminVenueConfigScope { venueId }
            `shouldBe` "admin-venue-config:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey AdminShiftTypesScope { venueId }
            `shouldBe` "admin-shift-types:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey AdminRosterGroupsScope { venueId }
            `shouldBe` "admin-roster-groups:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey AdminInvitesScope { venueId }
            `shouldBe` "admin-invites:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey AdminExportsScope { venueId }
            `shouldBe` "admin-exports:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey AdminXeroScope { venueId }
            `shouldBe` "admin-xero:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey BillingScope { venueId }
            `shouldBe` "billing:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey LeaveRequestsScope { venueId }
            `shouldBe` "leave-requests:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey TimesheetWeekScope { venueId, weekOffset = 2 }
            `shouldBe` "timesheets:11111111-1111-1111-1111-111111111111:2"
        liveUpdateScopeKey ProfileScope { venueId, staffId }
            `shouldBe` "profile:11111111-1111-1111-1111-111111111111:44444444-4444-4444-4444-444444444444"
        liveUpdateScopeKey SupportPlatformScope
            `shouldBe` "support"

    it "round-trips commands and encodes subscribed, invalidation, and error payloads as JSON" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let scope = RosterWeekScope { venueId, rosterGroupId, weekOffset = 0 }
        let fragment =
                LiveUpdateWireFragment
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
        encodedSubscribed `shouldSatisfy` Text.isInfixOf "\"scopeKey\":\"roster:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:0\""
        encodedInvalidated `shouldSatisfy` Text.isInfixOf "\"scopeKey\":\"roster:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:0\""

    it "exposes active live scopes without leaking websocket subscription internals" do
        activeLiveUpdateScopes `shouldReturn` []
        activeLiveUpdateScopeMatches supportScopeLabel `shouldReturn` []
        activeRosterWeekScopes `shouldReturn` []

    it "exercises isolated in-memory live buses without global state leakage" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let scope = LeaveRequestsScope { venueId }
        let fragment =
                LiveUpdateWireFragment
                    { fragmentKey = LeaveRequestsContentFragment
                    , targetId = "leave-requests-content"
                    , url = "/ShowLeaveRequestsContentFragment"
                    , deferUntilBlur = False
                    , protectionPolicy = NoProtection
                    }
        firstBus <- newInMemoryLiveBus
        secondBus <- newInMemoryLiveBus

        activeLiveUpdateScopesWithBus firstBus `shouldReturn` []
        activeLiveUpdateScopeMatchesWithBus firstBus supportScopeLabel `shouldReturn` []
        activeRosterWeekScopesWithBus firstBus `shouldReturn` []
        currentLiveUpdateVersionWithBus firstBus scope `shouldReturn` 0
        incrementLiveUpdateVersionWithBus firstBus scope `shouldReturn` 1
        currentLiveUpdateVersionWithBus firstBus scope `shouldReturn` 1
        currentLiveUpdateVersionWithBus secondBus scope `shouldReturn` 0

        result <- broadcastLiveInvalidationDetailedWithBus firstBus scope Nothing [fragment, fragment]

        result.broadcastVersion `shouldBe` 2
        result.broadcastSubscriberCount `shouldBe` 0
        result.broadcastFragmentCount `shouldBe` 2
        result.broadcastRefetchFragmentCount `shouldBe` 1
        result.broadcastCoalescedFragmentCount `shouldBe` 1
        result.broadcastDroppedSubscriptions `shouldBe` 0

    it "reports broadcast fanout counts for profiling hooks" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let scope = LeaveRequestsScope { venueId }
        let fragment =
                LiveUpdateWireFragment
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
        result.broadcastRefetchFragmentCount `shouldBe` 1
        result.broadcastCoalescedFragmentCount `shouldBe` 0
        result.broadcastDroppedSubscriptions `shouldBe` 0

    it "coalesces duplicate fragment refs before broadcasting" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let scope = LeaveRequestsScope { venueId }
        let fragment =
                LiveUpdateWireFragment
                    { fragmentKey = LeaveRequestsContentFragment
                    , targetId = "leave-requests-content"
                    , url = "/ShowLeaveRequestsContentFragment"
                    , deferUntilBlur = False
                    , protectionPolicy = NoProtection
                    }

        coalesceLiveUpdateWireFragments [fragment, fragment] `shouldBe` [fragment]
        result <- broadcastLiveInvalidationDetailedWithoutContext scope Nothing [fragment, fragment]

        result.broadcastFragmentCount `shouldBe` 2
        result.broadcastRefetchFragmentCount `shouldBe` 1
        result.broadcastCoalescedFragmentCount `shouldBe` 1

    it "keeps FrontendSurface support refs at the live-update compatibility boundary" do
        supportSurfaceWireFragments supportCandidateMountedFragments
            `shouldBe`
                [ supportAwardRatesSectionFragmentRef
                , supportPublicHolidaysSectionFragmentRef
                ]

    it "declares live authorization requirements at the surface boundary" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"

        defaultLiveUpdateScopeAuthorizationRequirement SupportPlatformScope `shouldBe` RequireSupportSuperAdmin
        defaultLiveUpdateScopeAuthorizationRequirement AdminXeroScope { venueId } `shouldBe` RequireCurrentVenueOwner venueId

    it "round-trips leave, timesheet, and protected roster surface configs through JSON" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let surfaces =
                [ testLiveSurfaceConfig
                    "leave-requests"
                    LeaveRequestsScope { venueId }
                    [ LiveUpdateWireFragment
                        { fragmentKey = LeaveRequestsContentFragment
                        , targetId = "leave-requests-content"
                        , url = "/ShowLeaveRequestsContentFragment"
                        , deferUntilBlur = False
                        , protectionPolicy = NoProtection
                        }
                    ]
                , testLiveSurfaceConfig
                    "timesheets"
                    TimesheetWeekScope { venueId, weekOffset = 1 }
                    [ LiveUpdateWireFragment
                        { fragmentKey = TimesheetDaySectionFragment { dayOffset = 2 }
                        , targetId = "timesheet-day-2"
                        , url = "/ShowTimesheetDaySectionFragment?weekOffset=1&dayOffset=2"
                        , deferUntilBlur = False
                        , protectionPolicy = NoProtection
                        }
                    ]
                , testLiveSurfaceConfig
                    "roster"
                    RosterWeekScope { venueId, rosterGroupId, weekOffset = 0 }
                    [ LiveUpdateWireFragment
                        { fragmentKey = RosterContentFragment
                        , targetId = "roster-content"
                        , url = "/ShowRosterWeekContentFragment?weekOffset=0"
                        , deferUntilBlur = False
                        , protectionPolicy = NoProtection
                        }
                    ]
                ]

        forM_ surfaces \surface ->
            Aeson.decode (LBS.fromStrict (cs (liveSurfaceConfigJson surface))) `shouldBe` Just surface

testLiveSurfaceConfig :: Text -> LiveUpdateScope -> [LiveUpdateWireFragment] -> LiveSurfaceConfig
testLiveSurfaceConfig feature scope resyncFragments =
    LiveSurfaceConfig
        { feature
        , socketPath = "/live-updates"
        , scope
        , scopeKey = liveUpdateScopeKey scope
        , resyncFragments
        , decorateRequestsWithin = []
        }

supportAwardRatesSectionFragmentRef :: LiveUpdateWireFragment
supportAwardRatesSectionFragmentRef =
    LiveUpdateWireFragment
        { fragmentKey = SupportAwardRatesSectionFragment
        , targetId = "support-award-rates-section"
        , url = "/ShowFwcMapdAwardRatesSection"
        , deferUntilBlur = False
        , protectionPolicy = NoProtection
        }

supportPublicHolidaysSectionFragmentRef :: LiveUpdateWireFragment
supportPublicHolidaysSectionFragmentRef =
    LiveUpdateWireFragment
        { fragmentKey = SupportPublicHolidaysSectionFragment
        , targetId = "support-public-holidays-section"
        , url = "/ShowPublicHolidaysSection"
        , deferUntilBlur = False
        , protectionPolicy = NoProtection
        }

expectUuid :: Text -> UUID.UUID
expectUuid value =
    fromMaybe (error ("Invalid UUID fixture: " <> cs value)) (UUID.fromText value)

supportScopeLabel :: LiveUpdateScope -> Maybe Text
supportScopeLabel SupportPlatformScope = Just "support"
supportScopeLabel _                    = Nothing
