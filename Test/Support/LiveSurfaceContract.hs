module Test.Support.LiveSurfaceContract
    ( liveFragmentResponseShouldBeDenied
    , liveFragmentResponseShouldRenderTarget
    ) where

import Application.Helper.LiveUpdate.Runtime
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status (Status, status200)
import Network.Wai (Response)
import Test.Hspec

liveFragmentResponseShouldRenderTarget :: Response -> LiveUpdateWireFragment -> Expectation
liveFragmentResponseShouldRenderTarget response fragment = do
    response `responseStatusShouldBe` status200
    response `responseBodyShouldContain` ("id=\"" <> fragment.targetId <> "\"")
    response `responseBodyShouldNotContain` "id=\"app\""

liveFragmentResponseShouldBeDenied :: Status -> Response -> Expectation
liveFragmentResponseShouldBeDenied expectedStatus response =
    response `responseStatusShouldBe` expectedStatus
