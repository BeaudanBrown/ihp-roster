{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.RosterWeeks.LiveSurface
    ( RosterInteractionIntent (..)
    , RosterInteractionLayer (..)
    , RosterInteractionSession (..)
    , RosterLiveSurface
    , rosterInteractionMountKey
    , rosterInteractionStaticSchema
    , rosterDragSessionKindName
    , rosterLayoutModeIntentField
    , rosterLayoutModeIntentName
    , rosterMoveShiftIntentName
    , mkRosterProjectionDefinition
    , rosterLiveSurfaceDefinition
    , rosterLiveSurfaceDefinitionForVenue
    , rosterProjectionVersion
    ) where

import Application.Helper.Controller
import Application.Helper.Frontend.AppConstants (interactionIntentSubmitHtmxTrigger)
import Application.Helper.Interaction
import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveUpdateScope (..),
                                      currentLiveUpdateVersion)
import Application.Helper.SurfaceProjection
import Application.Helper.UserPreferences
import Data.Coerce (coerce)
import qualified Data.Time.Calendar as Calendar
import Data.UUID (UUID)
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Filters
import Web.RosterWeeks.Paths (rosterLayoutPreferenceUrl, rosterMoveShiftUrl,
                              rosterWeekContentFragmentUrl,
                              rosterWeekDayColumnsFragmentUrl,
                              rosterWeekDayRailFragmentUrl,
                              rosterWeekDaySectionFragmentUrl,
                              rosterWeekGridFrameFragmentUrl,
                              rosterWeekGridToolbarFragmentUrl,
                              rosterWeekRowFragmentUrl,
                              rosterWeekSlotsGridFragmentUrl,
                              rosterWeekStaffPanelFragmentUrl,
                              rosterWeekWageRailFragmentUrl)
import Web.RosterWeeks.Projection
import Web.RosterWeeks.Types

data RosterLiveSurface

data RosterInteractionLayer = RosterDragPreviewLayer deriving (Eq, Show)
data RosterInteractionSession = RosterDragSession deriving (Eq, Show)
data RosterInteractionIntent
    = SetRosterLayoutModeIntent
    | MoveRosterShiftToSlotIntent
    deriving (Eq, Show)

rosterInteractionMountKey :: InteractionMountKey
rosterInteractionMountKey = InteractionMountKey "primary"

rosterLayoutModeIntentName :: Text
rosterLayoutModeIntentName = "set-roster-layout-mode"

rosterMoveShiftIntentName :: Text
rosterMoveShiftIntentName = "move-roster-shift-to-slot"

rosterDragSessionKindName :: Text
rosterDragSessionKindName = "drag"

rosterLayoutModeIntentField :: IntentFieldName
rosterLayoutModeIntentField = IntentFieldName "rosterLayoutMode"

rosterLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition RosterLiveSurface RosterProjectionScope RosterProjectionFragment RosterInteractionLayer RosterInteractionSession RosterInteractionIntent
rosterLiveSurfaceDefinition =
    (rosterLiveSurfaceDefinitionForVenue (unpackId currentVenueId))
        { typedSurfaceInteraction = rosterInteractionCapability
        }

