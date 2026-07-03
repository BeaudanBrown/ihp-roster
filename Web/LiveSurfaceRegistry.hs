module Web.LiveSurfaceRegistry
    ( LiveSurfaceInvalidationTarget (..)
    , RegisteredLiveSurfaceManifest (..)
    , authorizeRegisteredLiveSurfaceScope
    , performLiveSurfaceInvalidationTarget
    , performLiveSurfaceInvalidationTargetWithoutContext
    , planRegisteredLiveSurfaceInvalidations
    , planRegisteredLiveSurfaceInvalidationsWithoutContext
    , registeredLiveSurfaceDescriptors
    , registeredLiveSurfaceManifest
    ) where

import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface (LiveScopeAuthorizationRequirement (..),
                                       authorizeLiveScopeRequirement)
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

data RegisteredLiveSurfaceDescriptor = RegisteredLiveSurfaceDescriptor
    { descriptorManifest :: !RegisteredLiveSurfaceManifest
    }

data RegisteredLiveSurfaceManifest = RegisteredLiveSurfaceManifest
    { surfaceFamily     :: !Text
    , scopeKinds        :: ![Text]
    , fragmentKinds     :: ![Text]
    , interactionSchema :: !(Maybe Text)
    }
    deriving (Eq, Show)

registeredLiveSurfaceManifest :: [RegisteredLiveSurfaceManifest]
registeredLiveSurfaceManifest = fmap (.descriptorManifest) registeredLiveSurfaceDescriptors

registeredLiveSurfaceDescriptors :: [RegisteredLiveSurfaceDescriptor]
registeredLiveSurfaceDescriptors =
    [ timesheetsLiveSurfaceDescriptor
    , rosterLiveSurfaceDescriptor
    , leaveRequestsLiveSurfaceDescriptor
    , billingLiveSurfaceDescriptor
    , supportLiveSurfaceDescriptor
    , profileLiveSurfaceDescriptor
    , adminVenueSettingsDescriptor
    , adminInvitesDescriptor
    , adminExportsDescriptor
    , adminShiftTypesDescriptor
    , adminRosterGroupsDescriptor
    , adminXeroDescriptor
    ]

timesheetsLiveSurfaceDescriptor, rosterLiveSurfaceDescriptor, leaveRequestsLiveSurfaceDescriptor, billingLiveSurfaceDescriptor, supportLiveSurfaceDescriptor, profileLiveSurfaceDescriptor, adminVenueSettingsDescriptor, adminInvitesDescriptor, adminExportsDescriptor, adminShiftTypesDescriptor, adminRosterGroupsDescriptor, adminXeroDescriptor :: RegisteredLiveSurfaceDescriptor
timesheetsLiveSurfaceDescriptor = descriptor "timesheets" ["timesheet_week"] ["timesheet_toolbar", "timesheet_day_columns", "timesheet_day_section"] Nothing
rosterLiveSurfaceDescriptor = descriptor "roster" ["roster_week"] ["roster_content", "roster_grid_toolbar", "roster_grid_frame", "roster_day_columns", "roster_day_rail", "roster_wage_rail", "roster_slots_grid", "roster_staff_panel", "roster_day_section", "roster_row"] (Just "roster")
leaveRequestsLiveSurfaceDescriptor = descriptor "leave-requests" ["leave_requests"] ["leave_requests_content"] Nothing
billingLiveSurfaceDescriptor = descriptor "billing" ["billing"] ["billing_status"] Nothing
supportLiveSurfaceDescriptor = descriptor "support" ["support_platform"] ["support_award_rates_section", "support_public_holidays_section"] Nothing
profileLiveSurfaceDescriptor = descriptor "profile" ["profile"] ["profile_details_section", "profile_preferences_section", "profile_security_section", "profile_leave_section", "profile_rsa_section"] Nothing
adminVenueSettingsDescriptor = descriptor "admin-venue-config" ["admin_venue_config"] ["admin_venue_config"] Nothing
adminInvitesDescriptor = descriptor "admin-invites" ["admin_invites"] ["admin_invites"] Nothing
adminExportsDescriptor = descriptor "admin-exports" ["admin_exports"] ["admin_exports"] Nothing
adminShiftTypesDescriptor = descriptor "admin-shift-types" ["admin_shift_types"] ["admin_shift_types"] Nothing
adminRosterGroupsDescriptor = descriptor "admin-roster-groups" ["admin_roster_groups"] ["admin_roster_groups"] Nothing
adminXeroDescriptor = descriptor "admin-xero" ["admin_xero"] ["admin_xero", "admin_xero_staff_mappings", "admin_xero_pay_items", "admin_xero_timesheets"] Nothing

descriptor :: Text -> [Text] -> [Text] -> Maybe Text -> RegisteredLiveSurfaceDescriptor
descriptor surfaceFamily scopeKinds fragmentKinds interactionSchema =
    RegisteredLiveSurfaceDescriptor { descriptorManifest = RegisteredLiveSurfaceManifest { surfaceFamily, scopeKinds, fragmentKinds, interactionSchema } }

authorizeRegisteredLiveSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LiveUpdateScope -> IO Bool
authorizeRegisteredLiveSurfaceScope = \case
    TimesheetWeekScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenue venueId)
    RosterWeekScope { venueId, rosterGroupId } -> authorizeLiveScopeRequirement (RequireCurrentVenueRosterGroup venueId rosterGroupId)
    LeaveRequestsScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueManager venueId)
    BillingScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueOwner venueId)
    SupportPlatformScope -> authorizeLiveScopeRequirement RequireSupportSuperAdmin
    ProfileScope { venueId, staffId } -> authorizeLiveScopeRequirement (RequireCurrentVenueStaff venueId staffId)
    AdminVenueConfigScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueAdmin venueId)
    AdminInvitesScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueAdmin venueId)
    AdminExportsScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueAdmin venueId)
    AdminShiftTypesScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueAdmin venueId)
    AdminRosterGroupsScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueAdmin venueId)
    AdminXeroScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueOwner venueId)

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
