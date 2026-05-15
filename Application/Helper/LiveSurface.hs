module Application.Helper.LiveSurface
    ( LiveSurfaceConfig (..)
    , LiveSurfaceBroadcastOptions (..)
    , LiveSurfaceDefinition (..)
    , ProjectionLiveSurfaceDefinition (..)
    , SurfaceFragmentRef (..)
    , SurfaceScope (..)
    , TypedLiveSurfaceDefinition (..)
    , broadcastProjectionSurfaceFragments
    , broadcastProjectionSurfaceFragmentsWith
    , broadcastSurfaceFragments
    , defaultLiveSurfaceBroadcastOptions
    , liveSurfaceProjectionFragmentRef
    , liveSurfaceConfigJson
    , liveSurfaceFragmentRef
    , liveSurfaceFragmentRefs
    , loadLiveSurfaceProjection
    , loadLiveSurfaceProjectionFromStore
    , mkDefinedLiveSurface
    , mkLiveSurface
    , mkSurfaceProjectionDefinition
    , mkTypedDefinedLiveSurface
    , renderLiveSurfaceProjectionFragment
    , renderLiveSurfaceProjectionFragmentFromStore
    , typedLiveSurfaceDefinition
    , typedLiveSurfaceFragmentRef
    , typedLiveSurfaceFragmentRefs
    , unSurfaceFragmentRefs
    , warmLiveSurfaceProjection
    , warmLiveSurfaceProjectionFromStore
    ) where

import Application.Helper.LiveUpdate
import Application.Helper.SurfaceProjection
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Dynamic as Dynamic
import qualified Data.Text.Encoding as Text
import IHP.Controller.Context (ControllerContext)
import IHP.ControllerSupport (Request)
import IHP.Prelude
import qualified Text.Blaze.Html as Blaze

data LiveSurfaceConfig = LiveSurfaceConfig
    { feature                :: !Text
    , socketPath             :: !Text
    , scope                  :: !LiveUpdateScope
    , scopeKey               :: !Text
    , resyncFragments        :: ![LiveFragmentRef]
    , decorateRequestsWithin :: ![Text]
    }
    deriving (Eq, Show)

newtype SurfaceScope surface = SurfaceScope
    { unSurfaceScope :: LiveUpdateScope
    }
    deriving (Eq, Show)

newtype SurfaceFragmentRef surface = SurfaceFragmentRef
    { unSurfaceFragmentRef :: LiveFragmentRef
    }
    deriving (Eq, Show)

data LiveSurfaceDefinition scope fragment = LiveSurfaceDefinition
    { surfaceFeature                :: !Text
    , surfaceScope                  :: scope -> LiveUpdateScope
    , surfaceDefaultFragments       :: scope -> [fragment]
    , surfaceFragmentRef            :: scope -> fragment -> LiveFragmentRef
    , surfaceDecorateRequestsWithin :: scope -> [Text]
    }

data TypedLiveSurfaceDefinition surface scope fragment = TypedLiveSurfaceDefinition
    { typedSurfaceFeature                :: !Text
    , typedSurfaceScope                  :: scope -> SurfaceScope surface
    , typedSurfaceDefaultFragments       :: scope -> [fragment]
    , typedSurfaceFragmentRef            :: scope -> fragment -> SurfaceFragmentRef surface
    , typedSurfaceDecorateRequestsWithin :: scope -> [Text]
    }

data ProjectionLiveSurfaceDefinition scope snapshot fragment = ProjectionLiveSurfaceDefinition
    { liveSurfaceDefinition       :: !(LiveSurfaceDefinition scope fragment)
    , surfaceProjectionDefinition :: !(SurfaceProjectionDefinition scope snapshot fragment)
    }

data LiveSurfaceBroadcastOptions = LiveSurfaceBroadcastOptions
    { warmProjectionAfterBroadcast :: !Bool
    }
    deriving (Eq, Show)

