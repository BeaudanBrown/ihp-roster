{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.Grid
    ( lastRowIndexForRows
    , renderrosterContentLiveFragment
    , renderrosterContentLiveFragmentOob
    , renderrosterGridFrameLiveFragment
    , renderrosterGridFrameLiveFragmentWithSwap
    , renderrosterDayColumnsLiveFragment
    , renderrosterDayColumnsLiveFragmentWithSwap
    , renderrosterDayRailLiveFragment
    , renderrosterDayRailLiveFragmentWithSwap
    , renderHiddenDraftDayRailFragmentWithSwap
    , renderrosterSlotsGridLiveFragment
    , renderrosterSlotsGridLiveFragmentWithSwap
    , renderHiddenDraftSlotsGridFragmentWithSwap
    , renderrosterWageRailLiveFragment
    , renderrosterWageRailLiveFragmentWithSwap
    , renderrosterGridToolbarLiveFragment
    , renderrosterGridToolbarLiveFragmentWithSwap
    , renderRosterLayout
    , renderRosterDaySectionFragment
    , renderRowFragment
    , renderRowOob
    , compactDayColumnSlots
    , rowsForDay
    ) where

import Application.Helper.FrontendContract.AppShell (OpenRosterShiftDialog)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             applyAppShellActionAttrs)
import Application.Helper.FrontendContract.HorizontalScroll.Runtime
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceAction)
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Roster.Chrome (RosterColumnEditingState (..),
                                                                  rosterColumnEditDoneAttrs,
                                                                  rosterColumnEditStartAttrs,
                                                                  rosterColumnEditorAttrs)
import Application.Helper.FrontendContract.Surface.Roster.ImageExport (rosterImageExportCellAttrs,
                                                                       rosterImageExportProjectionAttrs,
                                                                       rosterImageExportRowAttrs)
import Application.Helper.FrontendContract.Surface.Roster.SidePanel (rosterSidePanelRenderAttrs)
import Application.Helper.FrontendContract.Surface.Roster.StaffPanel (rosterStaffHighlightDefaultAttrs)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceInteractionShellConfig (..),
                                                            FrontendSurfaceMountConfig (..),
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceInteractionShell)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldNameFrom)
import Application.Helper.Profiling (profileHtmlComponent, profileRenderCounter)
import Application.Helper.RosterWagePrediction
import Application.Helper.TimeRules (rosterOperationalFinalSelectableTimeText,
                                     rosterOperationalStartTimeText)
import Application.Helper.Url (appendQueryParams)
import Application.Helper.UserPreferences (rosterLayoutModeIsDayColumns,
                                           rosterLayoutModeValue)
import Application.Helper.View (staffDisplayName)
import Application.VenueTime.Model (rosterSlotStartTime)
import Data.Coerce (coerce)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import qualified Data.Time.Calendar as Calendar
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (TimeOfDay)
import Data.UUID (UUID)
import Web.RosterWeeks.DateRange (RosterWindowLane (..), RosterWindowScope (..),
                                  laneForOperationalDate, rosterWindowLaneName,
                                  rosterWindowLaneRepresentative)
import Web.RosterWeeks.Dom
import Web.RosterWeeks.FrontendSurface (RosterWeekScopeValue (..),
                                        rosterDayColumnDropzoneRef,
                                        rosterDragSourceRef,
                                        rosterFrontendSurfaceIR,
                                        rosterIntentForms,
                                        rosterMountedFragmentPlanFromRenderData,
                                        rosterSurfaceImpl)
import Web.RosterWeeks.Paths (rosterDayMutationUrl)
import Web.RosterWeeks.Types
import Web.RosterWeeks.WageFilter (rosterWageFilterConfigAttrs)
import Web.View.Prelude
import Web.View.RosterWeeks.Grid.Cells
import Web.View.RosterWeeks.Header (renderRosterGridHeader)
import Web.View.RosterWeeks.StaffPanel (renderrosterStaffPanelLiveFragment)
import Web.View.RosterWeeks.StaffSelfServicePanel (renderRosterStaffSelfServicePanelFragment)
import Web.View.RosterWeeks.Timeline (renderRosterDayTimelinePanel)

rosterGridActionRoute :: Text -> FrontendSurfaceActionRoute
rosterGridActionRoute actionUrl =
    FrontendSurfaceActionRoute
        { actionRouteUrl = actionUrl
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Just actionUrl
        , actionRouteExtraAttrs = []
        }

renderrosterContentLiveFragment :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderrosterContentLiveFragment =
    renderrosterContentLiveFragmentWithSwap Nothing

renderrosterContentLiveFragmentOob :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderrosterContentLiveFragmentOob =
    renderrosterContentLiveFragmentWithSwap (Just "outerHTML")

renderrosterContentLiveFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterGridRenderModel -> Html
renderrosterContentLiveFragmentWithSwap maybeSwapOob gridModel =
    profileHtmlComponent "render.roster.content_fragment" $
        if rosterHasSidePanel gridModel
            then renderSidePanelMainRegion rosterSidePanelRenderAttrs regionConfig (renderRosterContent gridModel)
            else [hsx|
                <div id={rosterContentFragmentId}
                     class={rosterContentColumnClasses gridModel}
                     hx-swap-oob={maybeSwapOob}>
                    {renderRosterContent gridModel}
                </div>
            |]
  where
    regionConfig = SidePanelRegionConfig
        { sidePanelRegionId = Just rosterContentFragmentId
        , sidePanelRegionClass = rosterContentColumnClasses gridModel
        , sidePanelRegionExtraAttrs = maybe [] (\swap -> [("hx-swap-oob", swap)]) maybeSwapOob <> rosterOwnLiveShiftHighlightAttrs gridModel
        }

