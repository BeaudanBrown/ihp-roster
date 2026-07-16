{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

-- | Checked production ownership registry for generated Surface adapters.
--
-- Feature-local modules own family-to-Surface associations. This aggregate
-- selects each registered family and exactly one canonical home for every
-- checked resource identity without repeating field or wire declarations.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.Registry
    ( RegisteredSurfaceAdapterFamilies
    , RegisteredSurfaceResourceAdapterHomes
    , registeredSurfaceActorOnlyFragments
    , registeredSurfaceAdapterRegistry
    ) where

import qualified Application.Helper.FrontendContract.Surface.Admin as Admin
import Application.Helper.FrontendContract.Surface.Admin.HaskellAdapter
import qualified Application.Helper.FrontendContract.Surface.Billing as Billing
import Application.Helper.FrontendContract.Surface.Billing.HaskellAdapter
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as LeaveRequests
import Application.Helper.FrontendContract.Surface.LeaveRequests.HaskellAdapter
import qualified Application.Helper.FrontendContract.Surface.Profile as Profile
import Application.Helper.FrontendContract.Surface.Profile.HaskellAdapter
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import Application.Helper.FrontendContract.Surface.Roster.HaskellAdapter
import qualified Application.Helper.FrontendContract.Surface.Support as Support
import Application.Helper.FrontendContract.Surface.Support.HaskellAdapter
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Timesheets.HaskellAdapter

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

registeredSurfaceActorOnlyFragments :: [ActorOnlyFragmentAdapterMetadata]
registeredSurfaceActorOnlyFragments =
    [ surfaceActorOnlyFragmentAdapter
        @AdminPageAdapterFamily
        @Admin.AdminPageContentFragment
        "Actor-local parent-page composition still constructs this non-passive semantic key"
    , surfaceActorOnlyFragmentAdapter
        @AdminXeroPageAdapterFamily
        @Admin.AdminXeroPageContentFragment
        "Actor-local parent-page composition still constructs this non-passive semantic key"
    ]

type RegisteredSurfaceResourceAdapterHomes =
    '[ SurfaceResourceAdapterHome TimesheetsAdapterFamily Timesheets.TimesheetDay
     , SurfaceResourceAdapterHome TimesheetsAdapterFamily Timesheets.TimesheetWeekBoundaryConfig
     , SurfaceResourceAdapterHome TimesheetsAdapterFamily Timesheets.TimesheetWeek
     , SurfaceResourceAdapterHome RosterAdapterFamily Roster.RosterWeek
     , SurfaceResourceAdapterHome RosterAdapterFamily Roster.RosterDay
     , SurfaceResourceAdapterHome RosterAdapterFamily Roster.RosterEndTimesConfig
     , SurfaceResourceAdapterHome RosterAdapterFamily Roster.RosterWeekBoundaryConfig
     , SurfaceResourceAdapterHome RosterDayTimelineAdapterFamily Roster.TimePickerConfig
     , SurfaceResourceAdapterHome LeaveRequestsAdapterFamily LeaveRequests.LeaveRequestsSection
     , SurfaceResourceAdapterHome BillingAdapterFamily Billing.Billing
     , SurfaceResourceAdapterHome SupportAdapterFamily Support.SupportAwardRates
     , SurfaceResourceAdapterHome SupportAdapterFamily Support.SupportPublicHolidays
     , SurfaceResourceAdapterHome ProfileAdapterFamily Profile.StaffProfile
     , SurfaceResourceAdapterHome ProfileAdapterFamily Profile.StaffPreferences
     , SurfaceResourceAdapterHome ProfileAdapterFamily Profile.StaffLeaveRequests
     , SurfaceResourceAdapterHome ProfileAdapterFamily Profile.StaffRsaDocuments
     , SurfaceResourceAdapterHome AdminVenueSettingsAdapterFamily Admin.AdminVenueSettings
     , SurfaceResourceAdapterHome AdminInvitesAdapterFamily Admin.AdminInvites
     , SurfaceResourceAdapterHome AdminExportsAdapterFamily Admin.AdminExports
     , SurfaceResourceAdapterHome AdminShiftTypesAdapterFamily Admin.AdminShiftTypes
     , SurfaceResourceAdapterHome AdminRosterGroupsAdapterFamily Admin.AdminRosterGroups
     , SurfaceResourceAdapterHome AdminXeroAdapterFamily Admin.XeroConnection
     ]

registeredSurfaceAdapterRegistry :: SurfaceAdapterRegistry
registeredSurfaceAdapterRegistry =
    reflectSurfaceAdapterRegistry
        @RegisteredSurfaceAdapterFamilies
        @RegisteredSurfaceResourceAdapterHomes
        @'[]
        @'[]
        registeredSurfaceActorOnlyFragments