defaultLiveSurfaceBroadcastOptions :: LiveSurfaceBroadcastOptions
defaultLiveSurfaceBroadcastOptions =
    LiveSurfaceBroadcastOptions
        { warmProjectionAfterBroadcast = False
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

typedLiveSurfaceDefinition :: TypedLiveSurfaceDefinition surface scope fragment -> LiveSurfaceDefinition scope fragment
typedLiveSurfaceDefinition definition =
    LiveSurfaceDefinition
        { surfaceFeature = definition.typedSurfaceFeature
        , surfaceScope = unSurfaceScope . definition.typedSurfaceScope
        , surfaceDefaultFragments = definition.typedSurfaceDefaultFragments
        , surfaceFragmentRef = \surfaceKey fragment ->
            unSurfaceFragmentRef (definition.typedSurfaceFragmentRef surfaceKey fragment)
        , surfaceDecorateRequestsWithin = definition.typedSurfaceDecorateRequestsWithin
        }

mkTypedDefinedLiveSurface :: TypedLiveSurfaceDefinition surface scope fragment -> scope -> LiveSurfaceConfig
mkTypedDefinedLiveSurface definition =
    mkDefinedLiveSurface (typedLiveSurfaceDefinition definition)

typedLiveSurfaceFragmentRef :: TypedLiveSurfaceDefinition surface scope fragment -> scope -> fragment -> SurfaceFragmentRef surface
typedLiveSurfaceFragmentRef definition surfaceKey fragment =
    definition.typedSurfaceFragmentRef surfaceKey fragment

typedLiveSurfaceFragmentRefs :: TypedLiveSurfaceDefinition surface scope fragment -> scope -> [fragment] -> [SurfaceFragmentRef surface]
typedLiveSurfaceFragmentRefs definition surfaceKey =
    map (typedLiveSurfaceFragmentRef definition surfaceKey)

unSurfaceFragmentRefs :: [SurfaceFragmentRef surface] -> [LiveFragmentRef]
unSurfaceFragmentRefs =
    map unSurfaceFragmentRef

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

broadcastProjectionSurfaceFragments ::
    forall scope snapshot fragment.
    (?context :: ControllerContext, ?request :: Request, Dynamic.Typeable snapshot) =>
    ProjectionLiveSurfaceDefinition scope snapshot fragment ->
    scope ->
    [fragment] ->
    IO LiveUpdateBroadcastResult
broadcastProjectionSurfaceFragments =
    broadcastProjectionSurfaceFragmentsWith defaultLiveSurfaceBroadcastOptions

broadcastProjectionSurfaceFragmentsWith ::
    forall scope snapshot fragment.
    (?context :: ControllerContext, ?request :: Request, Dynamic.Typeable snapshot) =>
    LiveSurfaceBroadcastOptions ->
    ProjectionLiveSurfaceDefinition scope snapshot fragment ->
    scope ->
    [fragment] ->
    IO LiveUpdateBroadcastResult
broadcastProjectionSurfaceFragmentsWith options definition surfaceKey fragments = do
    result <-
        broadcastLiveInvalidationDetailed
            (definition.liveSurfaceDefinition.surfaceScope surfaceKey)
            liveUpdateSourceClientId
            (liveSurfaceFragmentRefs definition.liveSurfaceDefinition surfaceKey fragments)
    when options.warmProjectionAfterBroadcast do
        warmLiveSurfaceProjection definition surfaceKey
    pure result

mkSurfaceProjectionDefinition ::
    LiveSurfaceDefinition scope fragment ->
    Text ->
    SurfaceProjectionCachePolicy ->
    (scope -> Text) ->
    IO Text ->
    (scope -> IO Int) ->
    (scope -> IO snapshot) ->
    (snapshot -> fragment -> Maybe Blaze.Html) ->
    ProjectionLiveSurfaceDefinition scope snapshot fragment
mkSurfaceProjectionDefinition liveSurfaceDefinition surfaceName cachePolicy scopeKey viewerKey currentVersion loadProjection renderFragment =
    ProjectionLiveSurfaceDefinition
        { liveSurfaceDefinition
        , surfaceProjectionDefinition =
            SurfaceProjectionDefinition
                { surfaceName
                , cachePolicy
                , scopeKey
                , viewerKey
                , currentVersion
                , loadProjection
                , renderFragment
                , buildFragmentRef = liveSurfaceFragmentRef liveSurfaceDefinition
                }
        }

liveSurfaceProjectionFragmentRef :: ProjectionLiveSurfaceDefinition scope snapshot fragment -> scope -> fragment -> LiveFragmentRef
liveSurfaceProjectionFragmentRef definition =
    liveSurfaceFragmentRef definition.liveSurfaceDefinition

loadLiveSurfaceProjection ::
    forall scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    ProjectionLiveSurfaceDefinition scope snapshot fragment ->
    scope ->
    IO snapshot
loadLiveSurfaceProjection definition =
    loadSurfaceProjection definition.surfaceProjectionDefinition

loadLiveSurfaceProjectionFromStore ::
    forall scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    SurfaceProjectionStore ->
    ProjectionLiveSurfaceDefinition scope snapshot fragment ->
    scope ->
    IO snapshot
loadLiveSurfaceProjectionFromStore store definition =
    loadSurfaceProjectionFromStore store definition.surfaceProjectionDefinition

warmLiveSurfaceProjection ::
    forall scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    ProjectionLiveSurfaceDefinition scope snapshot fragment ->
    scope ->
    IO ()
warmLiveSurfaceProjection definition =
    warmSurfaceProjection definition.surfaceProjectionDefinition

warmLiveSurfaceProjectionFromStore ::
    forall scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    SurfaceProjectionStore ->
    ProjectionLiveSurfaceDefinition scope snapshot fragment ->
    scope ->
    IO ()
warmLiveSurfaceProjectionFromStore store definition =
    warmSurfaceProjectionFromStore store definition.surfaceProjectionDefinition

renderLiveSurfaceProjectionFragment ::
    forall scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    ProjectionLiveSurfaceDefinition scope snapshot fragment ->
    scope ->
    fragment ->
    IO (Maybe Blaze.Html)
renderLiveSurfaceProjectionFragment definition =
    renderSurfaceProjectionFragment definition.surfaceProjectionDefinition

renderLiveSurfaceProjectionFragmentFromStore ::
    forall scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    SurfaceProjectionStore ->
    ProjectionLiveSurfaceDefinition scope snapshot fragment ->
    scope ->
    fragment ->
    IO (Maybe Blaze.Html)
renderLiveSurfaceProjectionFragmentFromStore store definition =
    renderSurfaceProjectionFragmentFromStore store definition.surfaceProjectionDefinition

liveSurfaceConfigJson :: LiveSurfaceConfig -> Text
liveSurfaceConfigJson =
    Text.decodeUtf8 . LBS.toStrict . Aeson.encode
