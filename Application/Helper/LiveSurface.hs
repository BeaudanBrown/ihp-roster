module Application.Helper.LiveSurface
    ( AuthorizedLiveFragment (..)
    , FragmentContract (..)
    , FragmentDependencies (..)
    , LiveScopeAuthorizationRequirement (..)
    , LiveSurfaceAuthorization (..)
    , LiveSurfaceConfig (..)
    , ProjectionLiveSurfaceDefinition (..)
    , SurfaceFragmentRef
    , SurfaceScope (..)
    , TypedLiveSurfaceDefinition (..)
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
    , renderLiveSurfaceProjectionFragment
    , renderLiveSurfaceProjectionFragmentFromStore
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

import qualified Application.Helper.LiveSurface.Internal as Internal
import Application.Helper.LiveSurface.Internal
    ( AuthorizedLiveFragment (..)
    , FragmentContract (..)
    , FragmentDependencies (..)
    , LiveScopeAuthorizationRequirement (..)
    , LiveSurfaceAuthorization (..)
    , LiveSurfaceConfig (..)
    , ProjectionLiveSurfaceDefinition (..)
    , SurfaceFragmentRef
    , SurfaceScope (..)
    , TypedLiveSurfaceDefinition (..)
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
    , normalizeSurfaceFragmentRefs
    , renderLiveSurfaceProjectionFragment
    , renderLiveSurfaceProjectionFragmentFromStore
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
    )
import Application.Helper.SurfaceProjection (SurfaceProjectionCachePolicy)
import IHP.Prelude
import qualified Text.Blaze.Html as Blaze

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
