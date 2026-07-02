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
import qualified Application.Helper.FrontendSurface.ContractIR as SurfaceIR
import Application.Helper.FrontendSurface.Reflect (reflectRegisteredFrontendSurfaces)
import qualified Application.Helper.FrontendSurface.Roster as FrontendRosterSurface
import Application.Helper.FrontendSurface.Runtime (FrontendSurfaceHtmxMethod (..),
                                                   FrontendSurfaceHtmxRequest (..),
                                                   FrontendSurfaceIntentForm (..),
                                                   SurfaceImpl (..))
import Application.Helper.Interaction
import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveUpdateScope (..),
                                      currentLiveUpdateVersion)
import Application.Helper.SurfaceProjection
import Application.Helper.UiRegion (UiRegionTransitionProfile (..))
import Application.Helper.UserPreferences
import Data.Coerce (coerce)
import qualified Data.Time.Calendar as Calendar
import Data.UUID (UUID)
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Filters
import qualified Web.RosterWeeks.FrontendSurface as FrontendSurface
import Web.RosterWeeks.Paths (rosterWeekContentFragmentUrl,
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
    rosterLiveSurfaceDefinitionForVenue (unpackId currentVenueId)

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
        , typedSurfaceInteraction = rosterInteractionCapability surfaceVenueId
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

-- Temporary compatibility adapter while the Roster view still renders through
-- Application.Helper.Interaction. The source of truth is the Roster
-- FrontendSurface IR; remove this projection when Roster gets native
-- FrontendSurface interaction render helpers.
rosterInteractionStaticSchema :: InteractionStaticSchema RosterProjectionFragment RosterInteractionLayer RosterInteractionSession RosterInteractionIntent
rosterInteractionStaticSchema =
    rosterFrontendSurfaceInteractionStaticSchema rosterFrontendSurfaceIR

rosterFrontendSurfaceIR :: SurfaceIR.SurfaceIR
rosterFrontendSurfaceIR =
    fromMaybe (error "registered FrontendSurface 'roster' is missing") do
        find ((== "roster") . (.surfaceName)) reflectRegisteredFrontendSurfaces.contractSurfaces

rosterFrontendSurfaceInteractionStaticSchema :: SurfaceIR.SurfaceIR -> InteractionStaticSchema RosterProjectionFragment RosterInteractionLayer RosterInteractionSession RosterInteractionIntent
rosterFrontendSurfaceInteractionStaticSchema surface =
    emptyInteractionStaticSchema
        { interactionStaticDisposableLayers = expectMappedRosterSurfaceIR "disposable layer" rosterDisposableLayerFromName surface.surfaceLayers
        , interactionStaticSessionKinds = expectMappedRosterSurfaceIR "session" (rosterSessionKindFromName surface) surface.surfaceSessions
        , interactionStaticIntents = expectMappedRosterSurfaceIR "intent" rosterIntentSchemaFromIR surface.surfaceIntents
        , interactionStaticConflictPolicies = expectMappedRosterSurfaceIR "conflict policy" rosterConflictPolicyFromIR surface.surfacePolicies
        }

expectMappedRosterSurfaceIR :: Show input => Text -> (input -> Maybe output) -> [input] -> [output]
expectMappedRosterSurfaceIR label convert =
    fmap \input -> fromMaybe (error ("unsupported Roster FrontendSurface " <> cs label <> ": " <> show input)) (convert input)

rosterDisposableLayerFromName :: Text -> Maybe (DisposableLayerDefinition RosterInteractionLayer)
rosterDisposableLayerFromName "drag-preview" = Just DisposableLayerDefinition
    { disposableLayerKind = RosterDragPreviewLayer
    , disposableLayerName = "drag-preview"
    , disposableLayerDomIdSuffix = "drag-preview"
    }
rosterDisposableLayerFromName _ = Nothing

rosterSessionKindFromName :: SurfaceIR.SurfaceIR -> Text -> Maybe (SessionKindDefinition RosterInteractionSession)
rosterSessionKindFromName surface "drag" = Just SessionKindDefinition
    { sessionKind = RosterDragSession
    , sessionKindName = rosterDragSessionKindName
    , sessionDescription = "Roster drag/drop prototype"
    , sessionEffects = rosterSessionEffectsFromIR surface.surfaceEffects
    }
rosterSessionKindFromName _ _ = Nothing

rosterSessionEffectsFromIR :: [(Text, [SurfaceIR.OptionIR])] -> InteractionSessionEffects
rosterSessionEffectsFromIR effects = InteractionSessionEffects
    { interactionSessionGlobalEffects = mapMaybe rosterGlobalEffectFromIR effects
    , interactionSessionContextualEffects = mapMaybe rosterContextualEffectFromIR effects
    }

rosterGlobalEffectFromIR :: (Text, [SurfaceIR.OptionIR]) -> Maybe InteractionSessionGlobalEffect
rosterGlobalEffectFromIR ("clone-shadow", options) = Just InteractionCloneShadowEffect
    { cloneShadowLayerName = fromMaybe "drag-preview" (firstLayerOption options)
    , cloneShadowSource = InteractionEffectPointerMarker
    , cloneShadowClassName = "bepis-pointer-clone-shadow"
    , cloneShadowPreserveGrabOffset = True
    }
rosterGlobalEffectFromIR _ = Nothing

rosterContextualEffectFromIR :: (Text, [SurfaceIR.OptionIR]) -> Maybe InteractionSessionContextualEffect
rosterContextualEffectFromIR ("dropzone-highlight", _) = Just InteractionDropzoneHighlightEffect
    { dropzoneHighlightClassName = "bepis-dropzone-highlight"
    }
rosterContextualEffectFromIR _ = Nothing

firstLayerOption :: [SurfaceIR.OptionIR] -> Maybe Text
firstLayerOption options = listToMaybe (mapMaybe layerName options)
    where
        layerName = \case
            SurfaceIR.LayerOption layer -> Just layer
            _                           -> Nothing

rosterIntentSchemaFromIR :: SurfaceIR.IntentIR -> Maybe (InteractionIntentSchema RosterInteractionIntent)
rosterIntentSchemaFromIR intent = do
    rosterIntent <- rosterIntentFromName intent.intentName
    pure InteractionIntentSchema
        { interactionIntentSchemaIntent = rosterIntent
        , interactionIntentSchemaName = intent.intentName
        , interactionIntentSchemaFields = fmap rosterIntentFieldFromIR intent.intentFields
        }

rosterIntentFromName :: Text -> Maybe RosterInteractionIntent
rosterIntentFromName "set-roster-layout-mode" = Just SetRosterLayoutModeIntent
rosterIntentFromName "move-roster-shift-to-slot" = Just MoveRosterShiftToSlotIntent
rosterIntentFromName _ = Nothing

rosterIntentFieldFromIR :: SurfaceIR.FieldIR -> IntentFieldSchema
rosterIntentFieldFromIR field = IntentFieldSchema
    { intentFieldName = IntentFieldName field.fieldName
    , intentFieldPresence = rosterFieldPresenceFromIR field.fieldPresence
    , intentFieldDefaultValue = Nothing
    }

rosterFieldPresenceFromIR :: SurfaceIR.FieldPresence -> InteractionFieldPresence
rosterFieldPresenceFromIR SurfaceIR.RequiredField         = IntentFieldRequired
rosterFieldPresenceFromIR SurfaceIR.OptionalFieldPresence = IntentFieldOptional
rosterFieldPresenceFromIR SurfaceIR.NullableFieldPresence = IntentFieldOptional

rosterConflictPolicyFromIR :: SurfaceIR.ConflictPolicyIR -> Maybe (InteractionConflictPolicy RosterProjectionFragment RosterInteractionSession)
rosterConflictPolicyFromIR policy = do
    session <- rosterSessionSelectorFromIR policy.conflictPolicySession
    fragment <- rosterFragmentSelectorFromIR policy.conflictPolicyFragment
    pure InteractionConflictPolicy
        { conflictPolicySession = session
        , conflictPolicyFragment = fragment
        , conflictPolicyResolution = rosterConflictResolutionFromIR policy.conflictPolicyResolution
        , conflictPolicyTimeoutMs = rosterConflictPolicyTimeout policy
        }

rosterSessionSelectorFromIR :: SurfaceIR.SessionSelectorIR -> Maybe (InteractionSessionSelector RosterInteractionSession)
rosterSessionSelectorFromIR SurfaceIR.AnySessionIR = Just AnyInteractionSession
rosterSessionSelectorFromIR (SurfaceIR.SessionKindIR "drag") = Just (InteractionSessionKind RosterDragSession)
rosterSessionSelectorFromIR _ = Nothing

rosterFragmentSelectorFromIR :: SurfaceIR.FragmentSelectorIR -> Maybe (InteractionFragmentSelector RosterProjectionFragment)
rosterFragmentSelectorFromIR SurfaceIR.AnyFragmentIR = Just AnyInteractionFragment
rosterFragmentSelectorFromIR SurfaceIR.FragmentKindIR {} = Just AnyInteractionFragment
rosterFragmentSelectorFromIR SurfaceIR.FragmentSubtreeIR {} = Just AnyInteractionFragment

rosterConflictResolutionFromIR :: SurfaceIR.ConflictResolutionIR -> InteractionConflictResolution
rosterConflictResolutionFromIR SurfaceIR.ApplyIR = ApplyLiveFragmentImmediately
rosterConflictResolutionFromIR SurfaceIR.DeferIR = DeferLiveFragmentUntilSessionEnds
rosterConflictResolutionFromIR SurfaceIR.CancelIR = CancelSessionAndApplyLiveFragment

rosterConflictPolicyTimeout :: SurfaceIR.ConflictPolicyIR -> Maybe Int
rosterConflictPolicyTimeout policy =
    case policy.conflictPolicyResolution of
        SurfaceIR.DeferIR -> Just 5000
        _                 -> Nothing

rosterInteractionCapability :: UUID -> RosterProjectionScope -> InteractionCapability (SurfaceFragmentRef RosterLiveSurface) RosterProjectionFragment RosterInteractionLayer RosterInteractionSession RosterInteractionIntent
rosterInteractionCapability surfaceVenueId scope =
    let impl = rosterFrontendSurfaceImpl surfaceVenueId scope
     in emptyInteractionCapability
            { interactionStaticSchema = rosterInteractionStaticSchema
            , interactionServerLayers = rosterInteractionStaticSchema.interactionStaticServerLayers
            , interactionDisposableLayers = rosterInteractionStaticSchema.interactionStaticDisposableLayers
            , interactionSessionKinds = rosterInteractionStaticSchema.interactionStaticSessionKinds
            , interactionIntentForms = expectMappedRosterSurfaceIR "intent form" (rosterFrontendSurfaceIntentForm scope) impl.surfaceImplIntents
            , interactionConflictPolicies = rosterInteractionStaticSchema.interactionStaticConflictPolicies
            }

rosterFrontendSurfaceImpl :: UUID -> RosterProjectionScope -> SurfaceImpl FrontendRosterSurface.RosterSurface
rosterFrontendSurfaceImpl surfaceVenueId scope =
    FrontendSurface.rosterSurfaceImpl
        FrontendSurface.RosterWeekScopeValue
            { rosterWeekVenueId = surfaceVenueId
            , rosterWeekGroupId = scope.rosterProjectionGroupId
            , rosterWeekWeekOffset = scope.rosterProjectionWeekOffset
            }
        FrontendSurface.RosterMountedFragmentPlan
            { rosterMountedDayIds = []
            , rosterMountedRows = []
            }

rosterFrontendSurfaceIntentForm :: RosterProjectionScope -> FrontendSurfaceIntentForm -> Maybe (IntentFormContract (SurfaceFragmentRef RosterLiveSurface) RosterInteractionIntent)
rosterFrontendSurfaceIntentForm scope FrontendSurfaceIntentForm { intentFormName, intentFormSubmit } = do
    intent <- rosterIntentFromName intentFormName
    schema <- find ((== intentFormName) . (.interactionIntentSchemaName)) rosterInteractionStaticSchema.interactionStaticIntents
    pure IntentFormContract
        { intentFormIntent = intent
        , intentFormName
        , intentFormAction = intentFormSubmit.htmxRequestUrl
        , intentFormMethod = frontendSurfaceHtmxMethodToInteraction intentFormSubmit.htmxRequestMethod
        , intentFormTrigger = interactionIntentSubmitHtmxTrigger
        , intentFormTarget = rosterFrontendSurfaceIntentTarget scope intentFormSubmit
        , intentFormSwap = frontendSurfaceHtmxSwapToInteraction intentFormSubmit.htmxRequestSwap
        , intentFormFields = schema.interactionIntentSchemaFields
        , intentFormHiddenFields = []
        , intentFormSync = Just ("#" <> rosterWeekShellId <> ":replace")
        , intentFormDisabledElement = Nothing
        }

rosterFrontendSurfaceIntentTarget :: RosterProjectionScope -> FrontendSurfaceHtmxRequest -> InteractionIntentTarget (SurfaceFragmentRef RosterLiveSurface)
rosterFrontendSurfaceIntentTarget scope request
    | request.htmxRequestTarget == "#" <> rosterContentFragmentId = IntentTargetLiveFragment (rosterFragmentRef scope RosterProjectionContent)
    | otherwise = IntentTargetLiveFragment (rosterFragmentRef scope RosterProjectionContent)

frontendSurfaceHtmxMethodToInteraction :: FrontendSurfaceHtmxMethod -> HtmxMethod
frontendSurfaceHtmxMethodToInteraction = \case
    FrontendSurfaceGet  -> HtmxGet
    FrontendSurfacePost -> HtmxPost

frontendSurfaceHtmxSwapToInteraction :: Text -> HtmxSwap
frontendSurfaceHtmxSwapToInteraction = \case
    "innerHTML" -> HtmxSwapInnerHtml
    "outerHTML" -> HtmxSwapOuterHtml
    "beforeend" -> HtmxSwapBeforeEnd
    "afterbegin" -> HtmxSwapAfterBegin
    "none" -> HtmxSwapNone
    value -> HtmxSwapCustom value

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
rosterFragmentLoadPolicy RosterProjectionStaffPanel contract =
    fragmentContractWithLazyLoad rosterStaffPanelLazyConfig contract
rosterFragmentLoadPolicy _ contract =
    contract

rosterStaffPanelLazyConfig :: LazyFragmentConfig
rosterStaffPanelLazyConfig =
    LazyFragmentConfig
        { lazyFragmentTrigger = "load"
        , lazyFragmentPlaceholderKind = lazyFragmentPlaceholderCustom
        , lazyFragmentAccessibleLabel = "Loading roster staff panel"
        , lazyFragmentClasses = rosterStaffPanelFragmentClasses
        , lazyFragmentDelayMs = Nothing
        , lazyFragmentTransition = UiRegionTransitionPanel
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
