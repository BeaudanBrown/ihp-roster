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
    , TimesheetWeekShell
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
data TimesheetWeekShell

type TimesheetDayResource = Resource TimesheetDay '[ Field VenueId 'WireUUID, Field WeekOffset 'WireInt, Field DayOffset 'WireInt ]
type TimesheetWeekResource = Resource TimesheetWeek '[ Field VenueId 'WireUUID, Field WeekOffset 'WireInt ]
data TimePickerConfig

type TimesheetWeekBoundaryConfigResource = Resource TimesheetWeekBoundaryConfig '[ Field VenueId 'WireUUID ]
type TimePickerConfigResource = Resource TimePickerConfig '[ Field VenueId 'WireUUID ]

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
    '[ DomToken TimesheetWeekShell
     , Action NavigateTimesheetWeek
        '[ Field WeekOffset 'WireInt
         , Field ShowApproved 'WireBool
         , Field ShowAllStaff 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxGet
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlTrue
         , 'HtmxSync ('HtmxSyncOn ('HtmxClosest ('HtmxId TimesheetWeekShell)) 'HtmxSyncReplace)
         ]
     , Action UpdateTimesheetFilters
        '[ Field WeekOffset 'WireInt
         , Field ShowApproved 'WireBool
         , Field ShowAllStaff 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxGet
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlTrue
         , 'HtmxSync ('HtmxSyncOn ('HtmxClosest ('HtmxId TimesheetWeekShell)) 'HtmxSyncReplace)
         ]
     , Action ApproveTimesheetEntry
        '[ Field WeekOffset 'WireInt
         , Field ShowApproved 'WireBool
         , Field ShowAllStaff 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , Action UnapproveTimesheetEntry
        '[ Field WeekOffset 'WireInt
         , Field ShowApproved 'WireBool
         , Field ShowAllStaff 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
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
         , 'DependsOn TimePickerConfigResource '[ 'FromScope VenueId ]
         ]
     , Fragment TimesheetDayColumns
        '[]
        '[ 'Eager
         , 'Live
         , 'DependsOn TimesheetWeekResource '[ 'FromScope VenueId, 'FromScope WeekOffset ]
         , 'DependsOn TimesheetWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn TimePickerConfigResource '[ 'FromScope VenueId ]
         ]
     , Fragment TimesheetDaySection
        '[ Field DayOffset 'WireInt ]
        '[ 'Lazy '[ 'DependsOnFragment TimesheetDayColumns ]
         , 'Live
         , 'DependsOn TimesheetDayResource '[ 'FromScope VenueId, 'FromScope WeekOffset, 'FromFragment DayOffset ]
         , 'DependsOn TimesheetWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn TimePickerConfigResource '[ 'FromScope VenueId ]
         ]
     ]

type TimesheetsSurface =
    Surface Timesheets (Concat '[ TimesheetScopeBundle, TimesheetFragmentBundle, TimesheetActionBundle ])
