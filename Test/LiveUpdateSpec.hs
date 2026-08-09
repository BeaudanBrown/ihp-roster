{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Test.LiveUpdateSpec where

import qualified Application.Helper.FrontendContract.App as AppContract
import Application.Helper.FrontendContract.AppValues (AppEvents (..),
                                                      canonicalAppEvents)
import qualified Application.Helper.FrontendContract.LiveUpdate as LiveContract
import qualified Application.Helper.FrontendContract.Surface.Admin.Live as AdminLive
import Application.Helper.FrontendContract.Surface.Authorization (frontendSurfaceScopeAuthorizationRequirement,
                                                                  validateFrontendSurfaceLiveSubscription)
import Application.Helper.FrontendContract.Surface.AuthorizationRequirement (SurfaceScopeAuthorizationRequirement (..))
import qualified Application.Helper.FrontendContract.Surface.Billing.Live as BillingLive
import Application.Helper.FrontendContract.Surface.LeaveRequests (LeaveSectionValue (..))
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests.Live as LeaveLive
import Application.Helper.FrontendContract.Surface.Live (frontendSurfaceFragmentKey,
                                                         frontendSurfaceScope,
                                                         matchFrontendSurfaceFragmentKey,
                                                         matchFrontendSurfaceScope)
import qualified Application.Helper.FrontendContract.Surface.Profile.Live as ProfileLive
import qualified Application.Helper.FrontendContract.Surface.Roster.Live as RosterLive
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountConfig (..),
                                                            SurfaceImpl (..))
import qualified Application.Helper.FrontendContract.Surface.Support.Live as SupportLive
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Live as TimesheetsLive
import Application.Helper.FrontendContract.Surface.Values (SurfaceFields,
                                                           noSurfaceFields,
                                                           surfaceField, (&:))
import Application.Helper.FrontendContract.Wire.Json (validateContractMarkerValue,
                                                      validateSurfaceFragmentKeyValue,
                                                      validateSurfaceScopeValue)
import qualified Application.Helper.FrontendContract.Wire.LiveUpdate as Wire
import Application.Helper.LiveUpdate (actorLiveFragmentsRefreshTriggerPayload)
import Application.Helper.LiveUpdate.Runtime
import Application.Support.LiveUpdates
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Lazy as LBS
import Data.Either (isLeft, isRight)
import qualified Data.Text as Text
import Data.Time.Calendar (addDays, fromGregorian)
import qualified Data.UUID as UUID
import IHP.Prelude
import Test.Hspec
import Test.Support (testAnchorForOffset)
import qualified Web.Admin.FrontendSurface as AdminSurface

