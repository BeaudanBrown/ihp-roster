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
                                       LiveScopeAuthorizationRequirement (..),
                                       SurfaceScope (..),
                                       TypedLiveSurfaceDefinition (..),
                                       authorizeLiveScopeRequirement,
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
                                              liveUpdateScopeKind,
                                              liveUpdateSourceClientId,
                                              liveUpdateWireFragmentKind)
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
    = AdminVenueSettingsSurfaceEntry
    | AdminInvitesSurfaceEntry
    | AdminExportsSurfaceEntry
    | AdminShiftTypesSurfaceEntry
    | AdminRosterGroupsSurfaceEntry
    | AdminXeroSurfaceEntry
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
    fmap (manifestDescriptorFromRegisteredSurface . manifestSurfaceForEntry) registeredLiveSurfaceCatalog <> [timesheetsLiveSurfaceDescriptor, rosterLiveSurfaceDescriptor, leaveRequestsLiveSurfaceDescriptor, billingLiveSurfaceDescriptor, supportLiveSurfaceDescriptor, profileLiveSurfaceDescriptor, adminVenueSettingsDescriptor, adminInvitesDescriptor, adminExportsDescriptor, adminShiftTypesDescriptor, adminRosterGroupsDescriptor, adminXeroDescriptor]

registeredLiveSurfaceCatalog :: [RegisteredLiveSurfaceEntry]
registeredLiveSurfaceCatalog =
    []

manifestSurfaceForEntry :: RegisteredLiveSurfaceEntry -> RegisteredLiveSurface
manifestSurfaceForEntry = \case
    AdminVenueSettingsSurfaceEntry -> registeredLiveSurface (adminVenueSettingsLiveSurfaceDefinitionForVenue sampleVenueId) () BackgroundPlannable defaultCandidateFragments Nothing
    AdminInvitesSurfaceEntry -> registeredLiveSurface (adminInvitesLiveSurfaceDefinitionForVenue sampleVenueId) AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Nothing } BackgroundPlannable defaultCandidateFragments Nothing
    AdminExportsSurfaceEntry -> registeredLiveSurface (adminExportsLiveSurfaceDefinitionForVenue sampleVenueId) () RequestContextOnly defaultCandidateFragments Nothing
    AdminShiftTypesSurfaceEntry -> registeredLiveSurface (adminShiftTypesLiveSurfaceDefinitionForVenue sampleVenueId) () RequestContextOnly defaultCandidateFragments Nothing
    AdminRosterGroupsSurfaceEntry -> registeredLiveSurface (adminRosterGroupsLiveSurfaceDefinitionForVenue sampleVenueId) () RequestContextOnly defaultCandidateFragments Nothing
    AdminXeroSurfaceEntry -> registeredLiveSurface (adminXeroLiveSurfaceDefinitionForVenue sampleVenueId) () BackgroundPlannable adminXeroManifestCandidateFragments Nothing

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
            , fragmentKinds = unique (map liveUpdateWireFragmentKind (unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs definition surfaceKey (candidateFragments definition surfaceKey))))
            , interactionSchema
            }
        }

sampleVenueId :: UUID
sampleVenueId = UUID.fromWords 0 0 0 0

sampleStaffId :: UUID
sampleStaffId = UUID.fromWords 1 0 0 0

timesheetsLiveSurfaceDescriptor :: RegisteredLiveSurfaceDescriptor
timesheetsLiveSurfaceDescriptor =
    RegisteredLiveSurfaceDescriptor
        { descriptorManifest = RegisteredLiveSurfaceManifest
            { surfaceFamily = "timesheets"
            , scopeKinds = ["timesheet_week"]
            , fragmentKinds = ["timesheet_toolbar", "timesheet_day_columns", "timesheet_day_section"]
            , interactionSchema = Nothing
            }
        }

rosterLiveSurfaceDescriptor :: RegisteredLiveSurfaceDescriptor
rosterLiveSurfaceDescriptor =
    RegisteredLiveSurfaceDescriptor
        { descriptorManifest = RegisteredLiveSurfaceManifest
            { surfaceFamily = "roster"
            , scopeKinds = ["roster_week"]
            , fragmentKinds = ["roster_content", "roster_grid_toolbar", "roster_grid_frame", "roster_day_columns", "roster_day_rail", "roster_wage_rail", "roster_slots_grid", "roster_staff_panel", "roster_day_section", "roster_row"]
            , interactionSchema = Just "roster"
            }
        }

