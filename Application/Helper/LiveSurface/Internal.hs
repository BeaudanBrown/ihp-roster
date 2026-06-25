module Application.Helper.LiveSurface.Internal
    ( LiveSurfaceConfig (..)
    , FragmentContract (..)
    , FragmentDependencies (..)
    , FragmentRenderMode (..)
    , AuthorizedLiveFragment (..)
    , LiveScopeAuthorizationRequirement (..)
    , LiveSurfaceAuthorization (..)
    , ProjectionLiveSurfaceDefinition (..)
    , SurfaceFragmentRef (..)
    , SurfaceScope (..)
    , TypedLiveSurfaceDefinition (..)
    , authorizeLiveScopeRequirement
    , authorizeTypedLiveSurfaceScope
    , authorizeTypedLiveSurfaceWireScope
    , defaultLiveUpdateScopeAuthorizationRequirement
    , ensureTypedLiveSurfaceAuthorized
    , liveFragmentDependsOn
    , liveFragmentResyncOnly
    , liveSurfaceAuthorizationByRequirement
    , liveSurfaceProjectionFragmentRef
    , liveSurfaceConfigJson
    , loadLiveSurfaceProjection
    , loadLiveSurfaceProjectionFromStore
    , mkSurfaceFragmentContract
    , mkSurfaceFragmentRef
    , mkSurfaceProjectionDefinition
    , mkTypedDefinedLiveSurface
    , normalizeSurfaceFragmentRefs
    , normalizeTypedLiveSurfaceFragments
    , renderLiveSurfaceProjectionFragment
    , renderLiveSurfaceProjectionFragmentFromStore
    , renderTypedLiveSurfaceFragmentsFromSnapshot
    , respondWithTypedLiveSurfaceFragments
    , serveTypedLiveFragment
    , setTypedLiveSurfaceActorRefresh
    , surfaceFragmentRefWithDeferUntilBlur
    , surfaceFragmentRefWithFocusedProtection
    , surfaceFragmentRefWithPath
    , surfaceFragmentRefWithProtection
    , typedLiveSurfaceAffectedFragments
    , typedLiveSurfaceFragmentRef
    , typedLiveSurfaceFragmentRefs
    , typedSurfaceDependsOn
    , unSurfaceFragmentRefs
    , warmLiveSurfaceProjection
    , warmLiveSurfaceProjectionFromStore
    ) where

import Application.Helper.ControllerAccess (hasRole)
import Application.Helper.ControllerContext (authenticatedCurrentUser,
                                             currentUserIsSuperAdmin,
                                             currentVenueOrNothing)
import Application.Helper.ControllerSupport (VenueRole (..))
import qualified Application.Helper.Frontend.LiveUpdateSchema as Wire
import Application.Helper.Interaction.Types (EmptyInteractionIntent,
                                             EmptyInteractionLayer,
                                             EmptyInteractionSession,
                                             InteractionCapability)
import Application.Helper.LiveResource (LiveResource)
import Application.Helper.LiveUpdate.Internal
import Application.Helper.Profiling (respondHtmlProfiled)
import Application.Helper.SurfaceProjection
import Application.Helper.View.Oob (OobSwapAttr, outerHtmlOobSwap)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString.Lazy as LBS
import Data.Coerce (coerce)
import qualified Data.Dynamic as Dynamic
import qualified Data.List as List
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Set as Set
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

data SurfaceFragmentRef surface = SurfaceFragmentRef
    { unSurfaceFragmentRef           :: !LiveUpdateWireFragment
    , surfaceFragmentContainmentPath :: ![Text]
    }
    deriving (Eq, Show)

data LiveSurfaceAuthorization scope = LiveSurfaceAuthorization
    { authorizeLiveSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => scope -> IO Bool
    }

data AuthorizedLiveFragment surface scope fragment = AuthorizedLiveFragment
    { authorizedLiveFragmentScope    :: !scope
    , authorizedLiveFragment         :: !fragment
    , authorizedLiveFragmentContract :: !(FragmentContract surface)
    }

data FragmentDependencies
    = DependsOnLiveResources !(NonEmpty LiveResource)
    | ResyncOnlyFragment !Text
    deriving (Eq, Show)

data FragmentRenderMode
    = FragmentPlain
    | FragmentOob !OobSwapAttr
    deriving (Eq, Show)

data FragmentContract surface = FragmentContract
    { fragmentContractRef          :: !(SurfaceFragmentRef surface)
    , fragmentContractDependencies :: !FragmentDependencies
    }
    deriving (Eq, Show)

