module Web.LiveResourceInvalidation
    ( PlannedLiveInvalidation (..)
    , invalidateTouchedResources
    , leaveRequestsContentDependsOn
    , planLiveInvalidationsForResources
    , profileLeaveRequestsDependsOn
    , rosterWeekLeaveCalendarDependsOn
    ) where

import Application.Helper.LiveResource
import Application.Helper.LiveSurface (broadcastSurfaceResync)
import Application.Helper.LiveUpdate (activeRosterWeekScopes)
import qualified Data.Set as Set
import Data.UUID (UUID)
import Web.Controller.Admin.Support (refreshAdminRosterGroups,
                                     refreshAdminShiftTypes)
import Application.Helper.RosterGroups (fetchStaffRosterGroupIds)
import Web.Controller.Admin.Xero.Responses (refreshAdminXero,
                                            refreshAdminXeroPayItems)
import Web.Controller.Prelude
import Web.Exports.LiveUpdates (refreshAdminExports)
import Web.LeaveRequests.Projection (broadcastLeaveRequestsInvalidation,
                                     leaveRequestsContentFragmentRefs)
import Web.Profiles.LiveUpdates (refreshProfileLeaveRequestsForStaffId)
import Web.RosterWeeks.LiveUpdates (refreshRosterFragments)
import Web.Profiles.LiveUpdates (refreshProfileContentForStaffId)
import Web.RosterWeeks.Projection (rosterContentAndStaffPanelFragments)
import Web.StaffDocuments.LiveUpdates (refreshStaffCompliance)
import Web.Timesheets.Projection (TimesheetProjectionRequest (..),
                                  refreshTimesheetFragments,
                                  timesheetDaySectionFragment,
                                  timesheetDaySectionFragments)
import Web.View.Admin.Invites (AdminInvitesSurfaceKey (..),
                               adminInvitesLiveSurfaceDefinitionForVenue)

data PlannedLiveInvalidation
    = InvalidateLeaveRequests
    | InvalidateProfileLeaveRequests !UUID
    | InvalidateRosterWeek !UUID !Int
    | InvalidateTimesheetWeek !UUID !Int
    | InvalidateTimesheetDay !UUID !Int !Int
    | InvalidateProfileContent !UUID !Text
    | InvalidateRosterWeeksForStaff !UUID
    | InvalidateAdminInvites !UUID
    | InvalidateAdminStaffCompliance !UUID
    | InvalidateAdminExports !UUID
    | InvalidateAdminRosterGroups !UUID
    | InvalidateAdminShiftTypes !UUID
    | InvalidateXeroPayItems !UUID
    | InvalidateAdminXeroForStaff !UUID
    deriving (Eq, Ord, Show)

leaveRequestsContentDependsOn :: Id Venue -> [LiveResource]
leaveRequestsContentDependsOn venueId =
    [LeaveRequestsResource (unpackId venueId)]

profileLeaveRequestsDependsOn :: UUID -> [LiveResource]
profileLeaveRequestsDependsOn staffId =
    [StaffLeaveRequestsResource staffId]

rosterWeekLeaveCalendarDependsOn :: Id Venue -> Int -> [LiveResource]
rosterWeekLeaveCalendarDependsOn venueId weekOffset =
    [LeaveCalendarResource (unpackId venueId) weekOffset]

planLiveInvalidationsForResources :: [(UUID, UUID, Int)] -> Set.Set LiveResource -> Set.Set PlannedLiveInvalidation
planLiveInvalidationsForResources activeRosterScopes resources =
    suppressTimesheetWeekWhenDaysPresent (Set.unions (map planForResource (Set.toList resources)))
    where
        planForResource (LeaveRequestsResource _) =
            Set.singleton InvalidateLeaveRequests
        planForResource (StaffLeaveRequestsResource staffId) =
            Set.singleton (InvalidateProfileLeaveRequests staffId)
        planForResource (LeaveCalendarResource venueId weekOffset) =
            Set.fromList
                [ InvalidateRosterWeek rosterGroupId weekOffset
                | (activeVenueId, rosterGroupId, activeWeekOffset) <- activeRosterScopes
                , activeVenueId == venueId
                , activeWeekOffset == weekOffset
                ]
        planForResource (RosterWeekResource rosterGroupId weekOffset) =
            Set.singleton (InvalidateRosterWeek rosterGroupId weekOffset)
        planForResource (TimesheetWeekResource venueId weekOffset) =
            Set.singleton (InvalidateTimesheetWeek venueId weekOffset)
        planForResource (TimesheetDayResource venueId weekOffset dayOffset) =
            Set.singleton (InvalidateTimesheetDay venueId weekOffset dayOffset)
        planForResource (StaffProfileResource staffId) =
            Set.fromList [InvalidateProfileContent staffId "profile", InvalidateRosterWeeksForStaff staffId]
        planForResource (StaffPreferencesResource staffId) =
            Set.singleton (InvalidateRosterWeeksForStaff staffId)
        planForResource (StaffRosterMembershipResource staffId) =
            Set.singleton (InvalidateRosterWeeksForStaff staffId)
        planForResource (StaffPayProfileResource staffId) =
            Set.singleton (InvalidateAdminXeroForStaff staffId)
        planForResource (StaffRsaDocumentsResource staffId) =
            Set.singleton (InvalidateProfileContent staffId "rsa")
        planForResource (AdminInvitesResource venueId) =
            Set.singleton (InvalidateAdminInvites venueId)
        planForResource (AdminStaffComplianceResource venueId) =
            Set.singleton (InvalidateAdminStaffCompliance venueId)
        planForResource (AdminExportsResource venueId) =
            Set.singleton (InvalidateAdminExports venueId)
        planForResource (AdminRosterGroupsResource venueId) =
            Set.singleton (InvalidateAdminRosterGroups venueId)
        planForResource (AdminShiftTypesResource venueId) =
            Set.singleton (InvalidateAdminShiftTypes venueId)
        planForResource (XeroPayItemsResource venueId) =
            Set.singleton (InvalidateXeroPayItems venueId)
        planForResource _ =
            Set.empty

