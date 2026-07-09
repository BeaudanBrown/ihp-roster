{-# LANGUAGE BlockArguments   #-}
{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.RosterWeeks.FrontendSurface
    ( RosterDayTimelineScopeValue (..)
    , RosterMountedFragmentPlan (..)
    , RosterWeekScopeValue (..)
    , rosterCandidateMountedFragments
    , rosterMountedFragmentForProjection
    , rosterDayColumnDropzoneRef
    , rosterDeleteShiftDropzoneRef
    , rosterDragDropzoneRef
    , rosterDragSessionKindName
    , rosterDragSourceRef
    , rosterExistingShiftDropzoneRef
    , rosterStaffCreateDropzoneRef
    , rosterShiftSlotDropzoneRef
    , rosterStaffDragSourceRef
    , rosterInteractionMountKey
    , rosterLayoutModeActivationRef
    , rosterLayoutModeIntentFieldName
    , rosterLayoutModeIntentName
    , rosterSurfaceScope
    , rosterMountedFragmentPlanFromRenderData
    , rosterMoveShiftIntentName
    , rosterFrontendSurfaceIR
    , rosterDayTimelineDropzoneRef
    , rosterDayTimelineFrontendSurfaceIR
    , rosterDayTimelineMoveShiftIntentName
    , rosterDayTimelineSourceRef
    , rosterDayTimelineSurfaceImpl
    , rosterSurfaceImpl
    , rosterSurfaceMountConfig
    , rosterSurfaceAction
    , rosterSurfaceScopeKey
    , rosterSurfaceWireFragments
    ) where

import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.DSL
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import Application.Helper.FrontendContract.Surface.Reflect (reflectRegisteredFrontendSurfaces)
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.LiveUpdate.Runtime
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import Data.Coerce (coerce)
import qualified Data.Map.Strict as Map
import qualified Data.UUID as UUID
import Generated.Types
import Web.Controller.Prelude
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Paths (rosterDayTimelineContentFragmentUrl,
                              rosterDropStaffUrl, rosterDuplicateShiftUrl,
                              rosterLayoutPreferenceUrl, rosterMoveShiftUrl,
                              rosterOverviewFragmentUrl,
                              rosterTimelineMoveShiftUrl,
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
import Web.RosterWeeks.Types (RosterProjectionFragment (..),
                              RosterRenderIndexes (..))

-- | Logical roster week live invalidation scope. Viewer-specific preferences and
-- visibility stay server-owned; the scope identifies the authorized data slice.
data RosterWeekScopeValue = RosterWeekScopeValue
    { rosterWeekVenueId           :: !UUID.UUID
    , rosterWeekGroupId           :: !(Id RosterGroup)
    , rosterWeekWeekOffset        :: !Int
    , rosterWeekTimelineDayOffset :: !(Maybe Int)
    }
    deriving (Eq, Show)

data RosterDayTimelineScopeValue = RosterDayTimelineScopeValue
    { rosterDayTimelineVenueId    :: !UUID.UUID
    , rosterDayTimelineGroupId    :: !(Id RosterGroup)
    , rosterDayTimelineWeekOffset :: !Int
    , rosterDayTimelineDayOffset  :: !Int
    , rosterDayTimelineDayId      :: !(Id RosterDay)
    }
    deriving (Eq, Show)

data RosterMountedFragmentPlan = RosterMountedFragmentPlan
    { rosterMountedDayIds :: ![Id RosterDay]
    , rosterMountedRows   :: ![(Id RosterDay, Int)]
    }
    deriving (Eq, Show)


rosterMountedFragmentPlanFromRenderData :: [RosterDay] -> RosterRenderIndexes -> RosterMountedFragmentPlan
rosterMountedFragmentPlanFromRenderData rosterDays renderIndexes =
    RosterMountedFragmentPlan
        { rosterMountedDayIds = map (.id) rosterDays
        , rosterMountedRows = do
            rosterDay <- rosterDays
            (rowIndex, _) <- fromMaybe [] (Map.lookup (unpackId rosterDay.id) renderIndexes.rosterDayRowsByDayId)
            pure (rosterDay.id, rowIndex)
        }

rosterSurfaceImpl :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> SurfaceImpl Surface.RosterSurface
rosterSurfaceImpl scope plan =
    mkSurfaceImpl "roster" (rosterSurfaceMountConfig scope plan) (rosterSurfaceHandlers scope plan)
        |> surfaceImplWithMountedFragments (rosterCandidateMountedFragments scope plan)

rosterDayTimelineSurfaceImpl :: RosterDayTimelineScopeValue -> SurfaceImpl Surface.RosterDayTimelineSurface
rosterDayTimelineSurfaceImpl scope =
    mkSurfaceImpl "roster-day-timeline" (rosterDayTimelineSurfaceMountConfig scope) (rosterDayTimelineSurfaceHandlers scope)
        |> surfaceImplWithMountedFragments (rosterDayTimelineCandidateMountedFragments scope)

rosterSurfaceMountConfig :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> FrontendSurfaceMountConfig
rosterSurfaceMountConfig scope plan =
    FrontendSurfaceMountConfig
        { mountSurfaceName = "roster"
        , mountScopeKey = rosterSurfaceScopeKey scope
        , mountKey = "primary"
        , mountScope = Aeson.Null
        , mountSubscription = Nothing
        , mountState = Aeson.object []
        , mountFragments = rosterCandidateMountedFragments scope plan
        }

rosterDayTimelineSurfaceMountConfig :: RosterDayTimelineScopeValue -> FrontendSurfaceMountConfig
rosterDayTimelineSurfaceMountConfig scope =
    FrontendSurfaceMountConfig
        { mountSurfaceName = "roster-day-timeline"
        , mountScopeKey = rosterDayTimelineSurfaceScopeKey scope
        , mountKey = tshow scope.rosterDayTimelineDayId
        , mountScope = Aeson.Null
        , mountSubscription = Nothing
        , mountState = Aeson.object []
        , mountFragments = rosterDayTimelineCandidateMountedFragments scope
        }

rosterSurfaceScopeKey :: RosterWeekScopeValue -> Text
rosterSurfaceScopeKey scope =
    "roster:" <> tshow scope.rosterWeekVenueId <> ":" <> tshow scope.rosterWeekGroupId <> ":" <> tshow scope.rosterWeekWeekOffset

rosterDayTimelineSurfaceScopeKey :: RosterDayTimelineScopeValue -> Text
rosterDayTimelineSurfaceScopeKey scope =
    "roster-day-timeline:"
        <> tshow scope.rosterDayTimelineVenueId
        <> ":"
        <> tshow scope.rosterDayTimelineGroupId
        <> ":"
        <> tshow scope.rosterDayTimelineWeekOffset
        <> ":"
        <> tshow scope.rosterDayTimelineDayId

rosterInteractionMountKey :: Text
rosterInteractionMountKey = "primary"

rosterDragSessionKindName :: Text
rosterDragSessionKindName = "drag"

rosterLayoutModeIntentName :: Text
rosterLayoutModeIntentName = "set-roster-layout-mode"

rosterLayoutModeIntentFieldName :: Text
rosterLayoutModeIntentFieldName = "rosterLayoutMode"

rosterMoveShiftIntentName :: Text
rosterMoveShiftIntentName = "move-roster-shift-to-slot"

rosterDayTimelineMoveShiftIntentName :: Text
rosterDayTimelineMoveShiftIntentName = "move-roster-timeline-shift"

rosterDuplicateShiftIntentName :: Text
rosterDuplicateShiftIntentName = "duplicate-roster-shift-to-day"

rosterDragSourceRef :: SurfaceIR.InteractionSourceRefIR
rosterDragSourceRef = rosterShiftDragSourceRef

rosterShiftDragSourceRef :: SurfaceIR.InteractionSourceRefIR
rosterShiftDragSourceRef = expectSourceRef "shift-drag-source"

rosterStaffDragSourceRef :: SurfaceIR.InteractionSourceRefIR
rosterStaffDragSourceRef = expectSourceRef "staff-drag-source"

rosterDragDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterDragDropzoneRef = rosterShiftSlotDropzoneRef

rosterShiftSlotDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterShiftSlotDropzoneRef = expectDropzoneRef "shift-slot-dropzone"

rosterStaffCreateDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterStaffCreateDropzoneRef = expectDropzoneRef "staff-create-dropzone"

rosterDayColumnDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterDayColumnDropzoneRef = expectDropzoneRef "day-column-dropzone"

rosterExistingShiftDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterExistingShiftDropzoneRef = expectDropzoneRef "existing-shift-dropzone"

rosterDeleteShiftDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterDeleteShiftDropzoneRef = expectDropzoneRef "delete-shift-dropzone"

rosterDayTimelineSourceRef :: SurfaceIR.InteractionSourceRefIR
rosterDayTimelineSourceRef = expectOne "timeline source ref" rosterDayTimelineFrontendSurfaceIR.surfaceSourceRefs

rosterDayTimelineDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterDayTimelineDropzoneRef = expectOne "timeline dropzone ref" rosterDayTimelineFrontendSurfaceIR.surfaceDropzoneRefs

rosterLayoutModeActivationRef :: SurfaceIR.InteractionActivationRefIR
rosterLayoutModeActivationRef = expectOne "activation ref" rosterFrontendSurfaceIR.surfaceActivationRefs

expectOne :: Text -> [value] -> value
expectOne label values =
    case values of
        [value] -> value
        []      -> error ("missing roster " <> cs label)
        _       -> error ("multiple roster " <> cs label <> " declarations")

expectSourceRef :: Text -> SurfaceIR.InteractionSourceRefIR
expectSourceRef refName =
    fromMaybe (error ("missing roster source ref: " <> cs refName)) do
        find ((== refName) . (.sourceRefName)) rosterFrontendSurfaceIR.surfaceSourceRefs

expectDropzoneRef :: Text -> SurfaceIR.InteractionDropzoneRefIR
expectDropzoneRef refName =
    fromMaybe (error ("missing roster dropzone ref: " <> cs refName)) do
        find ((== refName) . (.dropzoneRefName)) rosterFrontendSurfaceIR.surfaceDropzoneRefs

rosterFrontendSurfaceIR :: SurfaceIR.SurfaceIR
rosterFrontendSurfaceIR =
    fromMaybe (error "registered FrontendSurface 'roster' is missing") do
        find ((== "roster") . (.surfaceName)) reflectRegisteredFrontendSurfaces.contractSurfaces

rosterDayTimelineFrontendSurfaceIR :: SurfaceIR.SurfaceIR
rosterDayTimelineFrontendSurfaceIR =
    fromMaybe (error "registered FrontendSurface 'roster-day-timeline' is missing") do
        find ((== "roster-day-timeline") . (.surfaceName)) reflectRegisteredFrontendSurfaces.contractSurfaces

rosterSurfaceScope :: RosterWeekScopeValue -> SurfaceScope
rosterSurfaceScope scope =
    rosterWeekLiveScope scope.rosterWeekVenueId (unpackId scope.rosterWeekGroupId) scope.rosterWeekWeekOffset

rosterSurfaceWireFragments :: [FrontendSurfaceMountedFragment] -> [SurfaceWireFragment]
rosterSurfaceWireFragments =
    frontendSurfaceMountedFragmentsToWire "roster"

rosterCandidateMountedFragments :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> [FrontendSurfaceMountedFragment]
rosterCandidateMountedFragments scope plan =
    case scope.rosterWeekTimelineDayOffset of
        Just _  -> rosterTimelineModeMountedFragments scope
        Nothing -> rosterWeekGridMountedFragments scope plan

rosterTimelineModeMountedFragments :: RosterWeekScopeValue -> [FrontendSurfaceMountedFragment]
rosterTimelineModeMountedFragments scope =
    [ rosterGridToolbarMountedFragment scope
    , rosterGridFrameMountedFragment scope
    , rosterStaffPanelMountedFragment scope
    ]

rosterWeekGridMountedFragments :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> [FrontendSurfaceMountedFragment]
rosterWeekGridMountedFragments scope plan =
    [ rosterContentMountedFragment scope
    , rosterGridToolbarMountedFragment scope
    , rosterGridFrameMountedFragment scope
    , rosterDayColumnsMountedFragment scope
    , rosterDayRailMountedFragment scope
    , rosterWageRailMountedFragment scope
    , rosterSlotsGridMountedFragment scope
    , rosterStaffPanelMountedFragment scope
    ]
        <> map (rosterDaySectionMountedFragment scope) plan.rosterMountedDayIds
        <> map (uncurry (rosterRowMountedFragment scope)) plan.rosterMountedRows

rosterDayTimelineCandidateMountedFragments :: RosterDayTimelineScopeValue -> [FrontendSurfaceMountedFragment]
rosterDayTimelineCandidateMountedFragments scope =
    [rosterDayTimelineContentMountedFragment scope]

rosterMountedFragmentForProjection :: RosterWeekScopeValue -> RosterProjectionFragment -> FrontendSurfaceMountedFragment
rosterMountedFragmentForProjection scope = \case
    RosterProjectionContent -> rosterContentMountedFragment scope
    RosterProjectionGridToolbar -> rosterGridToolbarMountedFragment scope
    RosterProjectionGridFrame -> rosterGridFrameMountedFragment scope
    RosterProjectionDayColumns -> rosterDayColumnsMountedFragment scope
    RosterProjectionDayRail -> rosterDayRailMountedFragment scope
    RosterProjectionWageRail -> rosterWageRailMountedFragment scope
    RosterProjectionSlotsGrid -> rosterSlotsGridMountedFragment scope
    RosterProjectionStaffPanel -> rosterStaffPanelMountedFragment scope
    RosterProjectionDaySection rosterDayId -> rosterDaySectionMountedFragment scope (Id rosterDayId)
    RosterProjectionRow rosterDayId rowIndex -> rosterRowMountedFragment scope (Id rosterDayId) rowIndex

rosterDayTimelineSurfaceHandlers :: RosterDayTimelineScopeValue -> SurfaceImplHandlers Surface.RosterDayTimelineSurface
rosterDayTimelineSurfaceHandlers scope =
    SurfaceImplHandlers
        { surfaceScopeHandlers =
            FrontendSurfaceScopeHandler
                { scopeHandlerDefaultValue = rosterDayTimelineScopeFields scope
                , scopeHandlerKey = \fields ->
                    let venueId = fromMaybe (tshow scope.rosterDayTimelineVenueId) (getSurfaceField @Surface.VenueId fields)
                        rosterGroupId = fromMaybe (tshow scope.rosterDayTimelineGroupId) (getSurfaceField @Surface.RosterGroupId fields)
                        weekOffset = fromMaybe scope.rosterDayTimelineWeekOffset (getSurfaceField @Surface.WeekOffset fields)
                        rosterDayId = fromMaybe (tshow scope.rosterDayTimelineDayId) (getSurfaceField @Surface.RosterDayId fields)
                     in "roster-day-timeline:" <> venueId <> ":" <> rosterGroupId <> ":" <> tshow weekOffset <> ":" <> rosterDayId
                }
                `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers =
            FrontendSurfaceFragmentHandler
                { fragmentHandlerDefaultParams = frontendSurfaceFieldValues (Aeson.object ["rosterDayId" Aeson..= tshow scope.rosterDayTimelineDayId])
                , fragmentHandlerMountedFragment = \fields ->
                    let rosterDayId = maybe scope.rosterDayTimelineDayId coerce (getSurfaceField @Surface.RosterDayId fields >>= UUID.fromString . cs)
                     in rosterDayTimelineContentMountedFragment scope { rosterDayTimelineDayId = rosterDayId }
                , fragmentHandlerRender = const mempty
                }
                `HandlerCons` HandlerNil
        , surfaceActionHandlers =
            FrontendSurfaceActionHandler
                { actionHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["sourceItemKey" Aeson..= ("" :: Text), "targetDropzoneKey" Aeson..= ("" :: Text)])
                , actionHandlerRequest = rosterDayTimelineMoveShiftRequest scope
                }
                `HandlerCons` HandlerNil
        , surfaceIntentHandlers =
            FrontendSurfaceIntentHandler
                { intentHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["sourceItemKey" Aeson..= ("" :: Text), "targetDropzoneKey" Aeson..= ("" :: Text)])
                , intentHandlerForm = \fields -> FrontendSurfaceIntentForm "move-roster-timeline-shift" (rosterDayTimelineMoveShiftRequest scope fields)
                }
                `HandlerCons` HandlerNil
        }

rosterSurfaceHandlers :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> SurfaceImplHandlers Surface.RosterSurface
rosterSurfaceHandlers scope _plan =
    SurfaceImplHandlers
        { surfaceScopeHandlers =
            FrontendSurfaceScopeHandler
                { scopeHandlerDefaultValue = rosterWeekScopeFields scope
                , scopeHandlerKey = \fields ->
                    let venueId = fromMaybe (tshow scope.rosterWeekVenueId) (getSurfaceField @Surface.VenueId fields)
                        rosterGroupId = fromMaybe (tshow scope.rosterWeekGroupId) (getSurfaceField @Surface.RosterGroupId fields)
                        weekOffset = fromMaybe scope.rosterWeekWeekOffset (getSurfaceField @Surface.WeekOffset fields)
                     in "roster:" <> venueId <> ":" <> rosterGroupId <> ":" <> tshow weekOffset
                }
                `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers =
            FrontendSurfaceFragmentHandler
                { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                , fragmentHandlerMountedFragment = const (rosterContentMountedFragment scope)
                , fragmentHandlerRender = const mempty
                }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterGridToolbarMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterGridFrameMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterDayColumnsMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterDayRailMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterWageRailMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterSlotsGridMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterStaffPanelMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (rosterWeekOverviewMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues (Aeson.object ["rosterDayId" Aeson..= tshow placeholderRosterDayId])
                    , fragmentHandlerMountedFragment = \fields ->
                        let rosterDayId = maybe (coerce placeholderRosterDayId) coerce (getSurfaceField @Surface.RosterDayId fields >>= UUID.fromString . cs)
                         in rosterDaySectionMountedFragment scope rosterDayId
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues (Aeson.object ["rosterDayId" Aeson..= tshow placeholderRosterDayId, "rowIndex" Aeson..= (0 :: Int)])
                    , fragmentHandlerMountedFragment = \fields ->
                        let rosterDayId = maybe (coerce placeholderRosterDayId) coerce (getSurfaceField @Surface.RosterDayId fields >>= UUID.fromString . cs)
                            rowIndex = fromMaybe 0 (getSurfaceField @Surface.RowIndex fields)
                         in rosterRowMountedFragment scope rosterDayId rowIndex
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` HandlerNil
        , surfaceActionHandlers =
            rosterActionHandler "navigate-roster-week" (pathTo (ShowRosterWeekAction scope.rosterWeekWeekOffset)) `HandlerCons`
            rosterActionHandler "toggle-roster-warnings" (rosterLayoutPreferenceUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId) `HandlerCons`
            rosterActionHandler "toggle-roster-wage-estimates" (rosterLayoutPreferenceUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId) `HandlerCons`
            rosterActionHandler "sort-roster-week" (pathTo (SortRosterWeekAction (Id placeholderRosterDayId))) `HandlerCons`
            rosterActionHandler "toggle-roster-week-live-status" (pathTo (ToggleRosterWeekLiveStatusAction (Id placeholderRosterDayId))) `HandlerCons`
            rosterActionHandler "toggle-roster-assignment-filters" (rosterLayoutPreferenceUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId) `HandlerCons`
            rosterActionHandler "copy-roster-week" (pathTo (CopyRosterWeekAction 0 scope.rosterWeekWeekOffset)) `HandlerCons`
            rosterActionHandler "create-roster-self-service-leave-request" (pathTo CreateLeaveRequestAction) `HandlerCons`
            rosterActionHandler "create-roster-week-slot-definition" (pathTo (CreateRosterWeekSlotDefinitionAction (Id placeholderRosterDayId))) `HandlerCons`
            rosterActionHandler "delete-roster-week-slot-definition" (pathTo (DeleteRosterWeekSlotDefinitionAction (Id placeholderRosterDayId))) `HandlerCons`
            rosterActionHandler "toggle-roster-day-closed" (pathTo (ToggleRosterDayClosedAction (Id placeholderRosterDayId))) `HandlerCons`
            rosterActionHandler "add-roster-row" (pathTo (AddRosterRowAction (Id placeholderRosterDayId))) `HandlerCons`
            rosterActionHandler "remove-roster-row" (pathTo (RemoveRosterRowAction (Id placeholderRosterDayId))) `HandlerCons`
            rosterActionHandler "toggle-roster-staff-scope" (pathTo (ShowRosterWeekStaffPanelFragmentAction scope.rosterWeekWeekOffset)) `HandlerCons`
            FrontendSurfaceActionHandler
                { actionHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["rosterLayoutMode" Aeson..= ("day_rows" :: Text)])
                , actionHandlerRequest = rosterLayoutModeRequest scope
                }
                `HandlerCons` FrontendSurfaceActionHandler
                    { actionHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["sourceItemKey" Aeson..= ("" :: Text), "targetDropzoneKey" Aeson..= ("" :: Text)])
                    , actionHandlerRequest = rosterMoveShiftRequest scope
                    }
                `HandlerCons` FrontendSurfaceActionHandler
                    { actionHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["sourceItemKey" Aeson..= ("" :: Text), "targetDropzoneKey" Aeson..= ("" :: Text)])
                    , actionHandlerRequest = rosterDuplicateShiftRequest scope
                    }
                `HandlerCons` FrontendSurfaceActionHandler
                    { actionHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["sourceItemKey" Aeson..= ("" :: Text), "targetDropzoneKey" Aeson..= ("" :: Text)])
                    , actionHandlerRequest = rosterDropStaffRequest scope
                    }
                `HandlerCons` HandlerNil
        , surfaceIntentHandlers =
            FrontendSurfaceIntentHandler
                { intentHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["rosterLayoutMode" Aeson..= ("day_rows" :: Text)])
                , intentHandlerForm = \fields -> FrontendSurfaceIntentForm "set-roster-layout-mode" (rosterLayoutModeRequest scope fields)
                }
                `HandlerCons` FrontendSurfaceIntentHandler
                    { intentHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["sourceItemKey" Aeson..= ("" :: Text), "targetDropzoneKey" Aeson..= ("" :: Text)])
                    , intentHandlerForm = \fields -> FrontendSurfaceIntentForm "move-roster-shift-to-slot" (rosterMoveShiftRequest scope fields)
                    }
                `HandlerCons` FrontendSurfaceIntentHandler
                    { intentHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["sourceItemKey" Aeson..= ("" :: Text), "targetDropzoneKey" Aeson..= ("" :: Text)])
                    , intentHandlerForm = \fields -> FrontendSurfaceIntentForm "duplicate-roster-shift-to-day" (rosterDuplicateShiftRequest scope fields)
                    }
                `HandlerCons` FrontendSurfaceIntentHandler
                    { intentHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["sourceItemKey" Aeson..= ("" :: Text), "targetDropzoneKey" Aeson..= ("" :: Text)])
                    , intentHandlerForm = \fields -> FrontendSurfaceIntentForm "drop-roster-staff" (rosterDropStaffRequest scope fields)
                    }
                `HandlerCons` HandlerNil
        }

rosterActionHandler :: Text -> Text -> FrontendSurfaceActionHandler ('Action marker fields options)
rosterActionHandler actionName actionUrl = FrontendSurfaceActionHandler
    { actionHandlerDefaultFields = frontendSurfaceFieldValues Aeson.Null
    , actionHandlerRequest = const FrontendSurfaceHtmxRequest
        { htmxRequestName = actionName
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = actionUrl
        , htmxRequestTarget = ""
        , htmxRequestSwap = "none"
        , htmxRequestFields = []
        }
    }

rosterSurfaceAction :: Text -> SurfaceIR.HtmxActionIR
rosterSurfaceAction actionName =
    case [action | action <- rosterFrontendSurfaceIR.surfaceHtmxActions, action.htmxActionName == actionName] of
        action : _ -> action
        []         -> error ("missing roster surface action: " <> cs actionName)

rosterWeekScopeFields :: RosterWeekScopeValue -> FrontendSurfaceFieldValues '[ 'Field Surface.VenueId 'WireUUID, 'Field Surface.RosterGroupId 'WireUUID, 'Field Surface.WeekOffset 'WireInt]
rosterWeekScopeFields scope =
    frontendSurfaceFieldValues (Aeson.object
        [ "venueId" Aeson..= tshow scope.rosterWeekVenueId
        , "rosterGroupId" Aeson..= tshow scope.rosterWeekGroupId
        , "weekOffset" Aeson..= scope.rosterWeekWeekOffset
        ])

rosterDayTimelineScopeFields :: RosterDayTimelineScopeValue -> FrontendSurfaceFieldValues '[ 'Field Surface.VenueId 'WireUUID, 'Field Surface.RosterGroupId 'WireUUID, 'Field Surface.WeekOffset 'WireInt, 'Field Surface.RosterDayId 'WireUUID]
rosterDayTimelineScopeFields scope =
    frontendSurfaceFieldValues (Aeson.object
        [ "venueId" Aeson..= tshow scope.rosterDayTimelineVenueId
        , "rosterGroupId" Aeson..= tshow scope.rosterDayTimelineGroupId
        , "weekOffset" Aeson..= scope.rosterDayTimelineWeekOffset
        , "rosterDayId" Aeson..= tshow scope.rosterDayTimelineDayId
        ])

rosterLayoutModeRequest :: RosterWeekScopeValue -> FrontendSurfaceFieldValues '[ 'Field Surface.RosterLayoutMode 'WireText] -> FrontendSurfaceHtmxRequest
rosterLayoutModeRequest scope fields =
    FrontendSurfaceHtmxRequest
        { htmxRequestName = "set-roster-layout-mode"
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = rosterLayoutPreferenceUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , htmxRequestTarget = "#" <> rosterContentFragmentId
        , htmxRequestSwap = "none"
        , htmxRequestFields =
            [ FrontendSurfaceFieldValue "rosterLayoutMode" (fromMaybe "day_rows" (getSurfaceField @Surface.RosterLayoutMode fields))
            ]
        }

rosterMoveShiftRequest :: RosterWeekScopeValue -> FrontendSurfaceFieldValues DragDropFieldSpecs -> FrontendSurfaceHtmxRequest
rosterMoveShiftRequest scope fields =
    rosterDragDropRequest "move-roster-shift-to-slot" (rosterMoveShiftUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId) fields

rosterDuplicateShiftRequest :: RosterWeekScopeValue -> FrontendSurfaceFieldValues DragDropFieldSpecs -> FrontendSurfaceHtmxRequest
rosterDuplicateShiftRequest scope fields =
    rosterDragDropRequest "duplicate-roster-shift-to-day" (rosterDuplicateShiftUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId) fields

rosterDropStaffRequest :: RosterWeekScopeValue -> FrontendSurfaceFieldValues DragDropFieldSpecs -> FrontendSurfaceHtmxRequest
rosterDropStaffRequest scope fields =
    rosterDragDropRequest "drop-roster-staff" (rosterDropStaffUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId) fields

rosterDayTimelineMoveShiftRequest :: RosterDayTimelineScopeValue -> FrontendSurfaceFieldValues DragDropFieldSpecs -> FrontendSurfaceHtmxRequest
rosterDayTimelineMoveShiftRequest scope fields =
    rosterDragDropRequest "move-roster-timeline-shift" (rosterTimelineMoveShiftUrl scope.rosterDayTimelineWeekOffset scope.rosterDayTimelineGroupId scope.rosterDayTimelineDayOffset) fields

rosterDragDropRequest :: Text -> Text -> FrontendSurfaceFieldValues DragDropFieldSpecs -> FrontendSurfaceHtmxRequest
rosterDragDropRequest requestName requestUrl fields =
    FrontendSurfaceHtmxRequest
        { htmxRequestName = requestName
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = requestUrl
        , htmxRequestTarget = "#" <> rosterContentFragmentId
        , htmxRequestSwap = "none"
        , htmxRequestFields =
            [ FrontendSurfaceFieldValue "sourceItemKey" (fromMaybe "" (getSurfaceField @SurfaceInteraction.SourceItemKey fields))
            , FrontendSurfaceFieldValue "targetDropzoneKey" (fromMaybe "" (getSurfaceField @SurfaceInteraction.TargetDropzoneKey fields))
            ]
                <> optionalRequestField "sessionKind" (join (getSurfaceField @SurfaceInteraction.SessionKind fields))
                <> optionalRequestField "pointerId" (join (getSurfaceField @SurfaceInteraction.PointerId fields))
                <> optionalRequestField "pointerType" (join (getSurfaceField @SurfaceInteraction.PointerType fields))
                <> optionalRequestField "startClientX" (join (getSurfaceField @SurfaceInteraction.StartClientX fields))
                <> optionalRequestField "startClientY" (join (getSurfaceField @SurfaceInteraction.StartClientY fields))
                <> optionalRequestField "currentClientX" (join (getSurfaceField @SurfaceInteraction.CurrentClientX fields))
                <> optionalRequestField "currentClientY" (join (getSurfaceField @SurfaceInteraction.CurrentClientY fields))
                <> optionalRequestField "deltaX" (join (getSurfaceField @SurfaceInteraction.DeltaX fields))
                <> optionalRequestField "deltaY" (join (getSurfaceField @SurfaceInteraction.DeltaY fields))
        }

optionalRequestField :: Text -> Maybe Text -> [FrontendSurfaceFieldValue]
optionalRequestField name = \case
    Nothing -> []
    Just value -> [FrontendSurfaceFieldValue name value]

type DragDropFieldSpecs =
    '[ 'Field SurfaceInteraction.SourceItemKey 'WireText
     , 'Field SurfaceInteraction.TargetDropzoneKey 'WireText
     , 'OptionalField SurfaceInteraction.SessionKind 'WireText
     , 'OptionalField SurfaceInteraction.PointerId 'WireText
     , 'OptionalField SurfaceInteraction.PointerType 'WireText
     , 'OptionalField SurfaceInteraction.StartClientX 'WireText
     , 'OptionalField SurfaceInteraction.StartClientY 'WireText
     , 'OptionalField SurfaceInteraction.CurrentClientX 'WireText
     , 'OptionalField SurfaceInteraction.CurrentClientY 'WireText
     , 'OptionalField SurfaceInteraction.DeltaX 'WireText
     , 'OptionalField SurfaceInteraction.DeltaY 'WireText
     ]

placeholderRosterDayId :: UUID.UUID
placeholderRosterDayId = fromMaybe (error "invalid placeholder roster day id") (UUID.fromString "00000000-0000-0000-0000-000000000000")

rosterContentMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterContentMountedFragment scope =
    rosterMountedFragment "roster-content" Aeson.Null rosterContentFragmentId (rosterWeekContentFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)

rosterGridToolbarMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterGridToolbarMountedFragment scope =
    rosterMountedFragment "roster-grid-toolbar" Aeson.Null rosterGridToolbarFragmentId (rosterWeekGridToolbarFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId scope.rosterWeekTimelineDayOffset)

rosterGridFrameMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterGridFrameMountedFragment scope =
    rosterMountedFragment "roster-grid-frame" Aeson.Null rosterGridFrameFragmentId (rosterWeekGridFrameFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId scope.rosterWeekTimelineDayOffset)

rosterDayColumnsMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterDayColumnsMountedFragment scope =
    rosterMountedFragment "roster-day-columns" Aeson.Null rosterDayColumnsFragmentId (rosterWeekDayColumnsFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)

rosterDayRailMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterDayRailMountedFragment scope =
    rosterMountedFragment "roster-day-rail" Aeson.Null rosterDayRailFragmentId (rosterWeekDayRailFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)

rosterWageRailMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterWageRailMountedFragment scope =
    rosterMountedFragment "roster-wage-rail" Aeson.Null rosterWageRailFragmentId (rosterWeekWageRailFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)

rosterSlotsGridMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterSlotsGridMountedFragment scope =
    rosterMountedFragment "roster-slots-grid" Aeson.Null rosterSlotsGridFragmentId (rosterWeekSlotsGridFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)

rosterStaffPanelMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterStaffPanelMountedFragment scope =
    rosterMountedFragment "roster-staff-panel" Aeson.Null rosterStaffPanelFragmentId (rosterWeekStaffPanelFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)

rosterWeekOverviewMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterWeekOverviewMountedFragment scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "roster-week-overview" Aeson.Null
        , mountedFragmentTargetId = "roster-week-overview-mount-" <> tshow scope.rosterWeekGroupId <> "-" <> tshow scope.rosterWeekWeekOffset
        , mountedFragmentUrl = rosterOverviewFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "lazy"
        , mountedFragmentLazyTrigger = Just "load"
        , mountedFragmentPlaceholderKind = Nothing
        }

rosterDaySectionMountedFragment :: RosterWeekScopeValue -> Id RosterDay -> FrontendSurfaceMountedFragment
rosterDaySectionMountedFragment scope rosterDayId =
    rosterLazyMountedFragment "roster-day-section" (Aeson.object ["rosterDayId" Aeson..= tshow rosterDayId]) (rosterDaySectionDomId rosterDayId) (rosterWeekDaySectionFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId rosterDayId)

rosterRowMountedFragment :: RosterWeekScopeValue -> Id RosterDay -> Int -> FrontendSurfaceMountedFragment
rosterRowMountedFragment scope rosterDayId rowIndex =
    rosterLazyMountedFragment "roster-row" (Aeson.object ["rosterDayId" Aeson..= tshow rosterDayId, "rowIndex" Aeson..= rowIndex]) (rosterRowDomIdText rosterDayId rowIndex) (rosterWeekRowFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId rosterDayId rowIndex)

rosterDayTimelineContentMountedFragment :: RosterDayTimelineScopeValue -> FrontendSurfaceMountedFragment
rosterDayTimelineContentMountedFragment scope =
    frontendSurfaceMountedFragment
        "roster-day-timeline-content"
        (Aeson.object ["rosterDayId" Aeson..= tshow scope.rosterDayTimelineDayId])
        (rosterDayTimelineContentFragmentId scope.rosterDayTimelineDayId)
        (rosterDayTimelineContentFragmentUrl scope.rosterDayTimelineWeekOffset scope.rosterDayTimelineGroupId scope.rosterDayTimelineDayId)
        FrontendSurfaceReplace

rosterMountedFragment :: Text -> Aeson.Value -> Text -> Text -> FrontendSurfaceMountedFragment
rosterMountedFragment kind params targetId url =
    frontendSurfaceMountedFragment kind params targetId url FrontendSurfaceReplace

rosterLazyMountedFragment :: Text -> Aeson.Value -> Text -> Text -> FrontendSurfaceMountedFragment
rosterLazyMountedFragment kind params targetId url =
    (rosterMountedFragment kind params targetId url) { mountedFragmentLoadPolicy = "lazy" }
