{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

-- | Checked production ownership registry for generated Surface adapters.
--
-- Feature-local modules own family-to-Surface associations. This aggregate
-- selects each registered family and exactly one canonical home for every
-- eligible Resource, Live, Action, and Intent declaration without repeating
-- field or wire declarations.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.Registry
    ( RegisteredSurfaceAdapterFamilies
    , RegisteredSurfaceFragmentAdapterHomes
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
     , SurfaceFragmentAdapterHome TimesheetsAdapterFamily Timesheets.TimesheetSidePanelContent
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
     , SurfaceFragmentAdapterHome LeaveRequestsAdapterFamily LeaveRequests.LeaveSidePanelContent
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
     , SurfaceFragmentAdapterHome AdminXeroAdapterFamily Admin.AdminXeroReferenceSyncFragment
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
     , SurfaceResourceAdapterHome AdminVenueSettingsAdapterFamily Admin.AdminVenueSettings
     , SurfaceResourceAdapterHome AdminInvitesAdapterFamily Admin.AdminInvites
     , SurfaceResourceAdapterHome AdminExportsAdapterFamily Admin.AdminExports
     , SurfaceResourceAdapterHome AdminShiftTypesAdapterFamily Admin.AdminShiftTypes
     , SurfaceResourceAdapterHome AdminRosterGroupsAdapterFamily Admin.AdminRosterGroups
     , SurfaceResourceAdapterHome AdminXeroAdapterFamily Admin.XeroConnection
     , SurfaceResourceAdapterHome AdminXeroAdapterFamily Admin.XeroReferenceSyncState
     ]

-- The inventory contains every Action as either a generated registration or a
-- typed declaration exclusion. Generated operations emit builders/render
-- metadata, exact parsers are emitted only where the endpoint consumes a
-- complete Surface request envelope, and intent-only declarations remain typed
-- exclusions.

registeredSurfaceActionAdapterRegistrations :: [SurfaceRequestAdapterRegistration 'ActionAdapterKind]
registeredSurfaceActionAdapterRegistrations =
    [ surfaceOperationLocalActionAdapter @TimesheetsAdapterFamily @Timesheets.NavigateTimesheetWeek
        (requestAdapterOperationsWithoutParser "The endpoint consumes the routed week offset and canonical optional staff filter rather than a complete Surface request envelope")
    , surfaceOperationLocalActionAdapter @TimesheetsAdapterFamily @Timesheets.UpdateTimesheetFilters
        (requestAdapterOperationsWithoutParser "The shared navigation endpoint cannot distinguish this filter form from week navigation at the request boundary")
    , surfaceOperationLocalActionAdapter @TimesheetsAdapterFamily @Timesheets.ToggleTimesheetHideApproved allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @TimesheetsAdapterFamily @Timesheets.ToggleTimesheetShowSuggestions allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @TimesheetsAdapterFamily @Timesheets.CreateTimesheetEntryFromSuggestion allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @TimesheetsAdapterFamily @Timesheets.ApproveTimesheetEntry allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @TimesheetsAdapterFamily @Timesheets.UnapproveTimesheetEntry allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.NavigateRosterWeek requestAdapterOperationsWithParamsPresent
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.ToggleRosterWarnings allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.ToggleRosterWageEstimates allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.ToggleRosterOwnLiveShiftHighlight allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.SortRosterWeek
        (requestAdapterOperationsWithoutParser "The zero-field sort endpoint consumes route context and has no Surface request parser")
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.ToggleRosterWeekLiveStatus allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.ShowRosterNotificationConfirmation allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.CreateRosterNotificationRun allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.ToggleRosterAssignmentFilters allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.CopyRosterWeek allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.CreateRosterWeekSlotDefinition
        (requestAdapterOperationsWithoutParser "The zero-field slot creation endpoint consumes route context and has no Surface request parser")
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.DeleteRosterWeekSlotDefinition
        (requestAdapterOperationsWithoutParser "The zero-field slot deletion endpoint consumes route context and has no Surface request parser")
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.ToggleRosterDayClosed
        (requestAdapterOperationsWithoutParser "The zero-field day toggle endpoint consumes its route id and has no Surface request parser")
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.AddRosterRow
        (requestAdapterOperationsWithoutParser "The zero-field row creation endpoint consumes its route id and has no Surface request parser")
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.RemoveRosterRow
        (requestAdapterOperationsWithoutParser "The zero-field row removal endpoint consumes its route id and has no Surface request parser")
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.ToggleRosterStaffScope requestAdapterOperationsWithParamsPresent
    , surfaceOperationLocalActionAdapterExcluded @RosterAdapterFamily @Roster.SetRosterLayoutMode intentOnlyActionReason
    , surfaceOperationLocalActionAdapterExcluded @RosterAdapterFamily @Roster.MoveRosterShiftToSlot intentOnlyActionReason
    , surfaceOperationLocalActionAdapterExcluded @RosterAdapterFamily @Roster.DuplicateRosterShiftToDay intentOnlyActionReason
    , surfaceOperationLocalActionAdapterExcluded @RosterAdapterFamily @Roster.DropRosterStaff intentOnlyActionReason
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.PreviewRosterTemplateApplication allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @RosterAdapterFamily @Roster.ApplyRosterTemplateApplication allRequestAdapterOperations
    , surfaceOperationLocalActionAdapterExcluded @RosterDayTimelineAdapterFamily @Roster.MoveRosterTimelineShift intentOnlyActionReason
    , surfaceOperationLocalActionAdapter @LeaveRequestsAdapterFamily @LeaveRequests.ArchiveLeaveRequestsPage requestAdapterOperationsWithParamsPresent
    , surfaceOperationLocalActionAdapter @LeaveRequestsAdapterFamily @LeaveRequests.ApproveLeaveRequest
        (requestAdapterOperationsWithoutParser "The zero-field approval endpoint consumes its route id and has no Surface request parser")
    , surfaceOperationLocalActionAdapter @LeaveRequestsAdapterFamily @LeaveRequests.DenyLeaveRequest
        (requestAdapterOperationsWithoutParser "The zero-field denial endpoint consumes its route id and has no Surface request parser")
    , surfaceOperationLocalActionAdapter @LeaveRequestsAdapterFamily @LeaveRequests.CreateUnavailabilityBlackout allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @LeaveRequestsAdapterFamily @LeaveRequests.UpdateUnavailabilityBlackout allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @LeaveRequestsAdapterFamily @LeaveRequests.DeleteUnavailabilityBlackout
        (requestAdapterOperationsWithoutParser "The zero-field deletion endpoint consumes its route id and has no Surface request parser")
    , surfaceOperationLocalActionAdapter @SelfServiceLeaveAdapterFamily @SelfServiceLeave.CreateSelfServiceLeaveRequest allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @SupportAdapterFamily @Support.CreatePublicHolidayRefreshJob
        (requestAdapterOperationsWithoutParser "The zero-field refresh endpoint has no Surface request parser")
    , surfaceOperationLocalActionAdapter @SupportAdapterFamily @Support.CreateFwcMapdRefreshJob
        (requestAdapterOperationsWithoutParser "The zero-field refresh endpoint has no Surface request parser")
    , surfaceOperationLocalActionAdapter @ProfileAdapterFamily @Profile.UpdateProfileDetails allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @ProfileAdapterFamily @Profile.UpdateProfileShiftPreferences allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @StaffAdapterFamily @Profile.UpdateStaffProfile allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @StaffAdapterFamily @Profile.UpdateStaffShiftPreferences allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @StaffAdapterFamily @Profile.CreateStaffLeaveRequest allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminVenueSettingsAdapterFamily @Admin.UpdateRosterEndTimesEnabled allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminVenueSettingsAdapterFamily @Admin.UpdateMinutePrecisionShiftTimesEnabled allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminVenueSettingsAdapterFamily @Admin.UpdateUnavailableStaffWarningThreshold allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminVenueSettingsAdapterFamily @Admin.UpdateRosterTimePickerWindow allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminVenueSettingsAdapterFamily @Admin.UpdateRosterWeekStartsOn
        (requestAdapterParserOnly "The roster-week-start mutation is retained for compatibility but has no active rendered setting form")
    , surfaceOperationLocalActionAdapter @AdminInvitesAdapterFamily @Admin.CreateVenueInvitation allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminInvitesAdapterFamily @Admin.RevokeVenueInvitation
        (requestAdapterOperationsWithoutParser "The zero-field revoke endpoint consumes its route id and has no Surface request parser")
    , surfaceOperationLocalActionAdapter @AdminInvitesAdapterFamily @Admin.RenewVenueInvitation allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminExportsAdapterFamily @Admin.CreateExportJob allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminShiftTypesAdapterFamily @Admin.CreateShiftType allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminShiftTypesAdapterFamily @Admin.UpdateShiftType allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminShiftTypesAdapterFamily @Admin.MoveShiftTypeUp allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminShiftTypesAdapterFamily @Admin.MoveShiftTypeDown allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminShiftTypesAdapterFamily @Admin.AutosaveShiftTypeName
        (requestAdapterOperationsWithoutParser "Existing shift-type form handling consumes this field directly; no exact Surface parser is called")
    , surfaceOperationLocalActionAdapter @AdminShiftTypesAdapterFamily @Admin.AutosaveShiftTypeSelection
        (requestAdapterOperationsWithoutParser "Existing shift-type form handling consumes these fields directly; no exact Surface parser is called")
    , surfaceOperationLocalActionAdapter @AdminShiftTypesAdapterFamily @Admin.ToggleInactiveShiftTypes requestAdapterOperationsWithParamsPresent
    , surfaceOperationLocalActionAdapter @AdminRosterGroupsAdapterFamily @Admin.CreateRosterGroup allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminRosterGroupsAdapterFamily @Admin.UpdateRosterGroup allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminRosterGroupsAdapterFamily @Admin.MoveRosterGroupUp allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminRosterGroupsAdapterFamily @Admin.MoveRosterGroupDown allRequestAdapterOperations
    , surfaceOperationLocalActionAdapter @AdminRosterGroupsAdapterFamily @Admin.ToggleInactiveRosterGroups requestAdapterOperationsWithParamsPresent
    , surfaceOperationLocalActionAdapter @AdminXeroAdapterFamily @Admin.SyncXeroPayrollReferenceData
        (requestAdapterOperationsWithoutParser "The zero-field Xero sync endpoint has no Surface request parser")
    , surfaceOperationLocalActionAdapter @AdminXeroAdapterFamily @Admin.ShowXeroTimesheetPreparationStaffMappings allRequestAdapterOperations
    ]

-- All six production intents emit the complete inventoried builder,
-- form-metadata, and exact parser operation set through the Roster facade.
registeredSurfaceIntentAdapterRegistrations :: [SurfaceRequestAdapterRegistration 'IntentAdapterKind]
registeredSurfaceIntentAdapterRegistrations =
    [ surfaceOperationLocalIntentAdapter @RosterAdapterFamily @Roster.SetRosterLayoutMode allRequestAdapterOperations
    , surfaceOperationLocalIntentAdapter @RosterAdapterFamily @Roster.MoveRosterShiftToSlot allRequestAdapterOperations
    , surfaceOperationLocalIntentAdapter @RosterAdapterFamily @Roster.DuplicateRosterShiftToDay allRequestAdapterOperations
    , surfaceOperationLocalIntentAdapter @RosterAdapterFamily @Roster.DropRosterStaff allRequestAdapterOperations
    , surfaceOperationLocalIntentAdapter @RosterAdapterFamily @Roster.PreviewRosterTemplateApplication allRequestAdapterOperations
    , surfaceOperationLocalIntentAdapter @RosterDayTimelineAdapterFamily @Roster.MoveRosterTimelineShift allRequestAdapterOperations
    ]

allRequestAdapterOperations :: SurfaceRequestAdapterOperations
allRequestAdapterOperations =
    SurfaceRequestAdapterOperations
        { surfaceAdapterFieldsBuilderOperation = GenerateSurfaceAdapterOperation
        , surfaceAdapterRenderMetadataOperation = GenerateSurfaceAdapterOperation
        , surfaceAdapterRequestParserOperation = GenerateSurfaceAdapterOperation
        , surfaceAdapterParamsPresentOperation = ExcludeSurfaceAdapterOperation "No production caller needs envelope-presence detection"
        }

requestAdapterOperationsWithParamsPresent :: SurfaceRequestAdapterOperations
requestAdapterOperationsWithParamsPresent =
    allRequestAdapterOperations
        { surfaceAdapterParamsPresentOperation = GenerateSurfaceAdapterOperation
        }

requestAdapterOperationsWithoutParser :: Text -> SurfaceRequestAdapterOperations
requestAdapterOperationsWithoutParser reason =
    allRequestAdapterOperations
        { surfaceAdapterRequestParserOperation = ExcludeSurfaceAdapterOperation reason
        }

requestAdapterParserOnly :: Text -> SurfaceRequestAdapterOperations
requestAdapterParserOnly reason =
    SurfaceRequestAdapterOperations
        { surfaceAdapterFieldsBuilderOperation = ExcludeSurfaceAdapterOperation reason
        , surfaceAdapterRenderMetadataOperation = ExcludeSurfaceAdapterOperation reason
        , surfaceAdapterRequestParserOperation = GenerateSurfaceAdapterOperation
        , surfaceAdapterParamsPresentOperation = ExcludeSurfaceAdapterOperation "No envelope-presence consumer for this parser-only compatibility operation"
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
        registeredSurfaceActorOnlyFragments
        registeredSurfaceActionAdapterRegistrations
        registeredSurfaceIntentAdapterRegistrations
