module Web.LiveResourceInvalidation
    ( PlannedLiveInvalidation (..)
    , invalidateTouchedResources
    , leaveRequestsContentDependsOn
    , planLiveInvalidationsForResources
    , profileLeaveRequestsDependsOn
    , rosterWeekLeaveCalendarDependsOn
    ) where

import Application.Helper.LiveResource
import Application.Helper.LiveUpdate (activeRosterWeekScopes)
import qualified Data.Set as Set
import Data.UUID (UUID)
import Web.Controller.Admin.Support (refreshAdminInvites,
                                     refreshAdminRosterGroups,
                                     refreshAdminShiftTypes)
import Web.Controller.Admin.Xero.Responses (refreshAdminXeroPayItems)
import Web.Controller.Prelude
import Web.LeaveRequests.Projection (broadcastLeaveRequestsInvalidation,
                                     leaveRequestsContentFragmentRefs)
import Web.Profiles.LiveUpdates (refreshProfileLeaveRequestsForStaffId)
import Web.RosterWeeks.LiveUpdates (refreshRosterFragments)
import Web.RosterWeeks.Projection (rosterContentAndStaffPanelFragments)

data PlannedLiveInvalidation
    = InvalidateLeaveRequests
    | InvalidateProfileLeaveRequests !UUID
    | InvalidateRosterWeek !UUID !Int
    | InvalidateAdminInvites !UUID
    | InvalidateAdminRosterGroups !UUID
    | InvalidateAdminShiftTypes !UUID
    | InvalidateXeroPayItems !UUID
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
    Set.unions (map planForResource (Set.toList resources))
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
        planForResource (AdminInvitesResource venueId) =
            Set.singleton (InvalidateAdminInvites venueId)
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

performPlannedInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => PlannedLiveInvalidation -> IO ()
performPlannedInvalidation InvalidateLeaveRequests =
    broadcastLeaveRequestsInvalidation leaveRequestsContentFragmentRefs
performPlannedInvalidation (InvalidateProfileLeaveRequests staffId) =
    refreshProfileLeaveRequestsForStaffId staffId
performPlannedInvalidation (InvalidateRosterWeek rosterGroupId weekOffset) =
    refreshRosterFragments (Id rosterGroupId) weekOffset rosterContentAndStaffPanelFragments
performPlannedInvalidation (InvalidateAdminInvites venueId) =
    refreshAdminInvites (Id venueId)
performPlannedInvalidation (InvalidateAdminRosterGroups venueId) =
    refreshAdminRosterGroups (Id venueId)
performPlannedInvalidation (InvalidateAdminShiftTypes venueId) =
    refreshAdminShiftTypes (Id venueId)
performPlannedInvalidation (InvalidateXeroPayItems venueId) =
    refreshAdminXeroPayItems venueId
