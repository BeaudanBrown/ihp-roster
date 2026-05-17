module Application.Helper.LiveSurface.Internal
    ( LiveSurfaceConfig (..)
    , LiveSurfaceBroadcastOptions (..)
        , LiveScopeAuthorizationRequirement (..)
    , LiveSurfaceAuthorization (..)
    , ProjectionLiveSurfaceDefinition (..)
    , SurfaceFragmentRef (..)
    , LiveSurfaceMutation (..)
    , LiveSurfaceMutationResult (..)
    , SurfaceScope (..)
    , TypedLiveSurfaceDefinition (..)
    , authorizeLiveScopeRequirement
    , authorizeTypedLiveSurfaceScope
    , authorizeTypedLiveSurfaceWireScope
    , broadcastProjectionSurfaceFragments
    , broadcastProjectionSurfaceFragmentsWith
    , broadcastTypedSurfaceFragments
    , broadcastTypedSurfaceFragmentsAndSetActorRefresh
    , broadcastTypedSurfaceFragmentsWithoutContext
    , broadcastTypedSurfaceResync
    , broadcastTypedSurfaceResyncWithoutContext
    , defaultLiveSurfaceBroadcastOptions
    , defaultLiveUpdateScopeAuthorizationRequirement
    , ensureTypedLiveSurfaceAuthorized
    , liveSurfaceAuthorizationByRequirement
    , liveSurfaceMutation
    , liveSurfaceProjectionFragmentRef
    , liveSurfaceConfigJson
    , loadLiveSurfaceProjection
    , loadLiveSurfaceProjectionFromStore
    , mkSurfaceFragmentRef
    , mkSurfaceProjectionDefinition
    , mkTypedDefinedLiveSurface
    , performTypedLiveSurfaceMutation
    , performTypedLiveSurfaceMutationAndSetActorRefresh
    , renderLiveSurfaceProjectionFragment
    , renderLiveSurfaceProjectionFragmentFromStore
    , setTypedLiveSurfaceActorRefresh
    , surfaceFragmentRefWithDeferUntilBlur
    , surfaceFragmentRefWithFocusedProtection
    , surfaceFragmentRefWithProtection
    , typedLiveSurfaceFragmentRef
    , typedLiveSurfaceFragmentRefs
    , typedLiveSurfaceMutationRefs
    , unSurfaceFragmentRefs
    , warmLiveSurfaceProjection
    , warmLiveSurfaceProjectionFromStore
    ) where

import Application.Helper.LiveResource (LiveResource)
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
    , resyncFragments        :: ![LiveUpdateWireFragment]
    , decorateRequestsWithin :: ![Text]
    }
    deriving (Eq, Show)

newtype SurfaceScope surface = SurfaceScope
    { unSurfaceScope :: LiveUpdateScope
    }
    deriving (Eq, Show)

newtype SurfaceFragmentRef surface = SurfaceFragmentRef
    { unSurfaceFragmentRef :: LiveUpdateWireFragment
    }
    deriving (Eq, Show)

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
    , typedSurfaceDependsOn              :: scope -> fragment -> [LiveResource]
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
    | RequireCurrentVenueStaff UUID.UUID UUID.UUID
    | RequireCurrentVenueRosterGroup UUID.UUID UUID.UUID
    | RequireCurrentVenueAdmin UUID.UUID
    | RequireCurrentVenueManager UUID.UUID
    | RequireCurrentVenueOwner UUID.UUID
    | RequireCurrentVenueAdminRosterGroup UUID.UUID UUID.UUID
    | RequireSupportSuperAdmin
    deriving (Eq, Show)

data ProjectionLiveSurfaceDefinition surface scope snapshot fragment = ProjectionLiveSurfaceDefinition
    { projectionSurfaceScope       :: !(scope -> SurfaceScope surface)
    , projectionSurfaceFragmentRef :: !(scope -> fragment -> SurfaceFragmentRef surface)
    , surfaceProjectionDefinition  :: !(SurfaceProjectionDefinition scope snapshot fragment)
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

mkSurfaceFragmentRef :: LiveFragmentKey -> Text -> Text -> SurfaceFragmentRef surface
mkSurfaceFragmentRef fragmentKey targetId url =
    SurfaceFragmentRef (mkLiveUpdateWireFragment fragmentKey targetId url)

surfaceFragmentRefWithProtection :: LiveFragmentProtection -> SurfaceFragmentRef surface -> SurfaceFragmentRef surface
surfaceFragmentRefWithProtection protection (SurfaceFragmentRef ref) =
    SurfaceFragmentRef ref { protectionPolicy = protection }

surfaceFragmentRefWithDeferUntilBlur :: Bool -> SurfaceFragmentRef surface -> SurfaceFragmentRef surface
surfaceFragmentRefWithDeferUntilBlur defer (SurfaceFragmentRef ref) =
    SurfaceFragmentRef ref { deferUntilBlur = defer }

surfaceFragmentRefWithFocusedProtection :: LiveFragmentProtection -> SurfaceFragmentRef surface -> SurfaceFragmentRef surface
surfaceFragmentRefWithFocusedProtection protection =
    surfaceFragmentRefWithDeferUntilBlur True . surfaceFragmentRefWithProtection protection

mkTypedDefinedLiveSurface :: TypedLiveSurfaceDefinition surface scope fragment -> scope -> LiveSurfaceConfig
mkTypedDefinedLiveSurface definition surfaceKey =
    let surfaceScope = unSurfaceScope (definition.typedSurfaceScope surfaceKey)
     in LiveSurfaceConfig
            { feature = definition.typedSurfaceFeature
            , socketPath = "/live-updates"
            , scope = surfaceScope
            , scopeKey = liveUpdateScopeKey surfaceScope
            , resyncFragments = unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs definition surfaceKey (definition.typedSurfaceDefaultFragments surfaceKey))
            , decorateRequestsWithin = definition.typedSurfaceDecorateRequestsWithin surfaceKey
            }

