{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.Admin
    ( AdminPageSurface
    , AdminXeroPageSurface
    , AdminVenueSettingsSurface
    , AdminInvitesSurface
    , AdminExportsSurface
    , AdminShiftTypesSurface
    , AdminRosterGroupsSurface
    , AdminXeroSurface
    , AdminPageScope
    , AdminXeroPageScope
    , AdminVenueConfigScope
    , AdminInvitesScope
    , AdminExportsScope
    , AdminShiftTypesScope
    , AdminRosterGroupsScope
    , AdminXeroScope
    , VenueId
    , RosterGroupId
    , AdminPageContentFragment
    , AdminXeroPageContentFragment
    , AdminVenueSettingsFragment
    , AdminInvitesFragment
    , AdminExportsFragment
    , AdminShiftTypesFragment
    , AdminRosterGroupsFragment
    , AdminXeroShellFragment
    , AdminXeroReferenceSyncFragment
    , AdminXeroTimesheetPreparationWaitFragment
    , AdminXeroPayItemImportWaitFragment
    , AdminVenueSettings
    , AdminInvites
    , AdminExports
    , AdminShiftTypes
    , AdminRosterGroups
    , XeroConnection
    , XeroReferenceSyncState
    , CreateRosterGroup
    , UpdateRosterGroup
    , MoveRosterGroupUp
    , MoveRosterGroupDown
    , ToggleInactiveRosterGroups
    , UpdateRosterEndTimesEnabled
    , UpdateDefaultStaffPayRate
    , UpdateMinutePrecisionShiftTimesEnabled
    , UpdateUnavailableStaffWarningThreshold
    , UpdateRosterTimePickerWindow
    , UpdateRosterWeekStartsOn
    , CreateVenueInvitation
    , RevokeVenueInvitation
    , RenewVenueInvitation
    , CreateExportJob
    , CreateShiftType
    , UpdateShiftType
    , MoveShiftTypeUp
    , MoveShiftTypeDown
    , AutosaveShiftTypeName
    , AutosaveShiftTypeSelection
    , ToggleInactiveShiftTypes
    , SyncXeroPayrollReferenceData
    , ShowXeroTimesheetPreparationStaffMappings
    , RosterEndTimesEnabled
    , MinutePrecisionShiftTimesEnabled
    , TimePickerStart
    , TimePickerEnd
    , RosterWeekStartsOn
    , UnavailableStaffWarningThreshold
    , Email
    , RangeStart
    , RangeEnd
    , ExportType
    , ShowInactiveRosterGroups
    , ShowInactiveShiftTypes
    , Name
    , PayRateSelection
    , DefaultStaffAwardLevelId
    , ColourKey
    , IsActive
    , EditStaffId
    , ShowMatched
    ) where

import Application.Helper.Export.Types (ExportJobType)
import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.ShiftTypeColours (ShiftTypeColourKeyEnum)

data AdminPageScope
data AdminXeroPageScope
data AdminVenueConfigScope
data AdminInvitesScope
data AdminExportsScope
data AdminShiftTypesScope
data AdminRosterGroupsScope
data AdminXeroScope
data VenueId
data RosterGroupId

data AdminPage
data AdminXeroPage
data AdminVenueConfig
data AdminInvites
data AdminExports
data AdminShiftTypes
data AdminRosterGroups
data AdminXero

data AdminPageContentFragment
data AdminXeroPageContentFragment
data AdminVenueSettingsFragment
data AdminInvitesFragment
data AdminExportsFragment
data AdminShiftTypesFragment
data AdminRosterGroupsFragment
data AdminXeroShellFragment
data AdminXeroReferenceSyncFragment
data AdminXeroTimesheetPreparationWaitFragment
data AdminXeroPayItemImportWaitFragment

data CreateRosterGroup
data UpdateRosterGroup
data MoveRosterGroupUp
data MoveRosterGroupDown
data ToggleInactiveRosterGroups
data UpdateRosterEndTimesEnabled
data UpdateDefaultStaffPayRate
data UpdateMinutePrecisionShiftTimesEnabled
data UpdateUnavailableStaffWarningThreshold
data UpdateRosterTimePickerWindow
data UpdateRosterWeekStartsOn
data CreateVenueInvitation
data RevokeVenueInvitation
data RenewVenueInvitation
data CreateExportJob
data CreateShiftType
data UpdateShiftType
data MoveShiftTypeUp
data MoveShiftTypeDown
data AutosaveShiftTypeName
data AutosaveShiftTypeSelection
data ToggleInactiveShiftTypes
data SyncXeroPayrollReferenceData
data ShowXeroTimesheetPreparationStaffMappings
data RosterEndTimesEnabled
data MinutePrecisionShiftTimesEnabled
data TimePickerStart
data TimePickerEnd
data RosterWeekStartsOn
data UnavailableStaffWarningThreshold
data Email
data RangeStart
data RangeEnd
data ExportType
data ShowInactiveRosterGroups
data ShowInactiveShiftTypes
data Name
data PayRateSelection
data DefaultStaffAwardLevelId
data ColourKey
data IsActive
data EditStaffId
data ShowMatched
data XeroPreparationStaffMappings

data None
data OuterHTML
data Click
data ClosestFormCustomHtmx
data InputChangedAutosaveCustomHtmx
data ChangeAutosaveCustomHtmx
data LoadReferenceSyncCustomHtmx
data AdminXeroFragment

data AdminVenueSettings
data XeroConnection
data XeroReferenceSyncState

type AdminVenueSettingsResource = Resource AdminVenueSettings '[ Field VenueId 'WireUUID ]
type AdminInvitesResource = Resource AdminInvites '[ Field VenueId 'WireUUID ]
type AdminExportsResource = Resource AdminExports '[ Field VenueId 'WireUUID ]
type AdminShiftTypesResource = Resource AdminShiftTypes '[ Field VenueId 'WireUUID ]
type AdminRosterGroupsResource = Resource AdminRosterGroups '[ Field VenueId 'WireUUID ]
type XeroConnectionResource = Resource XeroConnection '[ Field VenueId 'WireUUID ]
type XeroReferenceSyncStateResource = Resource XeroReferenceSyncState '[ Field VenueId 'WireUUID ]