leaveRequestsLiveSurfaceDescriptor :: RegisteredLiveSurfaceDescriptor
leaveRequestsLiveSurfaceDescriptor =
    RegisteredLiveSurfaceDescriptor
        { descriptorManifest = RegisteredLiveSurfaceManifest
            { surfaceFamily = "leave-requests"
            , scopeKinds = ["leave_requests"]
            , fragmentKinds = ["leave_requests_content"]
            , interactionSchema = Nothing
            }
        }

billingLiveSurfaceDescriptor :: RegisteredLiveSurfaceDescriptor
billingLiveSurfaceDescriptor =
    RegisteredLiveSurfaceDescriptor
        { descriptorManifest = RegisteredLiveSurfaceManifest
            { surfaceFamily = "billing"
            , scopeKinds = ["billing"]
            , fragmentKinds = ["billing_status"]
            , interactionSchema = Nothing
            }
        }

supportLiveSurfaceDescriptor :: RegisteredLiveSurfaceDescriptor
supportLiveSurfaceDescriptor =
    RegisteredLiveSurfaceDescriptor
        { descriptorManifest = RegisteredLiveSurfaceManifest
            { surfaceFamily = "support"
            , scopeKinds = ["support_platform"]
            , fragmentKinds = ["support_award_rates_section", "support_public_holidays_section"]
            , interactionSchema = Nothing
            }
        }

profileLiveSurfaceDescriptor :: RegisteredLiveSurfaceDescriptor
profileLiveSurfaceDescriptor =
    RegisteredLiveSurfaceDescriptor
        { descriptorManifest = RegisteredLiveSurfaceManifest
            { surfaceFamily = "profile"
            , scopeKinds = ["profile"]
            , fragmentKinds = ["profile_details_section", "profile_preferences_section", "profile_security_section", "profile_leave_section", "profile_rsa_section"]
            , interactionSchema = Nothing
            }
        }

adminVenueSettingsDescriptor, adminInvitesDescriptor, adminExportsDescriptor, adminShiftTypesDescriptor, adminRosterGroupsDescriptor, adminXeroDescriptor :: RegisteredLiveSurfaceDescriptor
adminVenueSettingsDescriptor = simpleDescriptor "admin-venue-config" "admin_venue_config" "admin_venue_config"
adminInvitesDescriptor = simpleDescriptor "admin-invites" "admin_invites" "admin_invites"
adminExportsDescriptor = simpleDescriptor "admin-exports" "admin_exports" "admin_exports"
adminShiftTypesDescriptor = simpleDescriptor "admin-shift-types" "admin_shift_types" "admin_shift_types"
adminRosterGroupsDescriptor = simpleDescriptor "admin-roster-groups" "admin_roster_groups" "admin_roster_groups"
adminXeroDescriptor = RegisteredLiveSurfaceDescriptor { descriptorManifest = RegisteredLiveSurfaceManifest { surfaceFamily = "admin-xero", scopeKinds = ["admin_xero"], fragmentKinds = ["admin_xero", "admin_xero_staff_mappings", "admin_xero_pay_items", "admin_xero_timesheets"], interactionSchema = Nothing } }

simpleDescriptor :: Text -> Text -> Text -> RegisteredLiveSurfaceDescriptor
simpleDescriptor family scope fragment = RegisteredLiveSurfaceDescriptor { descriptorManifest = RegisteredLiveSurfaceManifest { surfaceFamily = family, scopeKinds = [scope], fragmentKinds = [fragment], interactionSchema = Nothing } }

unique :: Eq a => [a] -> [a]
unique = foldr (\value acc -> if value `elem` acc then acc else value : acc) []

authorizeRegisteredLiveSurfaceScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    LiveUpdateScope ->
    IO Bool
authorizeRegisteredLiveSurfaceScope scope = do
    legacyAuthorizations <- catMaybes <$> mapM (`authorizeRegisteredSurfaceWireScope` scope) registeredLiveSurfaceAuthorizationCatalog
    timesheetsAuthorization <- authorizeTimesheetsLiveSurfaceScope scope
    rosterAuthorization <- authorizeRosterLiveSurfaceScope scope
    leaveRequestsAuthorization <- authorizeLeaveRequestsLiveSurfaceScope scope
    billingAuthorization <- authorizeBillingLiveSurfaceScope scope
    supportAuthorization <- authorizeSupportLiveSurfaceScope scope
    profileAuthorization <- authorizeProfileLiveSurfaceScope scope
    adminAuthorization <- authorizeAdminFrontendSurfaceScope scope
    pure (or legacyAuthorizations || timesheetsAuthorization || rosterAuthorization || leaveRequestsAuthorization || billingAuthorization || supportAuthorization || profileAuthorization || adminAuthorization)

