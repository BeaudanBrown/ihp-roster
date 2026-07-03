module Test.LiveUpdateSpec where

import qualified Application.Helper.Frontend.LiveUpdateSchema as Wire
import Application.Helper.FrontendSurface.Authorization (frontendSurfaceScopeAuthorizationRequirement,
                                                         validateFrontendSurfaceLiveSubscription)
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
        let scope = rosterWeekLiveScope venueId rosterGroupId 0
        let fragment =
                LiveUpdateWireFragment
                    { fragmentKey = rosterStaffPanelLiveFragment
                    , targetId = "roster-staff-panel"
                    , url = "/ShowrosterStaffPanelLiveFragment?weekOffset=0"
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
                [ rosterWeekLiveScope venueId rosterGroupId 0
                , adminVenueConfigLiveScope venueId
                , adminShiftTypesLiveScope venueId
                , adminRosterGroupsLiveScope venueId
                , adminInvitesLiveScope venueId
                , adminExportsLiveScope venueId
                , adminXeroLiveScope venueId
                , billingLiveScope venueId
                , leaveRequestsLiveScope venueId
                , timesheetWeekLiveScope venueId 2
                , profileLiveScope venueId staffId
                , supportPlatformLiveScope
                ]

        forM_ scopes \scope ->
            Aeson.decode (Aeson.encode scope) `shouldBe` Just scope

    it "round-trips roster, admin, profile, leave, timesheet, and support fragment keys through JSON" do
        let rosterDayId = expectUuid "22222222-2222-2222-2222-222222222222"
        let fragmentKeys =
                [ rosterContentLiveFragment
                , rosterStaffPanelLiveFragment
                , rosterRowLiveFragment rosterDayId 1
                , leaveRequestsContentLiveFragment
                , timesheetDaySectionLiveFragment 4
                , adminVenueConfigLiveFragment
                , adminInvitesLiveFragment
                , adminExportsLiveFragment
                , adminShiftTypesLiveFragment
                , adminRosterGroupsLiveFragment
                , adminXeroShellLiveFragment
                , adminXeroStaffMappingsLiveFragment
                , adminXeroPayItemsLiveFragment
                , adminXeroTimesheetsLiveFragment
                , billingStatusLiveFragment
                , profileContentLiveFragment
                , profileLeaveRequestsContentLiveFragment
                , supportAwardRatesSectionLiveFragment
                , supportPublicHolidaysSectionLiveFragment
                ]

        forM_ fragmentKeys \fragmentKey ->
            Aeson.decode (Aeson.encode fragmentKey) `shouldBe` Just fragmentKey

    it "keeps wire fragment payloads self-describing for the browser" do
        let rosterDayId = expectUuid "22222222-2222-2222-2222-222222222222"
        let fragment =
                LiveUpdateWireFragment
                    { fragmentKey = rosterRowLiveFragment rosterDayId 2
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

        liveUpdateScopeKey (rosterWeekLiveScope venueId rosterGroupId (-1))
            `shouldBe` "roster:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:-1"
        liveUpdateScopeKey (adminVenueConfigLiveScope venueId)
            `shouldBe` "admin-venue-config:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey (adminShiftTypesLiveScope venueId)
            `shouldBe` "admin-shift-types:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey (adminRosterGroupsLiveScope venueId)
            `shouldBe` "admin-roster-groups:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey (adminInvitesLiveScope venueId)
            `shouldBe` "admin-invites:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey (adminExportsLiveScope venueId)
            `shouldBe` "admin-exports:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey (adminXeroLiveScope venueId)
            `shouldBe` "admin-xero:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey (billingLiveScope venueId)
            `shouldBe` "billing:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey (leaveRequestsLiveScope venueId)
            `shouldBe` "leave-requests:11111111-1111-1111-1111-111111111111"
        liveUpdateScopeKey (timesheetWeekLiveScope venueId 2)
            `shouldBe` "timesheets:11111111-1111-1111-1111-111111111111:2"
        liveUpdateScopeKey (profileLiveScope venueId staffId)
            `shouldBe` "profile:11111111-1111-1111-1111-111111111111:44444444-4444-4444-4444-444444444444"
        liveUpdateScopeKey supportPlatformLiveScope
            `shouldBe` "support"

    it "round-trips commands and encodes subscribed, invalidation, and error payloads as JSON" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let scope = rosterWeekLiveScope venueId rosterGroupId 0
        let fragment =
                LiveUpdateWireFragment
                    { fragmentKey = rosterStaffPanelLiveFragment
                    , targetId = "roster-staff-panel"
                    , url = "/ShowrosterStaffPanelLiveFragment?weekOffset=0"
                    , deferUntilBlur = False
                    , protectionPolicy = NoProtection
                    }
        let subscription =
                LiveUpdateSubscription
                    { subscriptionScope = scope
                    , subscriptionScopeKey = liveUpdateScopeKey scope
                    , subscriptionMountedFragments = [fragment]
                    }
        let commands =
                [ SubscribeLiveUpdates { subscription, clientId = "client-1", lastSeenVersion = Nothing }
                , SubscribeLiveUpdates { subscription, clientId = "client-1", lastSeenVersion = Just 4 }
                , UnsubscribeLiveUpdates { subscription }
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
        let scope = leaveRequestsLiveScope venueId
        let fragment =
                LiveUpdateWireFragment
                    { fragmentKey = leaveRequestsContentLiveFragment
                    , targetId = "leave-requests-content"
                    , url = "/ShowleaveRequestsContentLiveFragment"
                    , deferUntilBlur = False
                    , protectionPolicy = NoProtection
                    }
        firstBus <- newInMemoryLiveBus
        secondBus <- newInMemoryLiveBus

        activeLiveUpdateScopesWithBus firstBus `shouldReturn` []
        activeLiveUpdateSubscriptionsWithBus firstBus `shouldReturn` []
        activeLiveUpdateScopeMatchesWithBus firstBus supportScopeLabel `shouldReturn` []
        activeRosterWeekScopesWithBus firstBus `shouldReturn` []

        let subscription =
                LiveUpdateSubscription
                    { subscriptionScope = scope
                    , subscriptionScopeKey = liveUpdateScopeKey scope
                    , subscriptionMountedFragments = [fragment]
                    }
        registerLiveSubscriptionWithBus firstBus venueId subscription (error "unused websocket connection")
        activeLiveUpdateSubscriptionsWithBus firstBus `shouldReturn` [subscription]
        activeLiveUpdateScopesWithBus firstBus `shouldReturn` [scope]
        unregisterLiveSubscriptionWithBus firstBus venueId
        activeLiveUpdateSubscriptionsWithBus firstBus `shouldReturn` []
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
        let scope = leaveRequestsLiveScope venueId
        let fragment =
                LiveUpdateWireFragment
                    { fragmentKey = leaveRequestsContentLiveFragment
                    , targetId = "leave-requests-content"
                    , url = "/ShowleaveRequestsContentLiveFragment"
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
        let scope = leaveRequestsLiveScope venueId
        let fragment =
                LiveUpdateWireFragment
                    { fragmentKey = leaveRequestsContentLiveFragment
                    , targetId = "leave-requests-content"
                    , url = "/ShowleaveRequestsContentLiveFragment"
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

    it "validates live subscriptions from generated FrontendSurface metadata" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let scope = timesheetWeekLiveScope venueId 0
        let fragment =
                LiveUpdateWireFragment
                    { fragmentKey = timesheetDaySectionLiveFragment 1
                    , targetId = "timesheet-day-1"
                    , url = "/ShowTimesheetDaySectionFragment?weekOffset=0&dayOffset=1"
                    , deferUntilBlur = False
                    , protectionPolicy = NoProtection
                    }
        let subscription =
                LiveUpdateSubscription
                    { subscriptionScope = scope
                    , subscriptionScopeKey = liveUpdateScopeKey scope
                    , subscriptionMountedFragments = [fragment]
                    }

        validateFrontendSurfaceLiveSubscription subscription `shouldBe` True
        validateFrontendSurfaceLiveSubscription subscription { subscriptionScopeKey = "timesheets:wrong" } `shouldBe` False
        validateFrontendSurfaceLiveSubscription subscription { subscriptionMountedFragments = [fragment { fragmentKey = leaveRequestsContentLiveFragment }] } `shouldBe` False
        validateFrontendSurfaceLiveSubscription subscription { subscriptionMountedFragments = [fragment { fragmentKey = timesheetToolbarLiveFragment }] } `shouldBe` True

    it "declares live authorization requirements at the surface boundary" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"

        defaultLiveUpdateScopeAuthorizationRequirement supportPlatformLiveScope `shouldBe` RequireSupportSuperAdmin
        defaultLiveUpdateScopeAuthorizationRequirement (adminXeroLiveScope venueId) `shouldBe` RequireCurrentVenueOwner venueId
        frontendSurfaceScopeAuthorizationRequirement supportPlatformLiveScope `shouldBe` Just (Just RequireSupportSuperAdmin)
        frontendSurfaceScopeAuthorizationRequirement (adminXeroLiveScope venueId) `shouldBe` Just (Just (RequireCurrentVenueOwner venueId))
        frontendSurfaceScopeAuthorizationRequirement (timesheetWeekLiveScope venueId 0) `shouldBe` Just (Just (RequireCurrentVenue venueId))

    it "round-trips leave, timesheet, and protected roster surface configs through JSON" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let surfaces =
                [ testLiveSurfaceConfig
                    "leave-requests"
                    (leaveRequestsLiveScope venueId)
                    [ LiveUpdateWireFragment
                        { fragmentKey = leaveRequestsContentLiveFragment
                        , targetId = "leave-requests-content"
                        , url = "/ShowleaveRequestsContentLiveFragment"
                        , deferUntilBlur = False
                        , protectionPolicy = NoProtection
                        }
                    ]
                , testLiveSurfaceConfig
                    "timesheets"
                    (timesheetWeekLiveScope venueId 1)
                    [ LiveUpdateWireFragment
                        { fragmentKey = timesheetDaySectionLiveFragment 2
                        , targetId = "timesheet-day-2"
                        , url = "/ShowTimesheetDaySectionFragment?weekOffset=1&dayOffset=2"
                        , deferUntilBlur = False
                        , protectionPolicy = NoProtection
                        }
                    ]
                , testLiveSurfaceConfig
                    "roster"
                    (rosterWeekLiveScope venueId rosterGroupId 0)
                    [ LiveUpdateWireFragment
                        { fragmentKey = rosterContentLiveFragment
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
        { fragmentKey = supportAwardRatesSectionLiveFragment
        , targetId = "support-award-rates-section"
        , url = "/ShowFwcMapdAwardRatesSection"
        , deferUntilBlur = False
        , protectionPolicy = NoProtection
        }

supportPublicHolidaysSectionFragmentRef :: LiveUpdateWireFragment
supportPublicHolidaysSectionFragmentRef =
    LiveUpdateWireFragment
        { fragmentKey = supportPublicHolidaysSectionLiveFragment
        , targetId = "support-public-holidays-section"
        , url = "/ShowPublicHolidaysSection"
        , deferUntilBlur = False
        , protectionPolicy = NoProtection
        }

expectUuid :: Text -> UUID.UUID
expectUuid value =
    fromMaybe (error ("Invalid UUID fixture: " <> cs value)) (UUID.fromText value)

supportScopeLabel :: LiveUpdateScope -> Maybe Text
supportScopeLabel supportPlatformLiveScope = Just "support"
supportScopeLabel _                        = Nothing
