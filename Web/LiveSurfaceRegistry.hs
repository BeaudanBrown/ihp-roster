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

import Application.Helper.LiveResource (LiveResource)
import Application.Helper.LiveSurface (EmptyInteractionIntent,
                                       EmptyInteractionLayer,
                                       EmptyInteractionSession,
                                       SurfaceScope (..),
                                       TypedLiveSurfaceDefinition (..),
                                       authorizeTypedLiveSurfaceWireScope,
                                       emptyInteractionCapability,
                                       normalizeSurfaceFragmentRefs,
                                       typedLiveSurfaceAffectedFragments,
                                       typedLiveSurfaceFragmentRefs,
                                       unSurfaceFragmentRefs)
import Application.Helper.LiveUpdate.Runtime (LiveUpdateBroadcastResult,
                                              LiveUpdateScope (..),
                                              LiveUpdateWireFragment,
                                              broadcastLiveInvalidationDetailed,
                                              broadcastLiveInvalidationDetailedWithoutContext,
                                              coalesceLiveUpdateWireFragments,
                                              liveUpdateSourceClientId)
import qualified Application.Helper.LiveUpdate.Runtime as LiveRuntime
import Application.Support.LiveUpdates (supportLiveSurfaceDefinition)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import Web.Billing.LiveUpdates (BillingSurfaceKey (..),
                                billingLiveSurfaceDefinition)
import Web.Controller.Prelude
import Web.LeaveRequests.Projection (leaveRequestsLiveSurfaceDefinition)
import Web.Profiles.LiveUpdates (ProfileContentFragment (..),
                                 profileContentLiveSurfaceDefinition,
                                 profileLeaveRequestsLiveSurfaceDefinition)
import Web.RosterWeeks.LiveSurface (rosterLiveSurfaceDefinition)
import Web.Timesheets.Projection (timesheetLiveSurfaceCandidateFragments,
                                  timesheetLiveSurfaceDefinition,
                                  timesheetLiveSurfaceDefinitionForVenue)
import Web.View.Admin.Exports (adminExportsLiveSurfaceDefinition)
import Web.View.Admin.Invites (AdminInvitesSurfaceKey (..),
                               adminInvitesLiveSurfaceDefinition,
                               adminInvitesLiveSurfaceDefinitionForVenue)
import Web.View.Admin.RosterGroups (adminRosterGroupsLiveSurfaceDefinition)
import Web.View.Admin.ShiftTypes (adminShiftTypesLiveSurfaceDefinition)
import Web.View.Admin.VenueSettings (adminVenueSettingsLiveSurfaceDefinition,
                                     adminVenueSettingsLiveSurfaceDefinitionForVenue)
import Web.View.Admin.Xero (adminXeroLiveSurfaceDefinition,
                            adminXeroLiveSurfaceDefinitionForVenue)

data LiveSurfaceInvalidationTarget = LiveSurfaceInvalidationTarget
    { targetScope     :: !LiveUpdateScope
    , targetFragments :: ![LiveUpdateWireFragment]
    }
    deriving (Eq, Show)

data RegisteredLiveSurface = RegisteredLiveSurface
    { planRegisteredSurfaceInvalidation :: Set.Set LiveResource -> LiveUpdateScope -> Maybe LiveSurfaceInvalidationTarget
    }

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
registeredLiveSurfaceManifest =
    fmap (.descriptorManifest) registeredLiveSurfaceDescriptors

