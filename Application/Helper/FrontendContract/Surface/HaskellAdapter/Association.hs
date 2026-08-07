{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeFamilies   #-}

-- | Lightweight nominal association consumed by generated feature adapters.
-- Generator registry/reflection mechanics stay in @HaskellAdapter.Family@ so
-- importing a private generated module does not pull the generator core into a
-- feature's focused compile closure.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.Association
    ( AdapterFamilySurface
    , AdapterSurfaceMarker
    , SurfaceAdapterFamily
    ) where

import Application.Helper.FrontendContract.Surface.DSL
import Data.Kind (Type)

class SurfaceAdapterFamily (adapterFamily :: Type) where
    type AdapterFamilySurface adapterFamily :: SurfaceSpec

type family AdapterSurfaceMarker (surface :: SurfaceSpec) :: Type where
    AdapterSurfaceMarker ('Surface marker primitives) = marker