registeredLiveSurfaceAuthorizationCatalog :: (?context :: ControllerContext) => [RegisteredLiveSurface]
registeredLiveSurfaceAuthorizationCatalog =
    fmap authorizationSurfaceForEntry registeredLiveSurfaceCatalog

authorizationSurfaceForEntry :: (?context :: ControllerContext) => RegisteredLiveSurfaceEntry -> RegisteredLiveSurface
authorizationSurfaceForEntry = \case
    AdminVenueSettingsSurfaceEntry -> registeredLiveSurface adminVenueSettingsLiveSurfaceDefinition () BackgroundPlannable defaultCandidateFragments Nothing
    AdminInvitesSurfaceEntry -> registeredLiveSurface adminInvitesLiveSurfaceDefinition AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Nothing } BackgroundPlannable defaultCandidateFragments Nothing
    AdminExportsSurfaceEntry -> registeredLiveSurface adminExportsLiveSurfaceDefinition () RequestContextOnly defaultCandidateFragments Nothing
    AdminShiftTypesSurfaceEntry -> registeredLiveSurface adminShiftTypesLiveSurfaceDefinition () RequestContextOnly defaultCandidateFragments Nothing
    AdminRosterGroupsSurfaceEntry -> registeredLiveSurface adminRosterGroupsLiveSurfaceDefinition () RequestContextOnly defaultCandidateFragments Nothing
    AdminXeroSurfaceEntry -> registeredLiveSurface adminXeroLiveSurfaceDefinition () BackgroundPlannable defaultCandidateFragments Nothing

planRegisteredLiveSurfaceInvalidations ::
    (?context :: ControllerContext) =>
    Set.Set LiveResource ->
    [LiveUpdateScope] ->
    [LiveSurfaceInvalidationTarget]
planRegisteredLiveSurfaceInvalidations resources scopes =
    coalesceTargets $
        [ target
        | scope <- scopes
        , surface <- registeredLiveSurfacesForScope scope
        , Just target <- [planRegisteredSurfaceInvalidation surface resources scope]
        ] <> mapMaybe (planTimesheetsSurfaceInvalidation resources) scopes <> mapMaybe (planRosterSurfaceInvalidation resources) scopes <> mapMaybe (planLeaveRequestsSurfaceInvalidation resources) scopes <> mapMaybe (planBillingSurfaceInvalidation resources) scopes <> mapMaybe (planSupportSurfaceInvalidation resources) scopes <> mapMaybe (planProfileSurfaceInvalidation resources) scopes <> mapMaybe (planAdminSurfaceInvalidation resources) scopes

planRegisteredLiveSurfaceInvalidationsWithoutContext ::
    Set.Set LiveResource ->
    [LiveUpdateScope] ->
    [LiveSurfaceInvalidationTarget]
planRegisteredLiveSurfaceInvalidationsWithoutContext resources scopes =
    coalesceTargets $
        [ target
        | scope <- scopes
        , surface <- backgroundPlannableSurfacesForScope scope
        , Just target <- [planRegisteredSurfaceInvalidation surface resources scope]
        ] <> mapMaybe (planTimesheetsSurfaceInvalidation resources) scopes <> mapMaybe (planRosterSurfaceInvalidation resources) scopes <> mapMaybe (planLeaveRequestsSurfaceInvalidation resources) scopes <> mapMaybe (planBillingSurfaceInvalidation resources) scopes <> mapMaybe (planSupportSurfaceInvalidation resources) scopes <> mapMaybe (planProfileSurfaceInvalidation resources) scopes <> mapMaybe (planAdminSurfaceInvalidation resources) scopes

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
        _ -> []

backgroundPlannableSurfacesForScope :: LiveUpdateScope -> [RegisteredLiveSurface]
backgroundPlannableSurfacesForScope scope =
    concatMap (`backgroundPlannableSurfaceForEntry` scope) registeredLiveSurfaceCatalog

