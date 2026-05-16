module Application.Helper.LiveSurface.Internal
    ( LiveSurfaceConfig (..)
    , LiveSurfaceBroadcastOptions (..)
    , LiveSurfaceDefinition (..)
    , LiveScopeAuthorizationRequirement (..)
    , LiveSurfaceAuthorization (..)
    , ProjectionLiveSurfaceDefinition (..)
    , SurfaceFragmentRef (..)
    , LiveSurfaceMutation (..)
    , LiveSurfaceMutationResult (..)
    , SurfaceScope (..)
    , TypedLiveSurfaceDefinition (..)
    , authorizeLiveScopeRequirement
    , authorizeLiveUpdateScope
    , authorizeTypedLiveSurfaceScope
    , authorizeTypedLiveSurfaceWireScope
    , broadcastProjectionSurfaceFragments
    , broadcastProjectionSurfaceFragmentsWith
    , broadcastSurfaceFragments
    , broadcastTypedSurfaceFragments
    , broadcastTypedSurfaceFragmentsWithoutContext
    , broadcastTypedSurfaceResync
    , broadcastTypedSurfaceResyncWithoutContext
    , defaultLiveSurfaceBroadcastOptions
    , defaultLiveUpdateScopeAuthorizationRequirement
    , ensureTypedLiveSurfaceAuthorized
    , liveSurfaceAuthorizationByRequirement
    , liveSurfaceAuthorizationByScope
    , liveSurfaceMutation
    , liveSurfaceProjectionFragmentRef
    , liveSurfaceConfigJson
    , liveSurfaceFragmentRef
    , liveSurfaceFragmentRefs
    , loadLiveSurfaceProjection
    , loadLiveSurfaceProjectionFromStore
    , mkDefinedLiveSurface
    , mkLiveSurface
    , mkSurfaceFragmentRef
    , mkSurfaceProjectionDefinition
    , mkTypedDefinedLiveSurface
    , performTypedLiveSurfaceMutation
    , renderLiveSurfaceProjectionFragment
    , renderLiveSurfaceProjectionFragmentFromStore
    , setLiveSurfaceActorRefresh
    , setTypedLiveSurfaceActorRefresh
    , surfaceFragmentRefWithDeferUntilBlur
    , surfaceFragmentRefWithFocusedProtection
    , surfaceFragmentRefWithProtection
    , typedLiveSurfaceDefinition
    , typedLiveSurfaceFragmentRef
    , typedLiveSurfaceFragmentRefs
    , typedLiveSurfaceMutationRefs
    , unSurfaceFragmentRefs
    , warmLiveSurfaceProjection
    , warmLiveSurfaceProjectionFromStore
    ) where

import Application.Helper.LiveUpdate.Internal
import Application.Helper.SurfaceProjection
import Application.Helper.ControllerAccess (hasRole)
import Application.Helper.ControllerContext (authenticatedCurrentUser,
                                             currentUserIsSuperAdmin,
                                             currentVenueOrNothing)
import Application.Helper.ControllerSupport (VenueRole (..))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import Data.Coerce (coerce)
import qualified Data.Dynamic as Dynamic
import qualified Data.Text.Encoding as Text
import qualified Data.UUID as UUID
import Generated.Types
import IHP.Controller.Context (ControllerContext)
import IHP.ControllerPrelude (accessDeniedUnless, fetchOneOrNothing,
                              filterWhere, query, setHeader)
import IHP.ControllerSupport (Request)
import IHP.ModelSupport
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

data LiveSurfaceAuthorization scope = LiveSurfaceAuthorization
    { authorizeLiveSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => scope -> IO Bool
    }

data TypedLiveSurfaceDefinition surface scope fragment = TypedLiveSurfaceDefinition
    { typedSurfaceFeature                :: !Text
    , typedSurfaceScope                  :: scope -> SurfaceScope surface
    , typedSurfaceScopeFromWire          :: LiveUpdateScope -> Maybe scope
    , typedSurfaceDefaultFragments       :: scope -> [fragment]
    , typedSurfaceFragmentRef            :: scope -> fragment -> SurfaceFragmentRef surface
    , typedSurfaceDecorateRequestsWithin :: scope -> [Text]
    , typedSurfaceAuthorize              :: !(LiveSurfaceAuthorization scope)
    }