data TypedLiveSurfaceDefinition surface scope fragment layer session intent = TypedLiveSurfaceDefinition
    { typedSurfaceFeature                :: !Text
    , typedSurfaceScope                  :: scope -> SurfaceScope surface
    , typedSurfaceScopeFromWire          :: LiveUpdateScope -> Maybe scope
    , typedSurfaceDefaultFragments       :: scope -> [fragment]
    , typedSurfaceFragmentContract       :: scope -> fragment -> FragmentContract surface
    , typedSurfaceDecorateRequestsWithin :: scope -> [Text]
    , typedSurfaceAuthorize              :: !(LiveSurfaceAuthorization scope)
    , typedSurfaceInteraction            :: scope -> InteractionCapability (SurfaceFragmentRef surface) fragment layer session intent
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

instance Aeson.ToJSON LiveSurfaceConfig where
    toJSON = Aeson.toJSON . liveSurfaceConfigToWire

instance Aeson.FromJSON LiveSurfaceConfig where
    parseJSON value = liveSurfaceConfigFromWire =<< Aeson.parseJSON value

liveSurfaceConfigToWire :: LiveSurfaceConfig -> Wire.LiveSurfaceConfig
liveSurfaceConfigToWire LiveSurfaceConfig { feature, socketPath, scope, scopeKey, resyncFragments, decorateRequestsWithin } =
    Wire.LiveSurfaceConfig
        { feature
        , socketPath
        , scope = liveUpdateScopeToWire scope
        , scopeKey
        , resyncFragments = map liveUpdateWireFragmentToWire resyncFragments
        , decorateRequestsWithin
        }

liveSurfaceConfigFromWire :: Wire.LiveSurfaceConfig -> Aeson.Parser LiveSurfaceConfig
liveSurfaceConfigFromWire Wire.LiveSurfaceConfig { feature, socketPath, scope, scopeKey, resyncFragments, decorateRequestsWithin } = do
    parsedScope <- liveUpdateScopeFromWire scope
    parsedFragments <- mapM liveUpdateWireFragmentFromWire resyncFragments
    pure
        LiveSurfaceConfig
            { feature
            , socketPath
            , scope = parsedScope
            , scopeKey
            , resyncFragments = parsedFragments
            , decorateRequestsWithin
            }

mkSurfaceFragmentRef :: LiveFragmentKey -> Text -> Text -> SurfaceFragmentRef surface
mkSurfaceFragmentRef fragmentKey targetId url =
    SurfaceFragmentRef
        { unSurfaceFragmentRef = mkLiveUpdateWireFragment fragmentKey targetId url
        , surfaceFragmentContainmentPath = [targetId]
        }

surfaceFragmentRefWithProtection :: LiveFragmentProtection -> SurfaceFragmentRef surface -> SurfaceFragmentRef surface
surfaceFragmentRefWithProtection protection ref =
    ref { unSurfaceFragmentRef = ref.unSurfaceFragmentRef { protectionPolicy = protection } }

surfaceFragmentRefWithDeferUntilBlur :: Bool -> SurfaceFragmentRef surface -> SurfaceFragmentRef surface
surfaceFragmentRefWithDeferUntilBlur defer ref =
    ref { unSurfaceFragmentRef = ref.unSurfaceFragmentRef { deferUntilBlur = defer } }

surfaceFragmentRefWithPath :: [Text] -> SurfaceFragmentRef surface -> SurfaceFragmentRef surface
surfaceFragmentRefWithPath containmentPath ref =
    ref { surfaceFragmentContainmentPath = containmentPath }

surfaceFragmentRefWithFocusedProtection :: LiveFragmentProtection -> SurfaceFragmentRef surface -> SurfaceFragmentRef surface
surfaceFragmentRefWithFocusedProtection protection =
    surfaceFragmentRefWithDeferUntilBlur True . surfaceFragmentRefWithProtection protection

liveFragmentDependsOn :: LiveResource -> [LiveResource] -> FragmentDependencies
liveFragmentDependsOn resource additionalResources =
    DependsOnLiveResources (resource :| additionalResources)

liveFragmentResyncOnly :: Text -> FragmentDependencies
liveFragmentResyncOnly =
    ResyncOnlyFragment

mkSurfaceFragmentContract :: SurfaceFragmentRef surface -> FragmentDependencies -> FragmentContract surface
mkSurfaceFragmentContract fragmentContractRef fragmentContractDependencies =
    FragmentContract { fragmentContractRef, fragmentContractDependencies }

mkTypedDefinedLiveSurface :: TypedLiveSurfaceDefinition surface scope fragment layer session intent -> scope -> LiveSurfaceConfig
mkTypedDefinedLiveSurface definition surfaceKey =
    let surfaceScope = unSurfaceScope (definition.typedSurfaceScope surfaceKey)
     in LiveSurfaceConfig
            { feature = definition.typedSurfaceFeature
            , socketPath = "/live-updates"
            , scope = surfaceScope
            , scopeKey = liveUpdateScopeKey surfaceScope
            , resyncFragments = unSurfaceFragmentRefs (normalizeSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs definition surfaceKey (definition.typedSurfaceDefaultFragments surfaceKey)))
            , decorateRequestsWithin = definition.typedSurfaceDecorateRequestsWithin surfaceKey
            }

