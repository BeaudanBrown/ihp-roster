{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies     #-}
{-# LANGUAGE TypeOperators    #-}

-- | Nominal adapter families for the production Surface registry.
--
-- Resource homes intentionally remain empty in the generator-foundation slice;
-- feature resource migration registers them in the follow-up ticket.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.Registry
    ( AdminExportsAdapterFamily
    , AdminInvitesAdapterFamily
    , AdminPageAdapterFamily
    , AdminRosterGroupsAdapterFamily
    , AdminShiftTypesAdapterFamily
    , AdminVenueSettingsAdapterFamily
    , AdminXeroAdapterFamily
    , AdminXeroPageAdapterFamily
    , BillingAdapterFamily
    , LeaveRequestsAdapterFamily
    , ProfileAdapterFamily
    , RegisteredSurfaceAdapterFamilies
    , RegisteredSurfaceResourceAdapterHomes
    , RosterAdapterFamily
    , RosterDayTimelineAdapterFamily
    , StaffAdapterFamily
    , SupportAdapterFamily
    , TimesheetsAdapterFamily
    , registeredSurfaceAdapterRegistry
    ) where

import qualified Application.Helper.FrontendContract.Surface.Admin as Admin
import qualified Application.Helper.FrontendContract.Surface.Billing as Billing
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as LeaveRequests
import qualified Application.Helper.FrontendContract.Surface.Profile as Profile
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Support as Support
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets

-- These markers stay nominal even when multiple Surface aliases live in one
-- feature module. Generated modules can therefore use the associated type
-- without needing a runtime or source-level name for a type synonym.
data TimesheetsAdapterFamily
data RosterAdapterFamily
data RosterDayTimelineAdapterFamily
data LeaveRequestsAdapterFamily
data BillingAdapterFamily
data SupportAdapterFamily
data ProfileAdapterFamily
data StaffAdapterFamily
data AdminPageAdapterFamily
data AdminXeroPageAdapterFamily
data AdminVenueSettingsAdapterFamily
data AdminInvitesAdapterFamily
data AdminExportsAdapterFamily
data AdminShiftTypesAdapterFamily
data AdminRosterGroupsAdapterFamily
data AdminXeroAdapterFamily

instance SurfaceAdapterFamily TimesheetsAdapterFamily where
    type AdapterFamilySurface TimesheetsAdapterFamily = Timesheets.TimesheetsSurface

instance SurfaceAdapterFamily RosterAdapterFamily where
    type AdapterFamilySurface RosterAdapterFamily = Roster.RosterSurface

instance SurfaceAdapterFamily RosterDayTimelineAdapterFamily where
    type AdapterFamilySurface RosterDayTimelineAdapterFamily = Roster.RosterDayTimelineSurface

instance SurfaceAdapterFamily LeaveRequestsAdapterFamily where
    type AdapterFamilySurface LeaveRequestsAdapterFamily = LeaveRequests.LeaveRequestsSurface

instance SurfaceAdapterFamily BillingAdapterFamily where
    type AdapterFamilySurface BillingAdapterFamily = Billing.BillingSurface

instance SurfaceAdapterFamily SupportAdapterFamily where
    type AdapterFamilySurface SupportAdapterFamily = Support.SupportSurface

instance SurfaceAdapterFamily ProfileAdapterFamily where
    type AdapterFamilySurface ProfileAdapterFamily = Profile.ProfileSurface

instance SurfaceAdapterFamily StaffAdapterFamily where
    type AdapterFamilySurface StaffAdapterFamily = Profile.StaffSurface

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

type RegisteredSurfaceAdapterFamilies =
    '[ TimesheetsAdapterFamily
     , RosterAdapterFamily
     , RosterDayTimelineAdapterFamily
     , LeaveRequestsAdapterFamily
     , BillingAdapterFamily
     , SupportAdapterFamily
     , ProfileAdapterFamily
     , StaffAdapterFamily
     , AdminPageAdapterFamily
     , AdminXeroPageAdapterFamily
     , AdminVenueSettingsAdapterFamily
     , AdminInvitesAdapterFamily
     , AdminExportsAdapterFamily
     , AdminShiftTypesAdapterFamily
     , AdminRosterGroupsAdapterFamily
     , AdminXeroAdapterFamily
     ]

type RegisteredSurfaceResourceAdapterHomes = '[]

registeredSurfaceAdapterRegistry :: SurfaceAdapterRegistry
registeredSurfaceAdapterRegistry =
    reflectSurfaceAdapterRegistry
        @RegisteredSurfaceAdapterFamilies
        @RegisteredSurfaceResourceAdapterHomes