renderRosterLayout :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterLayout gridModel@RosterGridRenderModel { gridRosterWeek, gridRosterDays, gridWindowScope, gridRosterCalendarRevision, gridRosterGroups, gridCurrentRosterGroup, gridPanelStaff, gridTemplateLibrary, gridTemplateLibraryUserId, gridNotificationPanelData, gridStaffSelfServicePanel, gridRenderIndexes, gridViewMode } =
    let rosterSurfaceScope = RosterWeekScopeValue
            { rosterWeekVenueId = unpackId gridWindowScope.rosterWindowVenueId
            , rosterWeekGroupId = gridWindowScope.rosterWindowRosterGroupId
            , rosterWeekWindowStart = gridWindowScope.rosterWindowStart
            , rosterWeekWindowEnd = gridWindowScope.rosterWindowEnd
            , rosterWeekCalendarRevision = gridWindowScope.rosterWindowCalendarRevision
            , rosterWeekTimelineDate = case gridViewMode of
                RosterDayTimelineGridView dayOffset -> Just (Calendar.addDays (toInteger dayOffset) gridWindowScope.rosterWindowStart)
                RosterWeekGridView                  -> Nothing
            }
        rosterSurface = rosterSurfaceImpl rosterSurfaceScope (rosterMountedFragmentPlanFromRenderData gridTemplateLibraryUserId gridRosterDays gridRenderIndexes)
        renderStaffPanelMount =
            if currentUserIsManager
                then renderrosterStaffPanelLiveFragment RosterStaffPanelRenderModel
                    { staffPanelRosterWeek = gridRosterWeek
                    , staffPanelWeekStartDate = gridModel.gridWeekStartDate
                    , staffPanelCalendarRevision = gridModel.gridRosterCalendarRevision
                    , staffPanelRosterGroups = gridRosterGroups
                    , staffPanelCurrentRosterGroup = gridCurrentRosterGroup
                    , staffPanelAssignmentFilters = gridModel.gridAssignmentFilters
                    , staffPanelViewCapabilities = gridModel.gridViewCapabilities
                    , staffPanelRosterLayoutMode = gridModel.gridRosterLayoutMode
                    , staffPanelShowWageEstimates = gridModel.gridShowWageEstimates
                    , staffPanelShowRosterWarnings = gridModel.gridShowRosterWarnings
                    , staffPanelHighlightOwnLiveShifts = gridModel.gridHighlightOwnLiveShifts
                    , staffPanelViewMode = gridViewMode
                    , staffPanelScope = RosterStaffPanelCurrentGroup
                    , staffPanelEntries = gridPanelStaff
                    , staffPanelTemplateLibrary = gridModel.gridTemplateLibrary
                    , staffPanelTemplateUserId = gridModel.gridTemplateLibraryUserId
                    , staffPanelNotificationPanelData = gridNotificationPanelData
                    }
                else mempty
        layoutBody = [hsx|
            {renderrosterContentLiveFragment gridModel}
            {renderStaffPanelMount}
            {renderRosterStaffSelfServicePanelFragment gridStaffSelfServicePanel}
        |]
        layout = if rosterHasSidePanel gridModel
            then renderSidePanelLayout rosterSidePanelRenderAttrs SidePanelRegionConfig
                { sidePanelRegionId = Just rosterLayoutFragmentId
                , sidePanelRegionClass = "row g-4 align-items-start roster-layout"
                , sidePanelRegionExtraAttrs = []
                } layoutBody
            else [hsx|
                <div id={rosterLayoutFragmentId} class="row g-4 align-items-start roster-layout">
                    {layoutBody}
                </div>
            |]
     in profileHtmlComponent "render.roster.layout" do
        renderFrontendSurfaceInteractionShell rosterSurface rosterFrontendSurfaceIR FrontendSurfaceInteractionShellConfig
            { interactionShellHtmxSync = Just ("#" <> rosterWeekShellId <> ":replace")
            , interactionShellIntentForms = rosterIntentForms rosterSurfaceScope (rosterWeekIsEditable gridRosterWeek)
            } layout

rosterOwnLiveShiftHighlightAttrs :: RosterGridRenderModel -> [(Text, Text)]
rosterOwnLiveShiftHighlightAttrs gridModel =
    case (gridModel.gridRosterWeek, gridModel.gridHighlightOwnLiveShifts, gridModel.gridCurrentViewerStaffKey) of
        (Just rosterWeek, True, Just staffKey) | rosterWeek.windowIsPublished -> rosterStaffHighlightDefaultAttrs staffKey
        _ -> []

rosterContentColumnClasses :: (?context :: ControllerContext) => RosterGridRenderModel -> Text
rosterContentColumnClasses gridModel =
    classes [("col-12", True), ("col-xl-8", hasSidePanel), ("col-xxl-9", hasSidePanel), ("mx-auto", not hasSidePanel), ("roster-layout-main", hasSidePanel)]
    where
        hasSidePanel = rosterHasSidePanel gridModel

rosterHasSidePanel :: (?context :: ControllerContext) => RosterGridRenderModel -> Bool
rosterHasSidePanel RosterGridRenderModel { gridStaffSelfServicePanel } =
    currentUserIsManager || isJust gridStaffSelfServicePanel

renderRosterContent :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterContent =
    renderRosterMainPanel

renderRosterMainPanel :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterMainPanel gridModel =
    profileHtmlComponent "render.roster.main_panel" [hsx|
        <div class="app-panel mb-5 mb-xl-0 roster-main-panel">
            <span hidden
                  {...rosterWageFilterConfigAttrs (currentUserIsAdmin && gridModel.gridShowWageEstimates) gridModel.gridRosterDays gridModel.gridRosterLayoutMode gridModel.gridViewMode}></span>
            {renderrosterGridToolbarLiveFragment gridModel}
            {renderrosterGridFrameLiveFragment gridModel}
        </div>
    |]

renderrosterGridToolbarLiveFragment :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderrosterGridToolbarLiveFragment =
    renderrosterGridToolbarLiveFragmentWithSwap Nothing

renderrosterGridToolbarLiveFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterGridRenderModel -> Html
renderrosterGridToolbarLiveFragmentWithSwap maybeSwapOob RosterGridRenderModel { gridRosterWeek, gridCurrentRosterGroup, gridWeekStartDate, gridRosterCalendarRevision, gridViewCapabilities, gridRosterWagePrediction, gridStaffSelfServicePanel, gridViewMode, gridTimelineTodayUrl } =
    profileHtmlComponent "render.roster.toolbar" [hsx|
        <div id={rosterGridToolbarFragmentId} hx-swap-oob={maybeSwapOob}>
            {renderRosterGridHeader gridRosterWeek gridRosterCalendarRevision gridCurrentRosterGroup gridWeekStartDate gridViewCapabilities gridRosterWagePrediction hasSidePanel gridViewMode gridTimelineTodayUrl}
        </div>
    |]
    where
        hasSidePanel = currentUserIsManager || isJust gridStaffSelfServicePanel

renderrosterGridFrameLiveFragment :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderrosterGridFrameLiveFragment =
    renderrosterGridFrameLiveFragmentWithSwap Nothing

renderrosterGridFrameLiveFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterGridRenderModel -> Html
renderrosterGridFrameLiveFragmentWithSwap maybeSwapOob gridModel@RosterGridRenderModel { gridRosterWeek, gridRosterDays, gridWeekStartDate, gridSlotNames, gridViewCapabilities, gridRosterLayoutMode, gridRosterEndTimesEnabled, gridShowWageEstimates, gridShowRosterWarnings, gridViewMode } =
    let slotColumnsAreEditable = gridViewCapabilities.canManageRosterColumns
        rosterIsHiddenDraft = isNothing gridRosterWeek
        isTimelineLayout = case gridViewMode of
            RosterDayTimelineGridView _ -> True
            RosterWeekGridView          -> False
        isDayColumnsLayout = not rosterIsHiddenDraft && not isTimelineLayout && rosterLayoutModeIsDayColumns gridRosterLayoutMode
        frameLayoutValue = case gridViewMode of
            RosterDayTimelineGridView _ -> "timeline"
            RosterWeekGridView -> if rosterIsHiddenDraft then ("hidden_draft" :: Text) else rosterLayoutModeValue gridRosterLayoutMode
        gridBody = case gridViewMode of
            RosterDayTimelineGridView dayOffset ->
                let selectedDate = Calendar.addDays (toInteger dayOffset) gridWeekStartDate
                 in case find ((== selectedDate) . (.operationalDate)) gridRosterDays of
                        Nothing -> [hsx|<div class="alert alert-warning mb-0">Selected timeline day is not available.</div>|]
                        Just rosterDay -> renderRosterDayTimelinePanel gridModel rosterDay
            RosterWeekGridView -> renderRosterGridInnerFragments gridModel
        frameHtml = profileHtmlComponent "render.roster.grid_frame" [hsx|
        <div id={rosterGridFrameFragmentId}
             class={classes [("roster-grid-frame", True), ("roster-grid-frame-timeline", isTimelineLayout), ("app-horizontal-frame", isDayColumnsLayout)]}
             hx-swap-oob={maybeSwapOob}
             data-roster-layout={frameLayoutValue}
             data-roster-visibility={if rosterIsHiddenDraft then ("hidden-draft" :: Text) else "visible"}
             {...if isDayColumnsLayout
                    then horizontalSnapAttrs (HorizontalSnapNearestItem ".roster-day-column")
                        <> horizontalDragAttrs (HorizontalDragConfig (Just "[data-roster-shift-launcher]"))
                    else []}
             data-roster-end-times={if gridRosterEndTimesEnabled then ("true" :: Text) else "false"}
             {...rosterColumnEditorAttrs RosterColumnEditingInactive}
             data-roster-wages={if gridShowWageEstimates && not rosterIsHiddenDraft then ("visible" :: Text) else "hidden"}
             data-roster-warnings={if gridShowRosterWarnings && not rosterIsHiddenDraft then ("visible" :: Text) else "hidden"}
             {...if not rosterIsHiddenDraft && not isTimelineLayout && not isDayColumnsLayout then rosterImageExportProjectionAttrs else []}>
            {gridBody}
        </div>
|]
     in frameHtml

