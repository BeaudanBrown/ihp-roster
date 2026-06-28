{-# LANGUAGE GADTs #-}

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
import Data.Coerce (coerce)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import Web.Billing.LiveUpdates (BillingSurfaceKey (..),
                                billingLiveSurfaceDefinition)
import Web.Controller.Prelude
import Web.LeaveRequests.Projection (leaveRequestsLiveSurfaceDefinition,
                                     leaveRequestsLiveSurfaceDefinitionForVenue)
import Web.Profiles.LiveUpdates (ProfileContentFragment (..),
                                 ProfileContentSurfaceKey (..),
                                 ProfileLeaveSurfaceKey (..),
                                 profileContentLiveSurfaceDefinition,
                                 profileContentLiveSurfaceDefinitionForVenue,
                                 profileLeaveRequestsLiveSurfaceDefinition,
                                 profileLeaveRequestsLiveSurfaceDefinitionForVenue)
import Web.RosterWeeks.LiveSurface (rosterLiveSurfaceDefinition,
                                    rosterLiveSurfaceDefinitionForVenue)
import Web.RosterWeeks.Types (RosterProjectionFragment (..),
                              RosterProjectionScope (..))
import Web.Timesheets.Projection (TimesheetProjectionRequest (..),
                                  timesheetLiveSurfaceCandidateFragments,
                                  timesheetLiveSurfaceDefinition,
                                  timesheetLiveSurfaceDefinitionForVenue)
import Web.View.Admin.Exports (adminExportsLiveSurfaceDefinition,
                               adminExportsLiveSurfaceDefinitionForVenue)
import Web.View.Admin.Invites (AdminInvitesSurfaceKey (..),
                               adminInvitesLiveSurfaceDefinition,
                               adminInvitesLiveSurfaceDefinitionForVenue)
import Web.View.Admin.RosterGroups (adminRosterGroupsLiveSurfaceDefinition,
                                    adminRosterGroupsLiveSurfaceDefinitionForVenue)
import Web.View.Admin.ShiftTypes (adminShiftTypesLiveSurfaceDefinition,
                                  adminShiftTypesLiveSurfaceDefinitionForVenue)
import Web.View.Admin.VenueSettings (adminVenueSettingsLiveSurfaceDefinition,
                                     adminVenueSettingsLiveSurfaceDefinitionForVenue)
import Web.View.Admin.Xero (AdminXeroLiveFragment (..),
                            adminXeroLiveSurfaceDefinition,
                            adminXeroLiveSurfaceDefinitionForVenue)

data LiveSurfaceInvalidationTarget = LiveSurfaceInvalidationTarget
    { targetScope     :: !LiveUpdateScope
    , targetFragments :: ![LiveUpdateWireFragment]
    }
    deriving (Eq, Show)

data LiveSurfacePlanningMode
    = BackgroundPlannable
    | RequestContextOnly
    deriving (Eq, Show)

data RegisteredLiveSurface where
    RegisteredLiveSurface ::
        { registeredSurfaceDefinition        :: !(TypedLiveSurfaceDefinition surface scope fragment layer session intent)
        , registeredSurfaceSampleKey         :: !scope
        , registeredSurfaceCandidateFragments :: TypedLiveSurfaceDefinition surface scope fragment layer session intent -> scope -> [fragment]
        , registeredSurfacePlanningMode      :: !LiveSurfacePlanningMode
        , registeredSurfaceInteractionSchema :: !(Maybe Text)
        } ->
        RegisteredLiveSurface

data RegisteredLiveSurfaceEntry
    = SupportSurfaceEntry
    | AdminVenueSettingsSurfaceEntry
    | AdminInvitesSurfaceEntry
    | AdminExportsSurfaceEntry
    | AdminShiftTypesSurfaceEntry
    | AdminRosterGroupsSurfaceEntry
    | AdminXeroSurfaceEntry
    | BillingSurfaceEntry
    | LeaveRequestsSurfaceEntry
    | ProfileContentSurfaceEntry
    | ProfileLeaveRequestsSurfaceEntry
    | TimesheetSurfaceEntry
    | RosterSurfaceEntry
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
registeredLiveSurfaceManifest =
    fmap (.descriptorManifest) registeredLiveSurfaceDescriptors

registeredLiveSurfaceDescriptors :: [RegisteredLiveSurfaceDescriptor]
registeredLiveSurfaceDescriptors =
    fmap (manifestDescriptorFromRegisteredSurface . manifestSurfaceForEntry) registeredLiveSurfaceCatalog

registeredLiveSurfaceCatalog :: [RegisteredLiveSurfaceEntry]
registeredLiveSurfaceCatalog =
    [ SupportSurfaceEntry
    , AdminVenueSettingsSurfaceEntry
    , AdminInvitesSurfaceEntry
    , AdminExportsSurfaceEntry
    , AdminShiftTypesSurfaceEntry
    , AdminRosterGroupsSurfaceEntry
    , AdminXeroSurfaceEntry
    , BillingSurfaceEntry
    , LeaveRequestsSurfaceEntry
    , ProfileContentSurfaceEntry
    , ProfileLeaveRequestsSurfaceEntry
    , TimesheetSurfaceEntry
    , RosterSurfaceEntry
    ]

manifestSurfaceForEntry :: RegisteredLiveSurfaceEntry -> RegisteredLiveSurface
manifestSurfaceForEntry = \case
    SupportSurfaceEntry -> registeredLiveSurface supportLiveSurfaceDefinition () BackgroundPlannable defaultCandidateFragments Nothing
    AdminVenueSettingsSurfaceEntry -> registeredLiveSurface (adminVenueSettingsLiveSurfaceDefinitionForVenue sampleVenueId) () BackgroundPlannable defaultCandidateFragments Nothing
    AdminInvitesSurfaceEntry -> registeredLiveSurface (adminInvitesLiveSurfaceDefinitionForVenue sampleVenueId) AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Nothing } BackgroundPlannable defaultCandidateFragments Nothing
    AdminExportsSurfaceEntry -> registeredLiveSurface (adminExportsLiveSurfaceDefinitionForVenue sampleVenueId) () RequestContextOnly defaultCandidateFragments Nothing
    AdminShiftTypesSurfaceEntry -> registeredLiveSurface (adminShiftTypesLiveSurfaceDefinitionForVenue sampleVenueId) () RequestContextOnly defaultCandidateFragments Nothing
    AdminRosterGroupsSurfaceEntry -> registeredLiveSurface (adminRosterGroupsLiveSurfaceDefinitionForVenue sampleVenueId) () RequestContextOnly defaultCandidateFragments Nothing
    AdminXeroSurfaceEntry -> registeredLiveSurface (adminXeroLiveSurfaceDefinitionForVenue sampleVenueId) () BackgroundPlannable adminXeroManifestCandidateFragments Nothing
    BillingSurfaceEntry -> registeredLiveSurface billingLiveSurfaceDefinition BillingSurfaceKey { billingSurfaceVenueId = sampleVenueId } BackgroundPlannable defaultCandidateFragments Nothing
    LeaveRequestsSurfaceEntry -> registeredLiveSurface (leaveRequestsLiveSurfaceDefinitionForVenue sampleVenueId) () RequestContextOnly defaultCandidateFragments Nothing
    ProfileContentSurfaceEntry -> registeredLiveSurface (profileContentLiveSurfaceDefinitionForVenue sampleVenueId) sampleProfileContentSurfaceKey RequestContextOnly profileContentCandidateFragments Nothing
    ProfileLeaveRequestsSurfaceEntry -> registeredLiveSurface (profileLeaveRequestsLiveSurfaceDefinitionForVenue sampleVenueId) sampleProfileLeaveSurfaceKey RequestContextOnly defaultCandidateFragments Nothing
    TimesheetSurfaceEntry -> registeredLiveSurface (timesheetLiveSurfaceDefinitionForVenue sampleVenueId) sampleTimesheetSurfaceKey BackgroundPlannable (const timesheetLiveSurfaceCandidateFragments) Nothing
    RosterSurfaceEntry -> registeredLiveSurface (rosterLiveSurfaceDefinitionForVenue sampleVenueId) sampleRosterSurfaceKey RequestContextOnly rosterManifestCandidateFragments (Just "roster")

