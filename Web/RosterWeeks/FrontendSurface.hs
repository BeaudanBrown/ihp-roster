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
    , rosterDayTimelineIntentForms
    , rosterDayTimelineSurfaceImpl
    , rosterIntentForms
    , rosterSurfaceImpl
    , rosterSurfaceMountConfig
    , rosterSurfaceScopeKey
    , rosterSurfaceFragmentKeys
    ) where

import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.DSL
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import Application.Helper.FrontendContract.Surface.Reflect (reflectSurfaceSpec)
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.LiveUpdate.Runtime
import qualified Data.Map.Strict as Map
import qualified Data.UUID as UUID
import Generated.Types
import qualified IHP.Prelude as Prelude
import Web.Controller.Prelude
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Paths (rosterDayTimelineContentFragmentUrl,
                              rosterDropStaffUrl, rosterDuplicateShiftUrl,
                              rosterLayoutPreferenceUrl, rosterMoveShiftUrl,
                              rosterOverviewFragmentUrl,
                              rosterStaffSelfServiceLeaveFormFragmentUrl,
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
    mkSurfaceImplFromValues @Surface.RosterSurface @Surface.RosterWeek
        rosterInteractionMountKey
        (rosterWeekScopeFields scope)
        NoSurfaceFields
        (rosterCandidateMountedFragments scope plan)

rosterDayTimelineSurfaceImpl :: RosterDayTimelineScopeValue -> SurfaceImpl Surface.RosterDayTimelineSurface
rosterDayTimelineSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.RosterDayTimelineSurface @Surface.RosterDayTimeline
        (tshow scope.rosterDayTimelineDayId)
        (rosterDayTimelineScopeFields scope)
        NoSurfaceFields
        (rosterDayTimelineCandidateMountedFragments scope)

rosterSurfaceMountConfig :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> FrontendSurfaceMountConfig
rosterSurfaceMountConfig scope plan =
    (rosterSurfaceImpl scope plan).surfaceImplMountConfig

rosterSurfaceScopeKey :: RosterWeekScopeValue -> Text
rosterSurfaceScopeKey scope =
    frontendSurfaceScopeKeyFor @Surface.RosterSurface @Surface.RosterWeek (rosterWeekScopeFields scope)
        |> either (error . ("Typed Roster scope invariant failed: " <>)) Prelude.id

rosterDayTimelineSurfaceScopeKey :: RosterDayTimelineScopeValue -> Text
rosterDayTimelineSurfaceScopeKey scope =
    frontendSurfaceScopeKeyFor @Surface.RosterDayTimelineSurface @Surface.RosterDayTimeline (rosterDayTimelineScopeFields scope)
        |> either (error . ("Typed Roster timeline scope invariant failed: " <>)) Prelude.id

rosterInteractionMountKey :: Text
rosterInteractionMountKey = "primary"

rosterDragSessionKindName :: Text
rosterDragSessionKindName = "drag"

rosterLayoutModeIntentName :: Text
rosterLayoutModeIntentName = surfaceIntentNameValue @Surface.RosterSurface @Surface.SetRosterLayoutMode

rosterLayoutModeIntentFieldName :: Text
rosterLayoutModeIntentFieldName = surfaceIntentFieldName @Surface.RosterSurface @Surface.SetRosterLayoutMode @Surface.RosterLayoutMode

rosterMoveShiftIntentName :: Text
rosterMoveShiftIntentName = surfaceIntentNameValue @Surface.RosterSurface @Surface.MoveRosterShiftToSlot

rosterDayTimelineMoveShiftIntentName :: Text
rosterDayTimelineMoveShiftIntentName = surfaceIntentNameValue @Surface.RosterDayTimelineSurface @Surface.MoveRosterTimelineShift

rosterDuplicateShiftIntentName :: Text
rosterDuplicateShiftIntentName = surfaceIntentNameValue @Surface.RosterSurface @Surface.DuplicateRosterShiftToDay

rosterDragSourceRef :: SurfaceIR.InteractionSourceRefIR
rosterDragSourceRef = rosterShiftDragSourceRef

rosterShiftDragSourceRef :: SurfaceIR.InteractionSourceRefIR
rosterShiftDragSourceRef = surfaceSourceRefValue @Surface.RosterSurface @Surface.ShiftDragSource

rosterStaffDragSourceRef :: SurfaceIR.InteractionSourceRefIR
rosterStaffDragSourceRef = surfaceSourceRefValue @Surface.RosterSurface @Surface.StaffDragSource

rosterDragDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterDragDropzoneRef = rosterShiftSlotDropzoneRef

rosterShiftSlotDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterShiftSlotDropzoneRef = surfaceDropzoneRefValue @Surface.RosterSurface @Surface.ShiftSlotDropzone

rosterStaffCreateDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterStaffCreateDropzoneRef = surfaceDropzoneRefValue @Surface.RosterSurface @Surface.StaffCreateDropzone

rosterDayColumnDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterDayColumnDropzoneRef = surfaceDropzoneRefValue @Surface.RosterSurface @Surface.DayColumnDropzone

rosterExistingShiftDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterExistingShiftDropzoneRef = surfaceDropzoneRefValue @Surface.RosterSurface @Surface.ExistingShiftDropzone

rosterDeleteShiftDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterDeleteShiftDropzoneRef = surfaceDropzoneRefValue @Surface.RosterSurface @Surface.DeleteShiftDropzone

rosterDayTimelineSourceRef :: SurfaceIR.InteractionSourceRefIR
rosterDayTimelineSourceRef = surfaceSourceRefValue @Surface.RosterDayTimelineSurface @SurfaceInteraction.DragSourceRef

rosterDayTimelineDropzoneRef :: SurfaceIR.InteractionDropzoneRefIR
rosterDayTimelineDropzoneRef = surfaceDropzoneRefValue @Surface.RosterDayTimelineSurface @SurfaceInteraction.DragDropzoneRef

rosterLayoutModeActivationRef :: SurfaceIR.InteractionActivationRefIR
rosterLayoutModeActivationRef = surfaceActivationRefValue @Surface.RosterSurface @SurfaceInteraction.RosterLayoutModeActivationRef

rosterFrontendSurfaceIR :: SurfaceIR.SurfaceIR
rosterFrontendSurfaceIR = reflectSurfaceSpec @Surface.RosterSurface

rosterDayTimelineFrontendSurfaceIR :: SurfaceIR.SurfaceIR
rosterDayTimelineFrontendSurfaceIR = reflectSurfaceSpec @Surface.RosterDayTimelineSurface

rosterSurfaceScope :: RosterWeekScopeValue -> SurfaceScope
rosterSurfaceScope scope =
    rosterWeekLiveScope scope.rosterWeekVenueId (unpackId scope.rosterWeekGroupId) scope.rosterWeekWeekOffset

rosterSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
rosterSurfaceFragmentKeys =
    frontendSurfaceMountedFragmentsToKeysFor @Surface.RosterSurface

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
    , rosterStaffSelfServiceLeaveFormMountedFragment scope
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
    RosterProjectionStaffSelfServiceLeaveForm -> rosterStaffSelfServiceLeaveFormMountedFragment scope
    RosterProjectionDaySection rosterDayId -> rosterDaySectionMountedFragment scope (Id rosterDayId)
    RosterProjectionRow rosterDayId rowIndex -> rosterRowMountedFragment scope (Id rosterDayId) rowIndex

rosterWeekScopeFields :: RosterWeekScopeValue -> SurfaceFields (SurfaceScopeFieldSpecs Surface.RosterSurface Surface.RosterWeek)
rosterWeekScopeFields scope =
    surfaceField @Surface.VenueId scope.rosterWeekVenueId
        :& surfaceField @Surface.RosterGroupId (unpackId scope.rosterWeekGroupId)
        :& surfaceField @Surface.WeekOffset scope.rosterWeekWeekOffset
        :& NoSurfaceFields

rosterDayTimelineScopeFields :: RosterDayTimelineScopeValue -> SurfaceFields (SurfaceScopeFieldSpecs Surface.RosterDayTimelineSurface Surface.RosterDayTimeline)
rosterDayTimelineScopeFields scope =
    surfaceField @Surface.VenueId scope.rosterDayTimelineVenueId
        :& surfaceField @Surface.RosterGroupId (unpackId scope.rosterDayTimelineGroupId)
        :& surfaceField @Surface.WeekOffset scope.rosterDayTimelineWeekOffset
        :& surfaceField @Surface.RosterDayId (unpackId scope.rosterDayTimelineDayId)
        :& NoSurfaceFields

rosterIntentForms :: RosterWeekScopeValue -> [FrontendSurfaceIntentForm]
rosterIntentForms scope =
    [ FrontendSurfaceIntentForm
        rosterLayoutModeIntentName
        (rosterLayoutModeRequest scope (frontendSurfaceIntentFieldValues @Surface.RosterSurface @Surface.SetRosterLayoutMode rosterLayoutModeFields))
    , FrontendSurfaceIntentForm
        rosterMoveShiftIntentName
        (rosterMoveShiftRequest scope (frontendSurfaceIntentFieldValues @Surface.RosterSurface @Surface.MoveRosterShiftToSlot emptyRosterDragDropFields))
    , FrontendSurfaceIntentForm
        rosterDuplicateShiftIntentName
        (rosterDuplicateShiftRequest scope (frontendSurfaceIntentFieldValues @Surface.RosterSurface @Surface.DuplicateRosterShiftToDay emptyRosterDragDropFields))
    , FrontendSurfaceIntentForm
        (surfaceIntentNameValue @Surface.RosterSurface @Surface.DropRosterStaff)
        (rosterDropStaffRequest scope (frontendSurfaceIntentFieldValues @Surface.RosterSurface @Surface.DropRosterStaff emptyRosterDragDropFields))
    ]

rosterDayTimelineIntentForms :: RosterDayTimelineScopeValue -> [FrontendSurfaceIntentForm]
rosterDayTimelineIntentForms scope =
    [ FrontendSurfaceIntentForm
        rosterDayTimelineMoveShiftIntentName
        (rosterDayTimelineMoveShiftRequest scope (frontendSurfaceIntentFieldValues @Surface.RosterDayTimelineSurface @Surface.MoveRosterTimelineShift emptyRosterDragDropFields))
    ]

rosterLayoutModeFields :: SurfaceFields '[ 'Field Surface.RosterLayoutMode 'WireText]
rosterLayoutModeFields =
    surfaceField @Surface.RosterLayoutMode "day_rows" :& NoSurfaceFields

emptyRosterDragDropFields :: SurfaceFields SurfaceInteraction.DragDropFields
emptyRosterDragDropFields =
    surfaceField @SurfaceInteraction.SourceItemKey ""
        :& surfaceField @SurfaceInteraction.TargetDropzoneKey ""
        :& surfaceOptionalField @SurfaceInteraction.SessionKind (Just "")
        :& surfaceOptionalField @SurfaceInteraction.PointerId (Just "")
        :& surfaceOptionalField @SurfaceInteraction.PointerType (Just "")
        :& surfaceOptionalField @SurfaceInteraction.StartClientX (Just "")
        :& surfaceOptionalField @SurfaceInteraction.StartClientY (Just "")
        :& surfaceOptionalField @SurfaceInteraction.CurrentClientX (Just "")
        :& surfaceOptionalField @SurfaceInteraction.CurrentClientY (Just "")
        :& surfaceOptionalField @SurfaceInteraction.DeltaX (Just "")
        :& surfaceOptionalField @SurfaceInteraction.DeltaY (Just "")
        :& NoSurfaceFields

rosterLayoutModeRequest :: RosterWeekScopeValue -> [FrontendSurfaceFieldValue] -> FrontendSurfaceHtmxRequest
rosterLayoutModeRequest scope fields =
    FrontendSurfaceHtmxRequest
        { htmxRequestName = rosterLayoutModeIntentName
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = rosterLayoutPreferenceUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId
        , htmxRequestTarget = "#" <> rosterContentFragmentId
        , htmxRequestSwap = "none"
        , htmxRequestFields = fields
        }

rosterMoveShiftRequest :: RosterWeekScopeValue -> [FrontendSurfaceFieldValue] -> FrontendSurfaceHtmxRequest
rosterMoveShiftRequest scope =
    rosterDragDropRequest rosterMoveShiftIntentName (rosterMoveShiftUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)

rosterDuplicateShiftRequest :: RosterWeekScopeValue -> [FrontendSurfaceFieldValue] -> FrontendSurfaceHtmxRequest
rosterDuplicateShiftRequest scope =
    rosterDragDropRequest rosterDuplicateShiftIntentName (rosterDuplicateShiftUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)

rosterDropStaffRequest :: RosterWeekScopeValue -> [FrontendSurfaceFieldValue] -> FrontendSurfaceHtmxRequest
rosterDropStaffRequest scope =
    rosterDragDropRequest
        (surfaceIntentNameValue @Surface.RosterSurface @Surface.DropRosterStaff)
        (rosterDropStaffUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)

rosterDayTimelineMoveShiftRequest :: RosterDayTimelineScopeValue -> [FrontendSurfaceFieldValue] -> FrontendSurfaceHtmxRequest
rosterDayTimelineMoveShiftRequest scope =
    rosterDragDropRequest
        rosterDayTimelineMoveShiftIntentName
        (rosterTimelineMoveShiftUrl scope.rosterDayTimelineWeekOffset scope.rosterDayTimelineGroupId scope.rosterDayTimelineDayOffset)

rosterDragDropRequest :: Text -> Text -> [FrontendSurfaceFieldValue] -> FrontendSurfaceHtmxRequest
rosterDragDropRequest requestName requestUrl fields =
    FrontendSurfaceHtmxRequest
        { htmxRequestName = requestName
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = requestUrl
        , htmxRequestTarget = "#" <> rosterContentFragmentId
        , htmxRequestSwap = "none"
        , htmxRequestFields = fields
        }

rosterContentMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterContentMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterContent
        NoSurfaceFields
        rosterContentFragmentId
        (rosterWeekContentFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)
        FrontendSurfaceReplace

rosterGridToolbarMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterGridToolbarMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterGridToolbar
        NoSurfaceFields
        rosterGridToolbarFragmentId
        (rosterWeekGridToolbarFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId scope.rosterWeekTimelineDayOffset)
        FrontendSurfaceReplace

rosterGridFrameMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterGridFrameMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterGridFrame
        NoSurfaceFields
        rosterGridFrameFragmentId
        (rosterWeekGridFrameFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId scope.rosterWeekTimelineDayOffset)
        FrontendSurfaceReplace

rosterDayColumnsMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterDayColumnsMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterDayColumns
        NoSurfaceFields
        rosterDayColumnsFragmentId
        (rosterWeekDayColumnsFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)
        FrontendSurfaceReplace

rosterDayRailMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterDayRailMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterDayRail
        NoSurfaceFields
        rosterDayRailFragmentId
        (rosterWeekDayRailFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)
        FrontendSurfaceReplace

rosterWageRailMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterWageRailMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterWageRail
        NoSurfaceFields
        rosterWageRailFragmentId
        (rosterWeekWageRailFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)
        FrontendSurfaceReplace

rosterSlotsGridMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterSlotsGridMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterSlotsGrid
        NoSurfaceFields
        rosterSlotsGridFragmentId
        (rosterWeekSlotsGridFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)
        FrontendSurfaceReplace

rosterStaffPanelMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterStaffPanelMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterStaffPanel
        NoSurfaceFields
        rosterStaffPanelFragmentId
        (rosterWeekStaffPanelFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)
        FrontendSurfaceReplace

rosterStaffSelfServiceLeaveFormMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterStaffSelfServiceLeaveFormMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterStaffSelfServiceLeaveFormFragment
        NoSurfaceFields
        "roster-staff-self-service-leave-form-fragment"
        (rosterStaffSelfServiceLeaveFormFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)
        FrontendSurfaceReplace

rosterWeekOverviewMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterWeekOverviewMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterWeekOverview
        NoSurfaceFields
        ("roster-week-overview-mount-" <> tshow scope.rosterWeekGroupId <> "-" <> tshow scope.rosterWeekWeekOffset)
        (rosterOverviewFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId)
        FrontendSurfaceReplace

rosterDaySectionMountedFragment :: RosterWeekScopeValue -> Id RosterDay -> FrontendSurfaceMountedFragment
rosterDaySectionMountedFragment scope rosterDayId =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterDaySection
        (surfaceField @Surface.RosterDayId (unpackId rosterDayId) :& NoSurfaceFields)
        (rosterDaySectionDomId rosterDayId)
        (rosterWeekDaySectionFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId rosterDayId)
        FrontendSurfaceReplace

rosterRowMountedFragment :: RosterWeekScopeValue -> Id RosterDay -> Int -> FrontendSurfaceMountedFragment
rosterRowMountedFragment scope rosterDayId rowIndex =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterRow
        ( surfaceField @Surface.RosterDayId (unpackId rosterDayId)
            :& surfaceField @Surface.RowIndex rowIndex
            :& NoSurfaceFields
        )
        (rosterRowDomIdText rosterDayId rowIndex)
        (rosterWeekRowFragmentUrl scope.rosterWeekWeekOffset scope.rosterWeekGroupId rosterDayId rowIndex)
        FrontendSurfaceReplace

rosterDayTimelineContentMountedFragment :: RosterDayTimelineScopeValue -> FrontendSurfaceMountedFragment
rosterDayTimelineContentMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterDayTimelineSurface @Surface.RosterDayTimelineContent
        (surfaceField @Surface.RosterDayId (unpackId scope.rosterDayTimelineDayId) :& NoSurfaceFields)
        (rosterDayTimelineContentFragmentId scope.rosterDayTimelineDayId)
        (rosterDayTimelineContentFragmentUrl scope.rosterDayTimelineWeekOffset scope.rosterDayTimelineGroupId scope.rosterDayTimelineDayId)
        FrontendSurfaceReplace
