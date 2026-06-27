module Application.Helper.LiveSurface
    ( AuthorizedLiveFragment (..)
    , EmptyInteractionIntent
    , EmptyInteractionLayer
    , EmptyInteractionSession
    , FragmentContract (..)
    , FragmentDependencies (..)
    , FragmentRenderMode (..)
    , LiveFragmentDescriptor (..)
    , LiveScopeAuthorizationRequirement (..)
    , LiveSurfaceAuthorization (..)
    , LiveSurfaceConfig (..)
    , LiveSurfaceDescriptor (..)
    , ProjectionLiveSurfaceDefinition (..)
    , VenueLiveUpdateScope (..)
    , SurfaceFragmentRef
    , SurfaceScope (..)
    , TypedLiveSurfaceDefinition (..)
    , emptyInteractionCapability
    , emptyInteractionStaticSchema
    , authorizeLiveScopeRequirement
    , authorizeTypedLiveSurfaceScope
    , authorizeTypedLiveSurfaceWireScope
    , currentVenueLiveFragmentDescriptor
    , currentVenueLiveSurfaceDescriptor
    , currentVenueUnitScopeSurface
    , currentVenueUnitScopeSurfaceForVenue
    , defaultLiveFragmentTargetId
    , descriptorToTypedLiveSurfaceDefinition
    , liveFragmentDependsOn
    , liveFragmentDescriptor
    , liveFragmentDescriptorWithDeferUntilBlur
    , liveFragmentDescriptorWithFocusedProtection
    , liveFragmentDescriptorWithPath
    , liveFragmentDescriptorWithProtection
    , liveFragmentDescriptorWithTargetId
    , liveFragmentResyncOnly
    , liveSurfaceAuthorizationByRequirement
    , liveSurfaceConfigJson
    , liveSurfaceDescriptor
    , liveSurfaceDescriptorWithDecorateRequestsWithin
    , liveSurfaceProjectionFragmentRef
    , loadLiveSurfaceProjection
    , loadLiveSurfaceProjectionFromStore
    , mkSurfaceFragmentContract
    , mkSurfaceFragmentRef
    , mkTypedDefinedLiveSurface
    , nameToKebab
    , nameToSnake
    , mkTypedSurfaceProjectionDefinition
    , normalizeSurfaceFragmentRefs
    , normalizeTypedLiveSurfaceFragments
    , renderLiveSurfaceProjectionFragment
    , renderLiveSurfaceProjectionFragmentFromStore
    , renderTypedLiveSurfaceFragmentsFromSnapshot
    , respondWithTypedLiveSurfaceFragments
    , serveTypedLiveFragment
    , setTypedLiveSurfaceActorRefresh
    , staticLiveFragmentDescriptor
    , surfaceFragmentRefWithDeferUntilBlur
    , surfaceFragmentRefWithFocusedProtection
    , surfaceFragmentRefWithPath
    , surfaceFragmentRefWithProtection
    , typedLiveSurfaceAffectedFragments
    , typedLiveSurfaceFragmentRef
    , typedLiveSurfaceFragmentRefs
    , typedSurfaceDependsOn
    , unSurfaceFragmentRefs
    , venueLiveSurfaceDescriptorForVenue
    , venueLiveUpdateScope
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
                                                LiveFragmentDescriptor (..),
                                                LiveScopeAuthorizationRequirement (..),
                                                LiveSurfaceAuthorization (..),
                                                LiveSurfaceConfig (..),
                                                LiveSurfaceDescriptor (..),
                                                ProjectionLiveSurfaceDefinition (..),
                                                SurfaceFragmentRef,
                                                SurfaceScope (..),
                                                TypedLiveSurfaceDefinition (..),
                                                VenueLiveUpdateScope (..),
                                                authorizeLiveScopeRequirement,
                                                authorizeTypedLiveSurfaceScope,
                                                authorizeTypedLiveSurfaceWireScope,
                                                currentVenueLiveFragmentDescriptor,
                                                currentVenueLiveSurfaceDescriptor,
                                                currentVenueUnitScopeSurface,
                                                currentVenueUnitScopeSurfaceForVenue,
                                                defaultLiveFragmentTargetId,
                                                descriptorToTypedLiveSurfaceDefinition,
                                                liveFragmentDependsOn,
                                                liveFragmentDescriptor,
                                                liveFragmentDescriptorWithDeferUntilBlur,
                                                liveFragmentDescriptorWithFocusedProtection,
                                                liveFragmentDescriptorWithPath,
                                                liveFragmentDescriptorWithProtection,
                                                liveFragmentDescriptorWithTargetId,
                                                liveFragmentResyncOnly,
                                                liveSurfaceAuthorizationByRequirement,
                                                liveSurfaceConfigJson,
                                                liveSurfaceDescriptor,
                                                liveSurfaceDescriptorWithDecorateRequestsWithin,
                                                liveSurfaceProjectionFragmentRef,
                                                loadLiveSurfaceProjection,
                                                loadLiveSurfaceProjectionFromStore,
                                                mkSurfaceFragmentContract,
                                                mkSurfaceFragmentRef,
                                                mkTypedDefinedLiveSurface,
                                                nameToKebab, nameToSnake,
                                                normalizeSurfaceFragmentRefs,
                                                normalizeTypedLiveSurfaceFragments,
                                                renderLiveSurfaceProjectionFragment,
                                                renderLiveSurfaceProjectionFragmentFromStore,
                                                renderTypedLiveSurfaceFragmentsFromSnapshot,
                                                respondWithTypedLiveSurfaceFragments,
                                                serveTypedLiveFragment,
                                                setTypedLiveSurfaceActorRefresh,
                                                staticLiveFragmentDescriptor,
                                                surfaceFragmentRefWithDeferUntilBlur,
                                                surfaceFragmentRefWithFocusedProtection,
                                                surfaceFragmentRefWithPath,
                                                surfaceFragmentRefWithProtection,
                                                typedLiveSurfaceAffectedFragments,
                                                typedLiveSurfaceFragmentRef,
                                                typedLiveSurfaceFragmentRefs,
                                                typedSurfaceDependsOn,
                                                unSurfaceFragmentRefs,
                                                venueLiveSurfaceDescriptorForVenue,
                                                venueLiveUpdateScope,
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
