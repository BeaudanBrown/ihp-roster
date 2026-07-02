{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Registry
    ( RegisteredFrontendSurfaces
    ) where

import Application.Helper.FrontendSurface.Lab (SurfaceLabSurface)
import Application.Helper.FrontendSurface.LeaveRequests (LeaveRequestsSurface)
import Application.Helper.FrontendSurface.Roster (RosterSurface)
import Application.Helper.FrontendSurface.Timesheets (TimesheetsSurface)

type RegisteredFrontendSurfaces =
    '[ SurfaceLabSurface
     , TimesheetsSurface
     , RosterSurface
     , LeaveRequestsSurface
     ]