backgroundPlannableSurfaceForEntry :: RegisteredLiveSurfaceEntry -> LiveUpdateScope -> [RegisteredLiveSurface]
backgroundPlannableSurfaceForEntry entry scope =
    case (entry, scope) of
        (AdminInvitesSurfaceEntry, AdminInvitesScope { venueId }) ->
            [registeredLiveSurface (adminInvitesLiveSurfaceDefinitionForVenue venueId) AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Nothing } BackgroundPlannable defaultCandidateFragments Nothing]
        (AdminVenueSettingsSurfaceEntry, AdminVenueConfigScope { venueId }) ->
            [registeredLiveSurface (adminVenueSettingsLiveSurfaceDefinitionForVenue venueId) () BackgroundPlannable defaultCandidateFragments Nothing]
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

authorizeTimesheetsLiveSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LiveUpdateScope -> IO Bool
authorizeTimesheetsLiveSurfaceScope = \case
    TimesheetWeekScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenue venueId)
    _                              -> pure False

authorizeRosterLiveSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LiveUpdateScope -> IO Bool
authorizeRosterLiveSurfaceScope = \case
    RosterWeekScope { venueId, rosterGroupId } -> authorizeLiveScopeRequirement (RequireCurrentVenueRosterGroup venueId rosterGroupId)
    _                                         -> pure False

authorizeLeaveRequestsLiveSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LiveUpdateScope -> IO Bool
authorizeLeaveRequestsLiveSurfaceScope = \case
    LeaveRequestsScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueManager venueId)
    _                              -> pure False

authorizeBillingLiveSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LiveUpdateScope -> IO Bool
authorizeBillingLiveSurfaceScope = \case
    BillingScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueOwner venueId)
    _                        -> pure False

authorizeSupportLiveSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LiveUpdateScope -> IO Bool
authorizeSupportLiveSurfaceScope = \case
    SupportPlatformScope -> authorizeLiveScopeRequirement RequireSupportSuperAdmin
    _                    -> pure False

authorizeProfileLiveSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LiveUpdateScope -> IO Bool
authorizeProfileLiveSurfaceScope = \case
    ProfileScope { venueId, staffId } -> authorizeLiveScopeRequirement (RequireCurrentVenueStaff venueId staffId)
    _                                 -> pure False

authorizeAdminFrontendSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LiveUpdateScope -> IO Bool
authorizeAdminFrontendSurfaceScope = \case
    AdminVenueConfigScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueAdmin venueId)
    AdminInvitesScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueAdmin venueId)
    AdminExportsScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueAdmin venueId)
    AdminShiftTypesScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueAdmin venueId)
    AdminRosterGroupsScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueAdmin venueId)
    AdminXeroScope { venueId } -> authorizeLiveScopeRequirement (RequireCurrentVenueOwner venueId)
    _ -> pure False

planRosterSurfaceInvalidation :: Set.Set LiveResource -> LiveUpdateScope -> Maybe LiveSurfaceInvalidationTarget
planRosterSurfaceInvalidation resources RosterWeekScope { venueId, rosterGroupId, weekOffset } =
    let scopeValue = RosterWeekScopeValue
            { rosterWeekVenueId = venueId
            , rosterWeekGroupId = coerce rosterGroupId :: Id RosterGroup
            , rosterWeekWeekOffset = weekOffset
            }
        -- Passive viewers are planned from semantic default fragments. Actor-local
        -- responses still render parameterized day/row fragments explicitly.
        mountedPlan = RosterMountedFragmentPlan { rosterMountedDayIds = [], rosterMountedRows = [] }
        fragments = rosterSurfaceWireFragments (rosterAffectedMountedFragments scopeValue mountedPlan resources)
     in if null fragments
            then Nothing
            else Just LiveSurfaceInvalidationTarget { targetScope = RosterWeekScope { venueId, rosterGroupId, weekOffset }, targetFragments = fragments }
planRosterSurfaceInvalidation _ _ =
    Nothing

planTimesheetsSurfaceInvalidation :: Set.Set LiveResource -> LiveUpdateScope -> Maybe LiveSurfaceInvalidationTarget
planTimesheetsSurfaceInvalidation resources TimesheetWeekScope { venueId, weekOffset } =
    let scopeValue = TimesheetWeekScopeValue { timesheetWeekVenueId = venueId, timesheetWeekWeekOffset = weekOffset }
        -- Active mounts keep their filter state in fragment data-live-update-url and
        -- the live-update client prefers that URL. These default filters only build
        -- semantically keyed candidate fragments for dependency planning.
        mountStateValue = TimesheetsMountStateValue { timesheetsMountShowApproved = True, timesheetsMountShowAllStaff = True, timesheetsMountStaffFilterId = Nothing }
        fragments = timesheetsSurfaceWireFragments (timesheetsAffectedMountedFragments scopeValue mountStateValue resources)
     in if null fragments
            then Nothing
            else Just LiveSurfaceInvalidationTarget { targetScope = TimesheetWeekScope { venueId, weekOffset }, targetFragments = fragments }