typedLiveSurfaceFragmentRef :: TypedLiveSurfaceDefinition surface scope fragment -> scope -> fragment -> SurfaceFragmentRef surface
typedLiveSurfaceFragmentRef definition surfaceKey fragment =
    definition.typedSurfaceFragmentRef surfaceKey fragment

typedLiveSurfaceFragmentRefs :: TypedLiveSurfaceDefinition surface scope fragment -> scope -> [fragment] -> [SurfaceFragmentRef surface]
typedLiveSurfaceFragmentRefs definition surfaceKey =
    map (typedLiveSurfaceFragmentRef definition surfaceKey)

unSurfaceFragmentRefs :: [SurfaceFragmentRef surface] -> [LiveUpdateWireFragment]
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

performTypedLiveSurfaceMutationAndSetActorRefresh ::
    (?context :: ControllerContext, ?request :: Request) =>
    TypedLiveSurfaceDefinition surface scope fragment ->
    LiveSurfaceMutation scope fragment ->
    IO (LiveSurfaceMutationResult surface)
performTypedLiveSurfaceMutationAndSetActorRefresh definition mutation = do
    result <- performTypedLiveSurfaceMutation definition mutation
    setTypedLiveSurfaceActorRefresh definition mutation.liveMutationScope mutation.liveMutationActorFragments
    pure result

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

liveSurfaceAuthorizationByRequirement ::
    (scope -> LiveScopeAuthorizationRequirement) ->
    LiveSurfaceAuthorization scope
