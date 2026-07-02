module Application.Helper.LiveSurface
    ( AuthorizedLiveFragment (..)
    , EmptyInteractionIntent
    , EmptyInteractionLayer
    , EmptyInteractionSession
    , FragmentContract (..)
    , FragmentDependencies (..)
    , FragmentLoadPolicy (..)
    , FragmentRenderMode (..)
    , LazyFragmentConfig (..)
    , LiveFragmentDescriptor (..)
    , LiveScopeAuthorizationRequirement (..)
    , LiveSurfaceAuthorization (..)
    , LiveSurfaceConfig (..)
    , LiveSurfaceDescriptor (..)
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
    , fragmentContractWithEagerLoad
    , fragmentContractWithLazyLoad
    , liveFragmentDependsOn
    , liveFragmentDescriptor
    , liveFragmentDescriptorLoadPolicy
    , liveFragmentDescriptorWithDeferUntilBlur
    , liveFragmentDescriptorWithEagerLoad
    , liveFragmentDescriptorWithFocusedProtection
    , liveFragmentDescriptorWithLazyLoad
    , liveFragmentDescriptorWithPath
    , liveFragmentDescriptorWithProtection
    , liveFragmentDescriptorWithTargetId
    , liveFragmentResyncOnly
    , lazyFragmentPlaceholderCustom
    , lazyFragmentPlaceholderList
    , lazyFragmentPlaceholderPanel
    , lazyFragmentPlaceholderSpinner
    , lazyFragmentPlaceholderTable
    , liveSurfaceAuthorizationByRequirement
    , liveSurfaceConfigJson
    , liveSurfaceDescriptor
    , liveSurfaceDescriptorWithDecorateRequestsWithin
    , liveSurfaceDescriptorWithInteraction
    , mkSurfaceFragmentContract
    , mkSurfaceFragmentRef
    , mkTypedDefinedLiveSurface
    , nameToKebab
    , nameToSnake
    , normalizeSurfaceFragmentRefs
    , normalizeTypedLiveSurfaceFragments
    , renderTypedLiveSurfaceFragmentsFromSnapshot
    , respondWithTypedLiveSurfaceFragments
    , serveTypedLiveFragment
    , setTypedLiveSurfaceActorRefresh
    , staticLiveFragmentDescriptor
    , surfaceFragmentRefTargetId
    , surfaceFragmentRefUrl
    , surfaceFragmentRefWithDeferUntilBlur
    , surfaceFragmentRefWithFocusedProtection
    , surfaceFragmentRefWithPath
    , surfaceFragmentRefWithProtection
    , typedLiveSurfaceAffectedFragments
    , typedLiveSurfaceFragmentLoadPolicy
    , typedLiveSurfaceFragmentRef
    , typedLiveSurfaceFragmentRefs
    , typedSurfaceDependsOn
    , unSurfaceFragmentRefs
    , venueLiveSurfaceDescriptorForVenue
    , venueLiveUpdateScope
    ) where

import Application.Helper.Interaction.Types (EmptyInteractionIntent,
                                             EmptyInteractionLayer,
                                             EmptyInteractionSession,
                                             emptyInteractionCapability,
                                             emptyInteractionStaticSchema)
import Application.Helper.LiveSurface.Internal (AuthorizedLiveFragment (..),
                                                FragmentContract (..),
                                                FragmentDependencies (..),
                                                FragmentLoadPolicy (..),
                                                FragmentRenderMode (..),
                                                LazyFragmentConfig (..),
                                                LiveFragmentDescriptor (..),
                                                LiveScopeAuthorizationRequirement (..),
                                                LiveSurfaceAuthorization (..),
                                                LiveSurfaceConfig (..),
                                                LiveSurfaceDescriptor (..),
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
                                                fragmentContractWithEagerLoad,
                                                fragmentContractWithLazyLoad,
                                                lazyFragmentPlaceholderCustom,
                                                lazyFragmentPlaceholderList,
                                                lazyFragmentPlaceholderPanel,
                                                lazyFragmentPlaceholderSpinner,
                                                lazyFragmentPlaceholderTable,
                                                liveFragmentDependsOn,
                                                liveFragmentDescriptor,
                                                liveFragmentDescriptorLoadPolicy,
                                                liveFragmentDescriptorWithDeferUntilBlur,
                                                liveFragmentDescriptorWithEagerLoad,
                                                liveFragmentDescriptorWithFocusedProtection,
                                                liveFragmentDescriptorWithLazyLoad,
                                                liveFragmentDescriptorWithPath,
                                                liveFragmentDescriptorWithProtection,
                                                liveFragmentDescriptorWithTargetId,
                                                liveFragmentResyncOnly,
                                                liveSurfaceAuthorizationByRequirement,
                                                liveSurfaceConfigJson,
                                                liveSurfaceDescriptor,
                                                liveSurfaceDescriptorWithDecorateRequestsWithin,
                                                liveSurfaceDescriptorWithInteraction,
                                                mkSurfaceFragmentContract,
                                                mkSurfaceFragmentRef,
                                                mkTypedDefinedLiveSurface,
                                                nameToKebab, nameToSnake,
                                                normalizeSurfaceFragmentRefs,
                                                normalizeTypedLiveSurfaceFragments,
                                                renderTypedLiveSurfaceFragmentsFromSnapshot,
                                                respondWithTypedLiveSurfaceFragments,
                                                serveTypedLiveFragment,
                                                setTypedLiveSurfaceActorRefresh,
                                                staticLiveFragmentDescriptor,
                                                surfaceFragmentRefTargetId,
                                                surfaceFragmentRefUrl,
                                                surfaceFragmentRefWithDeferUntilBlur,
                                                surfaceFragmentRefWithFocusedProtection,
                                                surfaceFragmentRefWithPath,
                                                surfaceFragmentRefWithProtection,
                                                typedLiveSurfaceAffectedFragments,
                                                typedLiveSurfaceFragmentLoadPolicy,
                                                typedLiveSurfaceFragmentRef,
                                                typedLiveSurfaceFragmentRefs,
                                                typedSurfaceDependsOn,
                                                unSurfaceFragmentRefs,
                                                venueLiveSurfaceDescriptorForVenue,
                                                venueLiveUpdateScope)
