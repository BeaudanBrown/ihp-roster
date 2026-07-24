{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

module Application.Helper.FrontendContract.Surface.Live
    ( SurfaceFragmentKey
    , SurfaceScope
    , frontendSurfaceFragmentKey
    , frontendSurfaceScope
    , matchFrontendSurfaceFragmentKey
    , matchFrontendSurfaceScope
    , surfaceScopeKey
    ) where

import Application.Helper.FrontendContract.Surface.ContractIR (ScopeIR (..))
import Application.Helper.FrontendContract.Surface.Identity (canonicalFrontendSurfaceScopeKeyFromFields)
import Application.Helper.FrontendContract.Surface.Reflect (ReflectPrimitive,
                                                            ReflectSurfaceSpec)
import Application.Helper.FrontendContract.Surface.Values
import qualified Application.Helper.LiveUpdate.Internal as LiveUpdate
import qualified Data.Aeson.Types as Aeson
import IHP.Prelude

type SurfaceScope = LiveUpdate.SurfaceScope
type SurfaceFragmentKey = LiveUpdate.SurfaceFragmentKey

-- | Build one opaque live scope from the exact fields declared by its owning
-- Surface and scope marker. The declaration determines the Surface name,
-- payload shape, wire types, and canonical stable key.
frontendSurfaceScope ::
    forall spec marker.
    ( ReflectSurfaceSpec spec
    , ReflectPrimitive (SurfaceScopePrimitive spec marker)
    ) =>
    SurfaceFields (SurfaceScopeFieldSpecs spec marker) ->
    SurfaceScope
frontendSurfaceScope fields =
    LiveUpdate.mkSurfaceScope surfaceName payload stableKey
  where
    surfaceName = surfaceNameValue @spec
    payload = surfaceFieldsJson fields
    stableKey =
        either
            (error . ("Typed Surface scope invariant failed: " <>) . cs)
            id
            ( Aeson.parseEither
                (canonicalFrontendSurfaceScopeKeyFromFields surfaceName scopeIdentityFields)
                payload
            )
    scopeIdentityFields =
        case surfaceScopeValue @spec @marker of
            ScopeIR _ _ fields _ -> fields

-- | Build one opaque semantic fragment key from the exact fields declared by
-- its owning Surface and fragment marker.
frontendSurfaceFragmentKey ::
    forall spec marker.
    ( ReflectSurfaceSpec spec
    , ReflectPrimitive (SurfaceFragmentPrimitive spec marker)
    ) =>
    SurfaceFields (SurfaceFragmentFieldSpecs spec marker) ->
    SurfaceFragmentKey
frontendSurfaceFragmentKey fields =
    LiveUpdate.mkSurfaceFragmentKey
        (surfaceNameValue @spec)
        (surfaceFragmentNameValue @spec @marker)
        (surfaceFieldsJson fields)

-- | Match an opaque scope against an owning Surface/scope marker and recover
-- only its declaration-ordered typed values. Feature code never sees raw
-- transport names or JSON fields.
matchFrontendSurfaceScope ::
    forall spec marker.
    ( ReflectSurfaceSpec spec
    , ReflectPrimitive (SurfaceScopePrimitive spec marker)
    , KnownSurfaceFieldValues (SurfaceScopeFieldSpecs spec marker)
    ) =>
    SurfaceScope ->
    Maybe (SurfaceFieldValues (SurfaceScopeFieldSpecs spec marker))
matchFrontendSurfaceScope scope =
    let (actualSurface, payload) = LiveUpdate.surfaceScopeIdentity scope
     in if actualSurface == surfaceNameValue @spec
            then Aeson.parseMaybe (parseSurfaceFieldValues @(SurfaceScopeFieldSpecs spec marker)) payload
            else Nothing

-- | Match an opaque fragment key against an owning Surface/fragment marker and
-- recover only its declaration-ordered typed values.
matchFrontendSurfaceFragmentKey ::
    forall spec marker.
    ( ReflectSurfaceSpec spec
    , ReflectPrimitive (SurfaceFragmentPrimitive spec marker)
    , KnownSurfaceFieldValues (SurfaceFragmentFieldSpecs spec marker)
    ) =>
    SurfaceFragmentKey ->
    Maybe (SurfaceFieldValues (SurfaceFragmentFieldSpecs spec marker))
matchFrontendSurfaceFragmentKey fragmentKey =
    let (actualSurface, actualFragment, params) = LiveUpdate.surfaceFragmentKeyIdentity fragmentKey
     in if actualSurface == surfaceNameValue @spec
            && actualFragment == surfaceFragmentNameValue @spec @marker
            then Aeson.parseMaybe (parseSurfaceFieldValues @(SurfaceFragmentFieldSpecs spec marker)) params
            else Nothing

surfaceScopeKey :: SurfaceScope -> Text
surfaceScopeKey = LiveUpdate.surfaceScopeKey