registeredLiveSurfaceDescriptors :: [RegisteredLiveSurfaceDescriptor]
registeredLiveSurfaceDescriptors =
    [ manifestDescriptorFromTypedSurface supportLiveSurfaceDefinition () Nothing
    , manifestDescriptorFromTypedSurface (adminVenueSettingsLiveSurfaceDefinitionForVenue sampleVenueId) () Nothing
    , manifestDescriptorFromTypedSurface (adminInvitesLiveSurfaceDefinitionForVenue sampleVenueId) AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Nothing } Nothing
    , manifestDescriptor "admin-exports" [AdminExportsScope sampleVenueId] [LiveRuntime.AdminExportsFragment] Nothing
    , manifestDescriptor "admin-shift-types" [AdminShiftTypesScope sampleVenueId] [LiveRuntime.AdminShiftTypesFragment] Nothing
    , manifestDescriptor "admin-roster-groups" [AdminRosterGroupsScope sampleVenueId] [LiveRuntime.AdminRosterGroupsFragment] Nothing
    , manifestDescriptor "admin-xero" [AdminXeroScope sampleVenueId] [LiveRuntime.AdminXeroFragment, LiveRuntime.AdminXeroStaffMappingsFragment, LiveRuntime.AdminXeroPayItemsFragment, LiveRuntime.AdminXeroTimesheetsFragment] Nothing
    , manifestDescriptorFromTypedSurface billingLiveSurfaceDefinition BillingSurfaceKey { billingSurfaceVenueId = sampleVenueId } Nothing
    , manifestDescriptor "leave-requests" [LeaveRequestsScope sampleVenueId] [LiveRuntime.LeaveRequestsContentFragment] Nothing
    , manifestDescriptor "profile" [ProfileScope sampleVenueId sampleStaffId] [LiveRuntime.ProfileContentFragment] Nothing
    , manifestDescriptor "profile-leave-requests" [ProfileScope sampleVenueId sampleStaffId] [LiveRuntime.ProfileLeaveRequestsContentFragment] Nothing
    , manifestDescriptor "timesheets" [TimesheetWeekScope sampleVenueId 0] [LiveRuntime.TimesheetToolbarFragment, LiveRuntime.TimesheetDayColumnsFragment, LiveRuntime.TimesheetDaySectionFragment 0] Nothing
    , manifestDescriptor "roster" [RosterWeekScope sampleVenueId sampleRosterGroupId 0] [LiveRuntime.RosterContentFragment, LiveRuntime.RosterGridToolbarFragment, LiveRuntime.RosterGridFrameFragment, LiveRuntime.RosterDayColumnsFragment, LiveRuntime.RosterDayRailFragment, LiveRuntime.RosterWageRailFragment, LiveRuntime.RosterSlotsGridFragment, LiveRuntime.RosterStaffPanelFragment, LiveRuntime.RosterDaySectionFragment sampleRosterDayId, LiveRuntime.RosterRowFragment sampleRosterDayId 0] (Just "roster")
    ]

manifestDescriptorFromTypedSurface ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    scope ->
    Maybe Text ->
    RegisteredLiveSurfaceDescriptor
manifestDescriptorFromTypedSurface definition surfaceKey =
    manifestDescriptor
        definition.typedSurfaceFeature
        [unSurfaceScope (definition.typedSurfaceScope surfaceKey)]
        (map (.fragmentKey) (unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs definition surfaceKey (definition.typedSurfaceDefaultFragments surfaceKey))))

manifestDescriptor :: Text -> [LiveUpdateScope] -> [LiveRuntime.LiveFragmentKey] -> Maybe Text -> RegisteredLiveSurfaceDescriptor
manifestDescriptor surfaceFamily scopeSamples fragmentSamples interactionSchema =
    RegisteredLiveSurfaceDescriptor
        { descriptorManifest = RegisteredLiveSurfaceManifest
            { surfaceFamily
            , scopeKinds = unique (fmap liveUpdateScopeKind scopeSamples)
            , fragmentKinds = unique (fmap liveFragmentKeyKind fragmentSamples)
            , interactionSchema
            }
        }

sampleVenueId :: UUID
sampleVenueId = UUID.fromWords 0 0 0 0

sampleStaffId :: UUID
sampleStaffId = UUID.fromWords 1 0 0 0

sampleRosterGroupId :: UUID
sampleRosterGroupId = UUID.fromWords 2 0 0 0