registeredLiveSurface ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    scope ->
    LiveSurfacePlanningMode ->
    (TypedLiveSurfaceDefinition surface scope fragment layer session intent -> scope -> [fragment]) ->
    Maybe Text ->
    RegisteredLiveSurface
registeredLiveSurface registeredSurfaceDefinition registeredSurfaceSampleKey registeredSurfacePlanningMode registeredSurfaceCandidateFragments registeredSurfaceInteractionSchema =
    RegisteredLiveSurface { registeredSurfaceDefinition, registeredSurfaceSampleKey, registeredSurfacePlanningMode, registeredSurfaceCandidateFragments, registeredSurfaceInteractionSchema }

manifestDescriptorFromRegisteredSurface :: RegisteredLiveSurface -> RegisteredLiveSurfaceDescriptor
manifestDescriptorFromRegisteredSurface RegisteredLiveSurface { registeredSurfaceDefinition = definition, registeredSurfaceSampleKey = surfaceKey, registeredSurfaceCandidateFragments = candidateFragments, registeredSurfaceInteractionSchema = interactionSchema } =
    RegisteredLiveSurfaceDescriptor
        { descriptorManifest = RegisteredLiveSurfaceManifest
            { surfaceFamily = definition.typedSurfaceFeature
            , scopeKinds = unique [liveUpdateScopeKind (unSurfaceScope (definition.typedSurfaceScope surfaceKey))]
            , fragmentKinds = unique (map (liveFragmentKeyKind . (.fragmentKey)) (unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs definition surfaceKey (candidateFragments definition surfaceKey))))
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

sampleProfileContentSurfaceKey :: ProfileContentSurfaceKey
sampleProfileContentSurfaceKey = ProfileContentSurfaceKey sampleVenueId sampleStaffId "profile"

sampleProfileLeaveSurfaceKey :: ProfileLeaveSurfaceKey
sampleProfileLeaveSurfaceKey = ProfileLeaveSurfaceKey sampleVenueId sampleStaffId

sampleTimesheetSurfaceKey :: TimesheetProjectionRequest
sampleTimesheetSurfaceKey = TimesheetProjectionRequest 0 False False Nothing

sampleRosterSurfaceKey :: RosterProjectionScope
sampleRosterSurfaceKey = RosterProjectionScope (coerce sampleRosterGroupId) 0

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
    authorizations <- catMaybes <$> mapM (`authorizeRegisteredSurfaceWireScope` scope) registeredLiveSurfaceAuthorizationCatalog
    pure (or authorizations)

registeredLiveSurfaceAuthorizationCatalog :: (?context :: ControllerContext) => [RegisteredLiveSurface]
registeredLiveSurfaceAuthorizationCatalog =
    fmap authorizationSurfaceForEntry registeredLiveSurfaceCatalog

authorizationSurfaceForEntry :: (?context :: ControllerContext) => RegisteredLiveSurfaceEntry -> RegisteredLiveSurface
authorizationSurfaceForEntry = \case
    SupportSurfaceEntry -> registeredLiveSurface supportLiveSurfaceDefinition () BackgroundPlannable defaultCandidateFragments Nothing
    AdminVenueSettingsSurfaceEntry -> registeredLiveSurface adminVenueSettingsLiveSurfaceDefinition () BackgroundPlannable defaultCandidateFragments Nothing
    AdminInvitesSurfaceEntry -> registeredLiveSurface adminInvitesLiveSurfaceDefinition AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Nothing } BackgroundPlannable defaultCandidateFragments Nothing
    AdminExportsSurfaceEntry -> registeredLiveSurface adminExportsLiveSurfaceDefinition () RequestContextOnly defaultCandidateFragments Nothing
    AdminShiftTypesSurfaceEntry -> registeredLiveSurface adminShiftTypesLiveSurfaceDefinition () RequestContextOnly defaultCandidateFragments Nothing
    AdminRosterGroupsSurfaceEntry -> registeredLiveSurface adminRosterGroupsLiveSurfaceDefinition () RequestContextOnly defaultCandidateFragments Nothing
    AdminXeroSurfaceEntry -> registeredLiveSurface adminXeroLiveSurfaceDefinition () BackgroundPlannable defaultCandidateFragments Nothing
    BillingSurfaceEntry -> registeredLiveSurface billingLiveSurfaceDefinition BillingSurfaceKey { billingSurfaceVenueId = sampleVenueId } BackgroundPlannable defaultCandidateFragments Nothing
    LeaveRequestsSurfaceEntry -> registeredLiveSurface leaveRequestsLiveSurfaceDefinition () RequestContextOnly defaultCandidateFragments Nothing
    ProfileContentSurfaceEntry -> registeredLiveSurface profileContentLiveSurfaceDefinition sampleProfileContentSurfaceKey RequestContextOnly profileContentCandidateFragments Nothing
    ProfileLeaveRequestsSurfaceEntry -> registeredLiveSurface profileLeaveRequestsLiveSurfaceDefinition sampleProfileLeaveSurfaceKey RequestContextOnly defaultCandidateFragments Nothing
    TimesheetSurfaceEntry -> registeredLiveSurface timesheetLiveSurfaceDefinition sampleTimesheetSurfaceKey BackgroundPlannable (const timesheetLiveSurfaceCandidateFragments) Nothing
    RosterSurfaceEntry -> registeredLiveSurface rosterLiveSurfaceDefinition sampleRosterSurfaceKey RequestContextOnly defaultCandidateFragments (Just "roster")

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
        , surface <- backgroundPlannableSurfacesForScope scope
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
    backgroundPlannableSurfacesForScope scope <> requestContextSurfacesForScope scope