typedLiveSurfaceFragmentRef :: TypedLiveSurfaceDefinition surface scope fragment layer session intent -> scope -> fragment -> SurfaceFragmentRef surface
typedLiveSurfaceFragmentRef definition surfaceKey fragment =
    (definition.typedSurfaceFragmentContract surfaceKey fragment).fragmentContractRef

typedLiveSurfaceFragmentRefs :: TypedLiveSurfaceDefinition surface scope fragment layer session intent -> scope -> [fragment] -> [SurfaceFragmentRef surface]
typedLiveSurfaceFragmentRefs definition surfaceKey =
    map (typedLiveSurfaceFragmentRef definition surfaceKey)

typedLiveSurfaceAffectedFragments :: TypedLiveSurfaceDefinition surface scope fragment layer session intent -> scope -> Set.Set LiveResource -> [fragment] -> [fragment]
typedLiveSurfaceAffectedFragments definition surfaceKey touchedResources candidates =
    filter dependsOnTouchedResource candidates
    where
        dependsOnTouchedResource fragment =
            not (Set.null (Set.intersection touchedResources (Set.fromList (typedSurfaceDependsOn definition surfaceKey fragment))))

typedSurfaceDependsOn :: TypedLiveSurfaceDefinition surface scope fragment layer session intent -> scope -> fragment -> [LiveResource]
typedSurfaceDependsOn definition surfaceKey fragment =
    case (definition.typedSurfaceFragmentContract surfaceKey fragment).fragmentContractDependencies of
        DependsOnLiveResources resources -> NonEmpty.toList resources
        ResyncOnlyFragment _             -> []

unSurfaceFragmentRefs :: [SurfaceFragmentRef surface] -> [LiveUpdateWireFragment]
unSurfaceFragmentRefs =
    map unSurfaceFragmentRef

normalizeSurfaceFragmentRefs :: [SurfaceFragmentRef surface] -> [SurfaceFragmentRef surface]
normalizeSurfaceFragmentRefs fragmentRefs =
    filter isNotContainedByAnother uniqueRefs
    where
        uniqueRefs = List.nubBy sameContainmentPath fragmentRefs
        allPaths = map surfaceFragmentContainmentPath uniqueRefs
        sameContainmentPath left right =
            left.surfaceFragmentContainmentPath == right.surfaceFragmentContainmentPath
        isNotContainedByAnother ref =
            not (any (`isProperPrefixOf` ref.surfaceFragmentContainmentPath) allPaths)
        isProperPrefixOf prefix path =
            length prefix < length path && prefix `List.isPrefixOf` path

normalizeTypedLiveSurfaceFragments ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    scope ->
    [fragment] ->
    [fragment]
normalizeTypedLiveSurfaceFragments definition surfaceKey fragments =
    map fst normalizedPairs
    where
        fragmentPairs =
            map
                (\fragment -> (fragment, typedLiveSurfaceFragmentRef definition surfaceKey fragment))
                fragments
        normalizedRefs = normalizeSurfaceFragmentRefs (map snd fragmentPairs)
        normalizedPairs =
            mapMaybe
                (\normalizedRef -> List.find (sameContainmentPath normalizedRef . snd) fragmentPairs)
                normalizedRefs
        sameContainmentPath left right =
            surfaceFragmentContainmentPath left == surfaceFragmentContainmentPath right

renderTypedLiveSurfaceFragmentsFromSnapshot ::
    ProjectionLiveSurfaceDefinition surface scope snapshot fragment ->
    scope ->
    [fragment] ->
    FragmentRenderMode ->
    Blaze.Html ->
    (FragmentRenderMode -> snapshot -> fragment -> Maybe Blaze.Html) ->
    snapshot ->
    Blaze.Html
