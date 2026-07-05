{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Test.LiveUpdateSpec where

import Application.Helper.FrontendContract.Surface.Authorization (frontendSurfaceScopeAuthorizationRequirement,
                                                                  validateFrontendSurfaceLiveSubscription)
import Application.Helper.FrontendContract.Surface.AuthorizationRequirement (SurfaceScopeAuthorizationRequirement (..))
import Application.Helper.FrontendContract.Wire.Json (validateContractValue,
                                                      validateSurfaceFragmentKeyValue,
                                                      validateSurfaceScopeValue)
import qualified Application.Helper.FrontendContract.Wire.LiveUpdate as Wire
import Application.Helper.LiveUpdate.Runtime
import Application.Support.LiveUpdates
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Lazy as LBS
import Data.Either (isLeft, isRight)
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
                SurfaceWireFragment
                    { fragmentKey = rosterStaffPanelLiveFragment
                    , targetId = "roster-staff-panel"
                    , url = "/ShowrosterStaffPanelLiveFragment?weekOffset=0"
                    , deferUntilBlur = False
                    , protectionPolicy = NoProtection
                    }
        let message =
                LiveUpdatesInvalidated
                    { scope
                    , scopeKey = surfaceScopeKey scope
                    , version = 6
                    , fragments = [fragment]
                    , sourceClientId = Just "client-1"
                    }
        Aeson.toJSON scope `shouldBe` Aeson.toJSON (surfaceScopeToWire scope)
        Aeson.toJSON fragment `shouldBe` Aeson.toJSON (surfaceWireFragmentToWire fragment)
        Aeson.toJSON message
            `shouldBe`
                Aeson.toJSON
                    (Wire.Invalidate (surfaceScopeToWire scope) (surfaceScopeKey scope) 6 [surfaceWireFragmentToWire fragment] (Just "client-1"))

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
                SurfaceWireFragment
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

        surfaceScopeKey (rosterWeekLiveScope venueId rosterGroupId (-1))
            `shouldBe` "roster:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:-1"
        surfaceScopeKey (adminVenueConfigLiveScope venueId)
            `shouldBe` "admin-venue-config:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (adminShiftTypesLiveScope venueId)
            `shouldBe` "admin-shift-types:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (adminRosterGroupsLiveScope venueId)
            `shouldBe` "admin-roster-groups:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (adminInvitesLiveScope venueId)
            `shouldBe` "admin-invites:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (adminExportsLiveScope venueId)
            `shouldBe` "admin-exports:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (adminXeroLiveScope venueId)
            `shouldBe` "admin-xero:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (billingLiveScope venueId)
            `shouldBe` "billing:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (leaveRequestsLiveScope venueId)
            `shouldBe` "leave-requests:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (timesheetWeekLiveScope venueId 2)
            `shouldBe` "timesheets:11111111-1111-1111-1111-111111111111:2"
        surfaceScopeKey (profileLiveScope venueId staffId)
            `shouldBe` "profile:11111111-1111-1111-1111-111111111111:44444444-4444-4444-4444-444444444444"
        surfaceScopeKey supportPlatformLiveScope
            `shouldBe` "support"

    it "rejects unknown fields when decoding live-update wire carrier types directly" do
        let scope = Wire.SurfaceScope "timesheets" (Aeson.object ["venueId" Aeson..= ("11111111-1111-1111-1111-111111111111" :: Text), "weekOffset" Aeson..= (4 :: Int)])
        let fragmentKey = Wire.SurfaceFragmentKey "timesheets" "timesheet-day-section" (Aeson.object ["dayOffset" Aeson..= (2 :: Int)])
        let protection = Wire.FocusedFieldProtection ".timesheet-input:focus" "data-field-key" True (Just ".timesheet-row")
        let focusedConfig = Wire.FocusedFieldProtectionConfig ".timesheet-input:focus" "data-field-key" True (Just ".timesheet-row")
        let fragment = Wire.SurfaceWireFragment fragmentKey "timesheet-day-2" "/TimesheetDay?offset=2" True protection
        let subscription = Wire.SurfaceSubscription scope "timesheets:11111111-1111-1111-1111-111111111111:4" [fragment]
        let command = Wire.Subscribe subscription "client-1" (Just 9)
        let message = Wire.Invalidate scope subscription.scopeKey 10 [fragment] (Just "client-2")

        decodeValueAs @Wire.SurfaceScope (addJsonField "extra" (Aeson.Bool True) (Aeson.toJSON scope)) `shouldSatisfy` isLeft
        decodeValueAs @Wire.SurfaceFragmentKey (addJsonField "extra" (Aeson.Bool True) (Aeson.toJSON fragmentKey)) `shouldSatisfy` isLeft
        decodeValueAs @Wire.FocusedFieldProtectionConfig (addJsonField "extra" (Aeson.Bool True) (Aeson.toJSON focusedConfig)) `shouldSatisfy` isLeft
        decodeValueAs @Wire.SurfaceFragmentProtection (addJsonField "extra" (Aeson.Bool True) (Aeson.toJSON protection)) `shouldSatisfy` isLeft
        decodeValueAs @Wire.SurfaceWireFragment (addJsonField "extra" (Aeson.Bool True) (Aeson.toJSON fragment)) `shouldSatisfy` isLeft
        decodeValueAs @Wire.SurfaceSubscription (addJsonField "extra" (Aeson.Bool True) (Aeson.toJSON subscription)) `shouldSatisfy` isLeft
        decodeValueAs @Wire.LiveUpdateCommand (addJsonField "extra" (Aeson.Bool True) (Aeson.toJSON command)) `shouldSatisfy` isLeft
        decodeValueAs @Wire.LiveUpdateMessage (addJsonField "extra" (Aeson.Bool True) (Aeson.toJSON message)) `shouldSatisfy` isLeft

    it "validates every live-update wire carrier constructor against FrontendContract IR on encode" do
        let scope = Wire.SurfaceScope "timesheets" (Aeson.object ["venueId" Aeson..= ("11111111-1111-1111-1111-111111111111" :: Text), "weekOffset" Aeson..= (4 :: Int)])
        let fragmentKey = Wire.SurfaceFragmentKey "timesheets" "timesheet-day-section" (Aeson.object ["dayOffset" Aeson..= (2 :: Int)])
        let noProtection = Wire.NoProtection
        let focusedProtection = Wire.FocusedFieldProtection ".timesheet-input:focus" "data-field-key" True (Just ".timesheet-row")
        let fragment protection = Wire.SurfaceWireFragment fragmentKey "timesheet-day-2" "/TimesheetDay?offset=2" True protection
        let subscription protection = Wire.SurfaceSubscription scope "timesheets:11111111-1111-1111-1111-111111111111:4" [fragment protection]
        let commands =
                [ Wire.Subscribe (subscription noProtection) "client-1" Nothing
                , Wire.Subscribe (subscription focusedProtection) "client-1" (Just 9)
                , Wire.Unsubscribe (subscription noProtection)
                ]
        let messages =
                [ Wire.Subscribed scope "timesheets:11111111-1111-1111-1111-111111111111:4" 10 False
                , Wire.Invalidate scope "timesheets:11111111-1111-1111-1111-111111111111:4" 11 [fragment noProtection, fragment focusedProtection] (Just "client-2")
                , Wire.Error "Not authorized"
                ]

        AesonTypes.parseEither validateSurfaceScopeValue (Aeson.toJSON scope) `shouldSatisfy` isRight
        AesonTypes.parseEither validateSurfaceFragmentKeyValue (Aeson.toJSON fragmentKey) `shouldSatisfy` isRight
        forM_ [noProtection, focusedProtection] \value -> AesonTypes.parseEither (validateContractValue "SurfaceFragmentProtection") (Aeson.toJSON value) `shouldSatisfy` isRight
        forM_ [fragment noProtection, fragment focusedProtection] \value -> AesonTypes.parseEither (validateContractValue "SurfaceWireFragment") (Aeson.toJSON value) `shouldSatisfy` isRight
        forM_ [subscription noProtection, subscription focusedProtection] \value -> AesonTypes.parseEither (validateContractValue "SurfaceSubscription") (Aeson.toJSON value) `shouldSatisfy` isRight
        forM_ commands \value -> AesonTypes.parseEither (validateContractValue "LiveUpdateCommand") (Aeson.toJSON value) `shouldSatisfy` isRight
        forM_ messages \value -> AesonTypes.parseEither (validateContractValue "LiveUpdateMessage") (Aeson.toJSON value) `shouldSatisfy` isRight

    it "round-trips commands and encodes subscribed, invalidation, and error payloads as JSON" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let scope = rosterWeekLiveScope venueId rosterGroupId 0
        let fragment =
                SurfaceWireFragment
                    { fragmentKey = rosterStaffPanelLiveFragment
                    , targetId = "roster-staff-panel"
                    , url = "/ShowrosterStaffPanelLiveFragment?weekOffset=0"
                    , deferUntilBlur = False
                    , protectionPolicy = NoProtection
                    }
        let subscription =
                SurfaceSubscription
                    { subscriptionScope = scope
                    , subscriptionScopeKey = surfaceScopeKey scope
                    , subscriptionMountedFragments = [fragment]
                    }
        let commands =
                [ SubscribeLiveUpdates { subscription, clientId = "client-1", lastSeenVersion = Nothing }
                , SubscribeLiveUpdates { subscription, clientId = "client-1", lastSeenVersion = Just 4 }
                , UnsubscribeLiveUpdates { subscription }
                ]
        let messages =
                [ LiveUpdatesSubscribed { scope, scopeKey = surfaceScopeKey scope, currentVersion = 4, resync = False }
                , LiveUpdatesSubscribed { scope, scopeKey = surfaceScopeKey scope, currentVersion = 5, resync = True }
                , LiveUpdatesInvalidated { scope, scopeKey = surfaceScopeKey scope, version = 6, fragments = [fragment], sourceClientId = Just "client-1" }
                , LiveUpdatesInvalidated { scope, scopeKey = surfaceScopeKey scope, version = 7, fragments = [], sourceClientId = Nothing }
                , LiveUpdatesError { message = "Not authorized for requested live update scope" }
                ]

        forM_ commands \command ->
            Aeson.decode (Aeson.encode command) `shouldBe` Just command
        forM_ messages \message ->
            (Aeson.decode (Aeson.encode message) :: Maybe Aeson.Value) `shouldSatisfy` isJust

        let encodedSubscribed = cs (LBS.toStrict (Aeson.encode (LiveUpdatesSubscribed { scope, scopeKey = surfaceScopeKey scope, currentVersion = 4, resync = False }))) :: Text
        let encodedInvalidated = cs (LBS.toStrict (Aeson.encode (LiveUpdatesInvalidated { scope, scopeKey = surfaceScopeKey scope, version = 6, fragments = [fragment], sourceClientId = Nothing }))) :: Text
        encodedSubscribed `shouldSatisfy` Text.isInfixOf "\"scopeKey\":\"roster:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:0\""
        encodedInvalidated `shouldSatisfy` Text.isInfixOf "\"scopeKey\":\"roster:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:0\""

    it "exposes active live scopes without leaking websocket subscription internals" do
        activeSurfaceScopes `shouldReturn` []
        activeSurfaceScopeMatches supportScopeLabel `shouldReturn` []
        activeRosterWeekScopes `shouldReturn` []

    it "exercises isolated in-memory live buses without global state leakage" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let scope = leaveRequestsLiveScope venueId
        let fragment =
                SurfaceWireFragment
                    { fragmentKey = leaveRequestsContentLiveFragment
                    , targetId = "leave-requests-content"
                    , url = "/ShowleaveRequestsContentLiveFragment"
                    , deferUntilBlur = False
                    , protectionPolicy = NoProtection
                    }
        firstBus <- newInMemoryLiveBus
        secondBus <- newInMemoryLiveBus

        activeSurfaceScopesWithBus firstBus `shouldReturn` []
        activeSurfaceSubscriptionsWithBus firstBus `shouldReturn` []
        activeSurfaceScopeMatchesWithBus firstBus supportScopeLabel `shouldReturn` []
        activeRosterWeekScopesWithBus firstBus `shouldReturn` []

        let subscription =
                SurfaceSubscription
                    { subscriptionScope = scope
                    , subscriptionScopeKey = surfaceScopeKey scope
                    , subscriptionMountedFragments = [fragment]
                    }
        registerSurfaceSubscriptionWithBus firstBus venueId subscription (error "unused websocket connection")
        activeSurfaceSubscriptionsWithBus firstBus `shouldReturn` [subscription]
        activeSurfaceScopesWithBus firstBus `shouldReturn` [scope]
        unregisterSurfaceSubscriptionWithBus firstBus venueId
        activeSurfaceSubscriptionsWithBus firstBus `shouldReturn` []
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
                SurfaceWireFragment
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
                SurfaceWireFragment
                    { fragmentKey = leaveRequestsContentLiveFragment
                    , targetId = "leave-requests-content"
                    , url = "/ShowleaveRequestsContentLiveFragment"
                    , deferUntilBlur = False
                    , protectionPolicy = NoProtection
                    }

        coalesceSurfaceWireFragments [fragment, fragment] `shouldBe` [fragment]
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
                SurfaceWireFragment
                    { fragmentKey = timesheetDaySectionLiveFragment 1
                    , targetId = "timesheet-day-1"
                    , url = "/ShowTimesheetDaySectionFragment?weekOffset=0&dayOffset=1"
                    , deferUntilBlur = False
                    , protectionPolicy = NoProtection
                    }
        let subscription =
                SurfaceSubscription
                    { subscriptionScope = scope
                    , subscriptionScopeKey = surfaceScopeKey scope
                    , subscriptionMountedFragments = [fragment]
                    }

        validateFrontendSurfaceLiveSubscription subscription `shouldBe` True
        validateFrontendSurfaceLiveSubscription subscription { subscriptionScopeKey = "timesheets:wrong" } `shouldBe` False
        validateFrontendSurfaceLiveSubscription subscription { subscriptionMountedFragments = [fragment { fragmentKey = leaveRequestsContentLiveFragment }] } `shouldBe` False
        validateFrontendSurfaceLiveSubscription subscription { subscriptionMountedFragments = [fragment { fragmentKey = timesheetToolbarLiveFragment }] } `shouldBe` True

    it "declares live authorization requirements at the surface boundary" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"

        frontendSurfaceScopeAuthorizationRequirement supportPlatformLiveScope `shouldBe` Just (Just RequireSupportSuperAdmin)
        frontendSurfaceScopeAuthorizationRequirement (adminXeroLiveScope venueId) `shouldBe` Just (Just (RequireCurrentVenueOwner venueId))
        frontendSurfaceScopeAuthorizationRequirement (timesheetWeekLiveScope venueId 0) `shouldBe` Just (Just (RequireCurrentVenue venueId))

supportAwardRatesSectionFragmentRef :: SurfaceWireFragment
supportAwardRatesSectionFragmentRef =
    SurfaceWireFragment
        { fragmentKey = supportAwardRatesSectionLiveFragment
        , targetId = "support-award-rates-section"
        , url = "/ShowFwcMapdAwardRatesSection"
        , deferUntilBlur = False
        , protectionPolicy = NoProtection
        }

supportPublicHolidaysSectionFragmentRef :: SurfaceWireFragment
supportPublicHolidaysSectionFragmentRef =
    SurfaceWireFragment
        { fragmentKey = supportPublicHolidaysSectionLiveFragment
        , targetId = "support-public-holidays-section"
        , url = "/ShowPublicHolidaysSection"
        , deferUntilBlur = False
        , protectionPolicy = NoProtection
        }

decodeValueAs :: forall value. Aeson.FromJSON value => Aeson.Value -> Either String value
decodeValueAs value = Aeson.eitherDecode (Aeson.encode value)

addJsonField :: Text -> Aeson.Value -> Aeson.Value -> Aeson.Value
addJsonField name value = \case
    Aeson.Object object -> Aeson.Object (KeyMap.insert (AesonKey.fromText name) value object)
    other               -> other

expectUuid :: Text -> UUID.UUID
expectUuid value =
    fromMaybe (error ("Invalid UUID fixture: " <> cs value)) (UUID.fromText value)

supportScopeLabel :: SurfaceScope -> Maybe Text
supportScopeLabel supportPlatformLiveScope = Just "support"
supportScopeLabel _                        = Nothing
