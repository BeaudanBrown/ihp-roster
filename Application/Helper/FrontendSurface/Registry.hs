{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Registry
    ( RegisteredFrontendSurfaces
    ) where

import Application.Helper.FrontendSurface.Lab (SurfaceLabSurface)

type RegisteredFrontendSurfaces =
    '[ SurfaceLabSurface
     ]