renderTypedLiveSurfaceFragmentsFromSnapshot definition surfaceKey fragments renderMode extraHtml renderFragment snapshot =
    mconcat (map renderNormalizedFragment normalizedFragments) <> extraHtml
    where
        normalizedFragments =
            normalizeTypedLiveSurfaceFragmentsFromProjection definition surfaceKey fragments
        renderNormalizedFragment fragment =
            fromMaybe mempty (renderFragment renderMode snapshot fragment)

normalizeTypedLiveSurfaceFragmentsFromProjection ::
    ProjectionLiveSurfaceDefinition surface scope snapshot fragment ->
    scope ->
    [fragment] ->
    [fragment]
normalizeTypedLiveSurfaceFragmentsFromProjection definition surfaceKey fragments =
    map fst normalizedPairs
    where
        fragmentPairs =
            map
                (\fragment -> (fragment, definition.projectionSurfaceFragmentRef surfaceKey fragment))
                fragments
        normalizedRefs = normalizeSurfaceFragmentRefs (map snd fragmentPairs)
        normalizedPairs =
            mapMaybe
                (\normalizedRef -> List.find (sameContainmentPath normalizedRef . snd) fragmentPairs)
                normalizedRefs
        sameContainmentPath left right =
            surfaceFragmentContainmentPath left == surfaceFragmentContainmentPath right

authorizeTypedLiveSurfaceScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    scope ->
    IO Bool
authorizeTypedLiveSurfaceScope definition =
    authorizeLiveSurfaceScope definition.typedSurfaceAuthorize

authorizeTypedLiveSurfaceWireScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
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
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    scope ->
    IO ()
ensureTypedLiveSurfaceAuthorized definition surfaceKey = do
    authorized <- authorizeTypedLiveSurfaceScope definition surfaceKey
    accessDeniedUnless authorized

serveTypedLiveFragment ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    scope ->
    fragment ->
    (AuthorizedLiveFragment surface scope fragment -> IO ()) ->
    IO ()
serveTypedLiveFragment definition surfaceKey fragment serveFragment = do
    ensureTypedLiveSurfaceAuthorized definition surfaceKey
    let authorizedFragment =
            AuthorizedLiveFragment
                { authorizedLiveFragmentScope = surfaceKey
                , authorizedLiveFragment = fragment
                , authorizedLiveFragmentContract = definition.typedSurfaceFragmentContract surfaceKey fragment
                }
    serveFragment authorizedFragment

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
defaultLiveUpdateScopeAuthorizationRequirement AdminVenueConfigScope { venueId } =
    RequireCurrentVenueAdmin venueId
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

setTypedLiveSurfaceActorRefresh ::
    (?context :: ControllerContext, ?request :: Request) =>
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    scope ->
    [fragment] ->
    IO ()
setTypedLiveSurfaceActorRefresh definition surfaceKey fragments =
    setHeader
        ( "HX-Trigger"
        , cs (Aeson.encode (liveUpdateWireRefreshTriggerPayload (unSurfaceFragmentRefs (normalizeSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs definition surfaceKey fragments)))))
        )

liveUpdateWireRefreshTriggerPayload :: [LiveUpdateWireFragment] -> Aeson.Value
liveUpdateWireRefreshTriggerPayload fragments =
    let detail =
            Aeson.object
                [ "fragments" Aeson..= coalesceLiveUpdateWireFragments fragments
                ]
     in Aeson.object
            [ "app-live-fragments-refresh" Aeson..= detail
            ]

mkSurfaceProjectionDefinition ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
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
        , projectionSurfaceFragmentRef = typedLiveSurfaceFragmentRef typedDefinition
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
                    unSurfaceFragmentRef (typedLiveSurfaceFragmentRef typedDefinition surfaceKey fragment)
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

respondWithTypedLiveSurfaceFragments ::
    forall surface scope snapshot fragment.
    (?context :: ControllerContext, ?request :: Request, Dynamic.Typeable snapshot) =>
    ProjectionLiveSurfaceDefinition surface scope snapshot fragment ->
    scope ->
    [fragment] ->
    Blaze.Html ->
    (FragmentRenderMode -> snapshot -> fragment -> Maybe Blaze.Html) ->
    IO ()
respondWithTypedLiveSurfaceFragments definition surfaceKey fragments extraHtml renderFragment = do
    snapshot <- loadLiveSurfaceProjection definition surfaceKey
    respondHtmlProfiled $
        renderTypedLiveSurfaceFragmentsFromSnapshot
            definition
            surfaceKey
            fragments
            (FragmentOob outerHtmlOobSwap)
            extraHtml
            renderFragment
            snapshot

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
