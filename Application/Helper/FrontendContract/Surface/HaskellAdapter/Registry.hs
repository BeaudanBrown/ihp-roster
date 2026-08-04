{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

-- | Checked production ownership registry for generated Surface adapters.
--
-- Feature-local modules own family-to-Surface associations. This aggregate
-- selects each registered family and exactly one canonical home for every
-- eligible Resource, Live, Action, and Intent declaration without repeating
-- field or wire declarations.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.Registry
    ( RegisteredSurfaceActionAdapterHomes
    , RegisteredSurfaceAdapterFamilies
    , RegisteredSurfaceFragmentAdapterHomes
    , RegisteredSurfaceIntentAdapterHomes
    , registeredSurfaceActionAdapterRegistrations
    , registeredSurfaceIntentAdapterRegistrations
    , RegisteredSurfaceResourceAdapterHomes
    , RegisteredSurfaceScopeAdapterHomes
    , registeredSurfaceActorOnlyFragments
    , registeredSurfaceAdapterRegistry
    ) where

import qualified Application.Helper.FrontendContract.Surface.Admin as Admin
import Application.Helper.FrontendContract.Surface.Admin.HaskellAdapter
import qualified Application.Helper.FrontendContract.Surface.Billing as Billing
import Application.Helper.FrontendContract.Surface.Billing.HaskellAdapter
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core (SurfaceAdapterKind (..))
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as LeaveRequests
import Application.Helper.FrontendContract.Surface.LeaveRequests.HaskellAdapter
import qualified Application.Helper.FrontendContract.Surface.Profile as Profile
import Application.Helper.FrontendContract.Surface.Profile.HaskellAdapter
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import Application.Helper.FrontendContract.Surface.Roster.HaskellAdapter
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave as SelfServiceLeave
import Application.Helper.FrontendContract.Surface.SelfServiceLeave.HaskellAdapter
import qualified Application.Helper.FrontendContract.Surface.Support as Support
import Application.Helper.FrontendContract.Surface.Support.HaskellAdapter
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Timesheets.HaskellAdapter
import IHP.Prelude (Text)

type RegisteredSurfaceAdapterFamilies =
    '[ TimesheetsAdapterFamily
     , RosterAdapterFamily
     , RosterDayTimelineAdapterFamily
     , RosterTemplateDesignerAdapterFamily
     , LeaveRequestsAdapterFamily
     , SelfServiceLeaveAdapterFamily
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
     , SurfaceScopeAdapterHome RosterTemplateDesignerAdapterFamily Roster.RosterTemplateDesignerScope
     , SurfaceScopeAdapterHome LeaveRequestsAdapterFamily LeaveRequests.LeaveRequestsScope
     , SurfaceScopeAdapterHome SelfServiceLeaveAdapterFamily SelfServiceLeave.SelfServiceLeaveScope
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
     , SurfaceFragmentAdapterHome RosterAdapterFamily Roster.RosterTemplateLibraryFragment
     , SurfaceFragmentAdapterHome RosterAdapterFamily Roster.RosterDaySection
     , SurfaceFragmentAdapterHome RosterAdapterFamily Roster.RosterRow
     , SurfaceFragmentAdapterHome RosterDayTimelineAdapterFamily Roster.RosterDayTimelineContent
     , SurfaceFragmentAdapterHome LeaveRequestsAdapterFamily LeaveRequests.UnavailabilityBlackouts
     , SurfaceFragmentAdapterHome LeaveRequestsAdapterFamily LeaveRequests.LeaveAvailabilityWarnings
     , SurfaceFragmentAdapterHome LeaveRequestsAdapterFamily LeaveRequests.LeaveSectionCount
     , SurfaceFragmentAdapterHome LeaveRequestsAdapterFamily LeaveRequests.LeaveSectionList
     , SurfaceFragmentAdapterHome SelfServiceLeaveAdapterFamily SelfServiceLeave.VisibleUnavailabilityBlackoutsFragment
     , SurfaceFragmentAdapterHome SelfServiceLeaveAdapterFamily SelfServiceLeave.SelfServiceLeaveFormFragment
     , SurfaceFragmentAdapterHome SelfServiceLeaveAdapterFamily SelfServiceLeave.SelfServiceLeaveHistoryFragment
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
     , SurfaceFragmentAdapterHome StaffAdapterFamily Profile.StaffVisibleUnavailabilityBlackouts
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
     , SurfaceResourceAdapterHome RosterAdapterFamily Roster.RosterWeekStructure
     , SurfaceResourceAdapterHome RosterAdapterFamily Roster.RosterNotificationStatus
     , SurfaceResourceAdapterHome RosterAdapterFamily Roster.RosterSlotsStructure
     , SurfaceResourceAdapterHome RosterAdapterFamily Roster.RosterSlotsContent
     , SurfaceResourceAdapterHome RosterAdapterFamily Roster.RosterTemplateLibrary
     , SurfaceResourceAdapterHome RosterAdapterFamily Roster.RosterTemplate
     , SurfaceResourceAdapterHome RosterAdapterFamily Roster.RosterTemplateDraft
     , SurfaceResourceAdapterHome RosterAdapterFamily Roster.RosterDay
     , SurfaceResourceAdapterHome RosterAdapterFamily Roster.RosterEndTimesConfig
     , SurfaceResourceAdapterHome RosterAdapterFamily Roster.RosterWeekBoundaryConfig
     , SurfaceResourceAdapterHome RosterDayTimelineAdapterFamily Roster.TimePickerConfig
     , SurfaceResourceAdapterHome LeaveRequestsAdapterFamily LeaveRequests.UnavailabilityBlackouts
     , SurfaceResourceAdapterHome LeaveRequestsAdapterFamily LeaveRequests.LeaveAvailabilityWarnings
     , SurfaceResourceAdapterHome LeaveRequestsAdapterFamily LeaveRequests.LeaveRequestsSection
     , SurfaceResourceAdapterHome BillingAdapterFamily Billing.Billing
     , SurfaceResourceAdapterHome SupportAdapterFamily Support.SupportAwardRates
     , SurfaceResourceAdapterHome SupportAdapterFamily Support.SupportPublicHolidays
     , SurfaceResourceAdapterHome ProfileAdapterFamily Profile.StaffProfile
     , SurfaceResourceAdapterHome ProfileAdapterFamily Profile.StaffPreferences
     , SurfaceResourceAdapterHome SelfServiceLeaveAdapterFamily SelfServiceLeave.StaffLeaveRequests
     , SurfaceResourceAdapterHome ProfileAdapterFamily Profile.StaffRsaDocuments
     , SurfaceResourceAdapterHome AdminVenueSettingsAdapterFamily Admin.AdminVenueSettings
     , SurfaceResourceAdapterHome AdminInvitesAdapterFamily Admin.AdminInvites
     , SurfaceResourceAdapterHome AdminExportsAdapterFamily Admin.AdminExports
     , SurfaceResourceAdapterHome AdminShiftTypesAdapterFamily Admin.AdminShiftTypes
     , SurfaceResourceAdapterHome AdminRosterGroupsAdapterFamily Admin.AdminRosterGroups
     , SurfaceResourceAdapterHome AdminXeroAdapterFamily Admin.XeroConnection
     ]