tests :: Spec
tests = describe "LiveUpdate runtime types" do
    it "constructs and matches declaration-complete typed live identities" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let scope =
                frontendSurfaceScope @Timesheets.TimesheetsSurface @Timesheets.TimesheetWeek
                    ( surfaceField @Timesheets.VenueId venueId
                        &: surfaceField @Timesheets.WindowStartDate (fromGregorian 2025 2 3)
                        &: surfaceField @Timesheets.WindowEndDate (fromGregorian 2025 2 10)
                        &: surfaceField @Timesheets.RosterCalendarRevision 4
                        &: noSurfaceFields
                    )
        let fragmentKey =
                frontendSurfaceFragmentKey @Timesheets.TimesheetsSurface @Timesheets.TimesheetDaySection
                    (surfaceField @Timesheets.OperationalDate (fromGregorian 2025 2 5) &: noSurfaceFields)

        matchFrontendSurfaceScope @Timesheets.TimesheetsSurface @Timesheets.TimesheetWeek scope
            `shouldBe` Just (venueId, (fromGregorian 2025 2 3, (fromGregorian 2025 2 10, (4, ()))))
        matchFrontendSurfaceFragmentKey @Timesheets.TimesheetsSurface @Timesheets.TimesheetDaySection fragmentKey
            `shouldBe` Just (fromGregorian 2025 2 5, ())
        matchFrontendSurfaceFragmentKey @Timesheets.TimesheetsSurface @Timesheets.TimesheetToolbar fragmentKey
            `shouldBe` Nothing

    it "matches generated zero-field and parameterized Live fragments through the curated facade" do
        let parameterized = TimesheetsLive.timesheetDaySectionLiveFragment (addDays 2 (testAnchorForOffset 0))

        TimesheetsLive.matchTimesheetDaySectionLiveFragment parameterized
            `shouldBe` Just (addDays 2 (testAnchorForOffset 0), ())
        TimesheetsLive.matchTimesheetToolbarLiveFragment TimesheetsLive.timesheetToolbarLiveFragment
            `shouldBe` Just ()
        TimesheetsLive.matchTimesheetDayColumnsLiveFragment TimesheetsLive.timesheetDayColumnsLiveFragment
            `shouldBe` Just ()
        TimesheetsLive.matchTimesheetToolbarLiveFragment parameterized
            `shouldBe` Nothing

    it "encodes websocket invalidations with semantic fragment keys only" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let scope = RosterLive.rosterWeekLiveScope venueId rosterGroupId (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1
        let fragmentKey = RosterLive.rosterStaffPanelLiveFragment
        let message =
                LiveUpdatesInvalidated
                    { scope
                    , scopeKey = surfaceScopeKey scope
                    , version = 6
                    , fragments = [fragmentKey]
                    , sourceClientId = Just "client-1"
                    }
        let encoded = Aeson.toJSON message
        Aeson.toJSON scope `shouldBe` Aeson.toJSON (surfaceScopeToWire scope)
        encoded
            `shouldBe`
                Aeson.toJSON
                    (Wire.Invalidate (surfaceScopeToWire scope) (surfaceScopeKey scope) 6 [surfaceFragmentKeyToWire fragmentKey] (Just "client-1"))
        let encodedText = cs (LBS.toStrict (Aeson.encode encoded)) :: Text
        encodedText `shouldNotSatisfy` Text.isInfixOf "targetId"
        encodedText `shouldNotSatisfy` Text.isInfixOf "url"
        encodedText `shouldNotSatisfy` Text.isInfixOf "protectionPolicy"

    it "encodes actor-local refresh instructions with the websocket fragment-key type" do
        let fragmentKey = AdminLive.adminXeroShellLiveFragment
        let scope = AdminLive.adminXeroLiveScope (expectUuid "11111111-1111-1111-1111-111111111111")
        actorLiveFragmentsRefreshTriggerPayload scope [fragmentKey, fragmentKey]
            `shouldBe`
                Aeson.object
                    [ AesonKey.fromText canonicalAppEvents.appLiveFragmentsRefreshEventName Aeson..= Wire.LiveFragmentsRefreshEventDetail
                        { Wire.scope = surfaceScopeToWire scope
                        , Wire.scopeKey = surfaceScopeKey scope
                        , Wire.fragments = [surfaceFragmentKeyToWire fragmentKey]
                        }
                    ]

    it "round-trips roster, admin, leave, timesheet, and support scopes through JSON" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let staffId = expectUuid "44444444-4444-4444-4444-444444444444"
        let scopes =
                [ RosterLive.rosterWeekLiveScope venueId rosterGroupId (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1
                , AdminLive.adminVenueConfigLiveScope venueId
                , AdminLive.adminShiftTypesLiveScope venueId
                , AdminLive.adminRosterGroupsLiveScope venueId
                , AdminLive.adminInvitesLiveScope venueId
                , AdminLive.adminExportsLiveScope venueId
                , AdminLive.adminXeroLiveScope venueId
                , BillingLive.billingVenueLiveScope venueId
                , LeaveLive.leaveRequestsLiveScope venueId
                , TimesheetsLive.timesheetWeekLiveScope venueId (testAnchorForOffset 2) (addDays 7 (testAnchorForOffset 2)) 1
                , ProfileLive.profileLiveScope venueId staffId
                , SupportLive.supportPlatformLiveScope
                ]

        forM_ scopes \scope ->
            Aeson.decode (Aeson.encode scope) `shouldBe` Just scope

    it "round-trips roster, admin, profile, leave, timesheet, and support fragment keys through JSON" do
        let rosterDayId = expectUuid "22222222-2222-2222-2222-222222222222"
        let fragmentKeys =
                [ RosterLive.rosterContentLiveFragment
                , RosterLive.rosterStaffPanelLiveFragment
                , RosterLive.rosterRowLiveFragment rosterDayId 1
                , leavePendingCountLiveFragment
                , TimesheetsLive.timesheetDaySectionLiveFragment (addDays 4 (testAnchorForOffset 0))
                , AdminLive.adminVenueSettingsLiveFragment
                , AdminLive.adminInvitesLiveFragment
                , AdminLive.adminExportsLiveFragment
                , AdminLive.adminShiftTypesLiveFragment
                , AdminLive.adminRosterGroupsLiveFragment
                , AdminLive.adminXeroShellLiveFragment
                , AdminLive.adminXeroReferenceSyncLiveFragment
                , BillingLive.billingStatusLiveFragment
                , ProfileLive.profileDetailsSectionLiveFragment
                , SupportLive.supportAwardRatesLiveFragment
                , SupportLive.supportPublicHolidaysLiveFragment
                ]

        forM_ fragmentKeys \fragmentKey ->
            Aeson.decode (Aeson.encode fragmentKey) `shouldBe` Just fragmentKey

    it "pins the canonical scope JSON boundary across generated adapter migration" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let scope = RosterLive.rosterWeekLiveScope venueId rosterGroupId (testAnchorForOffset (-1)) (addDays 7 (testAnchorForOffset (-1))) 1

        Aeson.toJSON scope
            `shouldBe`
                Aeson.object
                    [ "surface" Aeson..= ("roster" :: Text)
                    , "scope" Aeson..= Aeson.object
                        [ "venueId" Aeson..= UUID.toText venueId
                        , "rosterGroupId" Aeson..= UUID.toText rosterGroupId
                        , "windowStartDate" Aeson..= ("2024-12-30" :: Text)
                        , "windowEndDate" Aeson..= ("2025-01-06" :: Text)
                        , "rosterCalendarRevision" Aeson..= (1 :: Int)
                        ]
                    ]

    it "pins the canonical fragment-key JSON boundary across generated adapter migration" do
        let rosterDayId = expectUuid "22222222-2222-2222-2222-222222222222"
        let fragmentKey = RosterLive.rosterRowLiveFragment rosterDayId 2

        Aeson.toJSON fragmentKey
            `shouldBe`
                Aeson.object
                    [ "surface" Aeson..= ("roster" :: Text)
                    , "kind" Aeson..= ("roster-row" :: Text)
                    , "params" Aeson..= Aeson.object
                        [ "rosterDayId" Aeson..= UUID.toText rosterDayId
                        , "rowIndex" Aeson..= (2 :: Int)
                        ]
                    ]

    it "pins stable scope keys across generated adapter migration" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let staffId = expectUuid "44444444-4444-4444-4444-444444444444"

        surfaceScopeKey (RosterLive.rosterWeekLiveScope venueId rosterGroupId (testAnchorForOffset (-1)) (addDays 7 (testAnchorForOffset (-1))) 1)
            `shouldBe` "roster:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:2024-12-30:2025-01-06:1"
        surfaceScopeKey (AdminLive.adminVenueConfigLiveScope venueId)
            `shouldBe` "admin-venue-config:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (AdminLive.adminShiftTypesLiveScope venueId)
            `shouldBe` "admin-shift-types:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (AdminLive.adminRosterGroupsLiveScope venueId)
            `shouldBe` "admin-roster-groups:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (AdminLive.adminInvitesLiveScope venueId)
            `shouldBe` "admin-invites:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (AdminLive.adminExportsLiveScope venueId)
            `shouldBe` "admin-exports:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (AdminLive.adminXeroLiveScope venueId)
            `shouldBe` "admin-xero:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (BillingLive.billingVenueLiveScope venueId)
            `shouldBe` "billing:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (LeaveLive.leaveRequestsLiveScope venueId)
            `shouldBe` "leave-requests:11111111-1111-1111-1111-111111111111"
        surfaceScopeKey (TimesheetsLive.timesheetWeekLiveScope venueId (testAnchorForOffset 2) (addDays 7 (testAnchorForOffset 2)) 1)
            `shouldBe` "timesheets:11111111-1111-1111-1111-111111111111:2025-01-20:2025-01-27:1"
        surfaceScopeKey (ProfileLive.profileLiveScope venueId staffId)
            `shouldBe` "profile:11111111-1111-1111-1111-111111111111:44444444-4444-4444-4444-444444444444"
        surfaceScopeKey SupportLive.supportPlatformLiveScope
            `shouldBe` "support"

    it "derives canonical stable keys from every registered Surface scope contract" do
        let venueId = "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = "33333333-3333-3333-3333-333333333333"
        let staffId = "44444444-4444-4444-4444-444444444444"
        let rosterDayId = "22222222-2222-2222-2222-222222222222"
        let cases =
                [ (Wire.SurfaceScope "timesheets" (Aeson.object ["venueId" Aeson..= venueId, "windowStartDate" Aeson..= ("2025-01-20" :: Text), "windowEndDate" Aeson..= ("2025-01-27" :: Text), "rosterCalendarRevision" Aeson..= (1 :: Int)]), "timesheets:" <> venueId <> ":2025-01-20:2025-01-27:1")
                , (Wire.SurfaceScope "roster" (Aeson.object ["venueId" Aeson..= venueId, "rosterGroupId" Aeson..= rosterGroupId, "windowStartDate" Aeson..= ("2024-12-30" :: Text), "windowEndDate" Aeson..= ("2025-01-06" :: Text), "rosterCalendarRevision" Aeson..= (1 :: Int)]), "roster:" <> venueId <> ":" <> rosterGroupId <> ":2024-12-30:2025-01-06:1")
                , (Wire.SurfaceScope "roster-day-timeline" (Aeson.object ["venueId" Aeson..= venueId, "rosterGroupId" Aeson..= rosterGroupId, "windowStartDate" Aeson..= ("2025-01-13" :: Text), "windowEndDate" Aeson..= ("2025-01-20" :: Text), "rosterCalendarRevision" Aeson..= (1 :: Int), "rosterDayId" Aeson..= rosterDayId]), "roster-day-timeline:" <> venueId <> ":" <> rosterGroupId <> ":2025-01-13:2025-01-20:1:" <> rosterDayId)
                , (Wire.SurfaceScope "leave-requests" (Aeson.object ["venueId" Aeson..= venueId]), "leave-requests:" <> venueId)
                , (Wire.SurfaceScope "billing" (Aeson.object ["venueId" Aeson..= venueId]), "billing:" <> venueId)
                , (Wire.SurfaceScope "support" (Aeson.object []), "support")
                , (Wire.SurfaceScope "support" Aeson.Null, "support")
                , (Wire.SurfaceScope "profile" (Aeson.object ["venueId" Aeson..= venueId, "staffId" Aeson..= staffId]), "profile:" <> venueId <> ":" <> staffId)
                , (Wire.SurfaceScope "staff" (Aeson.object ["venueId" Aeson..= venueId, "staffId" Aeson..= staffId]), "staff:" <> venueId <> ":" <> staffId)
                , (Wire.SurfaceScope "admin-page" (Aeson.object ["venueId" Aeson..= venueId]), "admin-page:" <> venueId)
                , (Wire.SurfaceScope "admin-xero-page" (Aeson.object ["venueId" Aeson..= venueId]), "admin-xero-page:" <> venueId)
                , (Wire.SurfaceScope "admin-venue-config" (Aeson.object ["venueId" Aeson..= venueId]), "admin-venue-config:" <> venueId)
                , (Wire.SurfaceScope "admin-invites" (Aeson.object ["venueId" Aeson..= venueId]), "admin-invites:" <> venueId)
                , (Wire.SurfaceScope "admin-exports" (Aeson.object ["venueId" Aeson..= venueId]), "admin-exports:" <> venueId)
                , (Wire.SurfaceScope "admin-shift-types" (Aeson.object ["venueId" Aeson..= venueId]), "admin-shift-types:" <> venueId)
                , (Wire.SurfaceScope "admin-roster-groups" (Aeson.object ["venueId" Aeson..= venueId]), "admin-roster-groups:" <> venueId)
                , (Wire.SurfaceScope "admin-xero" (Aeson.object ["venueId" Aeson..= venueId]), "admin-xero:" <> venueId)
                ]

        forM_ cases \(wireScope, expectedKey) ->
            (surfaceScopeKey <$> decodeValueAs @SurfaceScope (Aeson.toJSON wireScope)) `shouldBe` Right expectedKey

    it "emits canonical scope keys from every admin Surface mount" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let scope = AdminSurface.AdminVenueScopeValue { adminVenueId = venueId, adminRosterGroupId = Nothing }
        let expected surfaceName = surfaceName <> ":" <> UUID.toText venueId

        (AdminSurface.adminPageSurfaceImpl scope).surfaceImplMountConfig.mountScopeKey `shouldBe` expected "admin-page"
        (AdminSurface.adminXeroPageSurfaceImpl scope).surfaceImplMountConfig.mountScopeKey `shouldBe` expected "admin-xero-page"
        (AdminSurface.adminVenueSettingsSurfaceImpl scope).surfaceImplMountConfig.mountScopeKey `shouldBe` expected "admin-venue-config"
        (AdminSurface.adminInvitesSurfaceImpl scope).surfaceImplMountConfig.mountScopeKey `shouldBe` expected "admin-invites"
        (AdminSurface.adminExportsSurfaceImplForWindow scope (fromGregorian 2026 8 10)).surfaceImplMountConfig.mountScopeKey `shouldBe` expected "admin-exports"
        (AdminSurface.adminShiftTypesSurfaceImpl scope).surfaceImplMountConfig.mountScopeKey `shouldBe` expected "admin-shift-types"
        (AdminSurface.adminRosterGroupsSurfaceImpl scope).surfaceImplMountConfig.mountScopeKey `shouldBe` expected "admin-roster-groups"
        (AdminSurface.adminXeroSurfaceImpl scope).surfaceImplMountConfig.mountScopeKey `shouldBe` expected "admin-xero"

    it "rejects substituted or malformed subscription scope identity" do
        let venueId = "11111111-1111-1111-1111-111111111111"
        let otherVenueId = "99999999-9999-9999-9999-999999999999"
        let scope = Wire.SurfaceScope "timesheets" (Aeson.object ["venueId" Aeson..= venueId, "windowStartDate" Aeson..= ("2025-01-06" :: Text), "windowEndDate" Aeson..= ("2025-01-13" :: Text), "rosterCalendarRevision" Aeson..= (1 :: Int)])
        let fragmentKey = Wire.SurfaceFragmentKey "timesheets" "timesheet-toolbar" (Aeson.object [])
        let expectedScopeKey = "timesheets:" <> venueId <> ":2025-01-06:2025-01-13:1"
        let command key keyValue = Wire.Subscribe (Wire.SurfaceSubscription scope key [keyValue] 0) "client-1" Nothing

        decodeValueAs @LiveUpdateCommand (Aeson.toJSON (command expectedScopeKey fragmentKey)) `shouldSatisfy` isRight
        decodeValueAs @LiveUpdateCommand (Aeson.toJSON (command ("timesheets:" <> otherVenueId <> ":2025-01-06:2025-01-13:1") fragmentKey)) `shouldSatisfy` isLeft
        decodeValueAs @LiveUpdateCommand (Aeson.toJSON (command ("roster:" <> venueId <> ":2025-01-06:2025-01-13:1") fragmentKey)) `shouldSatisfy` isLeft
        decodeValueAs @LiveUpdateCommand (Aeson.toJSON (command expectedScopeKey (Wire.SurfaceFragmentKey "leave-requests" "leave-section-count" (Aeson.object ["leaveSection" Aeson..= ("pending" :: Text)])))) `shouldSatisfy` isLeft

        let malformedScope = Wire.SurfaceScope "timesheets" (Aeson.object ["venueId" Aeson..= ("not-a-uuid" :: Text), "windowStartDate" Aeson..= ("2025-01-06" :: Text), "windowEndDate" Aeson..= ("2025-01-13" :: Text), "rosterCalendarRevision" Aeson..= (1 :: Int)])
        let malformedCommand = Wire.Subscribe (Wire.SurfaceSubscription malformedScope "timesheets:not-a-uuid:2025-01-06:2025-01-13:1" [fragmentKey] 0) "client-1" Nothing
        decodeValueAs @LiveUpdateCommand (Aeson.toJSON malformedCommand) `shouldSatisfy` isLeft

    it "rejects unknown fields when decoding live-update wire carrier types directly" do
        let scope = Wire.SurfaceScope "timesheets" (Aeson.object ["venueId" Aeson..= ("11111111-1111-1111-1111-111111111111" :: Text), "weekOffset" Aeson..= (4 :: Int)])
        let fragmentKey = Wire.SurfaceFragmentKey "timesheets" "timesheet-day-section" (Aeson.object ["dayOffset" Aeson..= (2 :: Int)])
        let subscription = Wire.SurfaceSubscription scope "timesheets:11111111-1111-1111-1111-111111111111:4" [fragmentKey] 0
        let refreshDetail = Wire.LiveFragmentsRefreshEventDetail scope subscription.scopeKey [fragmentKey]
        let command = Wire.Subscribe subscription "client-1" (Just 9)
        let message = Wire.Invalidate scope subscription.scopeKey 10 [fragmentKey] (Just "client-2")
        let executableDescriptor = Aeson.object
                [ "fragmentKey" Aeson..= fragmentKey
                , "targetId" Aeson..= ("timesheet-day-2" :: Text)
                , "url" Aeson..= ("https://attacker.invalid/fragment" :: Text)
                , "deferUntilBlur" Aeson..= False
                , "protectionPolicy" Aeson..= Aeson.object ["kind" Aeson..= ("none" :: Text)]
                ]
        let descriptorSubscription = Aeson.object ["scope" Aeson..= scope, "scopeKey" Aeson..= subscription.scopeKey, "fragments" Aeson..= [executableDescriptor]]
        let descriptorMessage = Aeson.object ["type" Aeson..= ("invalidate" :: Text), "scope" Aeson..= scope, "scopeKey" Aeson..= subscription.scopeKey, "version" Aeson..= (10 :: Int), "fragments" Aeson..= [executableDescriptor], "sourceClientId" Aeson..= (Nothing :: Maybe Text)]

        decodeValueAs @Wire.SurfaceScope (addJsonField "extra" (Aeson.Bool True) (Aeson.toJSON scope)) `shouldSatisfy` isLeft
        decodeValueAs @Wire.SurfaceFragmentKey (addJsonField "extra" (Aeson.Bool True) (Aeson.toJSON fragmentKey)) `shouldSatisfy` isLeft
        decodeValueAs @Wire.SurfaceSubscription (addJsonField "extra" (Aeson.Bool True) (Aeson.toJSON subscription)) `shouldSatisfy` isLeft
        decodeValueAs @Wire.LiveFragmentsRefreshEventDetail (addJsonField "extra" (Aeson.Bool True) (Aeson.toJSON refreshDetail)) `shouldSatisfy` isLeft
        decodeValueAs @Wire.LiveUpdateCommand (addJsonField "extra" (Aeson.Bool True) (Aeson.toJSON command)) `shouldSatisfy` isLeft
        decodeValueAs @Wire.LiveUpdateMessage (addJsonField "extra" (Aeson.Bool True) (Aeson.toJSON message)) `shouldSatisfy` isLeft
        decodeValueAs @Wire.SurfaceSubscription descriptorSubscription `shouldSatisfy` isLeft
        decodeValueAs @Wire.LiveUpdateMessage descriptorMessage `shouldSatisfy` isLeft

    it "validates every live-update wire carrier constructor against FrontendContract IR on encode" do
        let scope = Wire.SurfaceScope "timesheets" (Aeson.object ["venueId" Aeson..= ("11111111-1111-1111-1111-111111111111" :: Text), "windowStartDate" Aeson..= ("2025-02-03" :: Text), "windowEndDate" Aeson..= ("2025-02-10" :: Text), "rosterCalendarRevision" Aeson..= (1 :: Int)])
        let fragmentKey = Wire.SurfaceFragmentKey "timesheets" "timesheet-day-section" (Aeson.object ["operationalDate" Aeson..= ("2025-02-05" :: Text)])
        let expectedScopeKey = "timesheets:11111111-1111-1111-1111-111111111111:2025-02-03:2025-02-10:1"
        let subscription = Wire.SurfaceSubscription scope expectedScopeKey [fragmentKey] 0
        let commands =
                [ Wire.Subscribe subscription "client-1" Nothing
                , Wire.Subscribe subscription "client-1" (Just 9)
                , Wire.Unsubscribe subscription
                ]
        let messages =
                [ Wire.Subscribed scope expectedScopeKey 10 False
                , Wire.Invalidate scope expectedScopeKey 11 [fragmentKey] (Just "client-2")
                , Wire.Error "Not authorized"
                ]

        AesonTypes.parseEither validateSurfaceScopeValue (Aeson.toJSON scope) `shouldSatisfy` isRight
        AesonTypes.parseEither validateSurfaceFragmentKeyValue (Aeson.toJSON fragmentKey) `shouldSatisfy` isRight
        AesonTypes.parseEither (validateContractMarkerValue @LiveContract.SurfaceSubscription) (Aeson.toJSON subscription) `shouldSatisfy` isRight
        AesonTypes.parseEither (validateContractMarkerValue @AppContract.LiveFragmentsRefresh) (Aeson.toJSON (Wire.LiveFragmentsRefreshEventDetail scope subscription.scopeKey [fragmentKey])) `shouldSatisfy` isRight
        forM_ commands \value -> AesonTypes.parseEither (validateContractMarkerValue @LiveContract.LiveUpdateCommand) (Aeson.toJSON value) `shouldSatisfy` isRight
        forM_ messages \value -> AesonTypes.parseEither (validateContractMarkerValue @LiveContract.LiveUpdateMessage) (Aeson.toJSON value) `shouldSatisfy` isRight

    it "resyncs stale or forged rendered watermarks without refetching an exact initial render" do
        liveUpdateSubscriptionNeedsResync maxBound 4 Nothing 4 `shouldBe` True
        liveUpdateSubscriptionNeedsResync 4 4 Nothing 4 `shouldBe` False
        liveUpdateSubscriptionNeedsResync 3 4 Nothing 4 `shouldBe` True
        liveUpdateSubscriptionNeedsResync 4 4 (Just 4) 4 `shouldBe` False
        liveUpdateSubscriptionNeedsResync 4 4 (Just 3) 4 `shouldBe` True

    it "round-trips commands and encodes subscribed, invalidation, and error payloads as JSON" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let scope = RosterLive.rosterWeekLiveScope venueId rosterGroupId (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1
        let fragmentKey = RosterLive.rosterStaffPanelLiveFragment
        let subscription =
                SurfaceSubscription
                    { subscriptionScope = scope
                    , subscriptionScopeKey = surfaceScopeKey scope
                    , subscriptionFragmentKeys = [fragmentKey]
                    , subscriptionRenderedDependencyWatermark = 0
                    }
        let commands =
                [ SubscribeLiveUpdates { subscription, clientId = "client-1", lastSeenVersion = Nothing }
                , SubscribeLiveUpdates { subscription, clientId = "client-1", lastSeenVersion = Just 4 }
                , UnsubscribeLiveUpdates { subscription }
                ]
        let messages =
                [ LiveUpdatesSubscribed { scope, scopeKey = surfaceScopeKey scope, currentVersion = 4, resync = False }
                , LiveUpdatesSubscribed { scope, scopeKey = surfaceScopeKey scope, currentVersion = 5, resync = True }
                , LiveUpdatesInvalidated { scope, scopeKey = surfaceScopeKey scope, version = 6, fragments = [fragmentKey], sourceClientId = Just "client-1" }
                , LiveUpdatesInvalidated { scope, scopeKey = surfaceScopeKey scope, version = 7, fragments = [], sourceClientId = Nothing }
                , LiveUpdatesError { message = "Not authorized for requested live update scope" }
                ]

        forM_ commands \command ->
            Aeson.decode (Aeson.encode command) `shouldBe` Just command
        forM_ messages \message ->
            (Aeson.decode (Aeson.encode message) :: Maybe Aeson.Value) `shouldSatisfy` isJust

        let encodedSubscribed = cs (LBS.toStrict (Aeson.encode (LiveUpdatesSubscribed { scope, scopeKey = surfaceScopeKey scope, currentVersion = 4, resync = False }))) :: Text
        let encodedInvalidated = cs (LBS.toStrict (Aeson.encode (LiveUpdatesInvalidated { scope, scopeKey = surfaceScopeKey scope, version = 6, fragments = [fragmentKey], sourceClientId = Nothing }))) :: Text
        encodedSubscribed `shouldSatisfy` Text.isInfixOf "\"scopeKey\":\"roster:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:2025-01-06:2025-01-13:1\""
        encodedInvalidated `shouldSatisfy` Text.isInfixOf "\"scopeKey\":\"roster:11111111-1111-1111-1111-111111111111:33333333-3333-3333-3333-333333333333:2025-01-06:2025-01-13:1\""

    it "exposes active roster scopes without leaking websocket subscription internals" do
        RosterLive.activeRosterWindowScopes `shouldReturn` []

    it "exercises isolated in-memory live buses without global state leakage" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let scope = LeaveLive.leaveRequestsLiveScope venueId
        let fragmentKey = leavePendingCountLiveFragment
        firstBus <- newInMemoryLiveBus
        secondBus <- newInMemoryLiveBus

        activeSurfaceScopesWithBus firstBus `shouldReturn` []
        activeSurfaceSubscriptionsWithBus firstBus `shouldReturn` []
        activeSurfaceScopeMatchesWithBus firstBus supportScopeLabel `shouldReturn` []
        RosterLive.activeRosterWindowScopesWithBus firstBus `shouldReturn` []

        let subscription =
                SurfaceSubscription
                    { subscriptionScope = scope
                    , subscriptionScopeKey = surfaceScopeKey scope
                    , subscriptionFragmentKeys = [fragmentKey]
                    , subscriptionRenderedDependencyWatermark = 0
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
        advanceLiveUpdateVersionWithBus secondBus scope 9 `shouldReturn` True
        advanceLiveUpdateVersionWithBus secondBus scope 7 `shouldReturn` False
        duplicate <- broadcastLiveInvalidationAtVersionWithBus secondBus scope 9 Nothing [fragmentKey]
        duplicate.broadcastSubscriberCount `shouldBe` 0
        currentLiveUpdateVersionWithBus secondBus scope `shouldReturn` 9

        result <- broadcastLiveInvalidationDetailedWithBus firstBus scope Nothing [fragmentKey, fragmentKey]

        result.broadcastVersion `shouldBe` 2
        result.broadcastSubscriberCount `shouldBe` 0
        result.broadcastFragmentCount `shouldBe` 2
        result.broadcastRefetchFragmentCount `shouldBe` 1
        result.broadcastCoalescedFragmentCount `shouldBe` 1
        result.broadcastDroppedSubscriptions `shouldBe` 0

    it "recovers active Timesheet week scopes for context-free resource fanout" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let scope = TimesheetsLive.timesheetWeekLiveScope venueId (testAnchorForOffset 3) (addDays 7 (testAnchorForOffset 3)) 1
        let subscription =
                SurfaceSubscription
                    { subscriptionScope = scope
                    , subscriptionScopeKey = surfaceScopeKey scope
                    , subscriptionFragmentKeys = [TimesheetsLive.timesheetToolbarLiveFragment]
                    , subscriptionRenderedDependencyWatermark = 0
                    }
        bus <- newInMemoryLiveBus

        TimesheetsLive.activeTimesheetWindowScopesWithBus bus `shouldReturn` []
        registerSurfaceSubscriptionWithBus bus venueId subscription (error "unused websocket connection")
        TimesheetsLive.activeTimesheetWindowScopesWithBus bus `shouldReturn` [(venueId, testAnchorForOffset 3, addDays 7 (testAnchorForOffset 3), 1)]

    it "reports broadcast fanout counts for profiling hooks" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let scope = LeaveLive.leaveRequestsLiveScope venueId
        result <- broadcastLiveInvalidationDetailedWithoutContext scope Nothing [leavePendingCountLiveFragment]

        result.broadcastVersion `shouldSatisfy` (> 0)
        result.broadcastSubscriberCount `shouldBe` 0
        result.broadcastFragmentCount `shouldBe` 1
        result.broadcastRefetchFragmentCount `shouldBe` 1
        result.broadcastCoalescedFragmentCount `shouldBe` 0
        result.broadcastDroppedSubscriptions `shouldBe` 0

    it "coalesces semantic fragment keys independently of parameter property order" do
        let rosterDayId = "22222222-2222-2222-2222-222222222222" :: Text
        let encoded params = Aeson.object
                [ "surface" Aeson..= ("roster" :: Text)
                , "kind" Aeson..= ("roster-row" :: Text)
                , "params" Aeson..= params
                ]
        let first = either (error . cs) id (decodeValueAs @SurfaceFragmentKey (encoded (Aeson.object ["rosterDayId" Aeson..= rosterDayId, "rowIndex" Aeson..= (2 :: Int)])))
        let reordered = either (error . cs) id (decodeValueAs @SurfaceFragmentKey (encoded (Aeson.object ["rowIndex" Aeson..= (2 :: Int), "rosterDayId" Aeson..= rosterDayId])))
        first `shouldBe` reordered
        coalesceSurfaceFragmentKeys [first, reordered] `shouldBe` [first]

    it "coalesces duplicate semantic fragment keys before broadcasting" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let scope = LeaveLive.leaveRequestsLiveScope venueId
        let fragmentKey = leavePendingCountLiveFragment

        coalesceSurfaceFragmentKeys [fragmentKey, fragmentKey] `shouldBe` [fragmentKey]
        result <- broadcastLiveInvalidationDetailedWithoutContext scope Nothing [fragmentKey, fragmentKey]

        result.broadcastFragmentCount `shouldBe` 2
        result.broadcastRefetchFragmentCount `shouldBe` 1
        result.broadcastCoalescedFragmentCount `shouldBe` 1

    it "projects FrontendSurface support mounts to semantic fragment keys" do
        supportSurfaceFragmentKeys supportCandidateMountedFragments
            `shouldBe`
                [ SupportLive.supportAwardRatesLiveFragment
                , SupportLive.supportPublicHolidaysLiveFragment
                ]

    it "validates live subscriptions from generated FrontendSurface metadata" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let scope = TimesheetsLive.timesheetWeekLiveScope venueId (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1
        let subscription =
                SurfaceSubscription
                    { subscriptionScope = scope
                    , subscriptionScopeKey = surfaceScopeKey scope
                    , subscriptionFragmentKeys = [TimesheetsLive.timesheetDaySectionLiveFragment (addDays 1 (testAnchorForOffset 0))]
                    , subscriptionRenderedDependencyWatermark = 0
                    }

        validateFrontendSurfaceLiveSubscription subscription `shouldBe` True
        validateFrontendSurfaceLiveSubscription subscription { subscriptionScopeKey = "timesheets:wrong" } `shouldBe` False
        validateFrontendSurfaceLiveSubscription subscription { subscriptionFragmentKeys = [leavePendingCountLiveFragment] } `shouldBe` False
        validateFrontendSurfaceLiveSubscription subscription { subscriptionFragmentKeys = [TimesheetsLive.timesheetToolbarLiveFragment] } `shouldBe` True

    it "projects closed live authorization IR without policy-name redispatch" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = expectUuid "33333333-3333-3333-3333-333333333333"
        let staffId = expectUuid "44444444-4444-4444-4444-444444444444"
        let staffScope = ProfileLive.staffLiveScope venueId staffId

        frontendSurfaceScopeAuthorizationRequirement SupportLive.supportPlatformLiveScope `shouldBe` Just (Just RequireSupportSuperAdmin)
        frontendSurfaceScopeAuthorizationRequirement (AdminLive.adminXeroLiveScope venueId) `shouldBe` Just (Just (RequireCurrentVenueOwner venueId))
        frontendSurfaceScopeAuthorizationRequirement (AdminLive.adminVenueConfigLiveScope venueId) `shouldBe` Just (Just (RequireCurrentVenueAdmin venueId))
        frontendSurfaceScopeAuthorizationRequirement (LeaveLive.leaveRequestsLiveScope venueId) `shouldBe` Just (Just (RequireCurrentVenueManager venueId))
        frontendSurfaceScopeAuthorizationRequirement (ProfileLive.profileLiveScope venueId staffId) `shouldBe` Just (Just (RequireCurrentVenueStaff venueId staffId))
        frontendSurfaceScopeAuthorizationRequirement (RosterLive.rosterWeekLiveScope venueId rosterGroupId (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1) `shouldBe` Just (Just (RequireCurrentVenueRosterGroup venueId rosterGroupId))
        frontendSurfaceScopeAuthorizationRequirement (TimesheetsLive.timesheetWeekLiveScope venueId (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1) `shouldBe` Just (Just (RequireCurrentVenue venueId))
        frontendSurfaceScopeAuthorizationRequirement staffScope `shouldBe` Just (Just (RequireCurrentVenueManager venueId))

leavePendingCountLiveFragment :: SurfaceFragmentKey
leavePendingCountLiveFragment = LeaveLive.leaveSectionCountLiveFragment LeavePendingSection

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
supportScopeLabel scope
    | SupportLive.matchSupportPlatformLiveScope scope = Just "support"
    | otherwise = Nothing