rosterLiveSurfaceDefinitionForVenue :: UUID -> TypedLiveSurfaceDefinition RosterLiveSurface RosterProjectionScope RosterProjectionFragment RosterInteractionLayer RosterInteractionSession RosterInteractionIntent
rosterLiveSurfaceDefinitionForVenue surfaceVenueId =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "roster"
        , typedSurfaceScope = rosterSurfaceScope
        , typedSurfaceScopeFromWire = rosterSurfaceScopeFromWire
        , typedSurfaceDefaultFragments = const [RosterProjectionGridToolbar, RosterProjectionDayColumns, RosterProjectionDayRail, RosterProjectionWageRail, RosterProjectionSlotsGrid, RosterProjectionStaffPanel]
        , typedSurfaceFragmentContract = \scope fragment ->
            mkSurfaceFragmentContract
                (rosterFragmentRef scope fragment)
                (rosterFragmentDependencies surfaceVenueId scope fragment)
                |> rosterFragmentLoadPolicy fragment
        , typedSurfaceDecorateRequestsWithin = const ["#roster-week-shell"]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (\scope -> RequireCurrentVenueRosterGroup surfaceVenueId (unpackId scope.rosterProjectionGroupId))
        , typedSurfaceInteractionSchema = rosterInteractionStaticSchema
        , typedSurfaceInteraction = const rosterStaticInteractionCapability
        }
    where
        rosterSurfaceScope scope =
            SurfaceScope RosterWeekScope
                { venueId = surfaceVenueId
                , rosterGroupId = unpackId scope.rosterProjectionGroupId
                , weekOffset = scope.rosterProjectionWeekOffset
                }

        rosterSurfaceScopeFromWire scope =
            case scope of
                RosterWeekScope { venueId, rosterGroupId, weekOffset } | venueId == surfaceVenueId ->
                    Just RosterProjectionScope
                        { rosterProjectionGroupId = coerce rosterGroupId
                        , rosterProjectionWeekOffset = weekOffset
                        }
                _ ->
                    Nothing

rosterInteractionStaticSchema :: InteractionStaticSchema RosterProjectionFragment RosterInteractionLayer RosterInteractionSession RosterInteractionIntent
rosterInteractionStaticSchema =
    emptyInteractionStaticSchema
        { interactionStaticDisposableLayers =
            [ DisposableLayerDefinition
                { disposableLayerKind = RosterDragPreviewLayer
                , disposableLayerName = "drag-preview"
                , disposableLayerDomIdSuffix = "drag-preview"
                }
            ]
        , interactionStaticSessionKinds =
            [ SessionKindDefinition
                { sessionKind = RosterDragSession
                , sessionKindName = rosterDragSessionKindName
                , sessionDescription = "Roster drag/drop prototype"
                }
            ]
        , interactionStaticIntents =
            [ InteractionIntentSchema
                { interactionIntentSchemaIntent = SetRosterLayoutModeIntent
                , interactionIntentSchemaName = rosterLayoutModeIntentName
                , interactionIntentSchemaFields = [IntentFieldSchema rosterLayoutModeIntentField IntentFieldRequired Nothing]
                }
            , InteractionIntentSchema
                { interactionIntentSchemaIntent = MoveRosterShiftToSlotIntent
                , interactionIntentSchemaName = rosterMoveShiftIntentName
                , interactionIntentSchemaFields = rosterMoveShiftIntentFields
                }
            ]
        , interactionStaticConflictPolicies =
            [ InteractionConflictPolicy
                { conflictPolicySession = InteractionSessionKind RosterDragSession
                , conflictPolicyFragment = AnyInteractionFragment
                , conflictPolicyResolution = DeferLiveFragmentUntilSessionEnds
                , conflictPolicyTimeoutMs = Just 5000
                }
            ]
        }

rosterStaticInteractionCapability :: InteractionCapability (SurfaceFragmentRef RosterLiveSurface) RosterProjectionFragment RosterInteractionLayer RosterInteractionSession RosterInteractionIntent
rosterStaticInteractionCapability =
    emptyInteractionCapability
        { interactionStaticSchema = rosterInteractionStaticSchema
        , interactionServerLayers = rosterInteractionStaticSchema.interactionStaticServerLayers
        , interactionDisposableLayers = rosterInteractionStaticSchema.interactionStaticDisposableLayers
        , interactionSessionKinds = rosterInteractionStaticSchema.interactionStaticSessionKinds
        , interactionConflictPolicies = rosterInteractionStaticSchema.interactionStaticConflictPolicies
        }

