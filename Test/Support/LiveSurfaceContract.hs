module Test.Support.LiveSurfaceContract
    ( liveFragmentResponseShouldBeDenied
    , liveFragmentResponseShouldRenderTarget
    , liveSurfaceConfigShouldExposeRefs
    , liveSurfaceConfigShouldRoundTrip
    , responseShouldMountLiveSurface
    ) where

import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate.Internal (LiveFragmentRef (..))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status (Status, status200)
import Network.Wai (Response)
import Test.Hspec

liveSurfaceConfigShouldRoundTrip :: LiveSurfaceConfig -> Expectation
liveSurfaceConfigShouldRoundTrip surface =
    Aeson.decode (LBS.fromStrict (cs (liveSurfaceConfigJson surface))) `shouldBe` Just surface

liveSurfaceConfigShouldExposeRefs :: LiveSurfaceConfig -> [LiveFragmentRef] -> Expectation
liveSurfaceConfigShouldExposeRefs surface refs = do
    surface.resyncFragments `shouldBe` refs
    map (.targetId) surface.resyncFragments `shouldBe` map (.targetId) refs
    map (.url) surface.resyncFragments `shouldBe` map (.url) refs

responseShouldMountLiveSurface :: Response -> LiveSurfaceConfig -> Expectation
responseShouldMountLiveSurface response surface = do
    response `responseStatusShouldBe` status200
    response `responseBodyShouldContain` "data-live-update-surface=\""
    response `responseBodyShouldContain` surface.feature
    response `responseBodyShouldContain` surface.scopeKey
    forM_ surface.resyncFragments \fragment -> do
        response `responseBodyShouldContain` fragment.targetId

liveFragmentResponseShouldRenderTarget :: Response -> LiveFragmentRef -> Expectation
liveFragmentResponseShouldRenderTarget response fragment = do
    response `responseStatusShouldBe` status200
    response `responseBodyShouldContain` ("id=\"" <> fragment.targetId <> "\"")
    response `responseBodyShouldNotContain` "id=\"app\""

liveFragmentResponseShouldBeDenied :: Status -> Response -> Expectation
liveFragmentResponseShouldBeDenied expectedStatus response =
    response `responseStatusShouldBe` expectedStatus
