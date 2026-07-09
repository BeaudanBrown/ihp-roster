{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.Registry
    ( RegisteredFrontendSurfaces
    ) where

import Application.Helper.FrontendContract.Surface.Admin (AdminExportsSurface,
                                                          AdminInvitesSurface,
                                                          AdminPageSurface,
                                                          AdminRosterGroupsSurface,
                                                          AdminShiftTypesSurface,
                                                          AdminVenueSettingsSurface,
                                                          AdminXeroPageSurface,
                                                          AdminXeroSurface)
import Application.Helper.FrontendContract.Surface.Billing (BillingSurface)
import Application.Helper.FrontendContract.Surface.Lab (SurfaceLabSurface)
import Application.Helper.FrontendContract.Surface.LeaveRequests (LeaveRequestsSurface)
import Application.Helper.FrontendContract.Surface.Profile (ProfileSurface,
                                                            StaffSurface)
import Application.Helper.FrontendContract.Surface.Roster (RosterDayTimelineSurface,
                                                           RosterSurface)
import Application.Helper.FrontendContract.Surface.Support (SupportSurface)
import Application.Helper.FrontendContract.Surface.Timesheets (TimesheetsSurface)

type RegisteredFrontendSurfaces =
    '[ SurfaceLabSurface
     , TimesheetsSurface
     , RosterSurface
     , RosterDayTimelineSurface
     , LeaveRequestsSurface
     , BillingSurface
     , SupportSurface
     , ProfileSurface
     , StaffSurface
     , AdminPageSurface
     , AdminXeroPageSurface
     , AdminVenueSettingsSurface
     , AdminInvitesSurface
     , AdminExportsSurface
     , AdminShiftTypesSurface
     , AdminRosterGroupsSurface
     , AdminXeroSurface
     ]
