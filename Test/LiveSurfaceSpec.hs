module Test.LiveSurfaceSpec where

import Application.Support.LiveUpdates
import IHP.Prelude
import Test.Hspec
import Test.Support.LiveSurfaceContract

tests :: Spec
tests = describe "LiveSurface contract helpers" do
    it "verify the typed support surface config contract" do
        liveSurfaceConfigShouldRoundTrip supportLiveSurface
        liveSurfaceConfigShouldExposeRefs
            supportLiveSurface
            [ supportAwardRatesSectionFragmentRef
            , supportPublicHolidaysSectionFragmentRef
            ]
