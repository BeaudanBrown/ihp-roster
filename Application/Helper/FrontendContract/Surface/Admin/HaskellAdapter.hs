{-# LANGUAGE TypeFamilies #-}

-- | Typed generator ownership for Admin Surface adapters.
module Application.Helper.FrontendContract.Surface.Admin.HaskellAdapter
    ( AdminExportsAdapterFamily
    , AdminInvitesAdapterFamily
    , AdminPageAdapterFamily
    , AdminRosterGroupsAdapterFamily
    , AdminShiftTypesAdapterFamily
    , AdminVenueSettingsAdapterFamily
    , AdminXeroAdapterFamily
    , AdminXeroPageAdapterFamily
    ) where

import qualified Application.Helper.FrontendContract.Surface.Admin as Admin
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family

data AdminPageAdapterFamily
data AdminXeroPageAdapterFamily
data AdminVenueSettingsAdapterFamily
data AdminInvitesAdapterFamily
data AdminExportsAdapterFamily
data AdminShiftTypesAdapterFamily
data AdminRosterGroupsAdapterFamily
data AdminXeroAdapterFamily

instance SurfaceAdapterFamily AdminPageAdapterFamily where
    type AdapterFamilySurface AdminPageAdapterFamily = Admin.AdminPageSurface

instance SurfaceAdapterFamily AdminXeroPageAdapterFamily where
    type AdapterFamilySurface AdminXeroPageAdapterFamily = Admin.AdminXeroPageSurface

instance SurfaceAdapterFamily AdminVenueSettingsAdapterFamily where
    type AdapterFamilySurface AdminVenueSettingsAdapterFamily = Admin.AdminVenueSettingsSurface

instance SurfaceAdapterFamily AdminInvitesAdapterFamily where
    type AdapterFamilySurface AdminInvitesAdapterFamily = Admin.AdminInvitesSurface

instance SurfaceAdapterFamily AdminExportsAdapterFamily where
    type AdapterFamilySurface AdminExportsAdapterFamily = Admin.AdminExportsSurface

instance SurfaceAdapterFamily AdminShiftTypesAdapterFamily where
    type AdapterFamilySurface AdminShiftTypesAdapterFamily = Admin.AdminShiftTypesSurface

instance SurfaceAdapterFamily AdminRosterGroupsAdapterFamily where
    type AdapterFamilySurface AdminRosterGroupsAdapterFamily = Admin.AdminRosterGroupsSurface

instance SurfaceAdapterFamily AdminXeroAdapterFamily where
    type AdapterFamilySurface AdminXeroAdapterFamily = Admin.AdminXeroSurface