data LiveSurfaceMutation scope fragment = LiveSurfaceMutation
    { liveMutationScope            :: !scope
    , liveMutationActorFragments   :: ![fragment]
    , liveMutationPassiveFragments :: ![fragment]
    }

data LiveSurfaceMutationResult surface = LiveSurfaceMutationResult
    { actorSurfaceFragmentRefs   :: ![SurfaceFragmentRef surface]
    , passiveSurfaceFragmentRefs :: ![SurfaceFragmentRef surface]
    , liveMutationBroadcast      :: !(Maybe LiveUpdateBroadcastResult)
    }

data LiveScopeAuthorizationRequirement
    = RequireCurrentVenue UUID.UUID
    | RequireCurrentVenueUser UUID.UUID UUID.UUID
    | RequireCurrentVenueRosterGroup UUID.UUID UUID.UUID
    | RequireCurrentVenueAdmin UUID.UUID
    | RequireCurrentVenueManager UUID.UUID
    | RequireCurrentVenueOwner UUID.UUID
    | RequireCurrentVenueAdminRosterGroup UUID.UUID UUID.UUID
    | RequireSupportSuperAdmin
    deriving (Eq, Show)

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

mkSurfaceFragmentRef :: LiveFragmentKey -> Text -> Text -> SurfaceFragmentRef surface
mkSurfaceFragmentRef fragmentKey targetId url =
    SurfaceFragmentRef (mkLiveFragmentRef fragmentKey targetId url)

surfaceFragmentRefWithProtection :: LiveFragmentProtection -> SurfaceFragmentRef surface -> SurfaceFragmentRef surface
surfaceFragmentRefWithProtection protection (SurfaceFragmentRef ref) =
    SurfaceFragmentRef ref { protectionPolicy = protection }

surfaceFragmentRefWithDeferUntilBlur :: Bool -> SurfaceFragmentRef surface -> SurfaceFragmentRef surface
surfaceFragmentRefWithDeferUntilBlur defer (SurfaceFragmentRef ref) =
    SurfaceFragmentRef ref { deferUntilBlur = defer }

surfaceFragmentRefWithFocusedProtection :: LiveFragmentProtection -> SurfaceFragmentRef surface -> SurfaceFragmentRef surface
surfaceFragmentRefWithFocusedProtection protection =
    surfaceFragmentRefWithDeferUntilBlur True . surfaceFragmentRefWithProtection protection

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

liveSurfaceMutation :: scope -> [fragment] -> LiveSurfaceMutation scope fragment
liveSurfaceMutation surfaceKey fragments =
    LiveSurfaceMutation
        { liveMutationScope = surfaceKey
        , liveMutationActorFragments = fragments
        , liveMutationPassiveFragments = fragments
        }

typedLiveSurfaceMutationRefs ::
    TypedLiveSurfaceDefinition surface scope fragment ->
    LiveSurfaceMutation scope fragment ->
    ([SurfaceFragmentRef surface], [SurfaceFragmentRef surface])
typedLiveSurfaceMutationRefs definition mutation =
    ( typedLiveSurfaceFragmentRefs definition mutation.liveMutationScope mutation.liveMutationActorFragments
    , typedLiveSurfaceFragmentRefs definition mutation.liveMutationScope mutation.liveMutationPassiveFragments
    )

performTypedLiveSurfaceMutation ::
    (?context :: ControllerContext, ?request :: Request) =>
    TypedLiveSurfaceDefinition surface scope fragment ->
    LiveSurfaceMutation scope fragment ->
    IO (LiveSurfaceMutationResult surface)
performTypedLiveSurfaceMutation definition mutation = do
    let (actorRefs, passiveRefs) = typedLiveSurfaceMutationRefs definition mutation
    broadcastResult <-
        if null mutation.liveMutationPassiveFragments
            then pure Nothing
            else
                Just
                    <$> broadcastLiveInvalidationDetailed
                        (unSurfaceScope (definition.typedSurfaceScope mutation.liveMutationScope))
                        liveUpdateSourceClientId
                        (unSurfaceFragmentRefs passiveRefs)
    pure
        LiveSurfaceMutationResult
            { actorSurfaceFragmentRefs = actorRefs
            , passiveSurfaceFragmentRefs = passiveRefs
            , liveMutationBroadcast = broadcastResult
            }

