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
        '[ 'NoAuth ]
     , MountState TimesheetsMountState
        '[ Field ShowApproved 'WireBool
         , Field ShowAllStaff 'WireBool
         , Field StaffFilterId ('WireOptional 'WireUUID)
         ]
     ]

type TimesheetFragmentBundle =
    '[ Fragment TimesheetToolbar '[] '[ 'Eager, 'Live, 'ResyncOnly ]
     , Fragment TimesheetDayColumns '[] '[ 'Eager, 'Live, 'ResyncOnly ]
     , Fragment TimesheetDaySection
        '[ Field DayOffset 'WireInt ]
        '[ 'Lazy '[ 'DependsOnFragment TimesheetDayColumns ], 'Live, 'ResyncOnly ]
     ]

type TimesheetsSurface =
    Surface Timesheets (Concat '[ TimesheetScopeBundle, TimesheetFragmentBundle ])