type RegisteredSurfaceActionAdapterHomes =
    '[ SurfaceActionAdapterHome TimesheetsAdapterFamily Timesheets.NavigateTimesheetWeek
     , SurfaceActionAdapterHome TimesheetsAdapterFamily Timesheets.UpdateTimesheetFilters
     , SurfaceActionAdapterHome TimesheetsAdapterFamily Timesheets.ToggleTimesheetHideApproved
     , SurfaceActionAdapterHome TimesheetsAdapterFamily Timesheets.ToggleTimesheetShowSuggestions
     , SurfaceActionAdapterHome TimesheetsAdapterFamily Timesheets.CreateTimesheetEntryFromSuggestion
     , SurfaceActionAdapterHome TimesheetsAdapterFamily Timesheets.ApproveTimesheetEntry
     , SurfaceActionAdapterHome TimesheetsAdapterFamily Timesheets.UnapproveTimesheetEntry
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.NavigateRosterWeek
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.ToggleRosterWarnings
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.ToggleRosterWageEstimates
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.SortRosterWeek
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.ToggleRosterWeekLiveStatus
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.ShowRosterNotificationConfirmation
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.CreateRosterNotificationRun
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.ToggleRosterAssignmentFilters
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.CopyRosterWeek
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.CreateRosterWeekSlotDefinition
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.DeleteRosterWeekSlotDefinition
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.ToggleRosterDayClosed
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.AddRosterRow
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.RemoveRosterRow
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.ToggleRosterStaffScope
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.PreviewRosterTemplateApplication
     , SurfaceActionAdapterHome RosterAdapterFamily Roster.ApplyRosterTemplateApplication
     , SurfaceActionAdapterHome LeaveRequestsAdapterFamily LeaveRequests.ArchiveLeaveRequestsPage
     , SurfaceActionAdapterHome LeaveRequestsAdapterFamily LeaveRequests.ApproveLeaveRequest
     , SurfaceActionAdapterHome LeaveRequestsAdapterFamily LeaveRequests.DenyLeaveRequest
     , SurfaceActionAdapterHome LeaveRequestsAdapterFamily LeaveRequests.CreateUnavailabilityBlackout
     , SurfaceActionAdapterHome LeaveRequestsAdapterFamily LeaveRequests.UpdateUnavailabilityBlackout
     , SurfaceActionAdapterHome LeaveRequestsAdapterFamily LeaveRequests.DeleteUnavailabilityBlackout
     , SurfaceActionAdapterHome SelfServiceLeaveAdapterFamily SelfServiceLeave.CreateSelfServiceLeaveRequest
     , SurfaceActionAdapterHome SupportAdapterFamily Support.CreatePublicHolidayRefreshJob
     , SurfaceActionAdapterHome SupportAdapterFamily Support.CreateFwcMapdRefreshJob
     , SurfaceActionAdapterHome ProfileAdapterFamily Profile.UpdateProfileDetails
     , SurfaceActionAdapterHome ProfileAdapterFamily Profile.UpdateProfileShiftPreferences
     , SurfaceActionAdapterHome StaffAdapterFamily Profile.UpdateStaffProfile
     , SurfaceActionAdapterHome StaffAdapterFamily Profile.UpdateStaffShiftPreferences
     , SurfaceActionAdapterHome StaffAdapterFamily Profile.CreateStaffLeaveRequest
     , SurfaceActionAdapterHome AdminVenueSettingsAdapterFamily Admin.UpdateVenueConfig
     , SurfaceActionAdapterHome AdminInvitesAdapterFamily Admin.CreateVenueInvitation
     , SurfaceActionAdapterHome AdminInvitesAdapterFamily Admin.RevokeVenueInvitation
     , SurfaceActionAdapterHome AdminInvitesAdapterFamily Admin.RenewVenueInvitation
     , SurfaceActionAdapterHome AdminExportsAdapterFamily Admin.CreateExportJob
     , SurfaceActionAdapterHome AdminShiftTypesAdapterFamily Admin.CreateShiftType
     , SurfaceActionAdapterHome AdminShiftTypesAdapterFamily Admin.UpdateShiftType
     , SurfaceActionAdapterHome AdminShiftTypesAdapterFamily Admin.MoveShiftTypeUp
     , SurfaceActionAdapterHome AdminShiftTypesAdapterFamily Admin.MoveShiftTypeDown
     , SurfaceActionAdapterHome AdminShiftTypesAdapterFamily Admin.AutosaveShiftTypeName
     , SurfaceActionAdapterHome AdminShiftTypesAdapterFamily Admin.AutosaveShiftTypeSelection
     , SurfaceActionAdapterHome AdminShiftTypesAdapterFamily Admin.ToggleInactiveShiftTypes
     , SurfaceActionAdapterHome AdminRosterGroupsAdapterFamily Admin.CreateRosterGroup
     , SurfaceActionAdapterHome AdminRosterGroupsAdapterFamily Admin.UpdateRosterGroup
     , SurfaceActionAdapterHome AdminRosterGroupsAdapterFamily Admin.MoveRosterGroupUp
     , SurfaceActionAdapterHome AdminRosterGroupsAdapterFamily Admin.MoveRosterGroupDown
     , SurfaceActionAdapterHome AdminRosterGroupsAdapterFamily Admin.ToggleInactiveRosterGroups
     , SurfaceActionAdapterHome AdminXeroAdapterFamily Admin.SyncXeroPayrollReferenceData
     , SurfaceActionAdapterHome AdminXeroAdapterFamily Admin.ShowXeroTimesheetPreparationStaffMappings
     ]

