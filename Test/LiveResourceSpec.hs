module Test.LiveResourceSpec where

import Application.Helper.LiveResource
import qualified Data.Set as Set
import Data.UUID (nil)
import IHP.Prelude
import System.Environment (unsetEnv)
import Test.Hspec

tests :: Spec
tests = do
    describe "LiveResource diagnostics" do
        it "preserves mutation results when diagnostics are disabled" do
            unsetEnv "LIVE_MUTATION_DIAGNOSTICS"
            let result = liveMutationResult ("ok" :: Text) [AdminVenueSettingsResource nil, AdminVenueSettingsResource nil]
            observed <- recordLiveMutationDiagnostics "test.disabled" result
            liveMutationValue observed `shouldBe` "ok"
            liveMutationTouchedResources observed `shouldBe` Set.fromList [AdminVenueSettingsResource nil]
