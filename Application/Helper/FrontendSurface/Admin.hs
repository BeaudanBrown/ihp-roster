{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Admin
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
    ) where

import Application.Helper.FrontendSurface.DSL

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

type AdminPageSurface =
    Surface AdminPage
        '[ Scope AdminPageScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
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
        '[ Scope AdminXeroPageScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment AdminXeroPageContentFragment '[]
            '[ 'Eager
             , ContainsSurface AdminXero
             ]
         ]

type AdminVenueSettingsSurface =
    Surface AdminVenueConfig
        '[ Scope AdminVenueConfigScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment AdminVenueConfigFragment '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         ]

type AdminInvitesSurface =
    Surface AdminInvites
        '[ Scope AdminInvitesScope
            '[ Field VenueId 'WireUUID
             , Field RosterGroupId 'WireUUID
             ]
            '[ 'NoAuth ]
         , Fragment AdminInvitesFragment '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         ]

type AdminExportsSurface =
    Surface AdminExports
        '[ Scope AdminExportsScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment AdminExportsFragment '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         ]

type AdminShiftTypesSurface =
    Surface AdminShiftTypes
        '[ Scope AdminShiftTypesScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment AdminShiftTypesFragment '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         ]

type AdminRosterGroupsSurface =
    Surface AdminRosterGroups
        '[ Scope AdminRosterGroupsScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment AdminRosterGroupsFragment '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         ]

type AdminXeroSurface =
    Surface AdminXero
        '[ Scope AdminXeroScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment AdminXeroShellFragment '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         , Fragment AdminXeroStaffMappingsFragment '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         , Fragment AdminXeroPayItemsFragment '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         , Fragment AdminXeroTimesheetsFragment '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         ]