rosterInteractionCapability :: (?context :: ControllerContext) => RosterProjectionScope -> InteractionCapability (SurfaceFragmentRef RosterLiveSurface) RosterProjectionFragment RosterInteractionLayer RosterInteractionSession RosterInteractionIntent
rosterInteractionCapability scope =
    emptyInteractionCapability
        { interactionStaticSchema = rosterInteractionStaticSchema
        , interactionServerLayers = rosterInteractionStaticSchema.interactionStaticServerLayers
        , interactionDisposableLayers = rosterInteractionStaticSchema.interactionStaticDisposableLayers
        , interactionSessionKinds = rosterInteractionStaticSchema.interactionStaticSessionKinds
        , interactionIntentForms = [rosterLayoutModeIntentForm scope, rosterMoveShiftIntentForm scope]
        , interactionConflictPolicies = rosterInteractionStaticSchema.interactionStaticConflictPolicies
        }

rosterLayoutModeIntentForm :: (?context :: ControllerContext) => RosterProjectionScope -> IntentFormContract (SurfaceFragmentRef RosterLiveSurface) RosterInteractionIntent
rosterLayoutModeIntentForm scope =
    IntentFormContract
        { intentFormIntent = SetRosterLayoutModeIntent
        , intentFormName = rosterLayoutModeIntentName
        , intentFormAction = rosterLayoutPreferenceUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId
        , intentFormMethod = HtmxPost
        , intentFormTrigger = interactionIntentSubmitHtmxTrigger
        , intentFormTarget = IntentTargetLiveFragment (rosterFragmentRef scope RosterProjectionContent)
        , intentFormSwap = HtmxSwapNone
        , intentFormFields = [IntentFieldSchema rosterLayoutModeIntentField IntentFieldRequired Nothing]
        , intentFormHiddenFields = []
        , intentFormSync = Just ("#" <> rosterWeekShellId <> ":replace")
        , intentFormDisabledElement = Nothing
        }

rosterMoveShiftIntentForm :: (?context :: ControllerContext) => RosterProjectionScope -> IntentFormContract (SurfaceFragmentRef RosterLiveSurface) RosterInteractionIntent
rosterMoveShiftIntentForm scope =
    IntentFormContract
        { intentFormIntent = MoveRosterShiftToSlotIntent
        , intentFormName = rosterMoveShiftIntentName
        , intentFormAction = rosterMoveShiftUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId
        , intentFormMethod = HtmxPost
        , intentFormTrigger = interactionIntentSubmitHtmxTrigger
        , intentFormTarget = IntentTargetLiveFragment (rosterFragmentRef scope RosterProjectionContent)
        , intentFormSwap = HtmxSwapNone
        , intentFormFields = rosterMoveShiftIntentFields
        , intentFormHiddenFields = []
        , intentFormSync = Just ("#" <> rosterWeekShellId <> ":replace")
        , intentFormDisabledElement = Nothing
        }

rosterMoveShiftIntentFields :: [IntentFieldSchema]
rosterMoveShiftIntentFields =
    [ IntentFieldSchema (IntentFieldName "sourceItemKey") IntentFieldRequired Nothing
    , IntentFieldSchema (IntentFieldName "targetDropzoneKey") IntentFieldRequired Nothing
    , IntentFieldSchema (IntentFieldName "sessionKind") IntentFieldOptional Nothing
    , IntentFieldSchema (IntentFieldName "pointerId") IntentFieldOptional Nothing
    , IntentFieldSchema (IntentFieldName "pointerType") IntentFieldOptional Nothing
    , IntentFieldSchema (IntentFieldName "startClientX") IntentFieldOptional Nothing
    , IntentFieldSchema (IntentFieldName "startClientY") IntentFieldOptional Nothing
    , IntentFieldSchema (IntentFieldName "currentClientX") IntentFieldOptional Nothing
    , IntentFieldSchema (IntentFieldName "currentClientY") IntentFieldOptional Nothing
    , IntentFieldSchema (IntentFieldName "deltaX") IntentFieldOptional Nothing
    , IntentFieldSchema (IntentFieldName "deltaY") IntentFieldOptional Nothing
    ]

