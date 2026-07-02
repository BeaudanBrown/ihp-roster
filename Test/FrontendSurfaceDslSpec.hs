{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Test.FrontendSurfaceDslSpec
    ( tests
    ) where

import Application.Helper.FrontendSurface.Lab (SurfaceLabSurface)
import Application.Helper.FrontendSurface.Registry (RegisteredFrontendSurfaces)
import Data.Proxy (Proxy (..))
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "FrontendSurface DSL foundation" do
    it "kind-checks the support lab surface and root registry" do
        let _lab = Proxy @SurfaceLabSurface
        let _registry = Proxy @RegisteredFrontendSurfaces
        True `shouldBe` True