planTimesheetsSurfaceInvalidation _ _ =
    Nothing

planLeaveRequestsSurfaceInvalidation :: Set.Set LiveResource -> LiveUpdateScope -> Maybe LiveSurfaceInvalidationTarget
planLeaveRequestsSurfaceInvalidation resources LeaveRequestsScope { venueId } =
    let scopeValue = LeaveRequestsScopeValue { leaveRequestsVenueId = venueId }
        fragments = leaveRequestsSurfaceWireFragments (leaveRequestsAffectedMountedFragments scopeValue resources)
     in if null fragments
            then Nothing
            else Just LiveSurfaceInvalidationTarget { targetScope = LeaveRequestsScope { venueId }, targetFragments = fragments }
planLeaveRequestsSurfaceInvalidation _ _ =
    Nothing

planBillingSurfaceInvalidation :: Set.Set LiveResource -> LiveUpdateScope -> Maybe LiveSurfaceInvalidationTarget
planBillingSurfaceInvalidation resources BillingScope { venueId } =
    let scopeValue = BillingScopeValue { billingVenueId = venueId }
        fragments = billingSurfaceWireFragments (billingAffectedMountedFragments scopeValue resources)
     in if null fragments
            then Nothing
            else Just LiveSurfaceInvalidationTarget { targetScope = BillingScope { venueId }, targetFragments = fragments }
planBillingSurfaceInvalidation _ _ =
    Nothing

planSupportSurfaceInvalidation :: Set.Set LiveResource -> LiveUpdateScope -> Maybe LiveSurfaceInvalidationTarget
planSupportSurfaceInvalidation resources SupportPlatformScope =
    let fragments = supportSurfaceWireFragments (supportAffectedMountedFragments resources)
     in if null fragments
            then Nothing
            else Just LiveSurfaceInvalidationTarget { targetScope = SupportPlatformScope, targetFragments = fragments }
planSupportSurfaceInvalidation _ _ =
    Nothing

planProfileSurfaceInvalidation :: Set.Set LiveResource -> LiveUpdateScope -> Maybe LiveSurfaceInvalidationTarget
planProfileSurfaceInvalidation resources ProfileScope { venueId, staffId } =
    let scopeValue = ProfileScopeValue { profileVenueId = venueId, profileStaffId = staffId }
        fragments = profileSurfaceWireFragments (profileAffectedMountedFragments scopeValue resources)
     in if null fragments
            then Nothing
            else Just LiveSurfaceInvalidationTarget { targetScope = ProfileScope { venueId, staffId }, targetFragments = fragments }
planProfileSurfaceInvalidation _ _ =
    Nothing

planAdminSurfaceInvalidation :: Set.Set LiveResource -> LiveUpdateScope -> Maybe LiveSurfaceInvalidationTarget
planAdminSurfaceInvalidation resources scope =
    let fragments = case scope of
            AdminVenueConfigScope { venueId } -> adminSurfaceWireFragments (adminVenueSettingsAffectedFragments (AdminVenueScopeValue venueId Nothing) resources)
            AdminInvitesScope { venueId } -> adminSurfaceWireFragments (adminInvitesAffectedFragments (AdminVenueScopeValue venueId Nothing) resources)
            AdminExportsScope { venueId } -> adminSurfaceWireFragments (adminExportsAffectedFragments (AdminVenueScopeValue venueId Nothing) resources)
            AdminShiftTypesScope { venueId } -> adminSurfaceWireFragments (adminShiftTypesAffectedFragments (AdminVenueScopeValue venueId Nothing) resources)
            AdminRosterGroupsScope { venueId } -> adminSurfaceWireFragments (adminRosterGroupsAffectedFragments (AdminVenueScopeValue venueId Nothing) resources)
            AdminXeroScope { venueId } -> adminSurfaceWireFragments (adminXeroAffectedFragments (AdminVenueScopeValue venueId Nothing) resources)
            _ -> []
     in if null fragments then Nothing else Just LiveSurfaceInvalidationTarget { targetScope = scope, targetFragments = fragments }

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
