module Web.LiveSurfaceRegistry
    ( LiveSurfaceInvalidationTarget (..)
    , authorizeRegisteredLiveSurfaceScope
    , performLiveSurfaceInvalidationTarget
    , performLiveSurfaceInvalidationTargetWithoutContext
    , planRegisteredLiveSurfaceInvalidations
    , planRegisteredLiveSurfaceInvalidationsWithoutContext
    ) where

import Application.Helper.FrontendSurface.Authorization (authorizeFrontendSurfaceLiveScope)
import Application.Helper.FrontendSurface.DependencyPlanner (planFrontendSurfaceInvalidation)
import Application.Helper.FrontendSurface.Runtime (FrontendSurfaceMountedFragment)
import Application.Helper.LiveResource
import Application.Helper.LiveUpdate.Runtime (LiveUpdateBroadcastResult,
                                              LiveUpdateScope (..),
                                              LiveUpdateWireFragment,
                                              broadcastLiveInvalidationDetailed,
                                              broadcastLiveInvalidationDetailedWithoutContext,
                                              coalesceLiveUpdateWireFragments,
                                              liveUpdateSourceClientId)
import Application.Support.LiveUpdates (supportCandidateMountedFragments,
                                        supportSurfaceWireFragments)
import Data.Coerce (coerce)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import Generated.Types (RosterGroup)
import Web.Admin.FrontendSurface (adminExportsFragment, adminInvitesFragment,
                                  adminRosterGroupsFragment,
                                  adminShiftTypesFragment,
                                  adminSurfaceWireFragments,
                                  adminVenueSettingsFragment,
                                  adminXeroPayItemsFragment,
                                  adminXeroShellFragment,
                                  adminXeroStaffMappingsFragment,
                                  adminXeroTimesheetsFragment)
import Web.Billing.FrontendSurface (billingCandidateMountedFragments,
                                    billingSurfaceWireFragments)
import Web.Controller.Prelude
import Web.LeaveRequests.FrontendSurface (LeaveRequestsScopeValue (..),
                                          leaveRequestsCandidateMountedFragments,
                                          leaveRequestsSurfaceWireFragments)
import Web.Profiles.FrontendSurface (ProfileScopeValue (..),
                                     profileCandidateMountedFragments,
                                     profileSurfaceWireFragments)
import Web.RosterWeeks.FrontendSurface (RosterMountedFragmentPlan (..),
                                        RosterWeekScopeValue (..),
                                        rosterCandidateMountedFragments,
                                        rosterSurfaceWireFragments)
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsCandidateMountedFragments,
                                       timesheetsSurfaceWireFragments)

data LiveSurfaceInvalidationTarget = LiveSurfaceInvalidationTarget
    { targetScope     :: !LiveUpdateScope
    , targetFragments :: ![LiveUpdateWireFragment]
    }
    deriving (Eq, Show)

authorizeRegisteredLiveSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LiveUpdateScope -> IO Bool
authorizeRegisteredLiveSurfaceScope = authorizeFrontendSurfaceLiveScope

planRegisteredLiveSurfaceInvalidations :: (?context :: ControllerContext) => Set.Set LiveResource -> [LiveUpdateScope] -> [LiveSurfaceInvalidationTarget]
planRegisteredLiveSurfaceInvalidations = planRegisteredLiveSurfaceInvalidationsWithoutContext

planRegisteredLiveSurfaceInvalidationsWithoutContext :: Set.Set LiveResource -> [LiveUpdateScope] -> [LiveSurfaceInvalidationTarget]
planRegisteredLiveSurfaceInvalidationsWithoutContext resources scopes =
    coalesceTargets $ mapMaybe (planSurfaceInvalidation resources) scopes

performLiveSurfaceInvalidationTarget :: (?context :: ControllerContext, ?request :: Request) => LiveSurfaceInvalidationTarget -> IO LiveUpdateBroadcastResult
performLiveSurfaceInvalidationTarget target = broadcastLiveInvalidationDetailed target.targetScope liveUpdateSourceClientId target.targetFragments

performLiveSurfaceInvalidationTargetWithoutContext :: LiveSurfaceInvalidationTarget -> IO LiveUpdateBroadcastResult
performLiveSurfaceInvalidationTargetWithoutContext target = broadcastLiveInvalidationDetailedWithoutContext target.targetScope Nothing target.targetFragments

