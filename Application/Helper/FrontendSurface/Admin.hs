{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Admin
    ( AdminVenueSettingsSurface
    , AdminInvitesSurface
    , AdminExportsSurface
    , AdminShiftTypesSurface
    , AdminRosterGroupsSurface
    , AdminXeroSurface
    , AdminVenueSettingsScope
    , AdminInvitesScope
    , AdminExportsScope
    , AdminShiftTypesScope
    , AdminRosterGroupsScope
    , AdminXeroScope
    , VenueId
    , RosterGroupId
    , AdminVenueSettingsFragment
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

data AdminVenueSettingsScope
data AdminInvitesScope
data AdminExportsScope
data AdminShiftTypesScope
data AdminRosterGroupsScope
data AdminXeroScope
data VenueId
data RosterGroupId

data AdminVenueSettings
data AdminInvites
data AdminExports
data AdminShiftTypes
data AdminRosterGroups
data AdminXero

data AdminVenueSettingsFragment
data AdminInvitesFragment
data AdminExportsFragment
data AdminShiftTypesFragment
data AdminRosterGroupsFragment
data AdminXeroShellFragment
data AdminXeroStaffMappingsFragment
data AdminXeroPayItemsFragment
data AdminXeroTimesheetsFragment

type AdminVenueSettingsSurface =
    Surface AdminVenueSettings
        '[ Scope AdminVenueSettingsScope '[ Field VenueId 'WireUUID ]
         , Fragment AdminVenueSettingsFragment '[] '[ 'Eager ]
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