rosterDayRenderModelFromGrid :: (?context :: ControllerContext) => RosterGridRenderModel -> RosterDayRenderModel
rosterDayRenderModelFromGrid RosterGridRenderModel { gridRosterWeek, gridAssignmentFilters, gridStaffMembers, gridSlotNames, gridShiftTypes, gridWeekStartDate, gridRosterCalendarRevision, gridAllSlots, gridSlotConflicts, gridRenderIndexes, gridRosterLayoutMode, gridRosterEndTimesEnabled, gridRosterWagePrediction, gridShowWageEstimates, gridShowRosterWarnings, gridPublicHolidays, gridPublishAttempted } =
    RosterDayRenderModel
        { dayIsEditable = rosterWeekIsEditable gridRosterWeek
        , daySlotNames = gridSlotNames
        , dayAssignmentFilters = gridAssignmentFilters
        , dayStaffMembers = gridStaffMembers
        , dayShiftTypes = gridShiftTypes
        , dayWeekStartDate = gridWeekStartDate
        , dayCalendarRevision = gridRosterCalendarRevision
        , dayAllSlots = gridAllSlots
        , daySlotConflicts = gridSlotConflicts
        , dayRenderIndexes = gridRenderIndexes
        , dayRosterLayoutMode = gridRosterLayoutMode
        , dayRosterEndTimesEnabled = gridRosterEndTimesEnabled
        , dayRosterWagePrediction = gridRosterWagePrediction
        , dayShowWageEstimates = gridShowWageEstimates
        , dayShowRosterWarnings = gridShowRosterWarnings
        , dayPublicHolidays = gridPublicHolidays
        , dayPublishAttempted = gridPublishAttempted
        }

renderRosterGridInnerFragments :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterGridInnerFragments gridModel@RosterGridRenderModel { gridRosterWeek, gridRosterDays, gridSlotNames, gridViewCapabilities, gridRosterLayoutMode, gridRosterEndTimesEnabled } =
    let dayModel = rosterDayRenderModelFromGrid gridModel
        slotColumnsAreEditable = gridViewCapabilities.canManageRosterColumns
     in if isNothing gridRosterWeek
            then renderHiddenDraftRosterGrid dayModel gridRosterDays
            else if rosterLayoutModeIsDayColumns gridRosterLayoutMode
                then renderrosterDayColumnsLiveFragment dayModel gridRosterDays
                else renderRosterDayRowsGrid gridRosterEndTimesEnabled slotColumnsAreEditable gridRosterWeek gridSlotNames dayModel gridRosterDays

renderDayRowsWageAmount :: Maybe RosterWagePrediction -> Day -> Html
renderDayRowsWageAmount Nothing _ = mempty
renderDayRowsWageAmount (Just prediction) date =
    case lookupRosterWagePredictionDayByDate prediction date of
        Nothing -> mempty
        Just dayPrediction -> [hsx|
            <div class="roster-day-wage-total" aria-label="Wages for day">
                {formatMoneyAmount dayPrediction.predictionDayTotal}
            </div>
        |]

renderDayColumnWageEstimate :: Maybe RosterWagePrediction -> Day -> Html
renderDayColumnWageEstimate Nothing _ = mempty
renderDayColumnWageEstimate (Just prediction) date =
    case lookupRosterWagePredictionDayByDate prediction date of
        Nothing -> mempty
        Just dayPrediction -> [hsx|
            <div class="roster-day-wage-total roster-day-wage-total-labeled" aria-label="Wages for day">
                <span class="roster-day-wage-label">Wages</span>
                <span>{formatMoneyAmount dayPrediction.predictionDayTotal}</span>
            </div>
        |]

rosterSlotsHorizontalSnapConfig :: HorizontalSnapConfig
rosterSlotsHorizontalSnapConfig = HorizontalSnapEqualGroups (HorizontalSnapGroupProperty
    { horizontalSnapGroupProperty = "--roster-slot-count"
    , horizontalSnapGroupScopeSelector = ".roster-slots-scroller"
    })

renderRosterDayRowsGrid :: (?context :: ControllerContext) => Bool -> Bool -> Maybe RosterWindowState -> [RosterWindowLane] -> RosterDayRenderModel -> [RosterDay] -> Html
renderRosterDayRowsGrid endTimesEnabled slotColumnsAreEditable maybeRosterWeek slotNames dayModel rosterDays = [hsx|
    {renderrosterDayRailLiveFragment slotColumnsAreEditable dayModel rosterDays}
    {when dayModel.dayShowWageEstimates (renderrosterWageRailLiveFragment dayModel rosterDays)}
    {renderrosterSlotsGridLiveFragment endTimesEnabled slotColumnsAreEditable maybeRosterWeek slotNames dayModel rosterDays}
|]

renderrosterDayRailLiveFragment :: (?context :: ControllerContext) => Bool -> RosterDayRenderModel -> [RosterDay] -> Html
renderrosterDayRailLiveFragment =
    renderrosterDayRailLiveFragmentWithSwap Nothing

renderrosterDayRailLiveFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Bool -> RosterDayRenderModel -> [RosterDay] -> Html
renderrosterDayRailLiveFragmentWithSwap maybeSwapOob slotColumnsAreEditable dayModel rosterDays = [hsx|
    <div id={rosterDayRailFragmentId} class="roster-day-rail" aria-label="Roster days" hx-swap-oob={maybeSwapOob}>
        <div class="roster-day-rail-head" {...rosterImageExportRowAttrs} {...rosterImageExportCellAttrs "Day"}>
            <span class="roster-day-rail-head-label">Day</span>
            {renderRosterColumnEditStartButton slotColumnsAreEditable}
            {renderRosterColumnEditDoneButton slotColumnsAreEditable}
        </div>
        <div class="roster-day-rail-body">
            {forEach rosterDays (renderRosterDayRailSection dayModel)}
        </div>
    </div>
|]

