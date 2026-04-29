module Application.Helper.LiveSurface
    ( LiveSurfaceConfig (..)
    , LiveSurfaceDefinition (..)
    , broadcastSurfaceFragments
    , liveSurfaceConfigJson
    , liveSurfaceFragmentRef
    , liveSurfaceFragmentRefs
    , mkDefinedLiveSurface
    , mkLiveSurface
    ) where

import Application.Helper.LiveUpdate
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as Text
import IHP.Controller.Context (ControllerContext)
import IHP.ControllerSupport (Request)
import IHP.Prelude

data LiveSurfaceConfig = LiveSurfaceConfig
    { feature                :: !Text
    , socketPath             :: !Text
    , scope                  :: !LiveUpdateScope
    , scopeKey               :: !Text
    , resyncFragments        :: ![LiveFragmentRef]
    , decorateRequestsWithin :: ![Text]
    }
    deriving (Eq, Show)

data LiveSurfaceDefinition scope fragment = LiveSurfaceDefinition
    { surfaceFeature                :: !Text
    , surfaceScope                  :: scope -> LiveUpdateScope
    , surfaceDefaultFragments       :: scope -> [fragment]
    , surfaceFragmentRef            :: scope -> fragment -> LiveFragmentRef
    , surfaceDecorateRequestsWithin :: scope -> [Text]
    }

instance Aeson.ToJSON LiveSurfaceConfig where
    toJSON LiveSurfaceConfig { feature, socketPath, scope, scopeKey, resyncFragments, decorateRequestsWithin } =
        Aeson.object
            [ "feature" Aeson..= feature
            , "socketPath" Aeson..= socketPath
            , "scope" Aeson..= scope
            , "scopeKey" Aeson..= scopeKey
            , "resyncFragments" Aeson..= resyncFragments
            , "decorateRequestsWithin" Aeson..= decorateRequestsWithin
            ]

instance Aeson.FromJSON LiveSurfaceConfig where
    parseJSON = Aeson.withObject "LiveSurfaceConfig" \object ->
        LiveSurfaceConfig
            <$> object Aeson..: "feature"
            <*> object Aeson..: "socketPath"
            <*> object Aeson..: "scope"
            <*> object Aeson..: "scopeKey"
            <*> object Aeson..: "resyncFragments"
            <*> object Aeson..: "decorateRequestsWithin"

mkLiveSurface :: Text -> LiveUpdateScope -> [LiveFragmentRef] -> LiveSurfaceConfig
mkLiveSurface feature scope resyncFragments =
    LiveSurfaceConfig
        { feature
        , socketPath = "/live-updates"
        , scope
        , scopeKey = liveUpdateScopeKey scope
        , resyncFragments
        , decorateRequestsWithin = []
        }

mkDefinedLiveSurface :: LiveSurfaceDefinition scope fragment -> scope -> LiveSurfaceConfig
mkDefinedLiveSurface definition surfaceKey =
    (mkLiveSurface
        definition.surfaceFeature
        (definition.surfaceScope surfaceKey)
        (liveSurfaceFragmentRefs definition surfaceKey (definition.surfaceDefaultFragments surfaceKey)))
        { decorateRequestsWithin = definition.surfaceDecorateRequestsWithin surfaceKey
        }

liveSurfaceFragmentRef :: LiveSurfaceDefinition scope fragment -> scope -> fragment -> LiveFragmentRef
liveSurfaceFragmentRef definition surfaceKey fragment =
    definition.surfaceFragmentRef surfaceKey fragment

liveSurfaceFragmentRefs :: LiveSurfaceDefinition scope fragment -> scope -> [fragment] -> [LiveFragmentRef]
liveSurfaceFragmentRefs definition surfaceKey =
    map (liveSurfaceFragmentRef definition surfaceKey)

broadcastSurfaceFragments ::
    (?context :: ControllerContext, ?request :: Request) =>
    LiveSurfaceDefinition scope fragment ->
    scope ->
    [fragment] ->
    IO ()
broadcastSurfaceFragments definition surfaceKey fragments =
    broadcastLiveInvalidation
        (definition.surfaceScope surfaceKey)
        liveUpdateSourceClientId
        (liveSurfaceFragmentRefs definition surfaceKey fragments)

liveSurfaceConfigJson :: LiveSurfaceConfig -> Text
liveSurfaceConfigJson =
    Text.decodeUtf8 . LBS.toStrict . Aeson.encode
