module Application.Helper.LiveSurface
    ( LiveScopeAuthorizationRequirement (..)
    , LiveSurfaceAuthorization (..)
    , LiveSurfaceBroadcastOptions (..)
    , LiveSurfaceConfig (..)
    , LiveSurfaceMutation (..)
    , LiveSurfaceMutationResult (..)
    , ProjectionLiveSurfaceDefinition (..)
    , SurfaceFragmentRef
    , SurfaceScope (..)
    , TypedLiveSurfaceDefinition (..)
    , authorizeLiveScopeRequirement
    , authorizeTypedLiveSurfaceScope
    , authorizeTypedLiveSurfaceWireScope
    , broadcastProjectionSurfaceFragments
    , broadcastProjectionSurfaceFragmentsWith
    , broadcastSurfaceFragments
    , broadcastSurfaceFragmentsAndSetActorRefresh
    , broadcastSurfaceFragmentsWithoutContext
    , broadcastSurfaceResync
    , broadcastSurfaceResyncWithoutContext
    , defaultLiveSurfaceBroadcastOptions
    , ensureTypedLiveSurfaceAuthorized
    , liveSurfaceAuthorizationByRequirement
    , liveSurfaceConfigJson
    , liveSurfaceMutation
    , liveSurfaceProjectionFragmentRef
    , loadLiveSurfaceProjection
    , loadLiveSurfaceProjectionFromStore
    , mkSurfaceFragmentRef
    , mkTypedDefinedLiveSurface
    , mkTypedSurfaceProjectionDefinition
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

import qualified Application.Helper.LiveSurface.Internal as Internal
import Application.Helper.LiveSurface.Internal
    ( LiveScopeAuthorizationRequirement (..)
    , LiveSurfaceAuthorization (..)
    , LiveSurfaceBroadcastOptions (..)
    , LiveSurfaceConfig (..)
    , LiveSurfaceMutation (..)
    , LiveSurfaceMutationResult (..)
    , ProjectionLiveSurfaceDefinition (..)
    , SurfaceFragmentRef
    , SurfaceScope (..)
    , TypedLiveSurfaceDefinition (..)
    , authorizeLiveScopeRequirement
    , authorizeTypedLiveSurfaceScope
    , authorizeTypedLiveSurfaceWireScope
    , broadcastProjectionSurfaceFragments
    , broadcastProjectionSurfaceFragmentsWith
    , broadcastTypedSurfaceFragmentsAndSetActorRefresh
    , broadcastTypedSurfaceFragmentsWithoutContext
    , broadcastTypedSurfaceResync
    , broadcastTypedSurfaceResyncWithoutContext
    , defaultLiveSurfaceBroadcastOptions
    , ensureTypedLiveSurfaceAuthorized
    , liveSurfaceAuthorizationByRequirement
    , liveSurfaceConfigJson
    , liveSurfaceMutation
    , liveSurfaceProjectionFragmentRef
    , loadLiveSurfaceProjection
    , loadLiveSurfaceProjectionFromStore
    , mkSurfaceFragmentRef
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
    )
import Application.Helper.LiveUpdate (LiveUpdateBroadcastResult)
import Application.Helper.SurfaceProjection (SurfaceProjectionCachePolicy)
import IHP.Controller.Context (ControllerContext)
import IHP.ControllerSupport (Request)
import IHP.ModelSupport (ModelContext)
import IHP.Prelude
import qualified Text.Blaze.Html as Blaze

broadcastSurfaceFragments ::
    (?context :: ControllerContext, ?request :: Request) =>
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    [fragment] ->
    IO ()
broadcastSurfaceFragments = Internal.broadcastTypedSurfaceFragments

broadcastSurfaceFragmentsAndSetActorRefresh ::
    (?context :: ControllerContext, ?request :: Request) =>
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    [fragment] ->
    IO ()
broadcastSurfaceFragmentsAndSetActorRefresh = Internal.broadcastTypedSurfaceFragmentsAndSetActorRefresh

broadcastSurfaceFragmentsWithoutContext ::
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    Maybe Text ->
    [fragment] ->
    IO LiveUpdateBroadcastResult
broadcastSurfaceFragmentsWithoutContext = Internal.broadcastTypedSurfaceFragmentsWithoutContext

broadcastSurfaceResync ::
    (?context :: ControllerContext, ?request :: Request) =>
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    IO ()
broadcastSurfaceResync = broadcastTypedSurfaceResync

broadcastSurfaceResyncWithoutContext ::
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    Maybe Text ->
    IO ()
broadcastSurfaceResyncWithoutContext = broadcastTypedSurfaceResyncWithoutContext

mkTypedSurfaceProjectionDefinition ::
    TypedLiveSurfaceDefinition surface scope fragment ->
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