sampleRosterDayId :: UUID
sampleRosterDayId = UUID.fromWords 3 0 0 0

liveUpdateScopeKind :: LiveUpdateScope -> Text
liveUpdateScopeKind RosterWeekScope {}        = "roster_week"
liveUpdateScopeKind AdminVenueConfigScope {}  = "admin_venue_config"
liveUpdateScopeKind AdminShiftTypesScope {}   = "admin_shift_types"
liveUpdateScopeKind AdminRosterGroupsScope {} = "admin_roster_groups"
liveUpdateScopeKind AdminInvitesScope {}      = "admin_invites"
liveUpdateScopeKind AdminExportsScope {}      = "admin_exports"
liveUpdateScopeKind AdminXeroScope {}         = "admin_xero"
liveUpdateScopeKind BillingScope {}           = "billing"
liveUpdateScopeKind LeaveRequestsScope {}     = "leave_requests"
liveUpdateScopeKind TimesheetWeekScope {}     = "timesheet_week"
liveUpdateScopeKind ProfileScope {}           = "profile"
liveUpdateScopeKind SupportPlatformScope      = "support_platform"

liveFragmentKeyKind :: LiveRuntime.LiveFragmentKey -> Text
liveFragmentKeyKind LiveRuntime.RosterContentFragment = "roster_content"
liveFragmentKeyKind LiveRuntime.RosterGridToolbarFragment = "roster_grid_toolbar"
liveFragmentKeyKind LiveRuntime.RosterGridFrameFragment = "roster_grid_frame"
liveFragmentKeyKind LiveRuntime.RosterDayColumnsFragment = "roster_day_columns"
liveFragmentKeyKind LiveRuntime.RosterDayRailFragment = "roster_day_rail"
liveFragmentKeyKind LiveRuntime.RosterWageRailFragment = "roster_wage_rail"
liveFragmentKeyKind LiveRuntime.RosterSlotsGridFragment = "roster_slots_grid"
liveFragmentKeyKind LiveRuntime.RosterStaffPanelFragment = "roster_staff_panel"
liveFragmentKeyKind LiveRuntime.RosterDaySectionFragment {} = "roster_day_section"
liveFragmentKeyKind LiveRuntime.RosterRowFragment {} = "roster_row"
liveFragmentKeyKind LiveRuntime.LeaveRequestsContentFragment = "leave_requests_content"
liveFragmentKeyKind LiveRuntime.TimesheetToolbarFragment = "timesheet_toolbar"
liveFragmentKeyKind LiveRuntime.TimesheetDayColumnsFragment = "timesheet_day_columns"
liveFragmentKeyKind LiveRuntime.TimesheetDaySectionFragment {} = "timesheet_day_section"
liveFragmentKeyKind LiveRuntime.AdminVenueConfigFragment = "admin_venue_config"
liveFragmentKeyKind LiveRuntime.AdminInvitesFragment = "admin_invites"
liveFragmentKeyKind LiveRuntime.AdminExportsFragment = "admin_exports"
liveFragmentKeyKind LiveRuntime.AdminShiftTypesFragment = "admin_shift_types"
liveFragmentKeyKind LiveRuntime.AdminRosterGroupsFragment = "admin_roster_groups"
liveFragmentKeyKind LiveRuntime.AdminXeroFragment = "admin_xero"
liveFragmentKeyKind LiveRuntime.AdminXeroStaffMappingsFragment = "admin_xero_staff_mappings"
liveFragmentKeyKind LiveRuntime.AdminXeroPayItemsFragment = "admin_xero_pay_items"
liveFragmentKeyKind LiveRuntime.AdminXeroTimesheetsFragment = "admin_xero_timesheets"
liveFragmentKeyKind LiveRuntime.BillingStatusFragment = "billing_status"
liveFragmentKeyKind LiveRuntime.ProfileContentFragment = "profile_content"
liveFragmentKeyKind LiveRuntime.ProfileLeaveRequestsContentFragment = "profile_leave_requests_content"
liveFragmentKeyKind LiveRuntime.SupportAwardRatesSectionFragment = "support_award_rates_section"
liveFragmentKeyKind LiveRuntime.SupportPublicHolidaysSectionFragment = "support_public_holidays_section"