renderHiddenDraftRosterGrid :: (?context :: ControllerContext) => RosterDayRenderModel -> [RosterDay] -> Html
renderHiddenDraftRosterGrid dayModel rosterDays = [hsx|
    {renderHiddenDraftDayRailFragment dayModel rosterDays}
    {renderHiddenDraftSlotsGridFragment rosterDays}
|]

renderHiddenDraftDayRailFragment :: (?context :: ControllerContext) => RosterDayRenderModel -> [RosterDay] -> Html
renderHiddenDraftDayRailFragment =
    renderHiddenDraftDayRailFragmentWithSwap Nothing

renderHiddenDraftDayRailFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterDayRenderModel -> [RosterDay] -> Html
renderHiddenDraftDayRailFragmentWithSwap maybeSwapOob dayModel rosterDays = [hsx|
    <div id={rosterDayRailFragmentId} class="roster-day-rail" aria-label="Roster days" hx-swap-oob={maybeSwapOob}>
        <div class="roster-day-rail-head">
            <span class="roster-day-rail-head-label">Day</span>
        </div>
        <div class="roster-day-rail-body">
            {forEach rosterDays (renderHiddenDraftDayRailSection dayModel)}
        </div>
    </div>
|]

renderHiddenDraftSlotsGridFragment :: [RosterDay] -> Html
renderHiddenDraftSlotsGridFragment =
    renderHiddenDraftSlotsGridFragmentWithSwap Nothing

renderHiddenDraftSlotsGridFragmentWithSwap :: Maybe Text -> [RosterDay] -> Html
renderHiddenDraftSlotsGridFragmentWithSwap maybeSwapOob _rosterDays = [hsx|
    <div id={rosterSlotsGridFragmentId}
         class="roster-slots-scroller"
         style="--roster-slot-count:1;"
         hx-swap-oob={maybeSwapOob}>
        <div class="roster-grid roster-slots-grid roster-hidden-draft-grid"
             role="region"
             aria-label="Roster visibility">
            <div class="roster-hidden-draft-grid-head" aria-hidden="true"></div>
            <div class="roster-hidden-draft-grid-body" role="status" aria-live="polite">
                <div class="roster-hidden-draft-message">This roster is still Draft.</div>
            </div>
        </div>
    </div>
|]

renderrosterSlotsGridLiveFragment :: (?context :: ControllerContext) => Bool -> Bool -> Maybe RosterWindowState -> [RosterWindowLane] -> RosterDayRenderModel -> [RosterDay] -> Html
renderrosterSlotsGridLiveFragment =
    renderrosterSlotsGridLiveFragmentWithSwap Nothing

renderrosterSlotsGridLiveFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Bool -> Bool -> Maybe RosterWindowState -> [RosterWindowLane] -> RosterDayRenderModel -> [RosterDay] -> Html
renderrosterSlotsGridLiveFragmentWithSwap maybeSwapOob endTimesEnabled slotColumnsAreEditable maybeRosterWeek slotNames dayModel rosterDays =
    let gridHeaders = profileHtmlComponent "render.roster.slots_grid_headers" [hsx|
            <div class="roster-grid-head" role="rowgroup">
                <div class="roster-grid-header-row roster-grid-header-row-blocks" role="row" {...rosterImageExportRowAttrs}>
                    {forEach (zip [0 :: Int ..] slotNames) (renderSlotHeaderGroup endTimesEnabled dayModel.dayWeekStartDate dayModel.dayCalendarRevision maybeRosterWeek slotColumnsAreEditable (length slotNames))}
                </div>
                <div class="roster-grid-header-row roster-grid-header-row-subheads" role="row" {...rosterImageExportRowAttrs}>
                    {forEach slotNames (renderSlotSubHeaders endTimesEnabled)}
                </div>
            </div>
        |]
        gridBody = profileHtmlComponent "render.roster.slots_grid_body" [hsx|{forEach rosterDays (renderRosterDay dayModel)}|]
     in profileHtmlComponent "render.roster.slots_grid_component" [hsx|
        {profileRenderCounter "render.roster.slots_grid" 1}
        {profileRenderCounter "render.roster.day" (length rosterDays)}
        {profileRenderCounter "render.roster.slot_definition" (length slotNames)}
        <div id={rosterSlotsGridFragmentId}
             class="roster-slots-scroller"
             style={"--roster-slot-count:" <> tshow (max 1 (length slotNames)) <> ";"}
             {...horizontalSnapAttrs rosterSlotsHorizontalSnapConfig}
             hx-swap-oob={maybeSwapOob}>
            <div class="roster-grid roster-slots-grid" role="grid" aria-label="Roster slots">
                {gridHeaders}
                {gridBody}
            </div>
        </div>
    |]

rosterWeekIsEditable :: (?context :: ControllerContext) => Maybe RosterWindowState -> Bool
rosterWeekIsEditable maybeRosterWeek =
    currentUserIsManager && maybe False (not . (.windowIsPublished)) maybeRosterWeek

renderRosterColumnEditStartButton :: Bool -> Html
renderRosterColumnEditStartButton True = [hsx|
    <button type="button"
            class="btn btn-sm btn-outline-secondary"
            {...rosterColumnEditStartAttrs}
            aria-label="Edit roster columns"
            aria-pressed="false"
            title="Edit roster columns">
        <i class="bi bi-pencil" aria-hidden="true"></i>
    </button>
|]
renderRosterColumnEditStartButton False = mempty

renderRosterColumnEditDoneButton :: Bool -> Html
renderRosterColumnEditDoneButton True = [hsx|
    <button type="button"
            class="btn btn-sm btn-outline-success"
            {...rosterColumnEditDoneAttrs}
            aria-label="Finish editing roster columns"
            title="Finish editing roster columns">
        <i class="bi bi-check-lg" aria-hidden="true"></i>
    </button>
|]
renderRosterColumnEditDoneButton False = mempty

renderSlotHeaderGroup :: (?context :: ControllerContext) => Bool -> Day -> Int -> Maybe RosterWindowState -> Bool -> Int -> (Int, RosterWindowLane) -> Html
renderSlotHeaderGroup endTimesEnabled _ _ _ False _ (slotIndex, _) = [hsx|
    <div role="columnheader"
         class="roster-block-header"
         aria-label={"Roster column " <> tshow (slotIndex + 1)}
         style={slotHeaderGridColumnStyle endTimesEnabled}
         {...rosterImageExportCellAttrs ""}></div>
|]
renderSlotHeaderGroup endTimesEnabled anchorDate calendarRevision (Just rosterWeek) True slotCount (slotIndex, slotName) = [hsx|
    <div role="columnheader"
         class="roster-block-header"
         aria-label={"Roster column " <> tshow (slotIndex + 1)}
         style={slotHeaderGridColumnStyle endTimesEnabled}
         {...rosterImageExportCellAttrs ""}>
        <div class="d-flex align-items-center justify-content-center gap-2 roster-slot-column-header">
            {renderSlotDeleteForm anchorDate calendarRevision rosterWeek.windowRosterGroupId slotCount slotName}
            {renderSlotAddButton anchorDate calendarRevision rosterWeek (slotIndex == slotCount - 1)}
        </div>
    </div>
|]
renderSlotHeaderGroup endTimesEnabled _ _ _ _ _ (slotIndex, _) = [hsx|
    <div role="columnheader"
         class="roster-block-header"
         aria-label={"Roster column " <> tshow (slotIndex + 1)}
         style={slotHeaderGridColumnStyle endTimesEnabled}
         {...rosterImageExportCellAttrs ""}></div>
|]