invalidateTouchedResources :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> LiveMutationResult a -> IO (LiveMutationResult a)
invalidateTouchedResources label result = do
    observed <- recordLiveMutationDiagnostics label result
    activeRosterScopes <- activeRosterWeekScopes
    let plannedInvalidations = planLiveInvalidationsForResources activeRosterScopes (liveMutationTouchedResources observed)
    forM_ (Set.toAscList plannedInvalidations) performPlannedInvalidation
    pure observed

suppressTimesheetWeekWhenDaysPresent :: Set.Set PlannedLiveInvalidation -> Set.Set PlannedLiveInvalidation
suppressTimesheetWeekWhenDaysPresent planned =
    Set.filter shouldKeep planned
    where
        dayScopes =
            Set.fromList
                [ (venueId, weekOffset)
                | InvalidateTimesheetDay venueId weekOffset _ <- Set.toList planned
                ]
        shouldKeep (InvalidateTimesheetWeek venueId weekOffset) =
            (venueId, weekOffset) `Set.notMember` dayScopes
        shouldKeep _ = True

performPlannedInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => PlannedLiveInvalidation -> IO ()
performPlannedInvalidation InvalidateLeaveRequests =
    broadcastLeaveRequestsInvalidation leaveRequestsContentFragmentRefs
performPlannedInvalidation (InvalidateProfileLeaveRequests staffId) =
    refreshProfileLeaveRequestsForStaffId staffId
performPlannedInvalidation (InvalidateRosterWeek rosterGroupId weekOffset) =
    refreshRosterFragments (Id rosterGroupId) weekOffset rosterContentAndStaffPanelFragments
performPlannedInvalidation (InvalidateTimesheetWeek _venueId weekOffset) =
    refreshTimesheetFragments
        (TimesheetProjectionRequest weekOffset True True Nothing)
        (timesheetDaySectionFragments [0 .. 6])
performPlannedInvalidation (InvalidateTimesheetDay _venueId weekOffset dayOffset) =
    refreshTimesheetFragments
        (TimesheetProjectionRequest weekOffset True True Nothing)
        [timesheetDaySectionFragment dayOffset]
performPlannedInvalidation (InvalidateProfileContent staffId openSection) =
    refreshProfileContentForStaffId staffId openSection
performPlannedInvalidation (InvalidateRosterWeeksForStaff staffId) =
    refreshActiveRosterWeeksForStaff staffId
performPlannedInvalidation (InvalidateAdminInvites venueId) =
    refreshAdminInvitesForVenue venueId
performPlannedInvalidation (InvalidateAdminStaffCompliance venueId) =
    refreshStaffCompliance venueId
performPlannedInvalidation (InvalidateAdminExports venueId) =
    refreshAdminExports venueId
performPlannedInvalidation (InvalidateAdminRosterGroups venueId) =
    refreshAdminRosterGroups (Id venueId)
performPlannedInvalidation (InvalidateAdminShiftTypes venueId) =
    refreshAdminShiftTypes (Id venueId)
performPlannedInvalidation (InvalidateXeroPayItems venueId) =
    refreshAdminXeroPayItems venueId
performPlannedInvalidation (InvalidateAdminXeroForStaff staffId) =
    refreshAdminXeroForStaff staffId

refreshAdminInvitesForVenue :: (?context :: ControllerContext, ?request :: Request) => UUID -> IO ()
refreshAdminInvitesForVenue venueId =
    broadcastSurfaceResync
        (adminInvitesLiveSurfaceDefinitionForVenue venueId)
        AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Nothing }

refreshAdminXeroForStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => UUID -> IO ()
refreshAdminXeroForStaff staffId = do
    maybeStaff <-
        query @Staff
            |> filterWhere (#id, Id staffId :: Id Staff)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOneOrNothing
    forM_ maybeStaff \staff ->
        refreshAdminXero (Id staff.venueId)

refreshActiveRosterWeeksForStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => UUID -> IO ()
refreshActiveRosterWeeksForStaff staffId = do
    maybeStaff <-
        query @Staff
            |> filterWhere (#id, Id staffId :: Id Staff)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOneOrNothing
    forM_ maybeStaff \staff -> do
        rosterGroupIds <- fetchStaffRosterGroupIds staff
        activeScopes <- activeRosterWeekScopes
        let rosterGroupIdSet = Set.fromList (map unpackId rosterGroupIds)
        let targets =
                Set.fromList
                    [ (rosterGroupId, weekOffset)
                    | (venueId, rosterGroupId, weekOffset) <- activeScopes
                    , venueId == unpackId currentVenueId
                    , rosterGroupId `Set.member` rosterGroupIdSet
                    ]
        forM_ (Set.toAscList targets) \(rosterGroupId, weekOffset) ->
            refreshRosterFragments (Id rosterGroupId) weekOffset rosterContentAndStaffPanelFragments
