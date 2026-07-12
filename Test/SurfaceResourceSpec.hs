{-# LANGUAGE TypeApplications #-}

module Test.SurfaceResourceSpec where

import qualified Application.Helper.FrontendContract.Surface.Profile as ProfileSurface
import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import Application.Helper.SurfaceResource
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
            let result = liveMutationResult ("ok" :: Text) [adminVenueSettingsResource nil, adminVenueSettingsResource nil]
            observed <- recordLiveMutationDiagnostics "test.disabled" result
            liveMutationValue observed `shouldBe` "ok"
            liveMutationTouchedResources observed `shouldBe` Set.fromList [adminVenueSettingsResource nil]

        it "matches and destructures feature resources through owning Surface markers" do
            let rosterConfig = rosterEndTimesConfigResource nil
            let staffProfile = staffProfileResource nil

            resourceMatchesFor @RosterSurface.RosterSurface @RosterSurface.RosterEndTimesConfig rosterConfig `shouldBe` True
            resourceMatchesFor @RosterSurface.RosterSurface @RosterSurface.RosterWeekBoundaryConfig rosterConfig `shouldBe` False
            resourceFieldUuidFor @RosterSurface.RosterSurface @RosterSurface.RosterEndTimesConfig @RosterSurface.VenueId rosterConfig `shouldBe` Just nil
            resourceMatchesFor @ProfileSurface.ProfileSurface @ProfileSurface.StaffProfile staffProfile `shouldBe` True
            resourceFieldUuidFor @ProfileSurface.ProfileSurface @ProfileSurface.StaffProfile @ProfileSurface.StaffId staffProfile `shouldBe` Just nil
