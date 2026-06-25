module Web.LiveSurfaceRegistry
    ( LiveSurfaceInvalidationTarget (..)
    , authorizeRegisteredLiveSurfaceScope
    , performLiveSurfaceInvalidationTarget
    , performLiveSurfaceInvalidationTargetWithoutContext
    , planRegisteredLiveSurfaceInvalidations
    , planRegisteredLiveSurfaceInvalidationsWithoutContext
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
import Application.Support.LiveUpdates (supportLiveSurfaceDefinition)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Web.Billing.LiveUpdates (billingLiveSurfaceDefinition)
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
import Web.View.Admin.Invites (adminInvitesLiveSurfaceDefinition,
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
    TypedLiveSurfaceDefinition surface scope fragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent ->
    scope ->
    [fragment]
defaultCandidateFragments definition surfaceKey =
    definition.typedSurfaceDefaultFragments surfaceKey

registeredTypedLiveSurface ::
    TypedLiveSurfaceDefinition surface scope fragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent ->
    (TypedLiveSurfaceDefinition surface scope fragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent -> scope -> [fragment]) ->
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
