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
        '[ Scope AdminPageScope '[ Field VenueId 'WireUUID ]
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
        '[ Scope AdminXeroPageScope '[ Field VenueId 'WireUUID ]
         , Fragment AdminXeroPageContentFragment '[]
            '[ 'Eager
             , ContainsSurface AdminXero
             ]
         ]

type AdminVenueSettingsSurface =
    Surface AdminVenueConfig
        '[ Scope AdminVenueConfigScope '[ Field VenueId 'WireUUID ]
         , Fragment AdminVenueConfigFragment '[] '[ 'Eager ]
         ]

type AdminInvitesSurface =
    Surface AdminInvites
        '[ Scope AdminInvitesScope
            '[ Field VenueId 'WireUUID
             , Field RosterGroupId 'WireUUID
             ]
         , Fragment AdminInvitesFragment '[] '[ 'Eager ]
         ]

type AdminExportsSurface =
    Surface AdminExports
        '[ Scope AdminExportsScope '[ Field VenueId 'WireUUID ]
         , Fragment AdminExportsFragment '[] '[ 'Eager ]
         ]

type AdminShiftTypesSurface =
    Surface AdminShiftTypes
        '[ Scope AdminShiftTypesScope '[ Field VenueId 'WireUUID ]
         , Fragment AdminShiftTypesFragment '[] '[ 'Eager ]
         ]

type AdminRosterGroupsSurface =
    Surface AdminRosterGroups
        '[ Scope AdminRosterGroupsScope '[ Field VenueId 'WireUUID ]
         , Fragment AdminRosterGroupsFragment '[] '[ 'Eager ]
         ]

type AdminXeroSurface =
    Surface AdminXero
        '[ Scope AdminXeroScope '[ Field VenueId 'WireUUID ]
         , Fragment AdminXeroShellFragment '[] '[ 'Eager ]
         , Fragment AdminXeroStaffMappingsFragment '[] '[ 'Eager ]
         , Fragment AdminXeroPayItemsFragment '[] '[ 'Eager ]
         , Fragment AdminXeroTimesheetsFragment '[] '[ 'Eager ]
         ]