-- Every eligible Action emits builders and render metadata. The exact parser
-- inventory contains 38 generated operations and 15 typed exclusions for
-- declarations whose current endpoint consumes no complete Surface envelope.
registeredSurfaceActionAdapterRegistrations :: [SurfaceRequestAdapterRegistration 'ActionAdapterKind]
registeredSurfaceActionAdapterRegistrations =
    [ surfaceActionAdapter @TimesheetsAdapterFamily @Timesheets.NavigateTimesheetWeek allRequestAdapterOperations
    , surfaceActionAdapter @TimesheetsAdapterFamily @Timesheets.UpdateTimesheetFilters allRequestAdapterOperations
    , surfaceActionAdapter @TimesheetsAdapterFamily @Timesheets.ToggleTimesheetHideApproved allRequestAdapterOperations
    , surfaceActionAdapter @TimesheetsAdapterFamily @Timesheets.ToggleTimesheetShowSuggestions allRequestAdapterOperations
    , surfaceActionAdapter @TimesheetsAdapterFamily @Timesheets.CreateTimesheetEntryFromSuggestion allRequestAdapterOperations
    , surfaceActionAdapter @TimesheetsAdapterFamily @Timesheets.ApproveTimesheetEntry allRequestAdapterOperations
    , surfaceActionAdapter @TimesheetsAdapterFamily @Timesheets.UnapproveTimesheetEntry allRequestAdapterOperations
    , surfaceActionAdapter @RosterAdapterFamily @Roster.NavigateRosterWeek allRequestAdapterOperations
    , surfaceActionAdapter @RosterAdapterFamily @Roster.ToggleRosterWarnings allRequestAdapterOperations
    , surfaceActionAdapter @RosterAdapterFamily @Roster.ToggleRosterWageEstimates allRequestAdapterOperations
    , surfaceActionAdapter @RosterAdapterFamily @Roster.SortRosterWeek
        (requestAdapterOperationsWithoutParser "The zero-field sort endpoint consumes route context and has no Surface request parser")
    , surfaceActionAdapter @RosterAdapterFamily @Roster.ToggleRosterWeekLiveStatus allRequestAdapterOperations
    , surfaceActionAdapter @RosterAdapterFamily @Roster.ShowRosterNotificationConfirmation allRequestAdapterOperations
    , surfaceActionAdapter @RosterAdapterFamily @Roster.CreateRosterNotificationRun allRequestAdapterOperations
    , surfaceActionAdapter @RosterAdapterFamily @Roster.ToggleRosterAssignmentFilters allRequestAdapterOperations
    , surfaceActionAdapter @RosterAdapterFamily @Roster.CopyRosterWeek allRequestAdapterOperations
    , surfaceActionAdapter @RosterAdapterFamily @Roster.CreateRosterWeekSlotDefinition
        (requestAdapterOperationsWithoutParser "The zero-field slot creation endpoint consumes route context and has no Surface request parser")
    , surfaceActionAdapter @RosterAdapterFamily @Roster.DeleteRosterWeekSlotDefinition
        (requestAdapterOperationsWithoutParser "The zero-field slot deletion endpoint consumes route context and has no Surface request parser")
    , surfaceActionAdapter @RosterAdapterFamily @Roster.ToggleRosterDayClosed
        (requestAdapterOperationsWithoutParser "The zero-field day toggle endpoint consumes its route id and has no Surface request parser")
    , surfaceActionAdapter @RosterAdapterFamily @Roster.AddRosterRow
        (requestAdapterOperationsWithoutParser "The zero-field row creation endpoint consumes its route id and has no Surface request parser")
    , surfaceActionAdapter @RosterAdapterFamily @Roster.RemoveRosterRow
        (requestAdapterOperationsWithoutParser "The zero-field row removal endpoint consumes its route id and has no Surface request parser")
    , surfaceActionAdapter @RosterAdapterFamily @Roster.ToggleRosterStaffScope allRequestAdapterOperations
    , surfaceActionAdapterExcluded @RosterAdapterFamily @Roster.SetRosterLayoutMode intentOnlyActionReason
    , surfaceActionAdapterExcluded @RosterAdapterFamily @Roster.MoveRosterShiftToSlot intentOnlyActionReason
    , surfaceActionAdapterExcluded @RosterAdapterFamily @Roster.DuplicateRosterShiftToDay intentOnlyActionReason
    , surfaceActionAdapterExcluded @RosterAdapterFamily @Roster.DropRosterStaff intentOnlyActionReason
    , surfaceActionAdapter @RosterAdapterFamily @Roster.PreviewRosterTemplateApplication allRequestAdapterOperations
    , surfaceActionAdapter @RosterAdapterFamily @Roster.ApplyRosterTemplateApplication allRequestAdapterOperations
    , surfaceActionAdapterExcluded @RosterDayTimelineAdapterFamily @Roster.MoveRosterTimelineShift intentOnlyActionReason
    , surfaceActionAdapter @LeaveRequestsAdapterFamily @LeaveRequests.ArchiveLeaveRequestsPage allRequestAdapterOperations
    , surfaceActionAdapter @LeaveRequestsAdapterFamily @LeaveRequests.ApproveLeaveRequest
        (requestAdapterOperationsWithoutParser "The zero-field approval endpoint consumes its route id and has no Surface request parser")
    , surfaceActionAdapter @LeaveRequestsAdapterFamily @LeaveRequests.DenyLeaveRequest
        (requestAdapterOperationsWithoutParser "The zero-field denial endpoint consumes its route id and has no Surface request parser")
    , surfaceActionAdapter @LeaveRequestsAdapterFamily @LeaveRequests.CreateUnavailabilityBlackout allRequestAdapterOperations
    , surfaceActionAdapter @LeaveRequestsAdapterFamily @LeaveRequests.UpdateUnavailabilityBlackout allRequestAdapterOperations
    , surfaceActionAdapter @LeaveRequestsAdapterFamily @LeaveRequests.DeleteUnavailabilityBlackout
        (requestAdapterOperationsWithoutParser "The zero-field deletion endpoint consumes its route id and has no Surface request parser")
    , surfaceActionAdapter @SelfServiceLeaveAdapterFamily @SelfServiceLeave.CreateSelfServiceLeaveRequest allRequestAdapterOperations
    , surfaceActionAdapter @SupportAdapterFamily @Support.CreatePublicHolidayRefreshJob
        (requestAdapterOperationsWithoutParser "The zero-field refresh endpoint has no Surface request parser")
    , surfaceActionAdapter @SupportAdapterFamily @Support.CreateFwcMapdRefreshJob
        (requestAdapterOperationsWithoutParser "The zero-field refresh endpoint has no Surface request parser")
    , surfaceActionAdapter @ProfileAdapterFamily @Profile.UpdateProfileDetails allRequestAdapterOperations
    , surfaceActionAdapter @ProfileAdapterFamily @Profile.UpdateProfileShiftPreferences allRequestAdapterOperations
    , surfaceActionAdapter @StaffAdapterFamily @Profile.UpdateStaffProfile allRequestAdapterOperations
    , surfaceActionAdapter @StaffAdapterFamily @Profile.UpdateStaffShiftPreferences allRequestAdapterOperations
    , surfaceActionAdapter @StaffAdapterFamily @Profile.CreateStaffLeaveRequest allRequestAdapterOperations
    , surfaceActionAdapter @AdminVenueSettingsAdapterFamily @Admin.UpdateVenueConfig allRequestAdapterOperations
    , surfaceActionAdapter @AdminInvitesAdapterFamily @Admin.CreateVenueInvitation allRequestAdapterOperations
    , surfaceActionAdapter @AdminInvitesAdapterFamily @Admin.RevokeVenueInvitation
        (requestAdapterOperationsWithoutParser "The zero-field revoke endpoint consumes its route id and has no Surface request parser")
    , surfaceActionAdapter @AdminInvitesAdapterFamily @Admin.RenewVenueInvitation allRequestAdapterOperations
    , surfaceActionAdapter @AdminExportsAdapterFamily @Admin.CreateExportJob allRequestAdapterOperations
    , surfaceActionAdapter @AdminShiftTypesAdapterFamily @Admin.CreateShiftType allRequestAdapterOperations
    , surfaceActionAdapter @AdminShiftTypesAdapterFamily @Admin.UpdateShiftType allRequestAdapterOperations
    , surfaceActionAdapter @AdminShiftTypesAdapterFamily @Admin.MoveShiftTypeUp allRequestAdapterOperations
    , surfaceActionAdapter @AdminShiftTypesAdapterFamily @Admin.MoveShiftTypeDown allRequestAdapterOperations
    , surfaceActionAdapter @AdminShiftTypesAdapterFamily @Admin.AutosaveShiftTypeName
        (requestAdapterOperationsWithoutParser "Existing shift-type form handling consumes this field directly; no exact Surface parser is called")
    , surfaceActionAdapter @AdminShiftTypesAdapterFamily @Admin.AutosaveShiftTypeSelection
        (requestAdapterOperationsWithoutParser "Existing shift-type form handling consumes these fields directly; no exact Surface parser is called")
    , surfaceActionAdapter @AdminShiftTypesAdapterFamily @Admin.ToggleInactiveShiftTypes allRequestAdapterOperations
    , surfaceActionAdapter @AdminRosterGroupsAdapterFamily @Admin.CreateRosterGroup allRequestAdapterOperations
    , surfaceActionAdapter @AdminRosterGroupsAdapterFamily @Admin.UpdateRosterGroup allRequestAdapterOperations
    , surfaceActionAdapter @AdminRosterGroupsAdapterFamily @Admin.MoveRosterGroupUp allRequestAdapterOperations
    , surfaceActionAdapter @AdminRosterGroupsAdapterFamily @Admin.MoveRosterGroupDown allRequestAdapterOperations
    , surfaceActionAdapter @AdminRosterGroupsAdapterFamily @Admin.ToggleInactiveRosterGroups allRequestAdapterOperations
    , surfaceActionAdapter @AdminXeroAdapterFamily @Admin.SyncXeroPayrollReferenceData
        (requestAdapterOperationsWithoutParser "The zero-field Xero sync endpoint has no Surface request parser")
    , surfaceActionAdapter @AdminXeroAdapterFamily @Admin.ShowXeroTimesheetPreparationStaffMappings allRequestAdapterOperations
    ]

type RegisteredSurfaceIntentAdapterHomes =
    '[ SurfaceIntentAdapterHome RosterAdapterFamily Roster.SetRosterLayoutMode
     , SurfaceIntentAdapterHome RosterAdapterFamily Roster.MoveRosterShiftToSlot
     , SurfaceIntentAdapterHome RosterAdapterFamily Roster.DuplicateRosterShiftToDay
     , SurfaceIntentAdapterHome RosterAdapterFamily Roster.DropRosterStaff
     , SurfaceIntentAdapterHome RosterAdapterFamily Roster.PreviewRosterTemplateApplication
     , SurfaceIntentAdapterHome RosterDayTimelineAdapterFamily Roster.MoveRosterTimelineShift
     ]

