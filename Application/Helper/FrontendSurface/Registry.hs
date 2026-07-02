{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Registry
    ( RegisteredFrontendSurfaces
    ) where

import Application.Helper.FrontendSurface.Lab (SurfaceLabSurface)
import Application.Helper.FrontendSurface.Timesheets (TimesheetsSurface)

type RegisteredFrontendSurfaces =
    '[ SurfaceLabSurface
     , TimesheetsSurface
     ]
