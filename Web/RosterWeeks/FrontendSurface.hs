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
    , rosterDragSourceRef
    , rosterExistingShiftDropzoneRef
    , rosterStaffCreateDropzoneRef
    , rosterShiftSlotDropzoneRef
    , rosterStaffDragSourceRef
    , rosterInteractionMountKey
    , rosterLayoutModeActivationRef
    , rosterStaffLinkedHighlight
    , rosterShiftGroupLinkedHighlight
    , rosterDayTimelineShiftGroupLinkedHighlight
    , rosterSurfaceScope
    , rosterMountedFragmentPlanFromRenderData
    , rosterMoveShiftIntentForm
    , rosterDuplicateShiftIntentForm
    , rosterFrontendSurfaceIR
    , rosterDayTimelineDropzoneRef
    , rosterDayTimelineFrontendSurfaceIR
    , rosterTimelineMoveShiftIntentForm
    , rosterDayTimelineSourceRef
    , rosterDayTimelineIntentForms
    , rosterDayTimelineSurfaceImpl
    , rosterIntentForms
    , rosterSurfaceImpl
    , rosterSurfaceFragmentKeys
    ) where

import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.DSL
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import Application.Helper.FrontendContract.Surface.Live (SurfaceFragmentKey,
                                                         SurfaceScope,
                                                         surfaceScopeKey)
