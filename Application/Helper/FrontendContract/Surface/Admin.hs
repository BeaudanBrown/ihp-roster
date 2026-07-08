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
    , AdminXeroStaffMappingsFragment
    , AdminXeroPayItemsFragment
    , AdminXeroTimesheetsFragment
    , CreateRosterGroup
    , UpdateRosterGroup
    , MoveRosterGroupUp
    , MoveRosterGroupDown
    , ToggleInactiveRosterGroups
    , UpdateVenueConfig
    , CreateVenueInvitation
    , RevokeVenueInvitation
    , CreateExportJob
    , CreateShiftType
    , UpdateShiftType
    , MoveShiftTypeUp
    , MoveShiftTypeDown
    , AutosaveShiftTypeName
    , AutosaveShiftTypeSelection
    , ToggleInactiveShiftTypes
    , SyncXeroPayrollReferenceData
    , SaveXeroPayrollCalendarSelection
    , SaveXeroPayItemAccountCodeSelection
    , CreateMissingXeroPayItems
    , ArchiveXeroImportedPayItem
    , SaveXeroStaffMapping
    , SuggestXeroStaffMapping
    , ConfigFieldField
    , RosterEndTimesEnabled
    , AutoTimesheetCreationEnabled
    , Email
    , RangeStart
    , RangeEnd
    , ExportType
    , ShowInactiveRosterGroups
    , ShowInactiveShiftTypes
    , Name
    , PayRateSelection
    , ColourKey
    , IsActive
    , XeroPayrollCalendarSelection
    , XeroPayItemAccountCodeSelection
    , StaffId
    , XeroEmployeeSelection
    ) where

import Application.Helper.FrontendContract.Surface.DSL

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
data AdminXeroStaffMappingsFragment
data AdminXeroPayItemsFragment
data AdminXeroTimesheetsFragment

data CreateRosterGroup
data UpdateRosterGroup
data MoveRosterGroupUp
data MoveRosterGroupDown
data ToggleInactiveRosterGroups
data UpdateVenueConfig
data CreateVenueInvitation
data RevokeVenueInvitation
data CreateExportJob
data CreateShiftType
data UpdateShiftType
data MoveShiftTypeUp
data MoveShiftTypeDown
data AutosaveShiftTypeName
data AutosaveShiftTypeSelection
data ToggleInactiveShiftTypes
data SyncXeroPayrollReferenceData
data SaveXeroPayrollCalendarSelection
data SaveXeroPayItemAccountCodeSelection
data CreateMissingXeroPayItems
data ArchiveXeroImportedPayItem
data SaveXeroStaffMapping
data SuggestXeroStaffMapping
data ConfigFieldField
data RosterEndTimesEnabled
data AutoTimesheetCreationEnabled
data Email
data RangeStart
data RangeEnd
data ExportType
data ShowInactiveRosterGroups
data ShowInactiveShiftTypes
data Name
data PayRateSelection
data ColourKey
data IsActive
data XeroPayrollCalendarSelection
data XeroPayItemAccountCodeSelection
data StaffId
data XeroEmployeeSelection
data None
data OuterHTML
data Click
data ClosestFormCustomHtmx
data InputChangedAutosaveCustomHtmx
data ChangeAutosaveCustomHtmx
data LoadReferenceSyncCustomHtmx
data XeroPayItemsSyncIndicator
data AdminXeroFragment
data XeroPayItemsData

data AdminVenueSettings
data AdminInvitesResourceMarker
data AdminExportsResourceMarker
data AdminShiftTypesResourceMarker
data AdminRosterGroupsResourceMarker
data XeroConnection
data XeroMappings
data XeroPayItems
data XeroTimesheets

type AdminVenueSettingsResource = Resource AdminVenueSettings '[ Field VenueId 'WireUUID ]
type AdminInvitesResource = Resource AdminInvites '[ Field VenueId 'WireUUID ]
type AdminExportsResource = Resource AdminExports '[ Field VenueId 'WireUUID ]
type AdminShiftTypesResource = Resource AdminShiftTypes '[ Field VenueId 'WireUUID ]
type AdminRosterGroupsResource = Resource AdminRosterGroups '[ Field VenueId 'WireUUID ]
type XeroConnectionResource = Resource XeroConnection '[ Field VenueId 'WireUUID ]
type XeroMappingsResource = Resource XeroMappings '[ Field VenueId 'WireUUID ]
type XeroPayItemsResource = Resource XeroPayItems '[ Field VenueId 'WireUUID ]
type XeroTimesheetsResource = Resource XeroTimesheets '[ Field VenueId 'WireUUID ]