unique :: Eq a => [a] -> [a]
unique = foldr (\value acc -> if value `elem` acc then acc else value : acc) []

authorizeRegisteredLiveSurfaceScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    LiveUpdateScope ->
    IO Bool
authorizeRegisteredLiveSurfaceScope scope = do
    authorizations <-
        catMaybes
            <$> sequence
                [ authorizeTypedLiveSurfaceWireScope supportLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminVenueSettingsLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminInvitesLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminExportsLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminShiftTypesLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminRosterGroupsLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminXeroLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope billingLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope leaveRequestsLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope profileContentLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope profileLeaveRequestsLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope timesheetLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope rosterLiveSurfaceDefinition scope
                ]
    pure (or authorizations)

planRegisteredLiveSurfaceInvalidations ::
    (?context :: ControllerContext) =>
    Set.Set LiveResource ->
    [LiveUpdateScope] ->
    [LiveSurfaceInvalidationTarget]
planRegisteredLiveSurfaceInvalidations resources scopes =
    coalesceTargets
        [ target
        | scope <- scopes
        , surface <- registeredLiveSurfacesForScope scope
        , Just target <- [planRegisteredSurfaceInvalidation surface resources scope]
        ]

planRegisteredLiveSurfaceInvalidationsWithoutContext ::
    Set.Set LiveResource ->
    [LiveUpdateScope] ->
    [LiveSurfaceInvalidationTarget]
planRegisteredLiveSurfaceInvalidationsWithoutContext resources scopes =
    coalesceTargets
        [ target
        | scope <- scopes
        , surface <- contextFreeRegisteredLiveSurfacesForScope scope
        , Just target <- [planRegisteredSurfaceInvalidation surface resources scope]
        ]

performLiveSurfaceInvalidationTarget ::
    (?context :: ControllerContext, ?request :: Request) =>
    LiveSurfaceInvalidationTarget ->
    IO LiveUpdateBroadcastResult
performLiveSurfaceInvalidationTarget target =
    broadcastLiveInvalidationDetailed target.targetScope liveUpdateSourceClientId target.targetFragments

performLiveSurfaceInvalidationTargetWithoutContext ::
    LiveSurfaceInvalidationTarget ->
    IO LiveUpdateBroadcastResult
performLiveSurfaceInvalidationTargetWithoutContext target =
    broadcastLiveInvalidationDetailedWithoutContext target.targetScope Nothing target.targetFragments

registeredLiveSurfacesForScope :: (?context :: ControllerContext) => LiveUpdateScope -> [RegisteredLiveSurface]
registeredLiveSurfacesForScope scope =
    contextFreeRegisteredLiveSurfacesForScope scope <> currentVenueRegisteredLiveSurfacesForScope scope

currentVenueRegisteredLiveSurfacesForScope :: (?context :: ControllerContext) => LiveUpdateScope -> [RegisteredLiveSurface]
currentVenueRegisteredLiveSurfacesForScope scope =
    case currentVenueOrNothing of
        Nothing -> []
        Just _ ->
            case scope of
                AdminVenueConfigScope {} -> [registeredTypedLiveSurface adminVenueSettingsLiveSurfaceDefinition defaultCandidateFragments]
                AdminExportsScope {} -> [registeredTypedLiveSurface adminExportsLiveSurfaceDefinition defaultCandidateFragments]
                AdminShiftTypesScope {} -> [registeredTypedLiveSurface adminShiftTypesLiveSurfaceDefinition defaultCandidateFragments]
                AdminRosterGroupsScope {} -> [registeredTypedLiveSurface adminRosterGroupsLiveSurfaceDefinition defaultCandidateFragments]
                LeaveRequestsScope {} -> [registeredTypedLiveSurface leaveRequestsLiveSurfaceDefinition defaultCandidateFragments]
                ProfileScope {} ->
                    [ registeredTypedLiveSurface profileContentLiveSurfaceDefinition profileContentCandidateFragments
                    , registeredTypedLiveSurface profileLeaveRequestsLiveSurfaceDefinition defaultCandidateFragments
                    ]
                RosterWeekScope {} -> [registeredTypedLiveSurface rosterLiveSurfaceDefinition defaultCandidateFragments]
                _ -> []

