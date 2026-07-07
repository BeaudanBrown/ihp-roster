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
    , AdminVenueConfigFragment
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
    , ShowInactiveRosterGroups
    , Name
    , IsActive
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
data AdminVenueConfigFragment
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
data ShowInactiveRosterGroups
data Name
data IsActive
data None
data OuterHTML
data Click
data ClosestFormCustomHtmx

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
         , Fragment AdminVenueConfigFragment '[] '[ 'Eager, 'Live, 'DependsOn AdminVenueSettingsResource '[ 'FromScope VenueId ] ]
         ]

type AdminInvitesSurface =
    Surface AdminInvites
        '[ Scope AdminInvitesScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminInvitesFragment '[] '[ 'Eager, 'Live, 'DependsOn AdminInvitesResource '[ 'FromScope VenueId ] ]
         ]

type AdminExportsSurface =
    Surface AdminExports
        '[ Scope AdminExportsScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminExportsFragment '[] '[ 'Eager, 'Live, 'DependsOn AdminExportsResource '[ 'FromScope VenueId ] ]
         ]

type AdminShiftTypesSurface =
    Surface AdminShiftTypes
        '[ Scope AdminShiftTypesScope '[ Field VenueId 'WireUUID ] '[ 'Authorize 'CurrentVenueAdmin '[ VenueId ] ]
         , Fragment AdminShiftTypesFragment '[] '[ 'Eager, 'Live, 'DependsOn AdminShiftTypesResource '[ 'FromScope VenueId ] ]
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
         ]