type AdminPageSurface =
    Surface AdminPage
        '[ Scope AdminPageScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminPageContentFragment '[]
            '[ 'Eager
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
            '[ 'Eager
             , ContainsSurface AdminXero
             ]
         ]

type AdminVenueSettingsSurface =
    Surface AdminVenueConfig
        '[ Scope AdminVenueConfigScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminVenueSettingsFragment '[] '[ 'Eager, 'Live, 'DependsOn AdminVenueSettingsResource '[ 'FromScope VenueId ] ]
         , Action UpdateVenueConfig
            '[ Field ConfigFieldField 'WireText
             , OptionalField RosterEndTimesEnabled 'WireBool
             , OptionalField AutoTimesheetCreationEnabled 'WireBool
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminVenueSettingsFragment
             , 'HtmxSwap None
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             , 'CustomHtmx ChangeAutosaveCustomHtmx "venue setting toggles submit the containing form on change"
             ]
         , DomToken AdminVenueSettingsFragment
         ]

type AdminInvitesSurface =
    Surface AdminInvites
        '[ Scope AdminInvitesScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminInvitesFragment '[] '[ 'Eager, 'Live, 'DependsOn AdminInvitesResource '[ 'FromScope VenueId ] ]
         , Action CreateVenueInvitation
            '[ Field Email 'WireText ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminInvitesFragment
             , 'HtmxSwap None
             ]
         , Action RevokeVenueInvitation
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminInvitesFragment
             , 'HtmxSwap None
             ]
         , DomToken AdminInvitesFragment
         ]

type AdminExportsSurface =
    Surface AdminExports
        '[ Scope AdminExportsScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminExportsFragment '[] '[ 'Eager, 'Live, 'DependsOn AdminExportsResource '[ 'FromScope VenueId ] ]
         , Action CreateExportJob
            '[ Field RangeStart 'WireDay
             , Field RangeEnd 'WireDay
             , Field ExportType 'WireText
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminExportsFragment
             , 'HtmxSwap None
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , DomToken AdminExportsFragment
         ]

type AdminShiftTypesSurface =
    Surface AdminShiftTypes
        '[ Scope AdminShiftTypesScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminShiftTypesFragment '[] '[ 'Eager, 'Live, 'DependsOn AdminShiftTypesResource '[ 'FromScope VenueId ] ]
         , Action CreateShiftType
            '[ Field ShowInactiveShiftTypes 'WireBool
             , Field Name 'WireText
             , Field PayRateSelection 'WireText
             , Field ColourKey 'WireText
             , Field IsActive 'WireBool
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminShiftTypesFragment
             , 'HtmxSwap OuterHTML
             ]
         , Action UpdateShiftType
            '[ Field ShowInactiveShiftTypes 'WireBool
             , Field Name 'WireText
             , Field PayRateSelection 'WireText
             , Field ColourKey 'WireText
             , Field IsActive 'WireBool
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminShiftTypesFragment
             , 'HtmxSwap OuterHTML
             ]
         , Action MoveShiftTypeUp
            '[ Field ShowInactiveShiftTypes 'WireBool ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTrigger Click
             , 'HtmxTarget AdminShiftTypesFragment
             , 'HtmxSwap OuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             , 'CustomHtmx ClosestFormCustomHtmx "move buttons submit the containing row form via hx-include=closest form"
             ]
         , Action MoveShiftTypeDown
            '[ Field ShowInactiveShiftTypes 'WireBool ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTrigger Click
             , 'HtmxTarget AdminShiftTypesFragment
             , 'HtmxSwap OuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             , 'CustomHtmx ClosestFormCustomHtmx "move buttons submit the containing row form via hx-include=closest form"
             ]
         , Action AutosaveShiftTypeName
            '[ Field ShowInactiveShiftTypes 'WireBool
             , Field Name 'WireText
             , Field PayRateSelection 'WireText
             , Field ColourKey 'WireText
             , Field IsActive 'WireBool
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminShiftTypesFragment
             , 'HtmxSwap OuterHTML
             , 'CustomHtmx InputChangedAutosaveCustomHtmx "name input autosave uses HTMX input changed delay:600ms, blur changed trigger and hx-include=closest form"
             ]
         , Action AutosaveShiftTypeSelection
            '[ Field ShowInactiveShiftTypes 'WireBool
             , Field Name 'WireText
             , Field PayRateSelection 'WireText
             , Field ColourKey 'WireText
             , Field IsActive 'WireBool
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminShiftTypesFragment
             , 'HtmxSwap OuterHTML
             , 'CustomHtmx ChangeAutosaveCustomHtmx "select autosave uses HTMX change trigger and hx-include=closest form"
             ]
         , Action ToggleInactiveShiftTypes
            '[ Field ShowInactiveShiftTypes 'WireBool ]
            '[ 'HtmxMethod 'HtmxGet
             , 'HtmxTarget AdminShiftTypesFragment
             , 'HtmxSwap OuterHTML
             ]
         , DomToken AdminShiftTypesFragment
         ]

