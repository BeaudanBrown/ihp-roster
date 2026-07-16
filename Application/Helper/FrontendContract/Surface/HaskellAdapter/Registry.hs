{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

-- | Checked production ownership registry for generated Surface adapters.
--
-- Feature-local modules own family-to-Surface associations. This aggregate
-- selects each registered family and exactly one canonical home for every
-- checked resource identity, runtime scope, and eligible Live fragment without
-- repeating field or wire declarations.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.Registry
    ( RegisteredSurfaceAdapterFamilies
    , RegisteredSurfaceFragmentAdapterHomes
    , RegisteredSurfaceResourceAdapterHomes
    , RegisteredSurfaceScopeAdapterHomes
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

type RegisteredSurfaceScopeAdapterHomes =
    '[ SurfaceScopeAdapterHome TimesheetsAdapterFamily Timesheets.TimesheetWeek
     , SurfaceScopeAdapterHome RosterAdapterFamily Roster.RosterWeek
     , SurfaceScopeAdapterHome RosterDayTimelineAdapterFamily Roster.RosterDayTimeline
     , SurfaceScopeAdapterHome LeaveRequestsAdapterFamily LeaveRequests.LeaveRequestsScope
     , SurfaceScopeAdapterHome BillingAdapterFamily Billing.BillingVenue
     , SurfaceScopeAdapterHome SupportAdapterFamily Support.SupportPlatform
     , SurfaceScopeAdapterHome ProfileAdapterFamily Profile.ProfileScope
     , SurfaceScopeAdapterHome StaffAdapterFamily Profile.StaffScope
     , SurfaceScopeAdapterHome AdminPageAdapterFamily Admin.AdminPageScope
     , SurfaceScopeAdapterHome AdminXeroPageAdapterFamily Admin.AdminXeroPageScope
     , SurfaceScopeAdapterHome AdminVenueSettingsAdapterFamily Admin.AdminVenueConfigScope
     , SurfaceScopeAdapterHome AdminInvitesAdapterFamily Admin.AdminInvitesScope
     , SurfaceScopeAdapterHome AdminExportsAdapterFamily Admin.AdminExportsScope
     , SurfaceScopeAdapterHome AdminShiftTypesAdapterFamily Admin.AdminShiftTypesScope
     , SurfaceScopeAdapterHome AdminRosterGroupsAdapterFamily Admin.AdminRosterGroupsScope
     , SurfaceScopeAdapterHome AdminXeroAdapterFamily Admin.AdminXeroScope
     ]

type RegisteredSurfaceFragmentAdapterHomes =
    '[ SurfaceFragmentAdapterHome TimesheetsAdapterFamily Timesheets.TimesheetToolbar
     , SurfaceFragmentAdapterHome TimesheetsAdapterFamily Timesheets.TimesheetDayColumns
     , SurfaceFragmentAdapterHome TimesheetsAdapterFamily Timesheets.TimesheetDaySection
     , SurfaceFragmentAdapterHome RosterAdapterFamily Roster.RosterContent
     , SurfaceFragmentAdapterHome RosterAdapterFamily Roster.RosterGridToolbar
     , SurfaceFragmentAdapterHome RosterAdapterFamily Roster.RosterGridFrame
     , SurfaceFragmentAdapterHome RosterAdapterFamily Roster.RosterDayColumns
     , SurfaceFragmentAdapterHome RosterAdapterFamily Roster.RosterDayRail
     , SurfaceFragmentAdapterHome RosterAdapterFamily Roster.RosterWageRail
     , SurfaceFragmentAdapterHome RosterAdapterFamily Roster.RosterSlotsGrid
     , SurfaceFragmentAdapterHome RosterAdapterFamily Roster.RosterStaffPanel
     , SurfaceFragmentAdapterHome RosterAdapterFamily Roster.RosterStaffSelfServiceLeaveFormFragment
     , SurfaceFragmentAdapterHome RosterAdapterFamily Roster.RosterDaySection
     , SurfaceFragmentAdapterHome RosterAdapterFamily Roster.RosterRow
     , SurfaceFragmentAdapterHome RosterDayTimelineAdapterFamily Roster.RosterDayTimelineContent
     , SurfaceFragmentAdapterHome LeaveRequestsAdapterFamily LeaveRequests.LeaveSectionCount
     , SurfaceFragmentAdapterHome LeaveRequestsAdapterFamily LeaveRequests.LeaveSectionList
     , SurfaceFragmentAdapterHome BillingAdapterFamily Billing.BillingStatus
     , SurfaceFragmentAdapterHome SupportAdapterFamily Support.SupportAwardRates
     , SurfaceFragmentAdapterHome SupportAdapterFamily Support.SupportPublicHolidays
     , SurfaceFragmentAdapterHome ProfileAdapterFamily Profile.ProfileDetailsSection
     , SurfaceFragmentAdapterHome ProfileAdapterFamily Profile.ProfilePreferencesSection
     , SurfaceFragmentAdapterHome ProfileAdapterFamily Profile.ProfileSecuritySection
     , SurfaceFragmentAdapterHome ProfileAdapterFamily Profile.ProfileLeaveSection
     , SurfaceFragmentAdapterHome ProfileAdapterFamily Profile.ProfileRsaSection
     , SurfaceFragmentAdapterHome StaffAdapterFamily Profile.StaffDetailsSection
     , SurfaceFragmentAdapterHome StaffAdapterFamily Profile.StaffPreferencesSection
     , SurfaceFragmentAdapterHome StaffAdapterFamily Profile.StaffLeaveSection
     , SurfaceFragmentAdapterHome AdminPageAdapterFamily Admin.AdminPageContentFragment
     , SurfaceFragmentAdapterHome AdminXeroPageAdapterFamily Admin.AdminXeroPageContentFragment
     , SurfaceFragmentAdapterHome AdminVenueSettingsAdapterFamily Admin.AdminVenueSettingsFragment
     , SurfaceFragmentAdapterHome AdminInvitesAdapterFamily Admin.AdminInvitesFragment
     , SurfaceFragmentAdapterHome AdminExportsAdapterFamily Admin.AdminExportsFragment
     , SurfaceFragmentAdapterHome AdminShiftTypesAdapterFamily Admin.AdminShiftTypesFragment
     , SurfaceFragmentAdapterHome AdminRosterGroupsAdapterFamily Admin.AdminRosterGroupsFragment
     , SurfaceFragmentAdapterHome AdminXeroAdapterFamily Admin.AdminXeroShellFragment
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
        @RegisteredSurfaceScopeAdapterHomes
        @RegisteredSurfaceFragmentAdapterHomes
        registeredSurfaceActorOnlyFragments
