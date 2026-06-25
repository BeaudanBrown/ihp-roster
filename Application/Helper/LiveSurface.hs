module Application.Helper.LiveSurface
    ( AuthorizedLiveFragment (..)
    , EmptyInteractionIntent
    , EmptyInteractionLayer
    , EmptyInteractionSession
    , FragmentContract (..)
    , FragmentDependencies (..)
    , FragmentRenderMode (..)
    , LiveScopeAuthorizationRequirement (..)
    , LiveSurfaceAuthorization (..)
    , LiveSurfaceConfig (..)
    , ProjectionLiveSurfaceDefinition (..)
    , SurfaceFragmentRef
    , SurfaceScope (..)
    , TypedLiveSurfaceDefinition (..)
    , emptyInteractionCapability
    , emptyInteractionStaticSchema
    , authorizeLiveScopeRequirement
    , authorizeTypedLiveSurfaceScope
    , authorizeTypedLiveSurfaceWireScope
    , liveFragmentDependsOn
    , liveFragmentResyncOnly
    , liveSurfaceAuthorizationByRequirement
    , liveSurfaceConfigJson
    , liveSurfaceProjectionFragmentRef
    , loadLiveSurfaceProjection
    , loadLiveSurfaceProjectionFromStore
    , mkSurfaceFragmentContract
    , mkSurfaceFragmentRef
    , mkTypedDefinedLiveSurface
    , mkTypedSurfaceProjectionDefinition
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

import Application.Helper.Interaction.Types (EmptyInteractionIntent,
                                             EmptyInteractionLayer,
                                             EmptyInteractionSession,
                                             emptyInteractionCapability,
                                             emptyInteractionStaticSchema)
import Application.Helper.LiveSurface.Internal (AuthorizedLiveFragment (..),
                                                FragmentContract (..),
                                                FragmentDependencies (..),
                                                FragmentRenderMode (..),
                                                LiveScopeAuthorizationRequirement (..),
                                                LiveSurfaceAuthorization (..),
                                                LiveSurfaceConfig (..),
                                                ProjectionLiveSurfaceDefinition (..),
                                                SurfaceFragmentRef,
                                                SurfaceScope (..),
                                                TypedLiveSurfaceDefinition (..),
                                                authorizeLiveScopeRequirement,
                                                authorizeTypedLiveSurfaceScope,
                                                authorizeTypedLiveSurfaceWireScope,
                                                liveFragmentDependsOn,
                                                liveFragmentResyncOnly,
                                                liveSurfaceAuthorizationByRequirement,
                                                liveSurfaceConfigJson,
                                                liveSurfaceProjectionFragmentRef,
                                                loadLiveSurfaceProjection,
                                                loadLiveSurfaceProjectionFromStore,
                                                mkSurfaceFragmentContract,
                                                mkSurfaceFragmentRef,
                                                mkTypedDefinedLiveSurface,
                                                normalizeSurfaceFragmentRefs,
                                                normalizeTypedLiveSurfaceFragments,
                                                renderLiveSurfaceProjectionFragment,
                                                renderLiveSurfaceProjectionFragmentFromStore,
                                                renderTypedLiveSurfaceFragmentsFromSnapshot,
                                                respondWithTypedLiveSurfaceFragments,
                                                serveTypedLiveFragment,
                                                setTypedLiveSurfaceActorRefresh,
                                                surfaceFragmentRefWithDeferUntilBlur,
                                                surfaceFragmentRefWithFocusedProtection,
                                                surfaceFragmentRefWithPath,
                                                surfaceFragmentRefWithProtection,
                                                typedLiveSurfaceAffectedFragments,
                                                typedLiveSurfaceFragmentRef,
                                                typedLiveSurfaceFragmentRefs,
                                                typedSurfaceDependsOn,
                                                unSurfaceFragmentRefs,
                                                warmLiveSurfaceProjection,
                                                warmLiveSurfaceProjectionFromStore)
import qualified Application.Helper.LiveSurface.Internal as Internal
import Application.Helper.SurfaceProjection (SurfaceProjectionCachePolicy)
import IHP.Prelude
import qualified Text.Blaze.Html as Blaze

mkTypedSurfaceProjectionDefinition ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    Text ->
    SurfaceProjectionCachePolicy ->
    (scope -> Text) ->
    IO Text ->
    (scope -> IO Int) ->
    (scope -> IO snapshot) ->
    (snapshot -> fragment -> Maybe Blaze.Html) ->
    ProjectionLiveSurfaceDefinition surface scope snapshot fragment
mkTypedSurfaceProjectionDefinition =
    Internal.mkSurfaceProjectionDefinition
