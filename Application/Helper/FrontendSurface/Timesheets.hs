{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Timesheets
    ( DayOffset
    , ShowAllStaff
    , ShowApproved
    , StaffFilterId
    , TimesheetDayColumns
    , TimesheetDaySection
    , TimesheetToolbar
    , TimesheetWeek
    , TimesheetsMountState
    , TimesheetsSurface
    , VenueId
    , WeekOffset
    ) where

import Application.Helper.FrontendSurface.DSL

data Timesheets

data TimesheetWeek
data VenueId
data WeekOffset

data TimesheetsMountState
data ShowApproved
data ShowAllStaff
data StaffFilterId

data TimesheetToolbar
data TimesheetDayColumns
data TimesheetDaySection
data DayOffset

type TimesheetScopeBundle =
    '[ Scope TimesheetWeek
        '[ Field VenueId 'WireUUID
         , Field WeekOffset 'WireInt
         ]
     , MountState TimesheetsMountState
        '[ Field ShowApproved 'WireBool
         , Field ShowAllStaff 'WireBool
         , Field StaffFilterId ('WireOptional 'WireUUID)
         ]
     ]

type TimesheetFragmentBundle =
    '[ Fragment TimesheetToolbar '[] '[ 'Eager, 'Live ]
     , Fragment TimesheetDayColumns '[] '[ 'Eager, 'Live ]
     , Fragment TimesheetDaySection
        '[ Field DayOffset 'WireInt ]
        '[ 'Lazy '[ 'DependsOn TimesheetDayColumns ], 'Live ]
     ]

type TimesheetsSurface =
    Surface Timesheets (Concat '[ TimesheetScopeBundle, TimesheetFragmentBundle ])