renderSlotDeleteForm :: Day -> Int -> UUID -> Int -> RosterWindowLane -> Html
renderSlotDeleteForm anchorDate calendarRevision rosterGroupId slotCount windowLane =
    renderFrontendSurfaceActionForm
        (RosterAction.deleteRosterWeekSlotDefinitionAction (RosterAction.deleteRosterWeekSlotDefinitionActionFields calendarRevision))
        (rosterGridActionRoute (appendQueryParams (pathTo (RemoveRosterWeekSlotDefinitionAction (rosterWindowLaneRepresentative windowLane).id)) [("anchorDate", tshow anchorDate), ("rosterGroupId", tshow rosterGroupId)]))
            { actionRouteExtraAttrs = [("class", "mb-0")]
            }
        [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision (RosterAction.deleteRosterWeekSlotDefinitionActionFields calendarRevision)} value={tshow calendarRevision} />
            <button type="submit"
                    class="btn btn-sm btn-outline-danger roster-slot-column-delete"
                    aria-label="Remove roster column"
                    title="Remove roster column"
                    disabled={slotCount <= 1}>
                <i class="bi bi-trash" aria-hidden="true"></i>
            </button>
        |]

slotHeaderGridColumnStyle :: Bool -> Text
slotHeaderGridColumnStyle endTimesEnabled =
    rosterGridColumnSpanStyle (slotColumnCount endTimesEnabled)

renderSlotAddButton :: (?context :: ControllerContext) => Day -> Int -> RosterWindowState -> Bool -> Html
renderSlotAddButton anchorDate calendarRevision rosterWeek True =
    renderFrontendSurfaceActionForm
        (RosterAction.createRosterWeekSlotDefinitionAction (RosterAction.createRosterWeekSlotDefinitionActionFields calendarRevision))
        (rosterGridActionRoute (appendQueryParams (pathTo CreateRosterWeekSlotDefinitionAction) [("anchorDate", tshow anchorDate), ("rosterGroupId", tshow rosterWeek.windowRosterGroupId)]))
            { actionRouteExtraAttrs = [("class", "mb-0 roster-slot-column-add-form")]
            }
        [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision (RosterAction.createRosterWeekSlotDefinitionActionFields calendarRevision)} value={tshow calendarRevision} />
            <button type="submit"
                    class="btn btn-sm btn-outline-primary roster-slot-column-add"
                    aria-label="Add roster column"
                    title="Add roster column">
                <i class="bi bi-plus-lg" aria-hidden="true"></i>
            </button>
        |]
renderSlotAddButton _ _ _ False = mempty

renderSlotSubHeaders :: Bool -> RosterWindowLane -> Html
renderSlotSubHeaders True _ =
    mconcat
        [ [hsx|<div role="columnheader" class="roster-subhead roster-col-time" {...rosterImageExportCellAttrs "Start"}>Start</div>|]
        , [hsx|<div role="columnheader" class="roster-subhead roster-col-time" {...rosterImageExportCellAttrs "End"}>End</div>|]
        , [hsx|<div role="columnheader" class="roster-subhead roster-col-staff" {...rosterImageExportCellAttrs "Staff"}>Staff</div>|]
        , [hsx|<div role="columnheader" class="roster-subhead roster-col-shift-type roster-block-end" {...rosterImageExportCellAttrs "Role"}>Role</div>|]
        ]
renderSlotSubHeaders False _ =
    mconcat
        [ [hsx|<div role="columnheader" class="roster-subhead roster-col-time" {...rosterImageExportCellAttrs "Start"}>Start</div>|]
        , [hsx|<div role="columnheader" class="roster-subhead roster-col-staff" {...rosterImageExportCellAttrs "Staff"}>Staff</div>|]
        , [hsx|<div role="columnheader" class="roster-subhead roster-col-code roster-block-end" {...rosterImageExportCellAttrs "Role"}>Role</div>|]
        ]

renderRosterDay :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Html
renderRosterDay =
    renderRosterDaySectionFragment

rosterDayIndex :: Day -> RosterDay -> Int
rosterDayIndex windowStart rosterDay =
    fromInteger (Calendar.diffDays rosterDay.operationalDate windowStart)

renderRosterDaySectionFragment :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Html
renderRosterDaySectionFragment =
    renderRosterDaySectionFragmentWithSwap Nothing


renderRosterDaySectionFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterDayRenderModel -> RosterDay -> Html
renderRosterDaySectionFragmentWithSwap maybeSwapOob dayModel@RosterDayRenderModel { dayRosterLayoutMode } rosterDay
    | rosterLayoutModeIsDayColumns dayRosterLayoutMode =
        renderRosterDayColumnWithSwap maybeSwapOob dayModel rosterDay
