{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.Timesheets
    ( DayOffset
    , ShowAllStaff
    , ShowApproved
    , StaffFilterId
    , TimesheetDay
    , TimesheetDayColumns
    , TimesheetDaySection
    , TimesheetWeekBoundaryConfig
    , TimesheetToolbar
    , NavigateTimesheetWeek
    , UpdateTimesheetFilters
    , ApproveTimesheetEntry
    , UnapproveTimesheetEntry
    , TimesheetWeek
    , TimesheetsMountState
    , TimesheetsSurface
    , VenueId
    , WeekOffset
    ) where

import Application.Helper.FrontendContract.Surface.DSL

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

data NavigateTimesheetWeek
data UpdateTimesheetFilters
data ApproveTimesheetEntry
data UnapproveTimesheetEntry
data None
data TimesheetWeekShellSyncCustomHtmx

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

type TimesheetActionBundle =
    '[ Action NavigateTimesheetWeek
        '[ Field WeekOffset 'WireInt
         , Field ShowApproved 'WireBool
         , Field ShowAllStaff 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxGet
         , 'HtmxSwap None
         , 'HtmxPushUrl 'HtmxPushUrlTrue
         , 'CustomHtmx TimesheetWeekShellSyncCustomHtmx "week navigation serializes through the timesheet week shell with hx-sync=closest shell:replace"
         ]
     , Action UpdateTimesheetFilters
        '[ Field WeekOffset 'WireInt
         , Field ShowApproved 'WireBool
         , Field ShowAllStaff 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxGet
         , 'HtmxSwap None
         , 'HtmxPushUrl 'HtmxPushUrlTrue
         , 'CustomHtmx TimesheetWeekShellSyncCustomHtmx "filter changes serialize through the timesheet week shell with hx-sync=closest shell:replace"
         ]
     , Action ApproveTimesheetEntry
        '[ Field WeekOffset 'WireInt
         , Field ShowApproved 'WireBool
         , Field ShowAllStaff 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap None
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , Action UnapproveTimesheetEntry
        '[ Field WeekOffset 'WireInt
         , Field ShowApproved 'WireBool
         , Field ShowAllStaff 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap None
         , 'HtmxPushUrl 'HtmxPushUrlFalse
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
    Surface Timesheets (Concat '[ TimesheetScopeBundle, TimesheetFragmentBundle, TimesheetActionBundle ])