import Application.Helper.FrontendContract.Surface.Reflect (reflectSurfaceSpec)
import Application.Helper.FrontendContract.Surface.Request.Runtime
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Intent as SurfaceIntent
import qualified Application.Helper.FrontendContract.Surface.Roster.Live as SurfaceLive
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Url (appendQueryParams)
import qualified Data.Map.Strict as Map
import Data.Time.Calendar (Day, addDays)
import qualified Data.UUID as UUID
import Generated.Types
import Web.Controller.Prelude
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Paths (rosterDayTimelineContentFragmentUrl,
                              rosterDropStaffUrl, rosterDuplicateShiftUrl,
                              rosterLayoutPreferenceUrl, rosterMoveShiftUrl,
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
    { rosterWeekVenueId          :: !UUID.UUID
    , rosterWeekGroupId          :: !(Id RosterGroup)
    , rosterWeekWindowStart      :: !Day
    , rosterWeekWindowEnd        :: !Day
    , rosterWeekCalendarRevision :: !Int
    , rosterWeekTimelineDate     :: !(Maybe Day)
    }
    deriving (Eq, Show)

data RosterDayTimelineScopeValue = RosterDayTimelineScopeValue
    { rosterDayTimelineVenueId          :: !UUID.UUID
    , rosterDayTimelineGroupId          :: !(Id RosterGroup)
    , rosterDayTimelineWindowStart      :: !Day
    , rosterDayTimelineWindowEnd        :: !Day
    , rosterDayTimelineCalendarRevision :: !Int
    , rosterDayTimelineOperationalDate  :: !Day
    , rosterDayTimelineDayId            :: !(Id RosterDay)
    }
    deriving (Eq, Show)

data RosterMountedFragmentPlan = RosterMountedFragmentPlan
    { rosterMountedDayIds             :: ![Id RosterDay]
    , rosterMountedRows               :: ![(Id RosterDay, Int)]
    , rosterMountedHasTemplateLibrary :: !Bool
    }
    deriving (Eq, Show)


rosterMountedFragmentPlanFromRenderData :: Bool -> [RosterDay] -> RosterRenderIndexes -> RosterMountedFragmentPlan
rosterMountedFragmentPlanFromRenderData hasTemplateLibrary rosterDays renderIndexes =
    RosterMountedFragmentPlan
        { rosterMountedDayIds = map (.id) rosterDays
        , rosterMountedHasTemplateLibrary = hasTemplateLibrary
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
        noSurfaceFields
        (rosterCandidateMountedFragments scope plan)

rosterDayTimelineSurfaceImpl :: RosterDayTimelineScopeValue -> SurfaceImpl Surface.RosterDayTimelineSurface
rosterDayTimelineSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.RosterDayTimelineSurface @Surface.RosterDayTimeline
        (tshow scope.rosterDayTimelineDayId)
        (rosterDayTimelineScopeFields scope)
        noSurfaceFields
        (rosterDayTimelineCandidateMountedFragments scope)




rosterInteractionMountKey :: Text
rosterInteractionMountKey = "primary"






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

rosterStaffLinkedHighlight :: SurfaceIR.LinkedHighlightIR
rosterStaffLinkedHighlight = surfaceLinkedHighlightValue @Surface.RosterSurface @Surface.StaffShiftsHighlight

rosterShiftGroupLinkedHighlight :: SurfaceIR.LinkedHighlightIR
rosterShiftGroupLinkedHighlight = surfaceLinkedHighlightValue @Surface.RosterSurface @Surface.ShiftGroupHighlight

rosterDayTimelineShiftGroupLinkedHighlight :: SurfaceIR.LinkedHighlightIR
rosterDayTimelineShiftGroupLinkedHighlight = surfaceLinkedHighlightValue @Surface.RosterDayTimelineSurface @Surface.ShiftGroupHighlight

rosterFrontendSurfaceIR :: SurfaceIR.SurfaceIR
rosterFrontendSurfaceIR = reflectSurfaceSpec @Surface.RosterSurface

rosterDayTimelineFrontendSurfaceIR :: SurfaceIR.SurfaceIR
rosterDayTimelineFrontendSurfaceIR = reflectSurfaceSpec @Surface.RosterDayTimelineSurface

rosterSurfaceScope :: RosterWeekScopeValue -> SurfaceScope
rosterSurfaceScope scope =
    SurfaceLive.rosterWeekLiveScope
        scope.rosterWeekVenueId
        (unpackId scope.rosterWeekGroupId)
        scope.rosterWeekWindowStart
        scope.rosterWeekWindowEnd
        scope.rosterWeekCalendarRevision

rosterSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
rosterSurfaceFragmentKeys = map (.mountedFragmentKey)

rosterCandidateMountedFragments :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> [FrontendSurfaceMountedFragment]
rosterCandidateMountedFragments scope plan =
    map (withRosterCalendarRevision scope.rosterWeekCalendarRevision) $
        case scope.rosterWeekTimelineDate of
            Just _  -> rosterTimelineModeMountedFragments scope plan
            Nothing -> rosterWeekGridMountedFragments scope plan

rosterTimelineModeMountedFragments :: RosterWeekScopeValue -> RosterMountedFragmentPlan -> [FrontendSurfaceMountedFragment]
rosterTimelineModeMountedFragments scope plan =
    [ rosterGridToolbarMountedFragment scope
    , rosterGridFrameMountedFragment scope
    , rosterStaffPanelMountedFragment scope
    ] <> [rosterTemplateLibraryMountedFragment scope | plan.rosterMountedHasTemplateLibrary]

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
        <> [rosterTemplateLibraryMountedFragment scope | plan.rosterMountedHasTemplateLibrary]
        <> map (rosterDaySectionMountedFragment scope) plan.rosterMountedDayIds
        <> map (uncurry (rosterRowMountedFragment scope)) plan.rosterMountedRows

rosterDayTimelineCandidateMountedFragments :: RosterDayTimelineScopeValue -> [FrontendSurfaceMountedFragment]
rosterDayTimelineCandidateMountedFragments scope =
    map (withRosterCalendarRevision scope.rosterDayTimelineCalendarRevision)
        [rosterDayTimelineContentMountedFragment scope]

withRosterCalendarRevision :: Int -> FrontendSurfaceMountedFragment -> FrontendSurfaceMountedFragment
withRosterCalendarRevision calendarRevision fragment =
    fragment
        { mountedFragmentUrl = appendQueryParams fragment.mountedFragmentUrl [("rosterCalendarRevision", tshow calendarRevision)]
        }

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

rosterWeekScopeFields :: RosterWeekScopeValue -> SurfaceFields (SurfaceScopeFieldSpecs Surface.RosterSurface Surface.RosterWeek)
rosterWeekScopeFields scope =
    surfaceField @Surface.VenueId scope.rosterWeekVenueId
        &: surfaceField @Surface.RosterGroupId (unpackId scope.rosterWeekGroupId)
        &: surfaceField @Surface.WindowStartDate scope.rosterWeekWindowStart
        &: surfaceField @Surface.WindowEndDate scope.rosterWeekWindowEnd
        &: surfaceField @Surface.RosterCalendarRevision scope.rosterWeekCalendarRevision
        &: noSurfaceFields

rosterDayTimelineScopeFields :: RosterDayTimelineScopeValue -> SurfaceFields (SurfaceScopeFieldSpecs Surface.RosterDayTimelineSurface Surface.RosterDayTimeline)
rosterDayTimelineScopeFields scope =
    surfaceField @Surface.VenueId scope.rosterDayTimelineVenueId
        &: surfaceField @Surface.RosterGroupId (unpackId scope.rosterDayTimelineGroupId)
        &: surfaceField @Surface.WindowStartDate scope.rosterDayTimelineWindowStart
        &: surfaceField @Surface.WindowEndDate scope.rosterDayTimelineWindowEnd
        &: surfaceField @Surface.RosterCalendarRevision scope.rosterDayTimelineCalendarRevision
        &: surfaceField @Surface.RosterDayId (unpackId scope.rosterDayTimelineDayId)
        &: noSurfaceFields

rosterMoveShiftIntentForm :: Day -> Id RosterGroup -> Int -> Text -> Text -> Maybe Text -> Maybe Text -> FrontendSurfaceIntentForm
rosterMoveShiftIntentForm anchorDate rosterGroupId calendarRevision sourceItemKey targetDropzoneKey startOccurrence endOccurrence =
    SurfaceIntent.moveRosterShiftToSlotIntentForm
        (SurfaceIntent.moveRosterShiftToSlotIntentFields sourceItemKey targetDropzoneKey Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing calendarRevision startOccurrence endOccurrence)
        (rosterDragDropRequest (rosterMoveShiftUrl anchorDate rosterGroupId))

rosterDuplicateShiftIntentForm :: Day -> Id RosterGroup -> Int -> Text -> Text -> Maybe Text -> Maybe Text -> FrontendSurfaceIntentForm
rosterDuplicateShiftIntentForm anchorDate rosterGroupId calendarRevision sourceItemKey targetDropzoneKey startOccurrence endOccurrence =
    SurfaceIntent.duplicateRosterShiftToDayIntentForm
        (SurfaceIntent.duplicateRosterShiftToDayIntentFields sourceItemKey targetDropzoneKey Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing calendarRevision startOccurrence endOccurrence)
        (rosterDragDropRequest (rosterDuplicateShiftUrl anchorDate rosterGroupId))

rosterTimelineMoveShiftIntentForm :: Day -> Id RosterGroup -> Day -> Int -> Text -> Text -> Maybe Text -> FrontendSurfaceIntentForm
rosterTimelineMoveShiftIntentForm anchorDate rosterGroupId operationalDate calendarRevision sourceItemKey targetDropzoneKey startOccurrence =
    SurfaceIntent.moveRosterTimelineShiftIntentForm
        (SurfaceIntent.moveRosterTimelineShiftIntentFields sourceItemKey targetDropzoneKey Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing calendarRevision startOccurrence)
        (rosterDragDropRequest (rosterTimelineMoveShiftUrl anchorDate rosterGroupId operationalDate))

rosterIntentForms :: RosterWeekScopeValue -> Bool -> [FrontendSurfaceIntentForm]
rosterIntentForms scope _templateApplicationAvailable =
    [ SurfaceIntent.setRosterLayoutModeIntentForm
        (SurfaceIntent.setRosterLayoutModeIntentFields DayRows)
        (rosterLayoutModeRequest scope)
    , SurfaceIntent.moveRosterShiftToSlotIntentForm
        (SurfaceIntent.moveRosterShiftToSlotIntentFields "" "" (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") scope.rosterWeekCalendarRevision (Just "") (Just ""))
        (rosterMoveShiftRequest scope)
    , SurfaceIntent.duplicateRosterShiftToDayIntentForm
        (SurfaceIntent.duplicateRosterShiftToDayIntentFields "" "" (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") scope.rosterWeekCalendarRevision (Just "") (Just ""))
        (rosterDuplicateShiftRequest scope)
    , SurfaceIntent.dropRosterStaffIntentForm
        (SurfaceIntent.dropRosterStaffIntentFields "" "" (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") scope.rosterWeekCalendarRevision)
        (rosterDropStaffRequest scope)
    ]

rosterDayTimelineIntentForms :: RosterDayTimelineScopeValue -> [FrontendSurfaceIntentForm]
rosterDayTimelineIntentForms scope =
    [ SurfaceIntent.moveRosterTimelineShiftIntentForm
        (SurfaceIntent.moveRosterTimelineShiftIntentFields "" "" (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") (Just "") scope.rosterDayTimelineCalendarRevision (Just ""))
        (rosterDayTimelineMoveShiftRequest scope)
    ]

rosterLayoutModeRequest :: RosterWeekScopeValue -> FrontendSurfaceHtmxRequest
rosterLayoutModeRequest scope =
    FrontendSurfaceHtmxRequest
        { htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = rosterLayoutPreferenceUrl scope.rosterWeekWindowStart scope.rosterWeekGroupId scope.rosterWeekCalendarRevision
        , htmxRequestTarget = "#" <> rosterContentFragmentId
        , htmxRequestSwap = "none"
        }

rosterMoveShiftRequest :: RosterWeekScopeValue -> FrontendSurfaceHtmxRequest
rosterMoveShiftRequest scope =
    rosterDragDropRequest (rosterMoveShiftUrl scope.rosterWeekWindowStart scope.rosterWeekGroupId)

rosterDuplicateShiftRequest :: RosterWeekScopeValue -> FrontendSurfaceHtmxRequest
rosterDuplicateShiftRequest scope =
    rosterDragDropRequest (rosterDuplicateShiftUrl scope.rosterWeekWindowStart scope.rosterWeekGroupId)

rosterDropStaffRequest :: RosterWeekScopeValue -> FrontendSurfaceHtmxRequest
rosterDropStaffRequest scope =
    rosterDragDropRequest (rosterDropStaffUrl scope.rosterWeekWindowStart scope.rosterWeekGroupId)

rosterDayTimelineMoveShiftRequest :: RosterDayTimelineScopeValue -> FrontendSurfaceHtmxRequest
rosterDayTimelineMoveShiftRequest scope =
    rosterDragDropRequest
        (rosterTimelineMoveShiftUrl scope.rosterDayTimelineWindowStart scope.rosterDayTimelineGroupId scope.rosterDayTimelineOperationalDate)

rosterDragDropRequest :: Text -> FrontendSurfaceHtmxRequest
rosterDragDropRequest requestUrl =
    FrontendSurfaceHtmxRequest
        { htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = requestUrl
        , htmxRequestTarget = "#" <> rosterContentFragmentId
        , htmxRequestSwap = "none"
        }

timelineDateForScope :: RosterWeekScopeValue -> Maybe Day
timelineDateForScope scope = scope.rosterWeekTimelineDate

rosterContentMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterContentMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterContent
        noSurfaceFields
        noSurfaceFields
        (rosterWeekContentFragmentUrl scope.rosterWeekWindowStart scope.rosterWeekGroupId)
        FrontendSurfaceReplace

rosterGridToolbarMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterGridToolbarMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterGridToolbar
        noSurfaceFields
        noSurfaceFields
        (rosterWeekGridToolbarFragmentUrl scope.rosterWeekWindowStart scope.rosterWeekGroupId (timelineDateForScope scope))
        FrontendSurfaceReplace

rosterGridFrameMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterGridFrameMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterGridFrame
        noSurfaceFields
        noSurfaceFields
        (rosterWeekGridFrameFragmentUrl scope.rosterWeekWindowStart scope.rosterWeekGroupId (timelineDateForScope scope))
        FrontendSurfaceReplace

rosterDayColumnsMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterDayColumnsMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterDayColumns
        noSurfaceFields
        noSurfaceFields
        (rosterWeekDayColumnsFragmentUrl scope.rosterWeekWindowStart scope.rosterWeekGroupId)
        FrontendSurfaceReplace

rosterDayRailMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterDayRailMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterDayRail
        noSurfaceFields
        noSurfaceFields
        (rosterWeekDayRailFragmentUrl scope.rosterWeekWindowStart scope.rosterWeekGroupId)
        FrontendSurfaceReplace

rosterWageRailMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterWageRailMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterWageRail
        noSurfaceFields
        noSurfaceFields
        (rosterWeekWageRailFragmentUrl scope.rosterWeekWindowStart scope.rosterWeekGroupId)
        FrontendSurfaceReplace

rosterSlotsGridMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterSlotsGridMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterSlotsGrid
        noSurfaceFields
        noSurfaceFields
        (rosterWeekSlotsGridFragmentUrl scope.rosterWeekWindowStart scope.rosterWeekGroupId)
        FrontendSurfaceReplace

rosterStaffPanelMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterStaffPanelMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterStaffPanel
        noSurfaceFields
        noSurfaceFields
        (rosterWeekStaffPanelFragmentUrl scope.rosterWeekWindowStart scope.rosterWeekGroupId)
        FrontendSurfaceReplace

rosterTemplateLibraryMountedFragment :: RosterWeekScopeValue -> FrontendSurfaceMountedFragment
rosterTemplateLibraryMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterTemplateLibraryFragment
        noSurfaceFields
        noSurfaceFields
        (appendQueryParams
            (pathTo ShowRosterTemplateLibraryFragmentAction { rosterGroupId = scope.rosterWeekGroupId })
            [("anchorDate", tshow scope.rosterWeekWindowStart)])
        FrontendSurfaceReplace


rosterDaySectionMountedFragment :: RosterWeekScopeValue -> Id RosterDay -> FrontendSurfaceMountedFragment
rosterDaySectionMountedFragment scope rosterDayId =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterDaySection
        (surfaceField @Surface.RosterDayId (unpackId rosterDayId) &: noSurfaceFields)
        (surfaceField @Surface.RosterDayId (unpackId rosterDayId) &: noSurfaceFields)
        (rosterWeekDaySectionFragmentUrl scope.rosterWeekWindowStart scope.rosterWeekGroupId rosterDayId)
        FrontendSurfaceReplace

rosterRowMountedFragment :: RosterWeekScopeValue -> Id RosterDay -> Int -> FrontendSurfaceMountedFragment
rosterRowMountedFragment scope rosterDayId rowIndex =
    frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterRow
        ( surfaceField @Surface.RosterDayId (unpackId rosterDayId)
            &: surfaceField @Surface.RowIndex rowIndex
            &: noSurfaceFields
        )
        ( surfaceField @Surface.RosterDayId (unpackId rosterDayId)
            &: surfaceField @Surface.RowIndex rowIndex
            &: noSurfaceFields
        )
        (rosterWeekRowFragmentUrl scope.rosterWeekWindowStart scope.rosterWeekGroupId rosterDayId rowIndex)
        FrontendSurfaceReplace

rosterDayTimelineContentMountedFragment :: RosterDayTimelineScopeValue -> FrontendSurfaceMountedFragment
rosterDayTimelineContentMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.RosterDayTimelineSurface @Surface.RosterDayTimelineContent
        (surfaceField @Surface.RosterDayId (unpackId scope.rosterDayTimelineDayId) &: noSurfaceFields)
        (surfaceField @Surface.RosterDayId (unpackId scope.rosterDayTimelineDayId) &: noSurfaceFields)
        (rosterDayTimelineContentFragmentUrl scope.rosterDayTimelineWindowStart scope.rosterDayTimelineGroupId scope.rosterDayTimelineDayId)
        FrontendSurfaceReplace