type AdminPageSurface =
    Surface AdminPage
        '[ Scope AdminPageScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminPageContentFragment '[]
            '[ 'MountTarget AdminPageContentFragment '[]
             , 'Eager
             , ContainsSurface AdminInvites
             , ContainsSurface AdminVenueConfig
             , ContainsSurface AdminExports
             , ContainsSurface AdminShiftTypes
             , ContainsSurface AdminRosterGroups
             ]
         ]

type AdminXeroPageSurface =
    Surface AdminXeroPage
        '[ Scope AdminXeroPageScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueOwner '[ VenueId ] ]
         , Fragment AdminXeroPageContentFragment '[]
            '[ 'MountTarget AdminXeroPageContentFragment '[]
             , 'Eager
             , ContainsSurface AdminXero
             ]
         ]

type AdminVenueSettingsSurface =
    Surface AdminVenueConfig
        '[ Scope AdminVenueConfigScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminVenueSettingsFragment '[] '[ 'MountTarget AdminVenueSettingsFragment '[], 'Eager, 'Live, 'DependsOn AdminVenueSettingsResource '[ 'FromScope VenueId ] ]
         , Action UpdateRosterEndTimesEnabled
            '[ Field RosterEndTimesEnabled 'WireBool ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminVenueSettingsFragment)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             , 'CustomHtmx ChangeAutosaveCustomHtmx "venue setting toggles submit the containing form on change"
             ]
         , Action UpdateDefaultStaffPayRate
            '[ NullableField DefaultStaffAwardLevelId 'WireUUID ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminVenueSettingsFragment)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             , 'CustomHtmx ChangeAutosaveCustomHtmx "venue staff-rate selection submits the containing form on change"
             ]
         , Action UpdateMinutePrecisionShiftTimesEnabled
            '[ Field MinutePrecisionShiftTimesEnabled 'WireBool ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminVenueSettingsFragment)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             , 'CustomHtmx ChangeAutosaveCustomHtmx "venue setting toggles submit the containing form on change"
             ]
         , Action UpdateUnavailableStaffWarningThreshold
            '[ OptionalField UnavailableStaffWarningThreshold 'WireInt ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminVenueSettingsFragment)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             , 'CustomHtmx ChangeAutosaveCustomHtmx "venue setting inputs submit on change"
             ]
         , Action UpdateRosterTimePickerWindow
            '[ Field TimePickerStart 'WireText
             , Field TimePickerEnd 'WireText
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminVenueSettingsFragment)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             , 'CustomHtmx ChangeAutosaveCustomHtmx "venue setting inputs submit on change"
             ]
         , Action UpdateRosterWeekStartsOn
            '[ Field RosterWeekStartsOn 'WireInt ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminVenueSettingsFragment)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         ]

