{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE TypeApplications #-}

module Test.SurfaceResourceSpec where

import qualified Application.Helper.FrontendContract.Core as Contract
import qualified Application.Helper.FrontendContract.Surface.Admin.Resource as AdminResource
import qualified Application.Helper.FrontendContract.Surface.ContractIR as Surface
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import qualified Application.Helper.FrontendContract.Surface.Profile.Resource as ProfileResource
import Application.Helper.FrontendContract.Surface.Resource (frontendSurfaceResource,
                                                             matchFrontendSurfaceResource)
import qualified Application.Helper.FrontendContract.Surface.Resource.Internal as ResourceInternal
import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import qualified Application.Helper.FrontendContract.Surface.Roster.Resource as RosterResource
import qualified Application.Helper.FrontendContract.Surface.Timesheets as TimesheetsSurface
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.LiveUpdate.DurableCodec (DurableResource (..),
                                                   decodeDurableResource,
                                                   encodeDurableResource)
import Application.Helper.SurfaceResource
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import Data.Either (isRight)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Data.UUID (nil)
import IHP.Prelude
import System.Environment (unsetEnv)
import Test.Hspec

tests :: Spec
sampleWireValue :: Contract.WireIR -> Aeson.Value
sampleWireValue = \case
    Contract.WireTextIR -> Aeson.String "sample"
    Contract.WireIntIR -> Aeson.Number 1
    Contract.WireBoolIR -> Aeson.Bool True
    Contract.WireUuidIR -> Aeson.toJSON nil
    Contract.WireDayIR -> Aeson.String "2026-01-01"
    Contract.WireClosedIR {} -> Aeson.String "sample"
    Contract.WireDomainIR {} -> Aeson.String "sample"
    Contract.WireUnknownIR -> Aeson.String "sample"
    Contract.WireListIR _ -> Aeson.Array mempty
    Contract.WireMapIR _ _ -> Aeson.Object mempty
    Contract.WireOptionalIR _ -> Aeson.Null
    Contract.WireNullableIR _ -> Aeson.Null
    Contract.WireRefIR _ -> Aeson.Object mempty
    Contract.WireSurfaceScopeIR -> Aeson.Object mempty
    Contract.WireSurfaceFragmentKeyIR -> Aeson.Object mempty

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

        it "round-trips every registered resource declaration through the durable codec" do
            let resources =
                    [ ResourceInternal.mkSurfaceResourceValue declaration.resourceName (Aeson.object [AesonKey.fromText field.fieldName Aeson..= sampleWireValue field.fieldWire | field <- declaration.resourceFields])
                    | surface <- registeredFrontendSurfaceContractIR.contractSurfaces
                    , fragment <- surface.surfaceFragments
                    , dependency <- Surface.optionResourceDependencies fragment.fragmentOptions
                    , let declaration = dependency.dependencyResource
                    ]
            let encoded = map encodeDurableResource resources
            length resources `shouldSatisfy` (> 0)
            encoded `shouldSatisfy` all isRight
            forM_ encoded \case
                Right resource -> decodeDurableResource resource.durableResourceKey resource.durableResourcePayload `shouldBe` Right resource
                Left _ -> expectationFailure "expected every registered resource to encode"

        it "rejects durable payloads with unknown resources, changed keys, or malformed fields" do
            decodeDurableResource "unknown:{}" (Aeson.object ["version" Aeson..= (1 :: Int), "resource" Aeson..= ("unknown" :: Text), "fields" Aeson..= Aeson.object []])
                `shouldBe` Left "unknown live resource"
            decodeDurableResource "wrong-key" (Aeson.object ["version" Aeson..= (1 :: Int), "resource" Aeson..= ("admin-venue-settings" :: Text), "fields" Aeson..= Aeson.object ["venueId" Aeson..= ("not-a-uuid" :: Text)]])
                `shouldBe` Left "malformed live resource field: venueId"
            decodeDurableResource "ignored" (Aeson.object ["version" Aeson..= (1 :: Int), "resource" Aeson..= ("admin-venue-settings" :: Text), "fields" Aeson..= Aeson.object ["venueId" Aeson..= nil], "padding" Aeson..= Text.replicate 9000 "x"])
                `shouldBe` Left "live resource payload exceeds 8192 bytes"
            decodeDurableResource "ignored" (Aeson.object ["version" Aeson..= (1 :: Int), "resource" Aeson..= ("admin-venue-settings" :: Text), "fields" Aeson..= Aeson.object ["venueId" Aeson..= nil], "extra" Aeson..= True])
                `shouldBe` Left "live resource payload fields do not match envelope"

        it "constructs and matches declaration-complete typed resources" do
            let resourceValue =
                    frontendSurfaceResource @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetDay
                        ( surfaceField @TimesheetsSurface.VenueId nil
                            &: surfaceField @TimesheetsSurface.OperationalDate (fromGregorian 2025 1 10)
                            &: noSurfaceFields
                        )

            matchFrontendSurfaceResource @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetDay resourceValue
                `shouldBe` Just (nil, (fromGregorian 2025 1 10, ()))
            matchFrontendSurfaceResource @RosterSurface.RosterSurface @RosterSurface.RosterDay resourceValue
                `shouldBe` Nothing

        it "matches and destructures resources through feature-owned typed matchers" do
            let rosterConfig = RosterResource.rosterEndTimesConfigResource nil
            let xeroSyncState = AdminResource.xeroReferenceSyncStateResource nil
            let staffProfile = ProfileResource.staffProfileResource nil
            let templateLibrary = RosterResource.rosterTemplateLibraryResource nil

            xeroSyncState `shouldNotBe` AdminResource.xeroConnectionResource nil
            RosterResource.matchRosterEndTimesConfigResource rosterConfig `shouldBe` Just nil
            RosterResource.matchRosterWeekBoundaryConfigResource rosterConfig `shouldBe` Nothing
            ProfileResource.matchStaffProfileResource staffProfile `shouldBe` Just nil
            ProfileResource.matchStaffPreferencesResource staffProfile `shouldBe` Nothing
            RosterResource.matchRosterTemplateLibraryResource templateLibrary `shouldBe` Just nil
