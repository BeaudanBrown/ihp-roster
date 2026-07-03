{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Timesheets
    ( DayOffset
    , ShowAllStaff
    , ShowApproved
    , StaffFilterId
    , TimesheetDay
    , TimesheetDayColumns
    , TimesheetDaySection
    , TimesheetWeekBoundaryConfig
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

data TimesheetDay
data TimesheetWeekBoundaryConfig

type TimesheetDayResource = Resource TimesheetDay '[ Field VenueId 'WireUUID, Field WeekOffset 'WireInt, Field DayOffset 'WireInt ]
type TimesheetWeekResource = Resource TimesheetWeek '[ Field VenueId 'WireUUID, Field WeekOffset 'WireInt ]
type TimesheetWeekBoundaryConfigResource = Resource TimesheetWeekBoundaryConfig '[ Field VenueId 'WireUUID ]

type TimesheetScopeBundle =
    '[ Scope TimesheetWeek
        '[ Field VenueId 'WireUUID
         , Field WeekOffset 'WireInt
         ]
        '[ 'Authorize 'CurrentVenue '[ VenueId ] ]
     , MountState TimesheetsMountState
        '[ Field ShowApproved 'WireBool
         , Field ShowAllStaff 'WireBool
         , Field StaffFilterId ('WireOptional 'WireUUID)
         ]
     ]

type TimesheetFragmentBundle =
    '[ Fragment TimesheetToolbar
        '[]
        '[ 'Eager
         , 'Live
         , 'DependsOn TimesheetWeekResource '[ 'FromScope VenueId, 'FromScope WeekOffset ]
         , 'DependsOn TimesheetWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         ]
     , Fragment TimesheetDayColumns
        '[]
        '[ 'Eager
         , 'Live
         , 'DependsOn TimesheetWeekResource '[ 'FromScope VenueId, 'FromScope WeekOffset ]
         , 'DependsOn TimesheetWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         ]
     , Fragment TimesheetDaySection
        '[ Field DayOffset 'WireInt ]
        '[ 'Lazy '[ 'DependsOnFragment TimesheetDayColumns ]
         , 'Live
         , 'DependsOn TimesheetDayResource '[ 'FromScope VenueId, 'FromScope WeekOffset, 'FromFragment DayOffset ]
         , 'DependsOn TimesheetWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         ]
     ]

type TimesheetsSurface =
    Surface Timesheets (Concat '[ TimesheetScopeBundle, TimesheetFragmentBundle ])
