module Test.Support.LiveSurfaceContract
    ( liveFragmentResponseShouldBeDenied
    , liveFragmentResponseShouldRenderTarget
    , liveSurfaceConfigShouldExposeRefs
    , liveSurfaceConfigShouldRoundTrip
    , responseShouldMountLiveSurface
    , typedLiveSurfaceConfigShouldExposeDefaultRefs
    , typedLiveSurfaceFragmentShouldMapTo
    ) where

import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate
import Application.Helper.LiveUpdate.Runtime
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

liveSurfaceConfigShouldExposeRefs :: LiveSurfaceConfig -> [LiveUpdateWireFragment] -> Expectation
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

typedLiveSurfaceConfigShouldExposeDefaultRefs ::
    TypedLiveSurfaceDefinition surface scope fragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent ->
    scope ->
    [fragment] ->
    Expectation
typedLiveSurfaceConfigShouldExposeDefaultRefs definition surfaceKey expectedDefaultFragments =
    liveSurfaceConfigShouldExposeRefs
        (mkTypedDefinedLiveSurface definition surfaceKey)
        (unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs definition surfaceKey expectedDefaultFragments))

typedLiveSurfaceFragmentShouldMapTo ::
    TypedLiveSurfaceDefinition surface scope fragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent ->
    scope ->
    fragment ->
    LiveFragmentKey ->
    Text ->
    Text ->
    Expectation
typedLiveSurfaceFragmentShouldMapTo definition surfaceKey fragment expectedFragmentKey expectedTargetId expectedUrl = do
    let wireFragment = singleWireFragment (typedLiveSurfaceFragmentRef definition surfaceKey fragment)
    wireFragment.fragmentKey `shouldBe` expectedFragmentKey
    wireFragment.targetId `shouldBe` expectedTargetId
    wireFragment.url `shouldBe` expectedUrl

singleWireFragment :: SurfaceFragmentRef surface -> LiveUpdateWireFragment
singleWireFragment fragmentRef =
    case unSurfaceFragmentRefs [fragmentRef] of
        [wireFragment] -> wireFragment
        _              -> error "Expected one live surface fragment ref"

liveFragmentResponseShouldRenderTarget :: Response -> LiveUpdateWireFragment -> Expectation
liveFragmentResponseShouldRenderTarget response fragment = do
    response `responseStatusShouldBe` status200
    response `responseBodyShouldContain` ("id=\"" <> fragment.targetId <> "\"")
    response `responseBodyShouldNotContain` "id=\"app\""

liveFragmentResponseShouldBeDenied :: Status -> Response -> Expectation
liveFragmentResponseShouldBeDenied expectedStatus response =
    response `responseStatusShouldBe` expectedStatus