requestContextSurfacesForScope :: (?context :: ControllerContext) => LiveUpdateScope -> [RegisteredLiveSurface]
requestContextSurfacesForScope scope =
    case currentVenueOrNothing of
        Nothing -> []
        Just _ -> concatMap (`requestContextSurfaceForEntry` scope) registeredLiveSurfaceCatalog

requestContextSurfaceForEntry :: (?context :: ControllerContext) => RegisteredLiveSurfaceEntry -> LiveUpdateScope -> [RegisteredLiveSurface]
requestContextSurfaceForEntry entry scope =
    case (entry, scope) of
        (AdminVenueSettingsSurfaceEntry, AdminVenueConfigScope {}) -> [registeredLiveSurface adminVenueSettingsLiveSurfaceDefinition () RequestContextOnly defaultCandidateFragments Nothing]
        (AdminExportsSurfaceEntry, AdminExportsScope {}) -> [registeredLiveSurface adminExportsLiveSurfaceDefinition () RequestContextOnly defaultCandidateFragments Nothing]
        (AdminShiftTypesSurfaceEntry, AdminShiftTypesScope {}) -> [registeredLiveSurface adminShiftTypesLiveSurfaceDefinition () RequestContextOnly defaultCandidateFragments Nothing]
        (AdminRosterGroupsSurfaceEntry, AdminRosterGroupsScope {}) -> [registeredLiveSurface adminRosterGroupsLiveSurfaceDefinition () RequestContextOnly defaultCandidateFragments Nothing]
        (LeaveRequestsSurfaceEntry, LeaveRequestsScope {}) -> [registeredLiveSurface leaveRequestsLiveSurfaceDefinition () RequestContextOnly defaultCandidateFragments Nothing]
        (ProfileContentSurfaceEntry, ProfileScope {}) -> [registeredLiveSurface profileContentLiveSurfaceDefinition sampleProfileContentSurfaceKey RequestContextOnly profileContentCandidateFragments Nothing]
        (ProfileLeaveRequestsSurfaceEntry, ProfileScope {}) -> [registeredLiveSurface profileLeaveRequestsLiveSurfaceDefinition sampleProfileLeaveSurfaceKey RequestContextOnly defaultCandidateFragments Nothing]
        (RosterSurfaceEntry, RosterWeekScope {}) -> [registeredLiveSurface rosterLiveSurfaceDefinition sampleRosterSurfaceKey RequestContextOnly defaultCandidateFragments (Just "roster")]
        _ -> []