setLiveSurfaceActorRefresh ::
    (?context :: ControllerContext, ?request :: Request) =>
    LiveSurfaceMutationResult surface ->
    IO ()
setLiveSurfaceActorRefresh result =
    setHeader
        ( "HX-Trigger"
        , cs (Aeson.encode (liveFragmentsRefreshTriggerPayload (unSurfaceFragmentRefs result.actorSurfaceFragmentRefs)))
        )

authorizeTypedLiveSurfaceScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    IO Bool
authorizeTypedLiveSurfaceScope definition =
    authorizeLiveSurfaceScope definition.typedSurfaceAuthorize

authorizeTypedLiveSurfaceWireScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    TypedLiveSurfaceDefinition surface scope fragment ->
    LiveUpdateScope ->
    IO (Maybe Bool)
authorizeTypedLiveSurfaceWireScope definition wireScope =
    case definition.typedSurfaceScopeFromWire wireScope of
        Just surfaceKey
            | unSurfaceScope (definition.typedSurfaceScope surfaceKey) == wireScope ->
                Just <$> authorizeTypedLiveSurfaceScope definition surfaceKey
        _ -> pure Nothing

ensureTypedLiveSurfaceAuthorized ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    IO ()
ensureTypedLiveSurfaceAuthorized definition surfaceKey = do
    authorized <- authorizeTypedLiveSurfaceScope definition surfaceKey
    accessDeniedUnless authorized

liveSurfaceAuthorizationByScope ::
    (scope -> SurfaceScope surface) ->
    LiveSurfaceAuthorization scope
liveSurfaceAuthorizationByScope surfaceScope =
    LiveSurfaceAuthorization
        { authorizeLiveSurfaceScope = authorizeLiveUpdateScope . unSurfaceScope . surfaceScope
        }

liveSurfaceAuthorizationByRequirement ::
    (scope -> LiveScopeAuthorizationRequirement) ->
    LiveSurfaceAuthorization scope
liveSurfaceAuthorizationByRequirement requirement =
    LiveSurfaceAuthorization
        { authorizeLiveSurfaceScope = authorizeLiveScopeRequirement . requirement
        }

authorizeLiveUpdateScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    LiveUpdateScope ->
    IO Bool
authorizeLiveUpdateScope =
    authorizeLiveScopeRequirement . defaultLiveUpdateScopeAuthorizationRequirement

defaultLiveUpdateScopeAuthorizationRequirement :: LiveUpdateScope -> LiveScopeAuthorizationRequirement
defaultLiveUpdateScopeAuthorizationRequirement RosterWeekScope { venueId, rosterGroupId } =
    RequireCurrentVenueRosterGroup venueId rosterGroupId
defaultLiveUpdateScopeAuthorizationRequirement AdminInvitesScope { venueId } =
    RequireCurrentVenueAdmin venueId
defaultLiveUpdateScopeAuthorizationRequirement AdminExportsScope { venueId } =
    RequireCurrentVenueAdmin venueId
defaultLiveUpdateScopeAuthorizationRequirement AdminShiftTypesScope { venueId } =
    RequireCurrentVenueAdmin venueId
defaultLiveUpdateScopeAuthorizationRequirement AdminRosterGroupsScope { venueId } =
    RequireCurrentVenueAdmin venueId
defaultLiveUpdateScopeAuthorizationRequirement AdminXeroScope { venueId } =
    RequireCurrentVenueOwner venueId
defaultLiveUpdateScopeAuthorizationRequirement BillingScope { venueId } =
    RequireCurrentVenueOwner venueId
defaultLiveUpdateScopeAuthorizationRequirement LeaveRequestsScope { venueId } =
    RequireCurrentVenueManager venueId
defaultLiveUpdateScopeAuthorizationRequirement TimesheetWeekScope { venueId } =
    RequireCurrentVenue venueId
defaultLiveUpdateScopeAuthorizationRequirement ProfileScope { venueId, userId } =
    RequireCurrentVenueUser venueId userId
defaultLiveUpdateScopeAuthorizationRequirement StaffComplianceScope { venueId } =
    RequireCurrentVenueManager venueId
defaultLiveUpdateScopeAuthorizationRequirement SupportPlatformScope =
    RequireSupportSuperAdmin

