-- | Stable generator facade. Kind-neutral mechanics live in 'Core' and each
-- declaration family keeps a focused renderer; resource output remains exposed
-- through the original interface and generated-by marker.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.Generator
    ( GeneratedHaskellModule (..)
    , generateSurfaceResourceAdapterModules
    ) where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core (GeneratedHaskellModule (..))
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Resource (generateSurfaceResourceAdapterModules)