-- All five production intents emit the complete inventoried builder,
-- form-metadata, and exact parser operation set through the Roster facade.
registeredSurfaceIntentAdapterRegistrations :: [SurfaceRequestAdapterRegistration 'IntentAdapterKind]
registeredSurfaceIntentAdapterRegistrations =
    [ surfaceIntentAdapter @RosterAdapterFamily @Roster.SetRosterLayoutMode allRequestAdapterOperations
    , surfaceIntentAdapter @RosterAdapterFamily @Roster.MoveRosterShiftToSlot allRequestAdapterOperations
    , surfaceIntentAdapter @RosterAdapterFamily @Roster.DuplicateRosterShiftToDay allRequestAdapterOperations
    , surfaceIntentAdapter @RosterAdapterFamily @Roster.DropRosterStaff allRequestAdapterOperations
    , surfaceIntentAdapter @RosterAdapterFamily @Roster.PreviewRosterTemplateApplication allRequestAdapterOperations
    , surfaceIntentAdapter @RosterDayTimelineAdapterFamily @Roster.MoveRosterTimelineShift allRequestAdapterOperations
    ]

allRequestAdapterOperations :: SurfaceRequestAdapterOperations
allRequestAdapterOperations =
    SurfaceRequestAdapterOperations
        { surfaceAdapterFieldsBuilderOperation = GenerateSurfaceAdapterOperation
        , surfaceAdapterRenderMetadataOperation = GenerateSurfaceAdapterOperation
        , surfaceAdapterRequestParserOperation = GenerateSurfaceAdapterOperation
        }

requestAdapterOperationsWithoutParser :: Text -> SurfaceRequestAdapterOperations
requestAdapterOperationsWithoutParser reason =
    allRequestAdapterOperations
        { surfaceAdapterRequestParserOperation = ExcludeSurfaceAdapterOperation reason
        }

intentOnlyActionReason :: Text
intentOnlyActionReason =
    "The declaration is consumed only through its corresponding Intent form and parser; no Haskell Action adapter operation has a current consumer"

registeredSurfaceAdapterRegistry :: SurfaceAdapterRegistry
registeredSurfaceAdapterRegistry =
    reflectSurfaceAdapterRegistry
        @RegisteredSurfaceAdapterFamilies
        @RegisteredSurfaceResourceAdapterHomes
        @RegisteredSurfaceScopeAdapterHomes
        @RegisteredSurfaceFragmentAdapterHomes
        @RegisteredSurfaceActionAdapterHomes
        @RegisteredSurfaceIntentAdapterHomes
        registeredSurfaceActorOnlyFragments
        registeredSurfaceActionAdapterRegistrations
        registeredSurfaceIntentAdapterRegistrations
