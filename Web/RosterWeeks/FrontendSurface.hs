{-# LANGUAGE BlockArguments   #-}
{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.RosterWeeks.FrontendSurface
    ( RosterMountedFragmentPlan (..)
    , RosterWeekScopeValue (..)
    , rosterCandidateMountedFragments
    , rosterMountedFragmentForProjection
    , rosterDragDropzoneRef
    , rosterDragSessionKindName
    , rosterDragSourceRef
    , rosterInteractionMountKey
    , rosterLayoutModeActivationRef
    , rosterLayoutModeIntentFieldName
    , rosterLayoutModeIntentName
    , rosterSurfaceScope
    , rosterMountedFragmentPlanFromRenderData
    , rosterMoveShiftIntentName
    , rosterFrontendSurfaceIR
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
import Web.RosterWeeks.Paths (rosterDuplicateShiftUrl,
                              rosterLayoutPreferenceUrl, rosterMoveShiftUrl,
                              rosterOverviewFragmentUrl,
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
    { rosterWeekVenueId    :: !UUID.UUID
    , rosterWeekGroupId    :: !(Id RosterGroup)
    , rosterWeekWeekOffset :: !Int
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
    let impl = mkSurfaceImpl "roster" (rosterSurfaceMountConfig scope plan) (rosterSurfaceHandlers scope plan)
     in impl { surfaceImplMountConfig = impl.surfaceImplMountConfig { mountFragments = rosterCandidateMountedFragments scope plan } }

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

rosterSurfaceScopeKey :: RosterWeekScopeValue -> Text
rosterSurfaceScopeKey scope =
    "roster:" <> tshow scope.rosterWeekVenueId <> ":" <> tshow scope.rosterWeekGroupId <> ":" <> tshow scope.rosterWeekWeekOffset

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

rosterDuplicateShiftIntentName :: Text
rosterDuplicateShiftIntentName = "duplicate-roster-shift-to-day"

rosterDragSourceRef :: SurfaceIR.InteractionSourceRefIR
rosterDragSourceRef = expectOne "source ref" rosterFrontendSurfaceIR.surfaceSourceRefs

rosterDragDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterDragDropzoneRef = expectOne "dropzone ref" rosterFrontendSurfaceIR.surfaceDropzoneRefs

rosterLayoutModeActivationRef :: SurfaceIR.InteractionActivationRefIR
rosterLayoutModeActivationRef = expectOne "activation ref" rosterFrontendSurfaceIR.surfaceActivationRefs

expectOne :: Text -> [value] -> value
expectOne label values =
    case values of
        [value] -> value
        []      -> error ("missing roster " <> cs label)
        _       -> error ("multiple roster " <> cs label <> " declarations")

rosterFrontendSurfaceIR :: SurfaceIR.SurfaceIR
rosterFrontendSurfaceIR =
    fromMaybe (error "registered FrontendSurface 'roster' is missing") do
        find ((== "roster") . (.surfaceName)) reflectRegisteredFrontendSurfaces.contractSurfaces

rosterSurfaceScope :: RosterWeekScopeValue -> SurfaceScope
rosterSurfaceScope scope =
    rosterWeekLiveScope scope.rosterWeekVenueId (unpackId scope.rosterWeekGroupId) scope.rosterWeekWeekOffset

rosterSurfaceWireFragments :: [FrontendSurfaceMountedFragment] -> [SurfaceWireFragment]
rosterSurfaceWireFragments =
    frontendSurfaceMountedFragmentsToWire "roster"

rosterCandidateMountedFragments :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> [FrontendSurfaceMountedFragment]
rosterCandidateMountedFragments scope plan =
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
    rosterMountedFragment "roster-grid-toolbar" Aeson.Null rosterGridToolbarFragmentId (rosterWeekGridToolbarFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)

rosterGridFrameMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterGridFrameMountedFragment scope =
    rosterMountedFragment "roster-grid-frame" Aeson.Null rosterGridFrameFragmentId (rosterWeekGridFrameFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)

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
    rosterLazyMountedFragment "roster-staff-panel" Aeson.Null rosterStaffPanelFragmentId (rosterWeekStaffPanelFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)

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

rosterMountedFragment :: Text -> Aeson.Value -> Text -> Text -> FrontendSurfaceMountedFragment
rosterMountedFragment kind params targetId url =
    frontendSurfaceMountedFragment kind params targetId url FrontendSurfaceReplace

rosterLazyMountedFragment :: Text -> Aeson.Value -> Text -> Text -> FrontendSurfaceMountedFragment
rosterLazyMountedFragment kind params targetId url =
    (rosterMountedFragment kind params targetId url) { mountedFragmentLoadPolicy = "lazy" }