rosterFragmentRef :: RosterProjectionScope -> RosterProjectionFragment -> SurfaceFragmentRef RosterLiveSurface
rosterFragmentRef scope = \case
    RosterProjectionContent ->
        mkSurfaceFragmentRef
            RosterContentFragment
            rosterContentFragmentId
            (rosterWeekContentFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionContent)
    RosterProjectionGridToolbar ->
        mkSurfaceFragmentRef
            RosterGridToolbarFragment
            rosterGridToolbarFragmentId
            (rosterWeekGridToolbarFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionGridToolbar)
    RosterProjectionGridFrame ->
        mkSurfaceFragmentRef
            RosterGridFrameFragment
            rosterGridFrameFragmentId
            (rosterWeekGridFrameFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionGridFrame)
    RosterProjectionDayColumns ->
        mkSurfaceFragmentRef
            RosterDayColumnsFragment
            rosterDayColumnsFragmentId
            (rosterWeekDayColumnsFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionDayColumns)
    RosterProjectionDayRail ->
        mkSurfaceFragmentRef
            RosterDayRailFragment
            rosterDayRailFragmentId
            (rosterWeekDayRailFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionDayRail)
    RosterProjectionWageRail ->
        mkSurfaceFragmentRef
            RosterWageRailFragment
            rosterWageRailFragmentId
            (rosterWeekWageRailFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionWageRail)
    RosterProjectionSlotsGrid ->
        mkSurfaceFragmentRef
            RosterSlotsGridFragment
            rosterSlotsGridFragmentId
            (rosterWeekSlotsGridFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionSlotsGrid)
    RosterProjectionStaffPanel ->
        mkSurfaceFragmentRef
            RosterStaffPanelFragment
            rosterStaffPanelFragmentId
            (rosterWeekStaffPanelFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionStaffPanel)
    RosterProjectionDaySection rosterDayId ->
        mkSurfaceFragmentRef
            RosterDaySectionFragment { rosterDayId }
            (rosterDaySectionDomId (coerce rosterDayId))
            (rosterWeekDaySectionFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId (coerce rosterDayId))
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath (RosterProjectionDaySection rosterDayId))
    RosterProjectionRow rosterDayId rowIndex ->
        mkSurfaceFragmentRef
            RosterRowFragment { rosterDayId, rowIndex }
            (rosterRowDomIdText (coerce rosterDayId) rowIndex)
            (rosterWeekRowFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId (coerce rosterDayId) rowIndex)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath (RosterProjectionRow rosterDayId rowIndex))

rosterFragmentLoadPolicy :: RosterProjectionFragment -> FragmentContract RosterLiveSurface -> FragmentContract RosterLiveSurface
rosterFragmentLoadPolicy RosterProjectionStaffPanel =
    fragmentContractWithLazyLoad rosterStaffPanelLazyConfig
rosterFragmentLoadPolicy _ =
    id

rosterStaffPanelLazyConfig :: LazyFragmentConfig
rosterStaffPanelLazyConfig =
    LazyFragmentConfig
        { lazyFragmentTrigger = "load"
        , lazyFragmentPlaceholderKind = lazyFragmentPlaceholderTable
        , lazyFragmentAccessibleLabel = "Loading roster staff panel"
        , lazyFragmentClasses = ["col-12", "col-xl-4", "col-xxl-3", "roster-layout-side"]
        , lazyFragmentDelayMs = Just 50
        }