type AdminInvitesSurface =
    Surface AdminInvites
        '[ Scope AdminInvitesScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminInvitesFragment '[] '[ 'MountTarget AdminInvitesFragment '[], 'Eager, 'Live, 'DependsOn AdminInvitesResource '[ 'FromScope VenueId ] ]
         , Action CreateVenueInvitation
            '[ Field Email 'WireText ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminInvitesFragment)
             , 'HtmxSwap 'HtmxNoSwap
             ]
         , Action RevokeVenueInvitation
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminInvitesFragment)
             , 'HtmxSwap 'HtmxNoSwap
             ]
         , Action RenewVenueInvitation
            '[ OptionalField Email 'WireText ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminInvitesFragment)
             , 'HtmxSwap 'HtmxNoSwap
             ]
         ]

type AdminExportsSurface =
    Surface AdminExports
        '[ Scope AdminExportsScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminExportsFragment '[] '[ 'MountTarget AdminExportsFragment '[], 'Eager, 'Live, 'DependsOn AdminExportsResource '[ 'FromScope VenueId ] ]
         , Action CreateExportJob
            '[ Field RangeStart 'WireDay
             , Field RangeEnd 'WireDay
             , Field ExportType ('WireClosed ExportJobType)
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminExportsFragment)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         ]

type AdminShiftTypesSurface =
    Surface AdminShiftTypes
        '[ Scope AdminShiftTypesScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminShiftTypesFragment '[] '[ 'MountTarget AdminShiftTypesFragment '[], 'Eager, 'Live, 'DependsOn AdminShiftTypesResource '[ 'FromScope VenueId ] ]
         , Action CreateShiftType
            '[ Field ShowInactiveShiftTypes 'WireBool
             , Field Name 'WireText
             , Field PayRateSelection 'WireText
             , Field ColourKey ('WireClosed ShiftTypeColourKeyEnum)
             , Field IsActive 'WireBool
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminShiftTypesFragment)
             , 'HtmxSwap 'HtmxOuterHTML
             ]
         , Action UpdateShiftType
            '[ Field ShowInactiveShiftTypes 'WireBool
             , Field Name 'WireText
             , Field PayRateSelection 'WireText
             , Field ColourKey ('WireClosed ShiftTypeColourKeyEnum)
             , Field IsActive 'WireBool
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminShiftTypesFragment)
             , 'HtmxSwap 'HtmxOuterHTML
             ]
         , Action MoveShiftTypeUp
            '[ Field ShowInactiveShiftTypes 'WireBool ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTrigger 'HtmxClick
             , 'HtmxTarget ('HtmxId AdminShiftTypesFragment)
             , 'HtmxSwap 'HtmxOuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             , 'CustomHtmx ClosestFormCustomHtmx "move buttons submit the containing row form via hx-include=closest form"
             ]
         , Action MoveShiftTypeDown
            '[ Field ShowInactiveShiftTypes 'WireBool ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTrigger 'HtmxClick
             , 'HtmxTarget ('HtmxId AdminShiftTypesFragment)
             , 'HtmxSwap 'HtmxOuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             , 'CustomHtmx ClosestFormCustomHtmx "move buttons submit the containing row form via hx-include=closest form"
             ]
         , Action AutosaveShiftTypeName
            '[ Field ShowInactiveShiftTypes 'WireBool
             , Field Name 'WireText
             , Field PayRateSelection 'WireText
             , Field ColourKey ('WireClosed ShiftTypeColourKeyEnum)
             , Field IsActive 'WireBool
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminShiftTypesFragment)
             , 'HtmxSwap 'HtmxOuterHTML
             , 'CustomHtmx InputChangedAutosaveCustomHtmx "name input autosave uses HTMX input changed delay:600ms, blur changed trigger and hx-include=closest form"
             ]
         , Action AutosaveShiftTypeSelection
            '[ Field ShowInactiveShiftTypes 'WireBool
             , Field Name 'WireText
             , Field PayRateSelection 'WireText
             , Field ColourKey ('WireClosed ShiftTypeColourKeyEnum)
             , Field IsActive 'WireBool
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminShiftTypesFragment)
             , 'HtmxSwap 'HtmxOuterHTML
             , 'CustomHtmx ChangeAutosaveCustomHtmx "select autosave uses HTMX change trigger and hx-include=closest form"
             ]
         , Action ToggleInactiveShiftTypes
            '[ Field ShowInactiveShiftTypes 'WireBool ]
            '[ 'HtmxMethod 'HtmxGet
             , 'HtmxTarget ('HtmxId AdminShiftTypesFragment)
             , 'HtmxSwap 'HtmxOuterHTML
             ]
         ]