renderRosterDaySectionFragmentWithSwap maybeSwapOob dayModel@RosterDayRenderModel { dayIsEditable, dayAllSlots, dayRenderIndexes } rosterDay =
    profileHtmlComponent "render.roster.day_section_component" [hsx|
    {profileRenderCounter "render.roster.day_section" 1}
    {profileRenderCounter "render.roster.row" (length dayRows)}
    <div id={rosterDaySectionDomId rosterDay.id}
         class="roster-grid-day-section"
         role="rowgroup"
         data-roster-day-section="true"
         hx-swap-oob={maybeSwapOob}
         style={"--roster-day-row-count:" <> tshow (length dayRows) <> ";"}>
        {renderDayRows dayModel rosterDay.operationalDate rosterDay dayRows}
    </div>
|]
    where
        dayRows = Map.findWithDefault (rowsForDay rosterDay daySlots) (coerce (get #id rosterDay)) dayRenderIndexes.rosterDayRowsByDayId
        daySlots = filter (\s -> s.rosterDayId == coerce (get #id rosterDay)) dayAllSlots

renderRosterDayRailSection :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Html
renderRosterDayRailSection RosterDayRenderModel { dayIsEditable, dayWeekStartDate, dayCalendarRevision, dayAllSlots, dayRenderIndexes, dayPublicHolidays } rosterDay =
    let daySlots = filter (\s -> s.rosterDayId == coerce (get #id rosterDay)) dayAllSlots
        dayRows = Map.findWithDefault (rowsForDay rosterDay daySlots) (coerce (get #id rosterDay)) dayRenderIndexes.rosterDayRowsByDayId
        rowCount = length dayRows
        lastRowIndex = lastRowIndexForRows dayRows
        date = rosterDay.operationalDate
        dayIndex = rosterDayIndex dayWeekStartDate rosterDay
     in [hsx|
        <div class={classes [("roster-day-rail-section", True), ("day-alt-dark", odd dayIndex), ("day-alt-light", even dayIndex)]}
             style={"--roster-day-label-rows:" <> tshow rowCount}
             {...rosterImageExportRowAttrs}
             {...rosterImageExportCellAttrs (rosterDayImageExportText date)}>
            <div class="roster-day-label-stack">
                <div class="roster-day-label-row roster-day-label-row-primary">
                    <div class="roster-day-heading">
                        {renderPrimaryDayLabel (Map.lookup date dayPublicHolidays) date}
                        {renderTimelineLink rosterDay}
                    </div>
                </div>
                <div class="roster-day-label-row roster-day-label-row-controls">
                    {renderDayRowControls dayIsEditable dayCalendarRevision rosterDay lastRowIndex}
                </div>
                {renderEmptyDayLabelRows rowCount 2}
            </div>
        </div>
    |]

renderHiddenDraftDayRailSection :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Html
renderHiddenDraftDayRailSection RosterDayRenderModel { dayWeekStartDate, dayPublicHolidays } rosterDay =
    let date = rosterDay.operationalDate
        dayIndex = rosterDayIndex dayWeekStartDate rosterDay
     in [hsx|
        <div class={classes [("roster-day-rail-section", True), ("roster-day-rail-section-hidden-draft", True), ("day-alt-dark", odd dayIndex), ("day-alt-light", even dayIndex)]}>
            <div class="roster-day-label-stack">
                <div class="roster-day-label-row roster-day-label-row-primary">
                    <div class="roster-day-heading">
                        {renderPrimaryDayLabel (Map.lookup date dayPublicHolidays) date}
                        {renderTimelineLink rosterDay}
                    </div>
                </div>
            </div>
        </div>
    |]

renderrosterWageRailLiveFragment :: RosterDayRenderModel -> [RosterDay] -> Html
renderrosterWageRailLiveFragment =
    renderrosterWageRailLiveFragmentWithSwap Nothing

renderrosterWageRailLiveFragmentWithSwap :: Maybe Text -> RosterDayRenderModel -> [RosterDay] -> Html
renderrosterWageRailLiveFragmentWithSwap maybeSwapOob dayModel rosterDays = [hsx|
    <div id={rosterWageRailFragmentId} class="roster-wage-rail" aria-label="Roster wages" hx-swap-oob={maybeSwapOob}>
        <div class="roster-wage-rail-head">Wages</div>
        <div class="roster-wage-rail-body">
            {forEach rosterDays (renderRosterWageRailSection dayModel)}
        </div>
    </div>
|]

renderRosterWageRailSection :: RosterDayRenderModel -> RosterDay -> Html
renderRosterWageRailSection RosterDayRenderModel { dayWeekStartDate, dayAllSlots, dayRenderIndexes, dayRosterWagePrediction } rosterDay =
    let daySlots = filter (\s -> s.rosterDayId == coerce (get #id rosterDay)) dayAllSlots
        dayRows = Map.findWithDefault (rowsForDay rosterDay daySlots) (coerce (get #id rosterDay)) dayRenderIndexes.rosterDayRowsByDayId
        rowCount = length dayRows
        date = rosterDay.operationalDate
        dayIndex = rosterDayIndex dayWeekStartDate rosterDay
     in [hsx|
        <div class={classes [("roster-wage-rail-section", True), ("day-alt-dark", odd dayIndex), ("day-alt-light", even dayIndex)]}
             style={"--roster-day-label-rows:" <> tshow rowCount}>
            {renderDayRowsWageAmount dayRosterWagePrediction date}
        </div>
    |]

renderrosterDayColumnsLiveFragment :: (?context :: ControllerContext) => RosterDayRenderModel -> [RosterDay] -> Html
renderrosterDayColumnsLiveFragment =
    renderrosterDayColumnsLiveFragmentWithSwap Nothing

renderrosterDayColumnsLiveFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterDayRenderModel -> [RosterDay] -> Html
renderrosterDayColumnsLiveFragmentWithSwap maybeSwapOob dayModel rosterDays = [hsx|
    <div id={rosterDayColumnsFragmentId} class="roster-day-columns app-horizontal-grid" hx-swap-oob={maybeSwapOob} style={"--roster-day-count:" <> tshow (max 1 (length rosterDays)) <> ";"}>
        {forEach rosterDays (renderRosterDayColumn dayModel)}
        <div class="roster-day-columns-end-buffer" aria-hidden="true"></div>
    </div>
|]

renderRosterDayColumn :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Html
renderRosterDayColumn =
    renderRosterDayColumnWithSwap Nothing

renderRosterDayColumnWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterDayRenderModel -> RosterDay -> Html
renderRosterDayColumnWithSwap maybeSwapOob dayModel@RosterDayRenderModel { dayIsEditable, dayWeekStartDate, dayAllSlots, dayRenderIndexes, dayRosterWagePrediction, dayPublicHolidays } rosterDay =
    let daySlots = filter (\s -> s.rosterDayId == coerce (get #id rosterDay)) dayAllSlots
        dayRows = Map.findWithDefault (rowsForDay rosterDay daySlots) (coerce (get #id rosterDay)) dayRenderIndexes.rosterDayRowsByDayId
        rowCount = length dayRows
        lastRowIndex = lastRowIndexForRows dayRows
        date = rosterDay.operationalDate
        dayIndex = rosterDayIndex dayWeekStartDate rosterDay
        compactSlots = if rosterDay.isClosed then [] else compactDayColumnSlots dayModel.daySlotNames daySlots
        maybeCreateTarget = if rosterDay.isClosed then Nothing else firstAvailableDayColumnTarget dayModel.daySlotNames rosterDay dayModel.dayCalendarRevision daySlots
        dayDropzoneKey = "day:" <> tshow rosterDay.id
        columnHtml = [hsx|
            <section id={rosterDaySectionDomId rosterDay.id}
                     data-roster-day-section="true"
                     role="group"
                     hx-swap-oob={maybeSwapOob}
                     class={classes [("roster-day-column", True), ("app-horizontal-panel", True), ("day-alt-dark", odd dayIndex), ("day-alt-light", even dayIndex)]}>
                <header class="roster-day-column-header">
                    <div class="roster-day-heading">
                        {renderPrimaryDayLabel (Map.lookup date dayPublicHolidays) date}
                        {renderTimelineLink rosterDay}
                    </div>
                    <div class="roster-day-column-wage-slot">
                        {renderDayColumnWageEstimate dayRosterWagePrediction date}
                    </div>
                    <div class="roster-day-column-control-slot">
                        {renderDayColumnHeaderControls dayIsEditable dayModel.dayCalendarRevision rosterDay}
                    </div>
                </header>
                <div class="roster-day-column-body">
                    {forEach compactSlots (renderDayColumnRosterSlotCard dayModel rosterDay)}
                    {renderDayColumnCreateCard dayModel rosterDay maybeCreateTarget}
                </div>
            </section>
        |]
     in if dayIsEditable && not rosterDay.isClosed
            then SurfaceInteraction.withFrontendSurfaceDropzoneRef rosterDayColumnDropzoneRef dayDropzoneKey columnHtml
            else columnHtml

compactDayColumnSlots :: [RosterWindowLane] -> [RosterSlot] -> [RosterSlot]
compactDayColumnSlots slotNames daySlots =
    sortOn slotOrder (filter rosterSlotHasVisibleData daySlots)
  where
    definitionOrderById =
        Map.fromList
            [ (unpackId lane.id, slotIndex)
            | (slotIndex, windowLane) <- zip [0 :: Int ..] slotNames
            , lane <- Map.elems windowLane.rosterWindowLaneByDate
            ]
    slotOrder slot =
        ( isNothing slot.startsAt
        , rosterSlotStartTime slot
        , Map.findWithDefault (length slotNames) slot.rosterLaneId definitionOrderById
        , slot.rowIndex
        , slot.createdAt
        , slot.id
        )

firstAvailableDayColumnTarget :: [RosterWindowLane] -> RosterDay -> Int -> [RosterSlot] -> Maybe RosterSlotCellTarget
firstAvailableDayColumnTarget [] _ _ _ = Nothing
firstAvailableDayColumnTarget slotNames rosterDay calendarRevision daySlots =
    let occupiedCells =
            Map.fromList
                [ ((slot.rosterLaneId, slot.rowIndex), ())
                | slot <- daySlots
                , rosterSlotHasVisibleData slot
                ]
        rowCount = max minimumOpenRosterRows rosterDay.rowCount
        dayLanes = mapMaybe (laneForOperationalDate rosterDay.operationalDate) slotNames
        candidateCells =
            [ (lane, rowIndex)
            | lane <- dayLanes
            , rowIndex <- [0 .. rowCount - 1]
            ]
        firstFree =
            find
                (\(slotName, rowIndex) -> Map.notMember (unpackId slotName.id, rowIndex) occupiedCells)
                candidateCells
     in case firstFree <|> fmap (\lane -> (lane, rowCount)) (listToMaybe dayLanes) of
            Nothing -> Nothing
            Just (slotName, rowIndex) -> Just (NewRosterSlotTarget rosterDay.id slotName.id (Id rosterDay.rosterGroupId) rosterDay.operationalDate calendarRevision rowIndex)

rosterSlotHasVisibleData :: RosterSlot -> Bool
rosterSlotHasVisibleData slot =
    isJust slot.staffId
        || isJust slot.startsAt
        || isJust slot.endsAt
        || isJust slot.shiftTypeId

renderDayColumnRow :: (?context :: ControllerContext) => RosterRowRenderModel -> (Int, (Int, [RosterSlot])) -> Maybe Text -> Html
renderDayColumnRow RosterRowRenderModel { rowIsEditable, rowSlotNames, rowAssignmentFilters, rowStaffMembers, rowShiftTypes, rowDayIndex, rowRosterDay, rowCalendarRevision, rowRenderIndexes, rowRosterEndTimesEnabled, rowPublishAttempted } (_, (rowIndex, rowSlots)) maybeSwapOob = [hsx|
    <div id={rosterRowDomIdText rowRosterDay.id rowIndex}
         data-roster-row="true"
         hx-swap-oob={maybeSwapOob}
         class={classes [("roster-day-column-row", True), ("day-row-" <> tshow rowDayIndex, True)]}>
        {forEach (zip [0 :: Int ..] rowSlotNames) (renderDayColumnSlotCard rowIsEditable rowAssignmentFilters rowStaffMembers rowShiftTypes rowRosterEndTimesEnabled rowPublishAttempted rowRosterDay rowCalendarRevision rowIndex rowSlots rowRenderIndexes)}
    </div>
|]

rowsForDay :: RosterDay -> [RosterSlot] -> [(Int, [RosterSlot])]
rowsForDay rosterDay slots =
    map (\rowIndex -> (rowIndex, Map.findWithDefault [] rowIndex slotsByRowIndex)) visibleIndices
    where
        slotsByRowIndex = Map.fromListWith (<>) [ (slot.rowIndex, [slot]) | slot <- slots ]
        highestSlotRowIndex = maximum (0 : map (.rowIndex) slots)
        visibleIndices
            | rosterDay.isClosed = [0 .. closedRosterDayRows - 1]
            | otherwise = [0 .. max highestSlotRowIndex (max minimumOpenRosterRows rosterDay.rowCount - 1)]

lastRowIndexForRows :: [(Int, [RosterSlot])] -> Int
lastRowIndexForRows dayRows = maybe (-1) fst (last dayRows)

renderDayRows :: (?context :: ControllerContext) => RosterDayRenderModel -> Day -> RosterDay -> [(Int, [RosterSlot])] -> Html
renderDayRows RosterDayRenderModel { dayIsEditable, daySlotNames, dayAssignmentFilters, dayStaffMembers, dayShiftTypes, dayWeekStartDate, dayCalendarRevision, dayRenderIndexes, dayRosterLayoutMode, dayRosterEndTimesEnabled, dayPublishAttempted } date rosterDay dayRows =
    let rowModel =
            RosterRowRenderModel
                { rowIsEditable = dayIsEditable
                , rowSlotNames = daySlotNames
                , rowAssignmentFilters = dayAssignmentFilters
                , rowStaffMembers = dayStaffMembers
                , rowShiftTypes = dayShiftTypes
                , rowDate = date
                , rowDayIndex = rosterDayIndex dayWeekStartDate rosterDay
                , rowRosterDay = rosterDay
                , rowCalendarRevision = dayCalendarRevision
                , rowCount
                , rowLastRowIndex = lastRowIndex
                , rowRenderIndexes = dayRenderIndexes
                , rowRosterLayoutMode = dayRosterLayoutMode
                , rowRosterEndTimesEnabled = dayRosterEndTimesEnabled
                , rowPublishAttempted = dayPublishAttempted
                }
     in [hsx|
    {forEach indexedRows (renderRow rowModel)}
|]
    where
        rowCount = length dayRows
        lastRowIndex = lastRowIndexForRows dayRows
        indexedRows = zip [0 :: Int ..] dayRows

renderRow :: (?context :: ControllerContext) => RosterRowRenderModel -> (Int, (Int, [RosterSlot])) -> Html
renderRow rowModel rowData =
    renderRowWithAttrs rowModel rowData Nothing

renderRowFragment :: (?context :: ControllerContext) => RosterRowRenderModel -> (Int, (Int, [RosterSlot])) -> Html
renderRowFragment = renderRow

renderRowOob :: (?context :: ControllerContext) => RosterRowRenderModel -> (Int, (Int, [RosterSlot])) -> Html
renderRowOob rowModel rowData =
    [hsx|<template>{renderRowWithAttrs rowModel rowData (Just "outerHTML")}</template>|]

renderRowWithAttrs :: (?context :: ControllerContext) => RosterRowRenderModel -> (Int, (Int, [RosterSlot])) -> Maybe Text -> Html
renderRowWithAttrs rowModel@RosterRowRenderModel { rowRosterLayoutMode } rowData maybeSwapOob
    | rosterLayoutModeIsDayColumns rowRosterLayoutMode =
        renderDayColumnRow rowModel rowData maybeSwapOob
renderRowWithAttrs RosterRowRenderModel { rowIsEditable, rowSlotNames, rowAssignmentFilters, rowStaffMembers, rowShiftTypes, rowDayIndex, rowRosterDay, rowCalendarRevision, rowRenderIndexes, rowRosterEndTimesEnabled, rowPublishAttempted } (_, (rowIndex, rowSlots)) maybeSwapOob =
    profileHtmlComponent "render.roster.row_component" [hsx|
    {profileRenderCounter "render.roster.row_render" 1}
    <div id={rosterRowDomIdText rowRosterDay.id rowIndex}
         role="row"
         data-roster-row="true"
         hx-swap-oob={maybeSwapOob}
         class={classes [("day-row", True), ("day-row-" <> tshow rowDayIndex, True), ("day-alt-dark", odd rowDayIndex), ("day-alt-light", even rowDayIndex)]}
         {...rosterImageExportRowAttrs}>
        {forEach (zip [0 :: Int ..] rowSlotNames) (renderBlockCells rowIsEditable rowAssignmentFilters rowStaffMembers rowShiftTypes rowRosterEndTimesEnabled rowPublishAttempted rowRosterDay rowCalendarRevision rowIndex rowSlots rowRenderIndexes)}
    </div>
|]

rosterDayImageExportText :: Day -> Text
rosterDayImageExportText date = Text.pack (formatTime defaultTimeLocale "%a %d/%m" date)

renderPrimaryDayLabel :: Maybe Text -> Day -> Html
renderPrimaryDayLabel maybeHolidayName date = [hsx|
    <div class="roster-day-date">
        {renderPublicHolidayIndicator maybeHolidayName}
        <span>{Text.pack (formatTime defaultTimeLocale "%a" date)} {Text.pack (formatTime defaultTimeLocale "%d/%m" date)}</span>
    </div>
|]

renderTimelineLink :: RosterDay -> Html
renderTimelineLink _ = mempty

renderPublicHolidayIndicator :: Maybe Text -> Html
renderPublicHolidayIndicator Nothing = mempty
renderPublicHolidayIndicator (Just holidayName) = [hsx|
    <span class="roster-public-holiday-indicator"
          title={holidayName}
          aria-label={"Public holiday: " <> holidayName}
          role="img">🎉</span>
|]

renderEmptyDayLabelRows :: Int -> Int -> Html
renderEmptyDayLabelRows rowCount consumedRows =
    mconcat (map (\_ -> [hsx|<div class="roster-day-label-row roster-day-label-row-empty" aria-hidden="true"></div>|]) [consumedRows + 1 .. rowCount])

renderDayRowControls :: (?context :: ControllerContext) => Bool -> Int -> RosterDay -> Int -> Html
renderDayRowControls isEditable calendarRevision rosterDay lastRowIndex
    | isEditable =
        [hsx|
            <span class="roster-day-actions">
                {renderToggleClosedButton calendarRevision rosterDay}
                {when (not rosterDay.isClosed) (renderDeleteLastRowButton calendarRevision rosterDay lastRowIndex)}
                {when (not rosterDay.isClosed) (renderAddRowButton calendarRevision rosterDay)}
            </span>
        |]
    | rosterDay.isClosed =
        [hsx|<span class="roster-day-closed-label">CLOSED</span>|]
    | otherwise =
        [hsx|<span class="roster-day-actions-placeholder"></span>|]

renderDayColumnHeaderControls :: (?context :: ControllerContext) => Bool -> Int -> RosterDay -> Html
renderDayColumnHeaderControls isEditable calendarRevision rosterDay
    | isEditable =
        [hsx|
            <span class="roster-day-actions">
                {renderToggleClosedButton calendarRevision rosterDay}
            </span>
        |]
    | rosterDay.isClosed =
        [hsx|<span class="roster-day-closed-label">CLOSED</span>|]
    | otherwise =
        [hsx|<span class="roster-day-actions-placeholder"></span>|]

renderToggleClosedButton :: (?context :: ControllerContext) => Int -> RosterDay -> Html
renderToggleClosedButton calendarRevision rosterDay =
    if currentUserIsManager
        then
            let buttonLabel = if rosterDay.isClosed then ("Reopen day" :: Text) else ("Mark day closed" :: Text)
                iconClass = if rosterDay.isClosed then ("bi bi-lock-fill" :: Text) else ("bi bi-unlock" :: Text)
                closedLabel = if rosterDay.isClosed then [hsx|<span class="roster-day-action-label">CLOSED</span>|] else mempty
             in renderRosterDayActionForm (surfaceFieldNameFrom @Surface.RosterCalendarRevision (RosterAction.toggleRosterDayClosedActionFields calendarRevision)) calendarRevision (RosterAction.toggleRosterDayClosedAction (RosterAction.toggleRosterDayClosedActionFields calendarRevision)) (rosterDayMutationUrl (ToggleRosterDayClosedAction rosterDay.id) (Id rosterDay.rosterGroupId) rosterDay.operationalDate calendarRevision) [hsx|
                <button type="submit"
                        class={classes [("btn btn-sm app-compact-action-button roster-day-action roster-day-action-toggle", True), ("is-active", rosterDay.isClosed)]}
                        aria-label={buttonLabel}
                        data-roster-day-closed-toggle="true"
                        title={buttonLabel}>
                    <i class={iconClass} aria-hidden="true"></i>
                    {closedLabel}
                </button>
            |]
        else [hsx|<span></span>|]

renderAddRowButton :: (?context :: ControllerContext) => Int -> RosterDay -> Html
renderAddRowButton calendarRevision rosterDay =
    if currentUserIsManager
        then renderRosterDayActionForm (surfaceFieldNameFrom @Surface.RosterCalendarRevision (RosterAction.addRosterRowActionFields calendarRevision)) calendarRevision (RosterAction.addRosterRowAction (RosterAction.addRosterRowActionFields calendarRevision)) (rosterDayMutationUrl (AddRosterRowAction rosterDay.id) (Id rosterDay.rosterGroupId) rosterDay.operationalDate calendarRevision) [hsx|
            <button type="submit"
                    class="btn btn-sm app-compact-action-button roster-day-action roster-day-action-add"
                    aria-label="Add shift row"
                    data-roster-day-add="true"
                    title="Add shift row">
                <i class="bi bi-plus-lg" aria-hidden="true"></i>
            </button>
        |]
        else [hsx|<span></span>|]

renderDeleteLastRowButton :: (?context :: ControllerContext) => Int -> RosterDay -> Int -> Html
renderDeleteLastRowButton calendarRevision rosterDay rowIndex =
    if currentUserIsManager
        then
            let canDelete = rowIndex >= minimumOpenRosterRows
             in renderRosterDayActionForm (surfaceFieldNameFrom @Surface.RosterCalendarRevision (RosterAction.removeRosterRowActionFields calendarRevision)) calendarRevision (RosterAction.removeRosterRowAction (RosterAction.removeRosterRowActionFields calendarRevision)) (rosterDayMutationUrl (RemoveRosterRowAction rosterDay.id) (Id rosterDay.rosterGroupId) rosterDay.operationalDate calendarRevision) [hsx|
                <button type="submit"
                        class="btn btn-sm app-compact-action-button roster-day-action roster-day-action-remove"
                        aria-label={if canDelete then ("Delete last shift row" :: Text) else ("Minimum day size reached" :: Text)}
                        data-roster-day-remove="true"
                        title={if canDelete then ("Delete last shift row" :: Text) else ("Minimum day size reached" :: Text)}
                        disabled={not canDelete}>
                    <i class="bi bi-dash-lg" aria-hidden="true"></i>
                </button>
            |]
        else [hsx|<span></span>|]

renderRosterDayActionForm :: Text -> Int -> FrontendSurfaceAction -> Text -> Html -> Html
renderRosterDayActionForm calendarRevisionFieldName calendarRevision action actionUrl body =
    renderFrontendSurfaceActionForm
        action
        (rosterGridActionRoute actionUrl)
            { actionRouteExtraAttrs = [("class", "d-inline")]
            }
        [hsx|
            <input type="hidden" name={calendarRevisionFieldName} value={tshow calendarRevision} />
            {body}
        |]