planSurfaceInvalidation :: Set.Set LiveResource -> LiveUpdateScope -> Maybe LiveSurfaceInvalidationTarget
planSurfaceInvalidation resources scope = do
    FrontendSurfacePlanningInput { planningCandidateFragments, planningWireFragments } <- planningInputForScope scope
    let fragments = planningWireFragments (planFrontendSurfaceInvalidation resources scope planningCandidateFragments)
    if null fragments then Nothing else Just LiveSurfaceInvalidationTarget { targetScope = scope, targetFragments = fragments }

data FrontendSurfacePlanningInput = FrontendSurfacePlanningInput
    { planningCandidateFragments :: ![FrontendSurfaceMountedFragment]
    , planningWireFragments      :: !([FrontendSurfaceMountedFragment] -> [LiveUpdateWireFragment])
    }

planningInputForScope :: LiveUpdateScope -> Maybe FrontendSurfacePlanningInput
planningInputForScope = \case
    RosterWeekScope { venueId, rosterGroupId, weekOffset } ->
        let scopeValue = RosterWeekScopeValue { rosterWeekVenueId = venueId, rosterWeekGroupId = coerce rosterGroupId :: Id RosterGroup, rosterWeekWeekOffset = weekOffset }
            mountedPlan = RosterMountedFragmentPlan { rosterMountedDayIds = [], rosterMountedRows = [] }
         in Just (planningInput (rosterCandidateMountedFragments scopeValue mountedPlan) rosterSurfaceWireFragments)
    TimesheetWeekScope { venueId, weekOffset } ->
        let scopeValue = TimesheetWeekScopeValue { timesheetWeekVenueId = venueId, timesheetWeekWeekOffset = weekOffset }
            mountStateValue = TimesheetsMountStateValue { timesheetsMountShowApproved = True, timesheetsMountShowAllStaff = True, timesheetsMountStaffFilterId = Nothing }
         in Just (planningInput (timesheetsCandidateMountedFragments scopeValue mountStateValue) timesheetsSurfaceWireFragments)
    LeaveRequestsScope { venueId } ->
        Just (planningInput (leaveRequestsCandidateMountedFragments LeaveRequestsScopeValue { leaveRequestsVenueId = venueId }) leaveRequestsSurfaceWireFragments)
    BillingScope {} ->
        Just (planningInput (billingCandidateMountedFragments (pathTo ShowBillingStatusFragmentAction)) billingSurfaceWireFragments)
    SupportPlatformScope ->
        Just (planningInput supportCandidateMountedFragments supportSurfaceWireFragments)
    ProfileScope { venueId, staffId } ->
        Just (planningInput (profileCandidateMountedFragments ProfileScopeValue { profileVenueId = venueId, profileStaffId = staffId }) profileSurfaceWireFragments)
    AdminVenueConfigScope {} ->
        Just (planningInput [adminVenueSettingsFragment] adminSurfaceWireFragments)
    AdminInvitesScope {} ->
        Just (planningInput [adminInvitesFragment Nothing] adminSurfaceWireFragments)
    AdminExportsScope {} ->
        Just (planningInput [adminExportsFragment] adminSurfaceWireFragments)
    AdminShiftTypesScope {} ->
        Just (planningInput [adminShiftTypesFragment] adminSurfaceWireFragments)
    AdminRosterGroupsScope {} ->
        Just (planningInput [adminRosterGroupsFragment] adminSurfaceWireFragments)
    AdminXeroScope {} ->
        Just (planningInput [adminXeroShellFragment, adminXeroStaffMappingsFragment, adminXeroPayItemsFragment, adminXeroTimesheetsFragment] adminSurfaceWireFragments)

planningInput :: [FrontendSurfaceMountedFragment] -> ([FrontendSurfaceMountedFragment] -> [LiveUpdateWireFragment]) -> FrontendSurfacePlanningInput
planningInput planningCandidateFragments planningWireFragments = FrontendSurfacePlanningInput { planningCandidateFragments, planningWireFragments }

coalesceTargets :: [LiveSurfaceInvalidationTarget] -> [LiveSurfaceInvalidationTarget]
coalesceTargets targets =
    [ LiveSurfaceInvalidationTarget scope (coalesceLiveUpdateWireFragments fragments)
    | (scope, fragments) <- Map.toAscList grouped
    ]
    where
        grouped = Map.fromListWith (<>) [(target.targetScope, target.targetFragments) | target <- targets]