type AdminRosterGroupsSurface =
    Surface AdminRosterGroups
        '[ Scope AdminRosterGroupsScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminRosterGroupsFragment '[] '[ 'MountTarget AdminRosterGroupsFragment '[], 'Eager, 'Live, 'DependsOn AdminRosterGroupsResource '[ 'FromScope VenueId ] ]
         , Action CreateRosterGroup
            '[ Field ShowInactiveRosterGroups 'WireBool
             , Field Name 'WireText
             , Field IsActive 'WireBool
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminRosterGroupsFragment)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , Action UpdateRosterGroup
            '[ Field ShowInactiveRosterGroups 'WireBool
             , Field Name 'WireText
             , Field IsActive 'WireBool
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminRosterGroupsFragment)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , Action MoveRosterGroupUp
            '[ Field ShowInactiveRosterGroups 'WireBool ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTrigger 'HtmxClick
             , 'HtmxTarget ('HtmxId AdminRosterGroupsFragment)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             , 'CustomHtmx ClosestFormCustomHtmx "move buttons submit the containing row form via hx-include=closest form"
             ]
         , Action MoveRosterGroupDown
            '[ Field ShowInactiveRosterGroups 'WireBool ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTrigger 'HtmxClick
             , 'HtmxTarget ('HtmxId AdminRosterGroupsFragment)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             , 'CustomHtmx ClosestFormCustomHtmx "move buttons submit the containing row form via hx-include=closest form"
             ]
         , Action ToggleInactiveRosterGroups
            '[ Field ShowInactiveRosterGroups 'WireBool ]
            '[ 'HtmxMethod 'HtmxGet
             , 'HtmxTarget ('HtmxId AdminRosterGroupsFragment)
             , 'HtmxSwap 'HtmxOuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         ]

type AdminXeroSurface =
    Surface AdminXero
        '[ Scope AdminXeroScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueOwner '[ VenueId ] ]
         , Fragment AdminXeroShellFragment '[] '[ 'MountTarget AdminXeroFragment '[], 'Eager, 'Live, 'DependsOn XeroConnectionResource '[ 'FromScope VenueId ], 'Contains AdminXeroReferenceSyncFragment ]
         , Fragment AdminXeroReferenceSyncFragment '[] '[ 'MountTarget AdminXeroReferenceSyncFragment '[], 'Eager, 'Live, 'DependsOn XeroReferenceSyncStateResource '[ 'FromScope VenueId ] ]
         , Fragment AdminXeroTimesheetPreparationWaitFragment '[] '[ 'MountTarget AdminXeroTimesheetPreparationWaitFragment '[], 'Eager, 'Live, 'DependsOn XeroReferenceSyncStateResource '[ 'FromScope VenueId ] ]
         , Fragment AdminXeroPayItemImportWaitFragment '[] '[ 'MountTarget AdminXeroPayItemImportWaitFragment '[], 'Eager, 'Live, 'DependsOn XeroReferenceSyncStateResource '[ 'FromScope VenueId ] ]
         , Action SyncXeroPayrollReferenceData
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId AdminXeroFragment)
             , 'HtmxSwap 'HtmxNoSwap
             , 'CustomHtmx LoadReferenceSyncCustomHtmx "automatic post-connect sync supplies load/push-url/indicator attributes; the manual shell action supplies this marker with no extra attributes"
             ]
         , Action ShowXeroTimesheetPreparationStaffMappings
            '[ Field ShowMatched 'WireBool
             , OptionalField EditStaffId 'WireUUID
             ]
            '[ 'HtmxMethod 'HtmxGet
             , 'HtmxTarget ('HtmxId XeroPreparationStaffMappings)
             , 'HtmxSwap 'HtmxOuterHTML
             ]
         , DomToken XeroPreparationStaffMappings
         ]