backgroundPlannableSurfacesForScope :: LiveUpdateScope -> [RegisteredLiveSurface]
backgroundPlannableSurfacesForScope scope =
    concatMap (`backgroundPlannableSurfaceForEntry` scope) registeredLiveSurfaceCatalog

backgroundPlannableSurfaceForEntry :: RegisteredLiveSurfaceEntry -> LiveUpdateScope -> [RegisteredLiveSurface]
backgroundPlannableSurfaceForEntry entry scope =
    case (entry, scope) of
        (SupportSurfaceEntry, SupportPlatformScope) ->
            [registeredLiveSurface supportLiveSurfaceDefinition () BackgroundPlannable defaultCandidateFragments Nothing]
        (BillingSurfaceEntry, BillingScope { venueId }) ->
            [registeredLiveSurface billingLiveSurfaceDefinition BillingSurfaceKey { billingSurfaceVenueId = venueId } BackgroundPlannable defaultCandidateFragments Nothing]
        (AdminInvitesSurfaceEntry, AdminInvitesScope { venueId }) ->
            [registeredLiveSurface (adminInvitesLiveSurfaceDefinitionForVenue venueId) AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Nothing } BackgroundPlannable defaultCandidateFragments Nothing]
        (AdminVenueSettingsSurfaceEntry, AdminVenueConfigScope { venueId }) ->
            [registeredLiveSurface (adminVenueSettingsLiveSurfaceDefinitionForVenue venueId) () BackgroundPlannable defaultCandidateFragments Nothing]
        (TimesheetSurfaceEntry, TimesheetWeekScope { venueId }) ->
            [registeredLiveSurface (timesheetLiveSurfaceDefinitionForVenue venueId) sampleTimesheetSurfaceKey BackgroundPlannable (const timesheetLiveSurfaceCandidateFragments) Nothing]
        (AdminXeroSurfaceEntry, AdminXeroScope { venueId }) ->
            [registeredLiveSurface (adminXeroLiveSurfaceDefinitionForVenue venueId) () BackgroundPlannable defaultCandidateFragments Nothing]
        _ ->
            []

