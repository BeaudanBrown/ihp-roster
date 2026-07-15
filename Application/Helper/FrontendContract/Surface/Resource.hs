{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.Surface.Resource
    ( SurfaceResourceValue
    , frontendSurfaceResource
    , matchFrontendSurfaceResource
    ) where

import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Reflect (ReflectResource)
import Application.Helper.FrontendContract.Surface.Resource.Internal (SurfaceResourceValue)
import qualified Application.Helper.FrontendContract.Surface.Resource.Internal as Internal
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.Aeson.Types as Aeson
import IHP.Prelude

-- | Construct an opaque resource from the exact declaration-ordered fields of
-- a marker owned by one Surface. Marker ownership, field presence, order, and
-- Haskell wire types are enforced by the Surface declaration.
frontendSurfaceResource ::
    forall spec marker.
    ReflectResource (SurfaceResourceSpec spec marker) =>
    SurfaceFields (SurfaceResourceFieldSpecs spec marker) ->
    SurfaceResourceValue
frontendSurfaceResource fields =
    Internal.mkSurfaceResourceValue expectedName (surfaceFieldsJson fields)
  where
    expectedName =
        SurfaceIR.resourceName (surfaceResourceValue @spec @marker)

-- | Match an opaque resource against an owning Surface/resource marker and
-- recover only its declaration-ordered typed values.
matchFrontendSurfaceResource ::
    forall spec marker.
    ( ReflectResource (SurfaceResourceSpec spec marker)
    , KnownSurfaceFieldValues (SurfaceResourceFieldSpecs spec marker)
    ) =>
    SurfaceResourceValue ->
    Maybe (SurfaceFieldValues (SurfaceResourceFieldSpecs spec marker))
matchFrontendSurfaceResource value =
    let (actualName, payload) = Internal.surfaceResourceIdentity value
        expectedName = SurfaceIR.resourceName (surfaceResourceValue @spec @marker)
     in if actualName == expectedName
            then Aeson.parseMaybe (parseSurfaceFieldValues @(SurfaceResourceFieldSpecs spec marker)) payload
            else Nothing
