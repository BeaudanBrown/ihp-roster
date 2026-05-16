module Test.LiveUpdateSpec where

import Application.Helper.LiveSurface
import Application.Helper.LiveSurface.Internal (defaultLiveUpdateScopeAuthorizationRequirement)
import Application.Helper.LiveUpdate.Internal
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
        let userId = expectUuid "44444444-4444-4444-4444-444444444444"
        let scopes =
                [ RosterWeekScope { venueId, rosterGroupId, weekOffset = 0 }
                , AdminShiftTypesScope { venueId }
                , AdminRosterGroupsScope { venueId }
                , AdminInvitesScope { venueId }
                , AdminExportsScope { venueId }
                , AdminXeroScope { venueId }
                , BillingScope { venueId }
                , LeaveRequestsScope { venueId }
                , TimesheetWeekScope { venueId, weekOffset = 2 }
                , ProfileScope { venueId, userId }
                , StaffComplianceScope { venueId }
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
                , StaffComplianceFragment
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
                        [ "kind" Aeson..= ("roster_row" :: Text)
                        , "rosterDayId" Aeson..= UUID.toText rosterDayId
                        , "rowIndex" Aeson..= (2 :: Int)
                        ]
                    , "targetId" Aeson..= ("roster-row-2" :: Text)
                    , "url" Aeson..= ("/ShowRosterWeekRowFragment?weekOffset=0&rowIndex=2" :: Text)
                    , "deferUntilBlur" Aeson..= True
                    , "protectionPolicy" Aeson..= NoProtection
                    ]

    it "uses stable live scope keys for client/server subscription matching" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let userId = expectUuid "44444444-4444-4444-4444-444444444444"

        liveUpdateScopeKey RosterWeekScope { venueId, rosterGroupId, weekOffset = -1 }
            `shouldBe` "roster_week:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:-1"
        liveUpdateScopeKey AdminShiftTypesScope { venueId }
            `shouldBe` "admin_shift_types:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey AdminRosterGroupsScope { venueId }
            `shouldBe` "admin_roster_groups:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey AdminInvitesScope { venueId }
            `shouldBe` "admin_invites:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey AdminExportsScope { venueId }
            `shouldBe` "admin_exports:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey AdminXeroScope { venueId }
            `shouldBe` "admin_xero:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey BillingScope { venueId }
            `shouldBe` "billing:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey LeaveRequestsScope { venueId }
            `shouldBe` "leave_requests:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey TimesheetWeekScope { venueId, weekOffset = 2 }
            `shouldBe` "timesheet_week:11111111-1111-1111-1111-111111111111:2"
        liveUpdateScopeKey ProfileScope { venueId, userId }
            `shouldBe` "profile:11111111-1111-1111-1111-111111111111:44444444-4444-4444-4444-444444444444"
        liveUpdateScopeKey StaffComplianceScope { venueId }
            `shouldBe` "staff_compliance:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey SupportPlatformScope
            `shouldBe` "support_platform"

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
        encodedSubscribed `shouldSatisfy` Text.isInfixOf "\"scopeKey\":\"roster_week:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:0\""
        encodedInvalidated `shouldSatisfy` Text.isInfixOf "\"scopeKey\":\"roster_week:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:0\""

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

    it "encodes support live surface config with stable JSON" do
        let surface = mkTypedDefinedLiveSurface supportLiveSurfaceDefinition ()

        liveSurfaceConfigJson surface
            `shouldBe` "{\"decorateRequestsWithin\":[\"#support-shell\",\"#support-award-rates-section\",\"#support-public-holidays-section\"],\"feature\":\"support\",\"resyncFragments\":[{\"deferUntilBlur\":false,\"fragmentKey\":{\"kind\":\"support_award_rates_section\"},\"protectionPolicy\":null,\"targetId\":\"support-award-rates-section\",\"url\":\"/ShowFwcMapdAwardRatesSection\"},{\"deferUntilBlur\":false,\"fragmentKey\":{\"kind\":\"support_public_holidays_section\"},\"protectionPolicy\":null,\"targetId\":\"support-public-holidays-section\",\"url\":\"/ShowPublicHolidaysSection\"}],\"scope\":{\"kind\":\"support_platform\"},\"scopeKey\":\"support_platform\",\"socketPath\":\"/live-updates\"}"

    it "keeps typed support surface refs at the compatibility boundary" do
        let typedRefs = typedLiveSurfaceFragmentRefs supportLiveSurfaceDefinition () supportLiveFragmentRefs

        unSurfaceFragmentRefs typedRefs
            `shouldBe`
                [ supportAwardRatesSectionFragmentRef
                , supportPublicHolidaysSectionFragmentRef
                ]
        supportLiveSurface
            `shouldBe` mkTypedDefinedLiveSurface supportLiveSurfaceDefinition ()

    it "declares live authorization requirements at the surface boundary" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"

        typedSurfaceScopeFromWire supportLiveSurfaceDefinition SupportPlatformScope `shouldBe` Just ()
        typedSurfaceScopeFromWire supportLiveSurfaceDefinition (LeaveRequestsScope { venueId }) `shouldBe` Nothing
        defaultLiveUpdateScopeAuthorizationRequirement SupportPlatformScope `shouldBe` RequireSupportSuperAdmin
        defaultLiveUpdateScopeAuthorizationRequirement AdminXeroScope { venueId } `shouldBe` RequireCurrentVenueOwner venueId

    it "derives actor and passive refs for typed live mutations" do
        let mutation =
                LiveSurfaceMutation
                    { liveMutationScope = ()
                    , liveMutationActorFragments = [SupportAwardRatesLiveFragment]
                    , liveMutationPassiveFragments = [SupportPublicHolidaysLiveFragment]
                    }
        let (actorRefs, passiveRefs) = typedLiveSurfaceMutationRefs supportLiveSurfaceDefinition mutation

        unSurfaceFragmentRefs actorRefs `shouldBe` [supportAwardRatesSectionFragmentRef]
        unSurfaceFragmentRefs passiveRefs `shouldBe` [supportPublicHolidaysSectionFragmentRef]

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
    case unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs supportLiveSurfaceDefinition () [SupportAwardRatesLiveFragment]) of
        [fragmentRef] -> fragmentRef
        _             -> error "Expected one support award rates fragment ref"

supportPublicHolidaysSectionFragmentRef :: LiveUpdateWireFragment
supportPublicHolidaysSectionFragmentRef =
    case unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs supportLiveSurfaceDefinition () [SupportPublicHolidaysLiveFragment]) of
        [fragmentRef] -> fragmentRef
        _             -> error "Expected one support public holidays fragment ref"

expectUuid :: Text -> UUID.UUID
expectUuid value =
    fromMaybe (error ("Invalid UUID fixture: " <> cs value)) (UUID.fromText value)

supportScopeLabel :: LiveUpdateScope -> Maybe Text
supportScopeLabel SupportPlatformScope = Just "support"
supportScopeLabel _                    = Nothing
