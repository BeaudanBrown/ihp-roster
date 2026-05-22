module Application.Helper.LiveSurface
    ( LiveScopeAuthorizationRequirement (..)
    , LiveSurfaceAuthorization (..)
    , LiveSurfaceConfig (..)
    , ProjectionLiveSurfaceDefinition (..)
    , SurfaceFragmentRef
    , SurfaceScope (..)
    , TypedLiveSurfaceDefinition (..)
    , authorizeLiveScopeRequirement
    , authorizeTypedLiveSurfaceScope
    , authorizeTypedLiveSurfaceWireScope
    , ensureTypedLiveSurfaceAuthorized
    , liveSurfaceAuthorizationByRequirement
    , liveSurfaceConfigJson
    , liveSurfaceProjectionFragmentRef
    , loadLiveSurfaceProjection
    , loadLiveSurfaceProjectionFromStore
    , mkSurfaceFragmentRef
    , mkTypedDefinedLiveSurface
    , mkTypedSurfaceProjectionDefinition
    , normalizeSurfaceFragmentRefs
    , renderLiveSurfaceProjectionFragment
    , renderLiveSurfaceProjectionFragmentFromStore
    , setTypedLiveSurfaceActorRefresh
    , surfaceFragmentRefWithDeferUntilBlur
    , surfaceFragmentRefWithFocusedProtection
    , surfaceFragmentRefWithPath
    , surfaceFragmentRefWithProtection
    , typedLiveSurfaceAffectedFragments
    , typedLiveSurfaceFragmentRef
    , typedLiveSurfaceFragmentRefs
    , unSurfaceFragmentRefs
    , warmLiveSurfaceProjection
    , warmLiveSurfaceProjectionFromStore
    ) where

import qualified Application.Helper.LiveSurface.Internal as Internal
import Application.Helper.LiveSurface.Internal
    ( LiveScopeAuthorizationRequirement (..)
    , LiveSurfaceAuthorization (..)
    , LiveSurfaceConfig (..)
    , ProjectionLiveSurfaceDefinition (..)
    , SurfaceFragmentRef
    , SurfaceScope (..)
    , TypedLiveSurfaceDefinition (..)
    , authorizeLiveScopeRequirement
    , authorizeTypedLiveSurfaceScope
    , authorizeTypedLiveSurfaceWireScope
    , ensureTypedLiveSurfaceAuthorized
    , liveSurfaceAuthorizationByRequirement
    , liveSurfaceConfigJson
    , liveSurfaceProjectionFragmentRef
    , loadLiveSurfaceProjection
    , loadLiveSurfaceProjectionFromStore
    , mkSurfaceFragmentRef
    , mkTypedDefinedLiveSurface
    , normalizeSurfaceFragmentRefs
    , renderLiveSurfaceProjectionFragment
    , renderLiveSurfaceProjectionFragmentFromStore
    , setTypedLiveSurfaceActorRefresh
    , surfaceFragmentRefWithDeferUntilBlur
    , surfaceFragmentRefWithFocusedProtection
    , surfaceFragmentRefWithPath
    , surfaceFragmentRefWithProtection
    , typedLiveSurfaceAffectedFragments
    , typedLiveSurfaceFragmentRef
    , typedLiveSurfaceFragmentRefs
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