liveSurfaceAuthorizationByRequirement requirement =
    LiveSurfaceAuthorization
        { authorizeLiveSurfaceScope = authorizeLiveScopeRequirement . requirement
        }

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
defaultLiveUpdateScopeAuthorizationRequirement ProfileScope { venueId, staffId } =
    RequireCurrentVenueStaff venueId staffId
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
authorizeLiveScopeRequirement (RequireCurrentVenueStaff venueId staffId) =
    if currentVenueMatches venueId
        then do
            maybeStaff <-
                query @Staff
                    |> filterWhere (#id, Id staffId :: Id Staff)
                    |> filterWhere (#venueId, venueId)
                    |> fetchOneOrNothing
            pure (maybe False (\staff -> staff.userId == Just (unpackId authenticatedCurrentUser.id)) maybeStaff)
        else pure False
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

broadcastTypedSurfaceFragmentsAndSetActorRefresh ::
    (?context :: ControllerContext, ?request :: Request) =>
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    [fragment] ->
    IO ()
broadcastTypedSurfaceFragmentsAndSetActorRefresh definition surfaceKey fragments = do
    _ <- performTypedLiveSurfaceMutationAndSetActorRefresh definition (liveSurfaceMutation surfaceKey fragments)
    pure ()

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
broadcastTypedSurfaceResyncWithoutContext definition surfaceKey =
    broadcastLiveResyncWithoutContext
        (unSurfaceScope (definition.typedSurfaceScope surfaceKey))

setTypedLiveSurfaceActorRefresh ::
    (?context :: ControllerContext, ?request :: Request) =>
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    [fragment] ->
    IO ()
setTypedLiveSurfaceActorRefresh definition surfaceKey fragments =
    setHeader
        ( "HX-Trigger"
        , cs (Aeson.encode (liveUpdateWireRefreshTriggerPayload (unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs definition surfaceKey fragments))))
        )

liveUpdateWireRefreshTriggerPayload :: [LiveUpdateWireFragment] -> Aeson.Value
liveUpdateWireRefreshTriggerPayload fragments =
    let detail =
            Aeson.object
                [ "fragments" Aeson..= coalesceLiveUpdateWireFragments fragments
                ]
     in Aeson.object
            [ "app-live-fragments-refresh" Aeson..= detail
            , "app-roster-fragments-refresh" Aeson..= detail
            ]

broadcastProjectionSurfaceFragments ::
    forall surface scope snapshot fragment.
    (?context :: ControllerContext, ?request :: Request, Dynamic.Typeable snapshot) =>
    ProjectionLiveSurfaceDefinition surface scope snapshot fragment ->
    scope ->
    [fragment] ->
    IO LiveUpdateBroadcastResult
broadcastProjectionSurfaceFragments =
    broadcastProjectionSurfaceFragmentsWith defaultLiveSurfaceBroadcastOptions

broadcastProjectionSurfaceFragmentsWith ::
    forall surface scope snapshot fragment.
    (?context :: ControllerContext, ?request :: Request, Dynamic.Typeable snapshot) =>
    LiveSurfaceBroadcastOptions ->
    ProjectionLiveSurfaceDefinition surface scope snapshot fragment ->
    scope ->
    [fragment] ->
    IO LiveUpdateBroadcastResult
broadcastProjectionSurfaceFragmentsWith options definition surfaceKey fragments = do
    result <-
        broadcastLiveInvalidationDetailed
            (unSurfaceScope (definition.projectionSurfaceScope surfaceKey))
            liveUpdateSourceClientId
            (unSurfaceFragmentRefs (map (definition.projectionSurfaceFragmentRef surfaceKey) fragments))
    when options.warmProjectionAfterBroadcast do
        warmLiveSurfaceProjection definition surfaceKey
    pure result

mkSurfaceProjectionDefinition ::
    TypedLiveSurfaceDefinition surface scope fragment ->
    Text ->
    SurfaceProjectionCachePolicy ->
    (scope -> Text) ->
    IO Text ->
    (scope -> IO Int) ->
    (scope -> IO snapshot) ->
    (snapshot -> fragment -> Maybe Blaze.Html) ->
    ProjectionLiveSurfaceDefinition surface scope snapshot fragment
mkSurfaceProjectionDefinition typedDefinition surfaceName cachePolicy scopeKey viewerKey currentVersion loadProjection renderFragment =
    ProjectionLiveSurfaceDefinition
        { projectionSurfaceScope = typedDefinition.typedSurfaceScope
        , projectionSurfaceFragmentRef = typedDefinition.typedSurfaceFragmentRef
        , surfaceProjectionDefinition =
            SurfaceProjectionDefinition
                { surfaceName
                , cachePolicy
                , scopeKey
                , viewerKey
                , currentVersion
                , loadProjection
                , renderFragment
                , buildFragmentRef = \surfaceKey fragment ->
                    unSurfaceFragmentRef (typedDefinition.typedSurfaceFragmentRef surfaceKey fragment)
                }
        }

liveSurfaceProjectionFragmentRef :: ProjectionLiveSurfaceDefinition surface scope snapshot fragment -> scope -> fragment -> LiveUpdateWireFragment
liveSurfaceProjectionFragmentRef definition surfaceKey fragment =
    unSurfaceFragmentRef (definition.projectionSurfaceFragmentRef surfaceKey fragment)

loadLiveSurfaceProjection ::
    forall surface scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    ProjectionLiveSurfaceDefinition surface scope snapshot fragment ->
    scope ->
    IO snapshot
loadLiveSurfaceProjection definition =
    loadSurfaceProjection definition.surfaceProjectionDefinition

loadLiveSurfaceProjectionFromStore ::
    forall surface scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    SurfaceProjectionStore ->
    ProjectionLiveSurfaceDefinition surface scope snapshot fragment ->
    scope ->
    IO snapshot
loadLiveSurfaceProjectionFromStore store definition =
    loadSurfaceProjectionFromStore store definition.surfaceProjectionDefinition

warmLiveSurfaceProjection ::
    forall surface scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    ProjectionLiveSurfaceDefinition surface scope snapshot fragment ->
    scope ->
    IO ()
warmLiveSurfaceProjection definition =
    warmSurfaceProjection definition.surfaceProjectionDefinition

warmLiveSurfaceProjectionFromStore ::
    forall surface scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    SurfaceProjectionStore ->
    ProjectionLiveSurfaceDefinition surface scope snapshot fragment ->
    scope ->
    IO ()
warmLiveSurfaceProjectionFromStore store definition =
    warmSurfaceProjectionFromStore store definition.surfaceProjectionDefinition

renderLiveSurfaceProjectionFragment ::
    forall surface scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    ProjectionLiveSurfaceDefinition surface scope snapshot fragment ->
    scope ->
    fragment ->
    IO (Maybe Blaze.Html)
renderLiveSurfaceProjectionFragment definition =
    renderSurfaceProjectionFragment definition.surfaceProjectionDefinition

renderLiveSurfaceProjectionFragmentFromStore ::
    forall surface scope snapshot fragment.
    (Dynamic.Typeable snapshot) =>
    SurfaceProjectionStore ->
    ProjectionLiveSurfaceDefinition surface scope snapshot fragment ->
    scope ->
    fragment ->
    IO (Maybe Blaze.Html)
renderLiveSurfaceProjectionFragmentFromStore store definition =
    renderSurfaceProjectionFragmentFromStore store definition.surfaceProjectionDefinition

liveSurfaceConfigJson :: LiveSurfaceConfig -> Text
liveSurfaceConfigJson =
    Text.decodeUtf8 . LBS.toStrict . Aeson.encode
