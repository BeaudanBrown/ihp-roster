module Web.LiveSurfaceRegistry
    ( LiveSurfaceInvalidationTarget (..)
    , authorizeRegisteredLiveSurfaceScope
    , performLiveSurfaceInvalidationTarget
    , performLiveSurfaceInvalidationTargetWithoutContext
    , planRegisteredLiveSurfaceInvalidations
    , planRegisteredLiveSurfaceInvalidationsWithoutContext
    ) where

import Application.Helper.LiveResource (LiveResource)
import Application.Helper.LiveSurface (SurfaceScope (..),
                                       TypedLiveSurfaceDefinition (..),
                                       authorizeTypedLiveSurfaceWireScope,
                                       typedLiveSurfaceFragmentRefs,
                                       unSurfaceFragmentRefs)
import Application.Helper.LiveUpdate (LiveUpdateScope (..),
                                      LiveUpdateWireFragment,
                                      broadcastLiveInvalidation,
                                      broadcastLiveInvalidationWithoutContext,
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
import Web.Timesheets.Projection (timesheetLiveSurfaceDefinition,
                                  timesheetLiveSurfaceDefinitionForVenue)
import Web.View.Admin.Compliance (staffComplianceLiveSurfaceDefinition)
import Web.View.Admin.Exports (adminExportsLiveSurfaceDefinition)
import Web.View.Admin.Invites (adminInvitesLiveSurfaceDefinition,
                               adminInvitesLiveSurfaceDefinitionForVenue)
import Web.View.Admin.RosterGroups (adminRosterGroupsLiveSurfaceDefinition)
import Web.View.Admin.ShiftTypes (adminShiftTypesLiveSurfaceDefinition)
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
                , authorizeTypedLiveSurfaceWireScope adminInvitesLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminExportsLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminShiftTypesLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminRosterGroupsLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope adminXeroLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope billingLiveSurfaceDefinition scope
                , authorizeTypedLiveSurfaceWireScope staffComplianceLiveSurfaceDefinition scope
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
        , surface <- registeredLiveSurfaces
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
    IO ()
performLiveSurfaceInvalidationTarget target =
    broadcastLiveInvalidation target.targetScope liveUpdateSourceClientId target.targetFragments

performLiveSurfaceInvalidationTargetWithoutContext ::
    LiveSurfaceInvalidationTarget ->
    IO ()
performLiveSurfaceInvalidationTargetWithoutContext target =
    broadcastLiveInvalidationWithoutContext target.targetScope Nothing target.targetFragments

registeredLiveSurfaces :: (?context :: ControllerContext) => [RegisteredLiveSurface]
registeredLiveSurfaces =
    [ registeredTypedLiveSurface supportLiveSurfaceDefinition defaultCandidateFragments
    , registeredTypedLiveSurface adminInvitesLiveSurfaceDefinition defaultCandidateFragments
    , registeredTypedLiveSurface adminExportsLiveSurfaceDefinition defaultCandidateFragments
    , registeredTypedLiveSurface adminShiftTypesLiveSurfaceDefinition defaultCandidateFragments
    , registeredTypedLiveSurface adminRosterGroupsLiveSurfaceDefinition defaultCandidateFragments
    , registeredTypedLiveSurface adminXeroLiveSurfaceDefinition defaultCandidateFragments
    , registeredTypedLiveSurface billingLiveSurfaceDefinition defaultCandidateFragments
    , registeredTypedLiveSurface staffComplianceLiveSurfaceDefinition defaultCandidateFragments
    , registeredTypedLiveSurface leaveRequestsLiveSurfaceDefinition defaultCandidateFragments
    , registeredTypedLiveSurface profileContentLiveSurfaceDefinition profileContentCandidateFragments
    , registeredTypedLiveSurface profileLeaveRequestsLiveSurfaceDefinition defaultCandidateFragments
    , registeredTypedLiveSurface timesheetLiveSurfaceDefinition defaultCandidateFragments
    , registeredTypedLiveSurface rosterLiveSurfaceDefinition defaultCandidateFragments
    ]

contextFreeRegisteredLiveSurfacesForScope :: LiveUpdateScope -> [RegisteredLiveSurface]
contextFreeRegisteredLiveSurfacesForScope = \case
    SupportPlatformScope ->
        [registeredTypedLiveSurface supportLiveSurfaceDefinition defaultCandidateFragments]
    BillingScope { venueId } ->
        [registeredTypedLiveSurface billingLiveSurfaceDefinition defaultCandidateFragments]
    AdminInvitesScope { venueId } ->
        [registeredTypedLiveSurface (adminInvitesLiveSurfaceDefinitionForVenue venueId) defaultCandidateFragments]
    TimesheetWeekScope { venueId } ->
        [registeredTypedLiveSurface (timesheetLiveSurfaceDefinitionForVenue venueId) defaultCandidateFragments]
    AdminXeroScope { venueId } ->
        [registeredTypedLiveSurface (adminXeroLiveSurfaceDefinitionForVenue venueId) defaultCandidateFragments]
    _ ->
        []

defaultCandidateFragments ::
    TypedLiveSurfaceDefinition surface scope fragment ->
    scope ->
    [fragment]
defaultCandidateFragments definition surfaceKey =
    definition.typedSurfaceDefaultFragments surfaceKey

registeredTypedLiveSurface ::
    TypedLiveSurfaceDefinition surface scope fragment ->
    (TypedLiveSurfaceDefinition surface scope fragment -> scope -> [fragment]) ->
    RegisteredLiveSurface
registeredTypedLiveSurface definition candidateFragments =
    RegisteredLiveSurface \resources wireScope -> do
        surfaceKey <- definition.typedSurfaceScopeFromWire wireScope
        if unSurfaceScope (definition.typedSurfaceScope surfaceKey) /= wireScope
            then Nothing
            else do
                let affectedFragments =
                        filter
                            (\fragment -> fragmentDependsOnAny resources (definition.typedSurfaceDependsOn surfaceKey fragment))
                            (candidateFragments definition surfaceKey)
                if null affectedFragments
                    then Nothing
                    else
                        Just
                            LiveSurfaceInvalidationTarget
                                { targetScope = wireScope
                                , targetFragments = unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs definition surfaceKey affectedFragments)
                                }

fragmentDependsOnAny :: Set.Set LiveResource -> [LiveResource] -> Bool
fragmentDependsOnAny touched dependencies =
    not (Set.null (Set.intersection touched (Set.fromList dependencies)))

profileContentCandidateFragments ::
    TypedLiveSurfaceDefinition surface scope ProfileContentFragment ->
    scope ->
    [ProfileContentFragment]
profileContentCandidateFragments _ _ =
    [ ProfileContentLiveFragment "profile"
    , ProfileContentLiveFragment "rsa"
    , ProfileContentLiveFragment "leave"
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
