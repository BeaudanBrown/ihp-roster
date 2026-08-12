{-# LANGUAGE TypeApplications #-}

module Test.SurfaceResourceSpec where

import qualified Application.Helper.FrontendContract.Surface.Admin.Resource as AdminResource
import qualified Application.Helper.FrontendContract.Surface.Profile.Resource as ProfileResource
import Application.Helper.FrontendContract.Surface.Resource (frontendSurfaceResource,
                                                             matchFrontendSurfaceResource)
import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import qualified Application.Helper.FrontendContract.Surface.Roster.Resource as RosterResource
import qualified Application.Helper.FrontendContract.Surface.Timesheets as TimesheetsSurface
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.SurfaceResource
import Application.Helper.LiveUpdate.DurableCodec (DurableResource (..), decodeDurableResource, encodeDurableResource)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import Data.UUID (nil)
import IHP.Prelude
import System.Environment (unsetEnv)
import Test.Hspec

tests :: Spec
tests = do
    describe "Surface resource diagnostics" do
        it "preserves mutation results when diagnostics are disabled" do
            unsetEnv "LIVE_MUTATION_DIAGNOSTICS"
            let result = liveMutationResult ("ok" :: Text) [AdminResource.adminVenueSettingsResource nil, AdminResource.adminVenueSettingsResource nil]
            observed <- recordLiveMutationDiagnostics "test.disabled" result
            liveMutationValue observed `shouldBe` "ok"
            liveMutationTouchedResources observed `shouldBe` Set.fromList [AdminResource.adminVenueSettingsResource nil]

        it "encodes registered resources as canonical versioned durable payloads" do
            let resource = AdminResource.adminVenueSettingsResource nil
            let Right encoded = encodeDurableResource resource
            encoded.durableResourceKey `shouldBe` "admin-venue-settings:{\"venueId\":\"00000000-0000-0000-0000-000000000000\"}"
            encoded.durableResourcePayload `shouldBe`
                Aeson.object
                    [ "version" Aeson..= (1 :: Int)
                    , "resource" Aeson..= ("admin-venue-settings" :: Text)
                    , "fields" Aeson..= Aeson.object ["venueId" Aeson..= nil]
                    ]
            decodeDurableResource encoded.durableResourceKey encoded.durableResourcePayload `shouldBe` Right encoded

        it "rejects durable payloads with unknown resources, changed keys, or malformed fields" do
            decodeDurableResource "unknown:{}" (Aeson.object ["version" Aeson..= (1 :: Int), "resource" Aeson..= ("unknown" :: Text), "fields" Aeson..= Aeson.object []])
                `shouldBe` Left "unknown live resource"
            decodeDurableResource "wrong-key" (Aeson.object ["version" Aeson..= (1 :: Int), "resource" Aeson..= ("admin-venue-settings" :: Text), "fields" Aeson..= Aeson.object ["venueId" Aeson..= ("not-a-uuid" :: Text)]])
                `shouldBe` Left "malformed live resource field: venueId"

        it "constructs and matches declaration-complete typed resources" do
            let resourceValue =
                    frontendSurfaceResource @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetDay
                        ( surfaceField @TimesheetsSurface.VenueId nil
                            &: surfaceField @TimesheetsSurface.WeekOffset 2
                            &: surfaceField @TimesheetsSurface.DayOffset 4
                            &: noSurfaceFields
                        )

            matchFrontendSurfaceResource @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetDay resourceValue
                `shouldBe` Just (nil, (2, (4, ())))
            matchFrontendSurfaceResource @RosterSurface.RosterSurface @RosterSurface.RosterDay resourceValue
                `shouldBe` Nothing

        it "matches and destructures resources through feature-owned typed matchers" do
            let rosterConfig = RosterResource.rosterEndTimesConfigResource nil
            let xeroSyncState = AdminResource.xeroReferenceSyncStateResource nil
            let staffProfile = ProfileResource.staffProfileResource nil
            let templateLibrary = RosterResource.rosterTemplateLibraryResource nil
            let template = RosterResource.rosterTemplateResource nil
            let templateDraft = RosterResource.rosterTemplateDraftResource nil

            xeroSyncState `shouldNotBe` AdminResource.xeroConnectionResource nil
            RosterResource.matchRosterEndTimesConfigResource rosterConfig `shouldBe` Just nil
            RosterResource.matchRosterWeekBoundaryConfigResource rosterConfig `shouldBe` Nothing
            ProfileResource.matchStaffProfileResource staffProfile `shouldBe` Just nil
            ProfileResource.matchStaffPreferencesResource staffProfile `shouldBe` Nothing
            RosterResource.matchRosterTemplateLibraryResource templateLibrary `shouldBe` Just nil
            RosterResource.matchRosterTemplateResource template `shouldBe` Just nil
            RosterResource.matchRosterTemplateDraftResource templateDraft `shouldBe` Just nil