type AdminRosterGroupsSurface =
    Surface AdminRosterGroups
        '[ Scope AdminRosterGroupsScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminRosterGroupsFragment '[] '[ 'Eager, 'Live, 'DependsOn AdminRosterGroupsResource '[ 'FromScope VenueId ] ]
         , Action CreateRosterGroup
            '[ Field ShowInactiveRosterGroups 'WireBool
             , Field Name 'WireText
             , Field IsActive 'WireBool
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminRosterGroupsFragment
             , 'HtmxSwap None
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , Action UpdateRosterGroup
            '[ Field ShowInactiveRosterGroups 'WireBool
             , Field Name 'WireText
             , Field IsActive 'WireBool
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminRosterGroupsFragment
             , 'HtmxSwap None
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , Action MoveRosterGroupUp
            '[ Field ShowInactiveRosterGroups 'WireBool ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTrigger Click
             , 'HtmxTarget AdminRosterGroupsFragment
             , 'HtmxSwap None
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             , 'CustomHtmx ClosestFormCustomHtmx "move buttons submit the containing row form via hx-include=closest form"
             ]
         , Action MoveRosterGroupDown
            '[ Field ShowInactiveRosterGroups 'WireBool ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTrigger Click
             , 'HtmxTarget AdminRosterGroupsFragment
             , 'HtmxSwap None
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             , 'CustomHtmx ClosestFormCustomHtmx "move buttons submit the containing row form via hx-include=closest form"
             ]
         , Action ToggleInactiveRosterGroups
            '[ Field ShowInactiveRosterGroups 'WireBool ]
            '[ 'HtmxMethod 'HtmxGet
             , 'HtmxTarget AdminRosterGroupsFragment
             , 'HtmxSwap OuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , DomToken AdminRosterGroupsFragment
         ]

type AdminXeroSurface =
    Surface AdminXero
        '[ Scope AdminXeroScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueOwner '[ VenueId ] ]
         , Fragment AdminXeroShellFragment '[] '[ 'Eager, 'Live, 'DependsOn XeroConnectionResource '[ 'FromScope VenueId ] ]
         , Fragment AdminXeroStaffMappingsFragment '[] '[ 'Eager, 'Live, 'DependsOn XeroMappingsResource '[ 'FromScope VenueId ] ]
         , Fragment AdminXeroPayItemsFragment '[] '[ 'Eager, 'Live, 'DependsOn XeroPayItemsResource '[ 'FromScope VenueId ] ]
         , Fragment AdminXeroTimesheetsFragment '[] '[ 'Eager, 'Live, 'DependsOn XeroTimesheetsResource '[ 'FromScope VenueId ] ]
         , Action SyncXeroPayrollReferenceData
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminXeroFragment
             , 'HtmxSwap OuterHTML
             , 'CustomHtmx LoadReferenceSyncCustomHtmx "automatic post-connect reference sync uses hx-trigger=load, a concrete Xero page push URL, and the connection status indicator"
             ]
         , Action SaveXeroPayrollCalendarSelection
            '[ Field XeroPayrollCalendarSelection 'WireText ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminXeroFragment
             , 'HtmxSwap None
             , 'CustomHtmx ChangeAutosaveCustomHtmx "payroll calendar selection submits on change"
             ]
         , Action SaveXeroPayItemAccountCodeSelection
            '[ Field XeroPayItemAccountCodeSelection 'WireText ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminXeroFragment
             , 'HtmxSwap None
             , 'CustomHtmx ChangeAutosaveCustomHtmx "pay item account-code selection submits on change"
             ]
         , Action CreateMissingXeroPayItems
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget XeroPayItemsData
             , 'HtmxSwap None
             , 'HtmxIndicator XeroPayItemsSyncIndicator
             ]
         , Action ArchiveXeroImportedPayItem
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget XeroPayItemsData
             , 'HtmxSwap None
             ]
         , Action SaveXeroStaffMapping
            '[ Field StaffId 'WireUUID
             , Field XeroEmployeeSelection 'WireText
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminXeroFragment
             , 'HtmxSwap None
             , 'CustomHtmx ChangeAutosaveCustomHtmx "staff mapping selection submits on change"
             ]
         , Action SuggestXeroStaffMapping
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget AdminXeroFragment
             , 'HtmxSwap None
             ]
         , DomToken AdminXeroFragment
         , DomToken XeroPayItemsData
         , DomToken XeroPayItemsSyncIndicator
         ]