rosterFragmentDependencies :: UUID -> RosterProjectionScope -> RosterProjectionFragment -> FragmentDependencies
rosterFragmentDependencies venueId scope =
    \case
            RosterProjectionContent ->
                liveFragmentDependsOn
                    (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionGridToolbar ->
                liveFragmentDependsOn
                    (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionGridFrame ->
                liveFragmentDependsOn
                    (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionDayColumns ->
                liveFragmentDependsOn
                    (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionDayRail ->
                liveFragmentDependsOn
                    (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionWageRail ->
                liveFragmentDependsOn
                    (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionSlotsGrid ->
                liveFragmentDependsOn
                    (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionStaffPanel ->
                liveFragmentDependsOn (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset) []
            RosterProjectionDaySection rosterDayId ->
                liveFragmentDependsOn
                    (RosterDayResource rosterDayId)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionRow rosterDayId _ ->
                liveFragmentDependsOn
                    (RosterDayResource rosterDayId)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]

rosterFragmentContainmentPath :: RosterProjectionFragment -> [Text]
rosterFragmentContainmentPath = \case
    RosterProjectionContent ->
        [rosterContentFragmentId]
    RosterProjectionGridToolbar ->
        [rosterContentFragmentId, rosterGridToolbarFragmentId]
    RosterProjectionGridFrame ->
        [rosterContentFragmentId, rosterGridFrameFragmentId]
    RosterProjectionDayColumns ->
        [rosterContentFragmentId, rosterGridFrameFragmentId, rosterDayColumnsFragmentId]
    RosterProjectionDayRail ->
        [rosterContentFragmentId, rosterGridFrameFragmentId, rosterDayRailFragmentId]
    RosterProjectionWageRail ->
        [rosterContentFragmentId, rosterGridFrameFragmentId, rosterWageRailFragmentId]
    RosterProjectionSlotsGrid ->
        [rosterContentFragmentId, rosterGridFrameFragmentId, rosterSlotsGridFragmentId]
    RosterProjectionStaffPanel ->
        [rosterStaffPanelFragmentId]
    RosterProjectionDaySection rosterDayId ->
        [rosterContentFragmentId, rosterGridFrameFragmentId, rosterDaySectionDomId (coerce rosterDayId)]
    RosterProjectionRow rosterDayId rowIndex ->
        [rosterContentFragmentId, rosterGridFrameFragmentId, rosterDaySectionDomId (coerce rosterDayId), rosterRowDomIdText (coerce rosterDayId) rowIndex]

mkRosterProjectionDefinition ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    (RosterProjectionScope -> IO snapshot) ->
    (snapshot -> RosterProjectionFragment -> Maybe Blaze.Html) ->
    ProjectionLiveSurfaceDefinition RosterLiveSurface RosterProjectionScope snapshot RosterProjectionFragment
mkRosterProjectionDefinition =
    mkTypedSurfaceProjectionDefinition
        rosterLiveSurfaceDefinition
        "roster-week"
        defaultSurfaceProjectionCachePolicy
        (\scope -> tshow scope.rosterProjectionGroupId <> ":" <> tshow scope.rosterProjectionWeekOffset)
        do
            filters <- fetchRosterAssignmentFilters
            layoutMode <- fetchCurrentRosterLayoutMode
            userShowWageEstimates <- fetchCurrentUserShowWageEstimates
            showRosterWarnings <- fetchCurrentUserShowRosterWarnings
            let showWageEstimates = hasRole VenueAdminRole && userShowWageEstimates
            pure (tshow currentUser.id <> ":" <> encodeRosterAssignmentFilters filters <> ":" <> rosterLayoutModeValue layoutMode <> ":" <> (if showWageEstimates then "wages" else "no-wages") <> ":" <> (if showRosterWarnings then "warnings" else "no-warnings"))
        rosterProjectionVersion

rosterProjectionVersion :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterProjectionScope -> IO Int
rosterProjectionVersion scope = do
    rosterVersion <- currentLiveUpdateVersion (buildRosterWeekScope scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset)
    if hasRole ManagerRole' || currentUserIsSuperAdmin
        then pure rosterVersion
        else do
            venueConfig <- fetchVenueConfig
            operationalDay <- currentOperationalDayForVenue venueConfig
            let timesheetWeekOffset = venueWeekOffsetForDay venueConfig operationalDay
            timesheetVersion <- currentLiveUpdateVersion TimesheetWeekScope { venueId = unpackId currentVenueId, weekOffset = timesheetWeekOffset }
            leaveVersion <- currentLiveUpdateVersion LeaveRequestsScope { venueId = unpackId currentVenueId }
            pure (rosterVersion + timesheetVersion + leaveVersion + fromInteger (Calendar.toModifiedJulianDay operationalDay))
