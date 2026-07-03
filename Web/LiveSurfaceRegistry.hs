module Web.LiveSurfaceRegistry
    ( LiveSurfaceInvalidationTarget (..)
    , authorizeRegisteredLiveSurfaceScope
    , performLiveSurfaceInvalidationTarget
    , performLiveSurfaceInvalidationTargetWithoutContext
    , planRegisteredLiveSurfaceInvalidations
    , planRegisteredLiveSurfaceInvalidationsWithoutContext
    ) where

import Application.Helper.FrontendSurface.Authorization (authorizeFrontendSurfaceLiveScope)
import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveUpdate.Runtime (LiveUpdateBroadcastResult,
                                              LiveUpdateScope (..),
                                              LiveUpdateWireFragment,
                                              broadcastLiveInvalidationDetailed,
                                              broadcastLiveInvalidationDetailedWithoutContext,
                                              coalesceLiveUpdateWireFragments,
                                              liveUpdateSourceClientId)
import Application.Support.LiveUpdates (supportAffectedMountedFragments,
                                        supportSurfaceWireFragments)
import Data.Coerce (coerce)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import Generated.Types (RosterGroup)
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminExportsAffectedFragments,
                                  adminInvitesAffectedFragments,
                                  adminRosterGroupsAffectedFragments,
                                  adminShiftTypesAffectedFragments,
                                  adminSurfaceWireFragments,
                                  adminVenueSettingsAffectedFragments,
                                  adminXeroAffectedFragments)
import Web.Billing.FrontendSurface (BillingScopeValue (..),
                                    billingAffectedMountedFragments,
                                    billingSurfaceWireFragments)
import Web.Controller.Prelude
import Web.LeaveRequests.FrontendSurface (LeaveRequestsScopeValue (..),
                                          leaveRequestsAffectedMountedFragments,
                                          leaveRequestsSurfaceWireFragments)
import Web.Profiles.FrontendSurface (ProfileScopeValue (..),
                                     profileAffectedMountedFragments,
                                     profileSurfaceWireFragments)
import Web.RosterWeeks.FrontendSurface (RosterMountedFragmentPlan (..),
                                        RosterWeekScopeValue (..),
                                        rosterAffectedMountedFragments,
                                        rosterSurfaceWireFragments)
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsAffectedMountedFragments,
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
    fragments <- case scope of
        RosterWeekScope { venueId, rosterGroupId, weekOffset } ->
            let scopeValue = RosterWeekScopeValue { rosterWeekVenueId = venueId, rosterWeekGroupId = coerce rosterGroupId :: Id RosterGroup, rosterWeekWeekOffset = weekOffset }
                mountedPlan = RosterMountedFragmentPlan { rosterMountedDayIds = [], rosterMountedRows = [] }
             in pure (rosterSurfaceWireFragments (rosterAffectedMountedFragments scopeValue mountedPlan resources))
        TimesheetWeekScope { venueId, weekOffset } ->
            let scopeValue = TimesheetWeekScopeValue { timesheetWeekVenueId = venueId, timesheetWeekWeekOffset = weekOffset }
                mountStateValue = TimesheetsMountStateValue { timesheetsMountShowApproved = True, timesheetsMountShowAllStaff = True, timesheetsMountStaffFilterId = Nothing }
             in pure (timesheetsSurfaceWireFragments (timesheetsAffectedMountedFragments scopeValue mountStateValue resources))
        LeaveRequestsScope { venueId } -> pure (leaveRequestsSurfaceWireFragments (leaveRequestsAffectedMountedFragments LeaveRequestsScopeValue { leaveRequestsVenueId = venueId } resources))
        BillingScope { venueId } -> pure (billingSurfaceWireFragments (billingAffectedMountedFragments BillingScopeValue { billingVenueId = venueId } resources))
        SupportPlatformScope -> pure (supportSurfaceWireFragments (supportAffectedMountedFragments resources))
        ProfileScope { venueId, staffId } -> pure (profileSurfaceWireFragments (profileAffectedMountedFragments ProfileScopeValue { profileVenueId = venueId, profileStaffId = staffId } resources))
        AdminVenueConfigScope { venueId } -> pure (adminSurfaceWireFragments (adminVenueSettingsAffectedFragments (AdminVenueScopeValue venueId Nothing) resources))
        AdminInvitesScope { venueId } -> pure (adminSurfaceWireFragments (adminInvitesAffectedFragments (AdminVenueScopeValue venueId Nothing) resources))
        AdminExportsScope { venueId } -> pure (adminSurfaceWireFragments (adminExportsAffectedFragments (AdminVenueScopeValue venueId Nothing) resources))
        AdminShiftTypesScope { venueId } -> pure (adminSurfaceWireFragments (adminShiftTypesAffectedFragments (AdminVenueScopeValue venueId Nothing) resources))
        AdminRosterGroupsScope { venueId } -> pure (adminSurfaceWireFragments (adminRosterGroupsAffectedFragments (AdminVenueScopeValue venueId Nothing) resources))
        AdminXeroScope { venueId } -> pure (adminSurfaceWireFragments (adminXeroAffectedFragments (AdminVenueScopeValue venueId Nothing) resources))
    if null fragments then Nothing else Just LiveSurfaceInvalidationTarget { targetScope = scope, targetFragments = fragments }

coalesceTargets :: [LiveSurfaceInvalidationTarget] -> [LiveSurfaceInvalidationTarget]
coalesceTargets targets =
    [ LiveSurfaceInvalidationTarget scope (coalesceLiveUpdateWireFragments fragments)
    | (scope, fragments) <- Map.toAscList grouped
    ]
    where
        grouped = Map.fromListWith (<>) [(target.targetScope, target.targetFragments) | target <- targets]