defaultCandidateFragments ::
    TypedLiveSurfaceDefinition surface scope fragment layer session intent ->
    scope ->
    [fragment]
defaultCandidateFragments definition surfaceKey =
    definition.typedSurfaceDefaultFragments surfaceKey

planRegisteredSurfaceInvalidation :: RegisteredLiveSurface -> Set.Set LiveResource -> LiveUpdateScope -> Maybe LiveSurfaceInvalidationTarget
planRegisteredSurfaceInvalidation RegisteredLiveSurface { registeredSurfaceDefinition = definition, registeredSurfaceCandidateFragments = candidateFragments } resources wireScope = do
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

authorizeRegisteredSurfaceWireScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    RegisteredLiveSurface ->
    LiveUpdateScope ->
    IO (Maybe Bool)
authorizeRegisteredSurfaceWireScope RegisteredLiveSurface { registeredSurfaceDefinition = definition } =
    authorizeTypedLiveSurfaceWireScope definition

adminXeroManifestCandidateFragments ::
    TypedLiveSurfaceDefinition surface scope AdminXeroLiveFragment layer session intent ->
    scope ->
    [AdminXeroLiveFragment]
adminXeroManifestCandidateFragments _ _ =
    [ AdminXeroShellLiveFragment
    , AdminXeroStaffMappingsLiveFragment
    , AdminXeroPayItemsLiveFragment
    , AdminXeroTimesheetsLiveFragment
    ]

rosterManifestCandidateFragments ::
    TypedLiveSurfaceDefinition surface scope RosterProjectionFragment layer session intent ->
    scope ->
    [RosterProjectionFragment]
rosterManifestCandidateFragments _ _ =
    [ RosterProjectionContent
    , RosterProjectionGridToolbar
    , RosterProjectionGridFrame
    , RosterProjectionDayColumns
    , RosterProjectionDayRail
    , RosterProjectionWageRail
    , RosterProjectionSlotsGrid
    , RosterProjectionStaffPanel
    , RosterProjectionDaySection sampleRosterDayId
    , RosterProjectionRow sampleRosterDayId 0
    ]

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