contextFreeRegisteredLiveSurfacesForScope :: LiveUpdateScope -> [RegisteredLiveSurface]
contextFreeRegisteredLiveSurfacesForScope = \case
    SupportPlatformScope ->
        [registeredTypedLiveSurface supportLiveSurfaceDefinition defaultCandidateFragments]
    BillingScope { venueId } ->
        [registeredTypedLiveSurface billingLiveSurfaceDefinition defaultCandidateFragments]
    AdminInvitesScope { venueId } ->
        [registeredTypedLiveSurface (adminInvitesLiveSurfaceDefinitionForVenue venueId) defaultCandidateFragments]
    AdminVenueConfigScope { venueId } ->
        [registeredTypedLiveSurface (adminVenueSettingsLiveSurfaceDefinitionForVenue venueId) defaultCandidateFragments]
    TimesheetWeekScope { venueId } ->
        [registeredTypedLiveSurface (timesheetLiveSurfaceDefinitionForVenue venueId) (const timesheetLiveSurfaceCandidateFragments)]
    AdminXeroScope { venueId } ->
        [registeredTypedLiveSurface (adminXeroLiveSurfaceDefinitionForVenue venueId) defaultCandidateFragments]
    _ ->
        []

defaultCandidateFragments ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    scope ->
    [fragment]
defaultCandidateFragments definition surfaceKey =
    definition.typedSurfaceDefaultFragments surfaceKey

registeredTypedLiveSurface ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    (TypedLiveSurfaceDefinition surface scope fragment layer session intent -> scope -> [fragment]) ->
    RegisteredLiveSurface
registeredTypedLiveSurface definition candidateFragments =
    RegisteredLiveSurface \resources wireScope -> do
        surfaceKey <- definition.typedSurfaceScopeFromWire wireScope
        if unSurfaceScope (definition.typedSurfaceScope surfaceKey) /= wireScope
            then Nothing
            else do
                let affectedFragments =
                        typedLiveSurfaceAffectedFragments
                            definition
                            surfaceKey
                            resources
                            (candidateFragments definition surfaceKey)
                if null affectedFragments
                    then Nothing
                    else
                        Just
                            LiveSurfaceInvalidationTarget
                                { targetScope = wireScope
                                , targetFragments = unSurfaceFragmentRefs (normalizeSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs definition surfaceKey affectedFragments))
                                }

profileContentCandidateFragments ::
    TypedLiveSurfaceDefinition surface scope ProfileContentFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent ->
    scope ->
    [ProfileContentFragment]
profileContentCandidateFragments _ _ =
    [ ProfileDetailsContentFragment
    , ProfileRsaContentFragment
    , ProfileLeaveContentFragment
    ]

coalesceTargets :: [LiveSurfaceInvalidationTarget] -> [LiveSurfaceInvalidationTarget]
coalesceTargets targets =
    [ LiveSurfaceInvalidationTarget scope (coalesceLiveUpdateWireFragments fragments)
    | (scope, fragments) <- Map.toAscList grouped
    ]
    where
        grouped =
            Map.fromListWith (<>)
                [ (target.targetScope, target.targetFragments)
                | target <- targets
                ]
