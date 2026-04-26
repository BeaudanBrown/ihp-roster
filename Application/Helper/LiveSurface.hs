module Application.Helper.LiveSurface
    ( LiveSurfaceConfig (..)
    , liveSurfaceConfigJson
    , mkLiveSurface
    ) where

import Application.Helper.LiveUpdate
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as Text
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

liveSurfaceConfigJson :: LiveSurfaceConfig -> Text
liveSurfaceConfigJson =
    Text.decodeUtf8 . LBS.toStrict . Aeson.encode