authorizeLiveScopeRequirement ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    LiveScopeAuthorizationRequirement ->
    IO Bool
authorizeLiveScopeRequirement (RequireCurrentVenue venueId) =
    pure (currentVenueMatches venueId)
authorizeLiveScopeRequirement (RequireCurrentVenueUser venueId userId) =
    pure (currentVenueMatches venueId && userId == unpackId authenticatedCurrentUser.id)
authorizeLiveScopeRequirement (RequireCurrentVenueRosterGroup venueId rosterGroupId) =
    if currentVenueMatches venueId
        then isAuthorizedCurrentVenueRosterGroupScope rosterGroupId
        else pure False
authorizeLiveScopeRequirement (RequireCurrentVenueAdmin venueId) =
    pure (currentVenueMatches venueId && hasRole VenueAdminRole)
authorizeLiveScopeRequirement (RequireCurrentVenueManager venueId) =
    pure (currentVenueMatches venueId && hasRole ManagerRole')
authorizeLiveScopeRequirement (RequireCurrentVenueOwner venueId) =
    pure (currentVenueMatches venueId && hasRole VenueOwnerRole)
authorizeLiveScopeRequirement (RequireCurrentVenueAdminRosterGroup venueId rosterGroupId) =
    if currentVenueMatches venueId
        then do
            hasRosterGroupAccess <- isAuthorizedCurrentVenueRosterGroupScope rosterGroupId
            pure (hasRosterGroupAccess && hasRole VenueAdminRole)
        else pure False
authorizeLiveScopeRequirement RequireSupportSuperAdmin =
    pure currentUserIsSuperAdmin

currentVenueMatches :: (?context :: ControllerContext) => UUID.UUID -> Bool
currentVenueMatches venueId =
    maybe False (\venue -> venueId == unpackId venue.id) currentVenueOrNothing

isAuthorizedCurrentVenueRosterGroupScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    UUID.UUID ->
    IO Bool
isAuthorizedCurrentVenueRosterGroupScope rosterGroupId = do
    case currentVenueOrNothing of
        Nothing -> pure False
        Just venue -> do
            rosterGroupOrNothing <-
                query @RosterGroup
                    |> filterWhere (#id, coerce rosterGroupId)
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchOneOrNothing
            pure (isJust rosterGroupOrNothing)

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

broadcastTypedSurfaceFragments ::
    (?context :: ControllerContext, ?request :: Request) =>
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    [fragment] ->
    IO ()
broadcastTypedSurfaceFragments definition surfaceKey fragments =
    broadcastLiveInvalidation
        (unSurfaceScope (definition.typedSurfaceScope surfaceKey))
        liveUpdateSourceClientId
        (unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs definition surfaceKey fragments))

broadcastTypedSurfaceResync ::
    (?context :: ControllerContext, ?request :: Request) =>
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    IO ()
broadcastTypedSurfaceResync definition surfaceKey =
    broadcastLiveResync
        (unSurfaceScope (definition.typedSurfaceScope surfaceKey))
        liveUpdateSourceClientId

broadcastTypedSurfaceFragmentsWithoutContext ::
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    Maybe Text ->
    [fragment] ->
    IO LiveUpdateBroadcastResult
broadcastTypedSurfaceFragmentsWithoutContext definition surfaceKey sourceClientId fragments =
    broadcastLiveInvalidationDetailedWithoutContext
        (unSurfaceScope (definition.typedSurfaceScope surfaceKey))
        sourceClientId
        (unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs definition surfaceKey fragments))

broadcastTypedSurfaceResyncWithoutContext ::
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    Maybe Text ->
    IO ()
broadcastTypedSurfaceResyncWithoutContext definition surfaceKey sourceClientId =
    broadcastLiveResyncWithoutContext
        (unSurfaceScope (definition.typedSurfaceScope surfaceKey))
        sourceClientId

setTypedLiveSurfaceActorRefresh ::
    (?context :: ControllerContext, ?request :: Request) =>
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    [fragment] ->
    IO ()
setTypedLiveSurfaceActorRefresh definition surfaceKey fragments =
    setHeader
        ( "HX-Trigger"
        , cs (Aeson.encode (liveFragmentsRefreshTriggerPayload (unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs definition surfaceKey fragments))))
        )

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
