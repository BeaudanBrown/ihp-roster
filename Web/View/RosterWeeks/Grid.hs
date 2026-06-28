module Web.View.RosterWeeks.Grid
    ( lastRowIndexForRows
    , renderRosterContentFragment
    , renderRosterContentFragmentOob
    , renderRosterGridFrameFragment
    , renderRosterGridFrameFragmentWithSwap
    , renderRosterDayColumnsFragment
    , renderRosterDayColumnsFragmentWithSwap
    , renderRosterDayRailFragment
    , renderRosterDayRailFragmentWithSwap
    , renderHiddenDraftDayRailFragmentWithSwap
    , renderRosterSlotsGridFragment
    , renderRosterSlotsGridFragmentWithSwap
    , renderHiddenDraftSlotsGridFragmentWithSwap
    , renderRosterWageRailFragment
    , renderRosterWageRailFragmentWithSwap
    , renderRosterGridToolbarFragment
    , renderRosterGridToolbarFragmentWithSwap
    , renderRosterLayout
    , renderRosterDaySectionFragment
    , renderRosterDaySectionFragmentOob
    , renderRowFragment
    , renderRowOob
    , compactDayColumnSlots
    , rowsForDay
    ) where

import Application.Helper.Interaction (InteractionSurfaceMount (..),
                                       renderInteractionCapabilityShell,
                                       withInteractionDropzoneMarker,
                                       withInteractionPointerSessionMarker)
import Application.Helper.Profiling (profileHtmlComponent, profileRenderCounter)
import Application.Helper.RosterWagePrediction
import Application.Helper.ShiftTypeColours (shiftTypeColourPaletteKeys)
import Application.Helper.TimeRules (rosterOperationalFinalSelectableTimeText,
                                     rosterOperationalStartTimeText)
import Application.Helper.UserPreferences (rosterLayoutModeValue)
import Application.Helper.View (dialogOverlayMountId,
                                renderLiveSurfaceFragmentMount,
                                staffDisplayName)
import Data.Coerce (coerce)
import Data.List (find, sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import qualified Data.Time.Calendar as Calendar
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (TimeOfDay)
import Data.UUID (UUID)
import Web.RosterWeeks.Dom
import Web.RosterWeeks.LiveSurface (rosterDragSessionKindName,
                                    rosterInteractionMountKey,
                                    rosterLiveSurfaceDefinition,
                                    rosterMoveShiftIntentName)
import Web.RosterWeeks.Projection (buildRosterProjectionScope)
import Web.RosterWeeks.Types
import Web.View.Prelude
import Web.View.RosterWeeks.Header (renderRosterGridHeader)
import Web.View.RosterWeeks.StaffPanel (renderRosterStaffPanelFragment)
import Web.View.RosterWeeks.StaffSelfServicePanel (renderRosterStaffSelfServicePanelFragment)

data RosterSlotCellTarget
    = ExistingRosterSlotTarget (Id RosterSlot)
    | NewRosterSlotTarget (Id RosterDay) (Id RosterWeekSlotDefinition) Int

data ExistingSlotDisplay = ExistingSlotDisplay
    { displayStartLabel         :: Text
    , displayEndLabel           :: Text
    , displayTimeLabel          :: Text
    , displayStaffLabel         :: Text
    , displayShiftTypeLabel     :: Text
    , displayShiftTypeColourKey :: Text
    , displayPrimaryConflict    :: Maybe RosterConflict
    , displayMissingStartTime   :: Bool
    , displayMissingEndTime     :: Bool
    , displayMissingShiftType   :: Bool
    , displayHasShiftType       :: Bool
    }

data ReadOnlyExistingSlotCell = ReadOnlyExistingSlotCell
    { readOnlyCellClasses       :: Text
    , readOnlyCellColourKey     :: Text
    , readOnlyCellContent       :: Html
    , readOnlyCellConflictAttrs :: Maybe Text
    }

renderRosterContentFragment :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterContentFragment =
    renderRosterContentFragmentWithSwap Nothing

renderRosterContentFragmentOob :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterContentFragmentOob =
    renderRosterContentFragmentWithSwap (Just "outerHTML")

renderRosterContentFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterGridRenderModel -> Html
renderRosterContentFragmentWithSwap maybeSwapOob gridModel =
    profileHtmlComponent "render.roster.content_fragment" [hsx|
        <div id={rosterContentFragmentId}
             class={rosterContentColumnClasses gridModel}
             hx-swap-oob={maybeSwapOob}>
            {renderRosterContent gridModel}
        </div>
    |]

renderRosterLayout :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterLayout gridModel@RosterGridRenderModel { gridRosterWeek, gridWeekOffset, gridRosterGroups, gridCurrentRosterGroup, gridPanelStaff, gridStaffSelfServicePanel } =
    let mount = InteractionSurfaceMount
            { interactionMountScope = buildRosterProjectionScope gridCurrentRosterGroup.id gridWeekOffset
            , interactionMountKey = rosterInteractionMountKey
            }
        renderStaffPanelMount rosterWeek =
            if currentUserIsManager
                then
                    renderLiveSurfaceFragmentMount
                        rosterLiveSurfaceDefinition
                        mount.interactionMountScope
                        RosterProjectionStaffPanel
                        (renderRosterStaffPanelFragment gridWeekOffset (coerce rosterWeek.rosterGroupId) (length gridRosterGroups > 1) RosterStaffPanelCurrentGroup gridPanelStaff)
                else mempty
     in profileHtmlComponent "render.roster.layout" do
        renderInteractionCapabilityShell rosterLiveSurfaceDefinition mount [hsx|
            <div class="row g-4 align-items-start roster-layout">
                {renderRosterContentFragment gridModel}
                {forEach gridRosterWeek renderStaffPanelMount}
                {renderRosterStaffSelfServicePanelFragment gridStaffSelfServicePanel}
            </div>
        |]

rosterContentColumnClasses :: (?context :: ControllerContext) => RosterGridRenderModel -> Text
rosterContentColumnClasses RosterGridRenderModel { gridStaffSelfServicePanel } =
    classes [("col-12", True), ("col-xl-8", hasSidePanel), ("col-xxl-9", hasSidePanel), ("mx-auto", not hasSidePanel), ("roster-layout-main", hasSidePanel)]
    where
        hasSidePanel = currentUserIsManager || isJust gridStaffSelfServicePanel

renderRosterContent :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterContent =
    renderRosterMainPanel

renderRosterMainPanel :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterMainPanel gridModel =
    profileHtmlComponent "render.roster.main_panel" [hsx|
        <div class="app-panel overflow-hidden mb-5 mb-xl-0 roster-main-panel">
            {renderRosterGridToolbarFragment gridModel}
            {renderRosterGridFrameFragment gridModel}
        </div>
    |]

renderRosterGridToolbarFragment :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterGridToolbarFragment =
    renderRosterGridToolbarFragmentWithSwap Nothing

renderRosterGridToolbarFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterGridRenderModel -> Html
renderRosterGridToolbarFragmentWithSwap maybeSwapOob RosterGridRenderModel { gridRosterWeek, gridWeekOffset, gridRosterGroups, gridCurrentRosterGroup, gridAssignmentFilters, gridWeekStartDate, gridViewCapabilities, gridRosterLayoutMode, gridRosterEndTimesEnabled, gridRosterWagePrediction, gridShowWageEstimates, gridShowRosterWarnings, gridStaffSelfServicePanel } =
    profileHtmlComponent "render.roster.toolbar" [hsx|
        <div id={rosterGridToolbarFragmentId} hx-swap-oob={maybeSwapOob}>
            {renderRosterGridHeader gridRosterWeek gridWeekOffset gridRosterGroups gridCurrentRosterGroup gridAssignmentFilters gridWeekStartDate gridViewCapabilities gridRosterLayoutMode gridRosterEndTimesEnabled gridRosterWagePrediction gridShowWageEstimates gridShowRosterWarnings hasSidePanel}
        </div>
    |]
    where
        hasSidePanel = currentUserIsManager || isJust gridStaffSelfServicePanel

renderRosterGridFrameFragment :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterGridFrameFragment =
    renderRosterGridFrameFragmentWithSwap Nothing

renderRosterGridFrameFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterGridRenderModel -> Html
renderRosterGridFrameFragmentWithSwap maybeSwapOob gridModel@RosterGridRenderModel { gridRosterWeek, gridSlotNames, gridViewCapabilities, gridRosterLayoutMode, gridRosterEndTimesEnabled, gridShowWageEstimates, gridShowRosterWarnings } =
    let slotColumnsAreEditable = gridViewCapabilities.canManageRosterColumns
        rosterIsHiddenDraft = isNothing gridRosterWeek
        isDayColumnsLayout = not rosterIsHiddenDraft && rosterLayoutModeValue gridRosterLayoutMode == "day_columns"
        frameLayoutValue = if rosterIsHiddenDraft then ("hidden_draft" :: Text) else rosterLayoutModeValue gridRosterLayoutMode
        gridBody = renderRosterGridInnerFragments gridModel
     in profileHtmlComponent "render.roster.grid_frame" [hsx|
        <div id={rosterGridFrameFragmentId}
             class={classes [("roster-grid-frame", True), ("app-horizontal-frame", isDayColumnsLayout)]}
             hx-swap-oob={maybeSwapOob}
             data-roster-layout={frameLayoutValue}
             data-roster-visibility={if rosterIsHiddenDraft then ("hidden-draft" :: Text) else "visible"}
             data-horizontal-snap={if isDayColumnsLayout then ("nearest-item" :: Text) else ""}
             data-horizontal-snap-item-selector={if isDayColumnsLayout then (".roster-day-column" :: Text) else ""}
             data-horizontal-drag-scroll={if isDayColumnsLayout then ("mouse" :: Text) else ""}
             data-horizontal-drag-scroll-ignore-selector={if isDayColumnsLayout then ("[data-roster-shift-launcher]" :: Text) else ""}
             data-roster-end-times={if gridRosterEndTimesEnabled then ("true" :: Text) else "false"}
             data-roster-column-editor={if slotColumnsAreEditable && not rosterIsHiddenDraft then ("available" :: Text) else "unavailable"}
             data-roster-wages={if gridShowWageEstimates && not rosterIsHiddenDraft then ("visible" :: Text) else "hidden"}
             data-roster-warnings={if gridShowRosterWarnings && not rosterIsHiddenDraft then ("visible" :: Text) else "hidden"}
             style={"--roster-slot-count:" <> tshow (max 1 (length gridSlotNames)) <> ";"}>
            {gridBody}
        </div>
|]

rosterDayRenderModelFromGrid :: (?context :: ControllerContext) => RosterGridRenderModel -> RosterDayRenderModel
rosterDayRenderModelFromGrid RosterGridRenderModel { gridRosterWeek, gridAssignmentFilters, gridStaffMembers, gridSlotNames, gridShiftTypes, gridWeekStartDate, gridAllSlots, gridSlotConflicts, gridRenderIndexes, gridRosterLayoutMode, gridRosterEndTimesEnabled, gridRosterWagePrediction, gridShowWageEstimates, gridShowRosterWarnings, gridPublicHolidays, gridPublishAttempted } =
    RosterDayRenderModel
        { dayIsEditable = rosterWeekIsEditable gridRosterWeek
        , daySlotNames = gridSlotNames
        , dayAssignmentFilters = gridAssignmentFilters
        , dayStaffMembers = gridStaffMembers
        , dayShiftTypes = gridShiftTypes
        , dayWeekStartDate = gridWeekStartDate
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
            else if rosterLayoutModeValue gridRosterLayoutMode == "day_columns"
                then renderRosterDayColumnsFragment dayModel gridRosterDays
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

renderRosterDayRowsGrid :: (?context :: ControllerContext) => Bool -> Bool -> Maybe RosterWeek -> [RosterWeekSlotDefinition] -> RosterDayRenderModel -> [RosterDay] -> Html
renderRosterDayRowsGrid endTimesEnabled slotColumnsAreEditable maybeRosterWeek slotNames dayModel rosterDays = [hsx|
    {renderRosterDayRailFragment slotColumnsAreEditable dayModel rosterDays}
    {when dayModel.dayShowWageEstimates (renderRosterWageRailFragment dayModel rosterDays)}
    <div class="roster-slots-scroller"
         data-horizontal-snap="equal-groups"
         data-horizontal-snap-group-var="--roster-slot-count"
         data-horizontal-snap-group-var-scope=".roster-grid-frame">
        {renderRosterSlotsGridFragment endTimesEnabled slotColumnsAreEditable maybeRosterWeek slotNames dayModel rosterDays}
    </div>
|]

renderRosterDayRailFragment :: (?context :: ControllerContext) => Bool -> RosterDayRenderModel -> [RosterDay] -> Html
renderRosterDayRailFragment =
    renderRosterDayRailFragmentWithSwap Nothing

renderRosterDayRailFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Bool -> RosterDayRenderModel -> [RosterDay] -> Html
renderRosterDayRailFragmentWithSwap maybeSwapOob slotColumnsAreEditable dayModel rosterDays = [hsx|
    <div id={rosterDayRailFragmentId} class="roster-day-rail" aria-label="Roster days" hx-swap-oob={maybeSwapOob}>
        <div class="roster-day-rail-head">
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
    <div class="roster-slots-scroller">
        {renderHiddenDraftSlotsGridFragment rosterDays}
    </div>
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
         class="roster-grid roster-slots-grid roster-hidden-draft-grid"
         role="region"
         aria-label="Roster visibility"
         hx-swap-oob={maybeSwapOob}>
        <div class="roster-hidden-draft-grid-head" aria-hidden="true"></div>
        <div class="roster-hidden-draft-grid-body" role="status" aria-live="polite">
            <div class="roster-hidden-draft-message">This roster isn't live yet.</div>
        </div>
    </div>
|]

renderRosterSlotsGridFragment :: (?context :: ControllerContext) => Bool -> Bool -> Maybe RosterWeek -> [RosterWeekSlotDefinition] -> RosterDayRenderModel -> [RosterDay] -> Html
renderRosterSlotsGridFragment =
    renderRosterSlotsGridFragmentWithSwap Nothing

renderRosterSlotsGridFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Bool -> Bool -> Maybe RosterWeek -> [RosterWeekSlotDefinition] -> RosterDayRenderModel -> [RosterDay] -> Html
renderRosterSlotsGridFragmentWithSwap maybeSwapOob endTimesEnabled slotColumnsAreEditable maybeRosterWeek slotNames dayModel rosterDays =
    let gridHeaders = profileHtmlComponent "render.roster.slots_grid_headers" [hsx|
            <div class="roster-grid-head" role="rowgroup">
                <div class="roster-grid-header-row roster-grid-header-row-blocks" role="row">
                    {forEach (zip [0 :: Int ..] slotNames) (renderSlotHeaderGroup endTimesEnabled maybeRosterWeek slotColumnsAreEditable (length slotNames))}
                </div>
                <div class="roster-grid-header-row roster-grid-header-row-subheads" role="row">
                    {forEach slotNames (renderSlotSubHeaders endTimesEnabled)}
                </div>
            </div>
        |]
        gridBody = profileHtmlComponent "render.roster.slots_grid_body" [hsx|{forEach rosterDays (renderRosterDay dayModel)}|]
     in profileHtmlComponent "render.roster.slots_grid_component" [hsx|
        {profileRenderCounter "render.roster.slots_grid" 1}
        {profileRenderCounter "render.roster.day" (length rosterDays)}
        {profileRenderCounter "render.roster.slot_definition" (length slotNames)}
        <div id={rosterSlotsGridFragmentId} class="roster-grid roster-slots-grid" role="grid" aria-label="Roster slots" hx-swap-oob={maybeSwapOob}>
            {gridHeaders}
            {gridBody}
        </div>
    |]

rosterWeekIsEditable :: (?context :: ControllerContext) => Maybe RosterWeek -> Bool
rosterWeekIsEditable maybeRosterWeek =
    currentUserIsManager && maybe False (not . (.isLive)) maybeRosterWeek

renderRosterColumnEditStartButton :: Bool -> Html
renderRosterColumnEditStartButton True = [hsx|
    <button type="button"
            class="btn btn-sm btn-outline-secondary roster-column-edit-start"
            data-roster-column-edit-start="true"
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
            class="btn btn-sm btn-outline-success roster-column-edit-done"
            data-roster-column-edit-done="true"
            aria-label="Finish editing roster columns"
            title="Finish editing roster columns">
        <i class="bi bi-check-lg" aria-hidden="true"></i>
    </button>
|]
renderRosterColumnEditDoneButton False = mempty

renderSlotHeaderGroup :: (?context :: ControllerContext) => Bool -> Maybe RosterWeek -> Bool -> Int -> (Int, RosterWeekSlotDefinition) -> Html
renderSlotHeaderGroup endTimesEnabled _ False _ (slotIndex, _) = [hsx|
    <div role="columnheader"
         class="roster-block-header"
         aria-label={"Roster column " <> tshow (slotIndex + 1)}
         style={slotHeaderGridColumnStyle endTimesEnabled}></div>
|]
renderSlotHeaderGroup endTimesEnabled (Just rosterWeek) True slotCount (slotIndex, slotName) = [hsx|
    <div role="columnheader"
         class="roster-block-header"
         aria-label={"Roster column " <> tshow (slotIndex + 1)}
         style={slotHeaderGridColumnStyle endTimesEnabled}>
        <div class="d-flex align-items-center justify-content-center gap-2 roster-slot-column-header">
            <form method="POST"
                  action={DeleteRosterWeekSlotDefinitionAction slotName.id}
                  class="mb-0"
                  data-disable-javascript-submission="true"
                  hx-delete={DeleteRosterWeekSlotDefinitionAction slotName.id}
                  hx-target={"#" <> rosterContentFragmentId}
                  hx-swap="none"
                  hx-push-url="false"
                  hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
                <input type="hidden" name="_method" value="DELETE" />
                <button type="submit"
                        class="btn btn-sm btn-outline-danger roster-slot-column-delete"
                        aria-label="Remove roster column"
                        title="Remove roster column"
                        disabled={slotCount <= 1}>
                    <i class="bi bi-trash" aria-hidden="true"></i>
                </button>
            </form>
            {renderSlotAddButton rosterWeek (slotIndex == slotCount - 1)}
        </div>
    </div>
|]
renderSlotHeaderGroup endTimesEnabled _ _ _ (slotIndex, _) = [hsx|
    <div role="columnheader"
         class="roster-block-header"
         aria-label={"Roster column " <> tshow (slotIndex + 1)}
         style={slotHeaderGridColumnStyle endTimesEnabled}></div>
|]

slotColumnCount :: Bool -> Int
slotColumnCount True  = 4
slotColumnCount False = 3

slotHeaderGridColumnStyle :: Bool -> Text
slotHeaderGridColumnStyle endTimesEnabled =
    rosterGridColumnSpanStyle (slotColumnCount endTimesEnabled)

rosterGridColumnSpanStyle :: Int -> Text
rosterGridColumnSpanStyle gridSpan =
    "--roster-grid-column-span: " <> tshow gridSpan <> ";"

renderSlotAddButton :: (?context :: ControllerContext) => RosterWeek -> Bool -> Html
renderSlotAddButton rosterWeek True = [hsx|
    <form method="POST"
          action={CreateRosterWeekSlotDefinitionAction rosterWeek.id}
          class="mb-0 roster-slot-column-add-form"
          data-disable-javascript-submission="true"
          hx-post={CreateRosterWeekSlotDefinitionAction rosterWeek.id}
          hx-target={"#" <> rosterContentFragmentId}
          hx-swap="none"
          hx-push-url="false"
          hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
        <button type="submit"
                class="btn btn-sm btn-outline-primary roster-slot-column-add"
                aria-label="Add roster column"
                title="Add roster column">
            <i class="bi bi-plus-lg" aria-hidden="true"></i>
        </button>
    </form>
|]
renderSlotAddButton _ False = mempty

renderSlotSubHeaders :: Bool -> RosterWeekSlotDefinition -> Html
renderSlotSubHeaders True _ =
    mconcat
        [ [hsx|<div role="columnheader" class="roster-subhead roster-col-time">Start</div>|]
        , [hsx|<div role="columnheader" class="roster-subhead roster-col-time">End</div>|]
        , [hsx|<div role="columnheader" class="roster-subhead roster-col-staff">Staff</div>|]
        , [hsx|<div role="columnheader" class="roster-subhead roster-col-shift-type roster-block-end">Role</div>|]
        ]
renderSlotSubHeaders False _ =
    mconcat
        [ [hsx|<div role="columnheader" class="roster-subhead roster-col-time">Start</div>|]
        , [hsx|<div role="columnheader" class="roster-subhead roster-col-staff">Staff</div>|]
        , [hsx|<div role="columnheader" class="roster-subhead roster-col-code roster-block-end">Role</div>|]
        ]

renderRosterDay :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Html
renderRosterDay =
    renderRosterDaySectionFragment

renderRosterDaySectionFragment :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Html
renderRosterDaySectionFragment =
    renderRosterDaySectionFragmentWithSwap Nothing

renderRosterDaySectionFragmentOob :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Html
renderRosterDaySectionFragmentOob dayModel rosterDay =
    [hsx|<template>{renderRosterDaySectionFragmentWithSwap (Just "outerHTML") dayModel rosterDay}</template>|]

renderRosterDaySectionFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterDayRenderModel -> RosterDay -> Html
renderRosterDaySectionFragmentWithSwap maybeSwapOob dayModel@RosterDayRenderModel { dayRosterLayoutMode } rosterDay
    | rosterLayoutModeValue dayRosterLayoutMode == "day_columns" =
        renderRosterDayColumnWithSwap maybeSwapOob dayModel rosterDay
renderRosterDaySectionFragmentWithSwap maybeSwapOob dayModel@RosterDayRenderModel { dayWeekStartDate, dayAllSlots, dayRenderIndexes } rosterDay =
    profileHtmlComponent "render.roster.day_section_component" [hsx|
    {profileRenderCounter "render.roster.day_section" 1}
    {profileRenderCounter "render.roster.row" (length dayRows)}
    <div id={rosterDaySectionDomId rosterDay.id}
         class="roster-grid-day-section"
         role="rowgroup"
         data-roster-day-section="true"
         hx-swap-oob={maybeSwapOob}
         style={"--roster-day-row-count:" <> tshow (length dayRows) <> ";"}>
        {renderDayRows dayModel (Calendar.addDays (toInteger (get #dayOffset rosterDay)) dayWeekStartDate) rosterDay dayRows}
    </div>
|]
    where
        dayRows = Map.findWithDefault (rowsForDay rosterDay daySlots) (coerce (get #id rosterDay)) dayRenderIndexes.rosterDayRowsByDayId
        daySlots = filter (\s -> s.rosterDayId == coerce (get #id rosterDay)) dayAllSlots

renderRosterDayRailSection :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Html
renderRosterDayRailSection RosterDayRenderModel { dayIsEditable, dayWeekStartDate, dayAllSlots, dayRenderIndexes, dayPublicHolidays } rosterDay =
    let daySlots = filter (\s -> s.rosterDayId == coerce (get #id rosterDay)) dayAllSlots
        dayRows = Map.findWithDefault (rowsForDay rosterDay daySlots) (coerce (get #id rosterDay)) dayRenderIndexes.rosterDayRowsByDayId
        rowCount = length dayRows
        lastRowIndex = lastRowIndexForRows dayRows
        date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) dayWeekStartDate
     in [hsx|
        <div class={classes [("roster-day-rail-section", True), ("day-alt-dark", odd (get #dayOffset rosterDay)), ("day-alt-light", even (get #dayOffset rosterDay))]}
             style={"--roster-day-label-rows:" <> tshow rowCount}>
            <div class="roster-day-label-stack">
                <div class="roster-day-label-row roster-day-label-row-primary">
                    <div class="roster-day-heading">
                        {renderPrimaryDayLabel (Map.lookup date dayPublicHolidays) date}
                    </div>
                </div>
                <div class="roster-day-label-row roster-day-label-row-controls">
                    {renderDayRowControls dayIsEditable rosterDay lastRowIndex}
                </div>
                {renderEmptyDayLabelRows rowCount 2}
            </div>
        </div>
    |]

renderHiddenDraftDayRailSection :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Html
renderHiddenDraftDayRailSection RosterDayRenderModel { dayWeekStartDate, dayPublicHolidays } rosterDay =
    let date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) dayWeekStartDate
     in [hsx|
        <div class={classes [("roster-day-rail-section", True), ("roster-day-rail-section-hidden-draft", True), ("day-alt-dark", odd (get #dayOffset rosterDay)), ("day-alt-light", even (get #dayOffset rosterDay))]}>
            <div class="roster-day-label-stack">
                <div class="roster-day-label-row roster-day-label-row-primary">
                    <div class="roster-day-heading">
                        {renderPrimaryDayLabel (Map.lookup date dayPublicHolidays) date}
                    </div>
                </div>
            </div>
        </div>
    |]

renderRosterWageRailFragment :: RosterDayRenderModel -> [RosterDay] -> Html
renderRosterWageRailFragment =
    renderRosterWageRailFragmentWithSwap Nothing

renderRosterWageRailFragmentWithSwap :: Maybe Text -> RosterDayRenderModel -> [RosterDay] -> Html
renderRosterWageRailFragmentWithSwap maybeSwapOob dayModel rosterDays = [hsx|
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
        date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) dayWeekStartDate
     in [hsx|
        <div class={classes [("roster-wage-rail-section", True), ("day-alt-dark", odd (get #dayOffset rosterDay)), ("day-alt-light", even (get #dayOffset rosterDay))]}
             style={"--roster-day-label-rows:" <> tshow rowCount}>
            {renderDayRowsWageAmount dayRosterWagePrediction date}
        </div>
    |]

renderRosterDayColumnsFragment :: (?context :: ControllerContext) => RosterDayRenderModel -> [RosterDay] -> Html
renderRosterDayColumnsFragment =
    renderRosterDayColumnsFragmentWithSwap Nothing

renderRosterDayColumnsFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterDayRenderModel -> [RosterDay] -> Html
renderRosterDayColumnsFragmentWithSwap maybeSwapOob dayModel rosterDays = [hsx|
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
        date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) dayWeekStartDate
        compactSlots = if rosterDay.isClosed then [] else compactDayColumnSlots dayModel.daySlotNames daySlots
        maybeCreateTarget = if rosterDay.isClosed then Nothing else firstAvailableDayColumnTarget dayModel.daySlotNames rosterDay daySlots
     in [hsx|
        <section id={rosterDaySectionDomId rosterDay.id}
                 data-roster-day-section="true"
                 hx-swap-oob={maybeSwapOob}
                 class={classes [("roster-day-column", True), ("app-horizontal-panel", True), ("day-alt-dark", odd (get #dayOffset rosterDay)), ("day-alt-light", even (get #dayOffset rosterDay))]}>
            <header class="roster-day-column-header">
                <div class="roster-day-heading">
                    {renderPrimaryDayLabel (Map.lookup date dayPublicHolidays) date}
                </div>
                <div class="roster-day-column-wage-slot">
                    {renderDayColumnWageEstimate dayRosterWagePrediction date}
                </div>
                <div class="roster-day-column-control-slot">
                    {renderDayColumnHeaderControls dayIsEditable rosterDay}
                </div>
            </header>
            <div class="roster-day-column-body">
                {forEach compactSlots (renderDayColumnRosterSlotCard dayModel)}
                {renderDayColumnCreateCard dayModel rosterDay maybeCreateTarget}
            </div>
        </section>
    |]

compactDayColumnSlots :: [RosterWeekSlotDefinition] -> [RosterSlot] -> [RosterSlot]
compactDayColumnSlots slotNames daySlots =
    sortOn slotOrder (filter rosterSlotHasVisibleData daySlots)
  where
    definitionOrderById =
        Map.fromList
            [ (unpackId slotName.id, slotIndex)
            | (slotIndex, slotName) <- zip [0 :: Int ..] slotNames
            ]
    slotOrder slot =
        ( isNothing slot.startTime
        , slot.startTime
        , Map.findWithDefault (length slotNames) slot.rosterWeekSlotDefinitionId definitionOrderById
        , slot.rowIndex
        , slot.createdAt
        , slot.id
        )

firstAvailableDayColumnTarget :: [RosterWeekSlotDefinition] -> RosterDay -> [RosterSlot] -> Maybe RosterSlotCellTarget
firstAvailableDayColumnTarget [] _ _ = Nothing
firstAvailableDayColumnTarget slotNames rosterDay daySlots =
    let occupiedCells =
            Map.fromList
                [ ((slot.rosterWeekSlotDefinitionId, slot.rowIndex), ())
                | slot <- daySlots
                , rosterSlotHasVisibleData slot
                ]
        rowCount = max minimumOpenRosterRows rosterDay.rowCount
        candidateCells =
            [ (slotName, rowIndex)
            | slotName <- slotNames
            , rowIndex <- [0 .. rowCount - 1]
            ]
        firstFree =
            find
                (\(slotName, rowIndex) -> Map.notMember (unpackId slotName.id, rowIndex) occupiedCells)
                candidateCells
     in case firstFree <|> fmap (\slotName -> (slotName, rowCount)) (head slotNames) of
            Nothing -> Nothing
            Just (slotName, rowIndex) -> Just (NewRosterSlotTarget rosterDay.id slotName.id rowIndex)

rosterSlotHasVisibleData :: RosterSlot -> Bool
rosterSlotHasVisibleData slot =
    isJust slot.staffId
        || isJust slot.startTime
        || isJust slot.endTime
        || isJust slot.shiftTypeId
        || isJust slot.durationMinutes

renderDayColumnRow :: (?context :: ControllerContext) => RosterRowRenderModel -> (Int, (Int, [RosterSlot])) -> Maybe Text -> Html
renderDayColumnRow RosterRowRenderModel { rowIsEditable, rowSlotNames, rowAssignmentFilters, rowStaffMembers, rowShiftTypes, rowRosterDay, rowRenderIndexes, rowRosterEndTimesEnabled, rowPublishAttempted } (_, (rowIndex, rowSlots)) maybeSwapOob = [hsx|
    <div id={rosterRowDomIdText rowRosterDay.id rowIndex}
         data-roster-row="true"
         hx-swap-oob={maybeSwapOob}
         class={classes [("roster-day-column-row", True), ("day-row-" <> tshow (get #dayOffset rowRosterDay), True)]}>
        {forEach (zip [0 :: Int ..] rowSlotNames) (renderDayColumnSlotCard rowIsEditable rowAssignmentFilters rowStaffMembers rowShiftTypes rowRosterEndTimesEnabled rowPublishAttempted rowRosterDay rowIndex rowSlots rowRenderIndexes)}
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
renderDayRows RosterDayRenderModel { dayIsEditable, daySlotNames, dayAssignmentFilters, dayStaffMembers, dayShiftTypes, dayRenderIndexes, dayRosterLayoutMode, dayRosterEndTimesEnabled, dayPublishAttempted } date rosterDay dayRows =
    let rowModel =
            RosterRowRenderModel
                { rowIsEditable = dayIsEditable
                , rowSlotNames = daySlotNames
                , rowAssignmentFilters = dayAssignmentFilters
                , rowStaffMembers = dayStaffMembers
                , rowShiftTypes = dayShiftTypes
                , rowDate = date
                , rowRosterDay = rosterDay
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
    | rosterLayoutModeValue rowRosterLayoutMode == "day_columns" =
        renderDayColumnRow rowModel rowData maybeSwapOob
renderRowWithAttrs RosterRowRenderModel { rowIsEditable, rowSlotNames, rowAssignmentFilters, rowStaffMembers, rowShiftTypes, rowRosterDay, rowRenderIndexes, rowRosterEndTimesEnabled, rowPublishAttempted } (_, (rowIndex, rowSlots)) maybeSwapOob =
    profileHtmlComponent "render.roster.row_component" [hsx|
    {profileRenderCounter "render.roster.row_render" 1}
    <div id={rosterRowDomIdText rowRosterDay.id rowIndex}
         role="row"
         data-roster-row="true"
         hx-swap-oob={maybeSwapOob}
         class={classes [("day-row", True), ("day-row-" <> tshow (get #dayOffset rowRosterDay), True), ("day-alt-dark", odd (get #dayOffset rowRosterDay)), ("day-alt-light", even (get #dayOffset rowRosterDay))]}>
        {forEach (zip [0 :: Int ..] rowSlotNames) (renderBlockCells rowIsEditable rowAssignmentFilters rowStaffMembers rowShiftTypes rowRosterEndTimesEnabled rowPublishAttempted rowRosterDay rowIndex rowSlots rowRenderIndexes)}
    </div>
|]

renderPrimaryDayLabel :: Maybe Text -> Day -> Html
renderPrimaryDayLabel maybeHolidayName date = [hsx|
    <div class="roster-day-date">
        {renderPublicHolidayIndicator maybeHolidayName}
        <span>{Text.pack (formatTime defaultTimeLocale "%a" date)} {Text.pack (formatTime defaultTimeLocale "%d/%m" date)}</span>
    </div>
|]

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

renderDayRowControls :: (?context :: ControllerContext) => Bool -> RosterDay -> Int -> Html
renderDayRowControls isEditable rosterDay lastRowIndex
    | isEditable =
        [hsx|
            <span class="roster-day-actions">
                {renderToggleClosedButton rosterDay}
                {when (not rosterDay.isClosed) (renderDeleteLastRowButton rosterDay lastRowIndex)}
                {when (not rosterDay.isClosed) (renderAddRowButton rosterDay)}
            </span>
        |]
    | rosterDay.isClosed =
        [hsx|<span class="roster-day-closed-label">CLOSED</span>|]
    | otherwise =
        [hsx|<span class="roster-day-actions-placeholder"></span>|]

renderDayColumnHeaderControls :: (?context :: ControllerContext) => Bool -> RosterDay -> Html
renderDayColumnHeaderControls isEditable rosterDay
    | isEditable =
        [hsx|
            <span class="roster-day-actions">
                {renderToggleClosedButton rosterDay}
            </span>
        |]
    | rosterDay.isClosed =
        [hsx|<span class="roster-day-closed-label">CLOSED</span>|]
    | otherwise =
        [hsx|<span class="roster-day-actions-placeholder"></span>|]

renderToggleClosedButton :: (?context :: ControllerContext) => RosterDay -> Html
renderToggleClosedButton rosterDay =
    if currentUserIsManager
        then
            let buttonLabel = if rosterDay.isClosed then ("Reopen day" :: Text) else ("Mark day closed" :: Text)
                iconClass = if rosterDay.isClosed then ("bi bi-lock-fill" :: Text) else ("bi bi-unlock" :: Text)
                closedLabel = if rosterDay.isClosed then [hsx|<span class="roster-day-action-label">CLOSED</span>|] else mempty
             in [hsx|
            <form method="POST"
                  action={ToggleRosterDayClosedAction rosterDay.id}
                  class="d-inline"
                  data-disable-javascript-submission="true"
                  hx-post={ToggleRosterDayClosedAction rosterDay.id}
                  hx-target={"#" <> rosterDaySectionDomId rosterDay.id}
                  hx-swap="none"
                  hx-push-url="false"
                  hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
                <button type="submit"
                        class={classes [("btn btn-sm app-compact-action-button roster-day-action roster-day-action-toggle", True), ("is-active", rosterDay.isClosed)]}
                        aria-label={buttonLabel}
                        data-roster-day-closed-toggle="true"
                        title={buttonLabel}>
                    <i class={iconClass} aria-hidden="true"></i>
                    {closedLabel}
                </button>
            </form>
        |]
        else [hsx|<span></span>|]

renderAddRowButton :: (?context :: ControllerContext) => RosterDay -> Html
renderAddRowButton rosterDay =
    if currentUserIsManager
        then [hsx|
            <form method="POST"
                  action={AddRosterRowAction rosterDay.id}
                  class="d-inline"
                  data-disable-javascript-submission="true"
                  hx-post={AddRosterRowAction rosterDay.id}
                  hx-target={"#" <> rosterDaySectionDomId rosterDay.id}
                  hx-swap="none"
                  hx-push-url="false"
                  hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
                <button type="submit"
                        class="btn btn-sm app-compact-action-button roster-day-action roster-day-action-add"
                        aria-label="Add shift row"
                        data-roster-day-add="true"
                        title="Add shift row">
                    <i class="bi bi-plus-lg" aria-hidden="true"></i>
                </button>
            </form>
        |]
        else [hsx|<span></span>|]

renderDeleteLastRowButton :: (?context :: ControllerContext) => RosterDay -> Int -> Html
renderDeleteLastRowButton rosterDay rowIndex =
    if currentUserIsManager
        then
            let canDelete = rowIndex >= minimumOpenRosterRows
             in [hsx|
            <form method="POST"
                  action={RemoveRosterRowAction rosterDay.id}
                  class="d-inline"
                  data-disable-javascript-submission="true"
                  hx-post={RemoveRosterRowAction rosterDay.id}
                  hx-target={"#" <> rosterDaySectionDomId rosterDay.id}
                  hx-swap="none"
                  hx-push-url="false"
                  hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
                <button type="submit"
                        class="btn btn-sm app-compact-action-button roster-day-action roster-day-action-remove"
                        aria-label={if canDelete then ("Delete last shift row" :: Text) else ("Minimum day size reached" :: Text)}
                        data-roster-day-remove="true"
                        title={if canDelete then ("Delete last shift row" :: Text) else ("Minimum day size reached" :: Text)}
                        disabled={not canDelete}>
                    <i class="bi bi-dash-lg" aria-hidden="true"></i>
                </button>
            </form>
        |]
        else [hsx|<span></span>|]

renderBlockCells :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> Bool -> Bool -> RosterDay -> Int -> [RosterSlot] -> RosterRenderIndexes -> (Int, RosterWeekSlotDefinition) -> Html
renderBlockCells isEditable assignmentFilters staffMembers shiftTypes endTimesEnabled publishAttempted rosterDay rowIndex _rowSlots renderIndexes (blockIndex, slotName) =
    mconcat
        [ profileRenderCounter "render.roster.slot_block" 1
        , if isEditable
            then renderEditableBlockCells assignmentFilters staffMembers shiftTypes endTimesEnabled publishAttempted rosterDay rowIndex renderIndexes blockIndex slotName
            else renderReadOnlyBlockCells shiftTypes endTimesEnabled publishAttempted rosterDay rowIndex renderIndexes blockIndex slotName
        ]

renderEditableBlockCells :: (?context :: ControllerContext) => RosterAssignmentFilters -> [Staff] -> [ShiftType] -> Bool -> Bool -> RosterDay -> Int -> RosterRenderIndexes -> Int -> RosterWeekSlotDefinition -> Html
renderEditableBlockCells assignmentFilters staffMembers shiftTypes endTimesEnabled publishAttempted rosterDay rowIndex renderIndexes blockIndex slotName
    | rosterDay.isClosed = renderClosedBlockCells endTimesEnabled blockIndex
    | otherwise =
        maybe
            (renderCreateBlockCells assignmentFilters staffMembers shiftTypes endTimesEnabled rosterDay rowIndex blockIndex slotName)
            (renderEditableExistingSlotBlockCells assignmentFilters staffMembers shiftTypes endTimesEnabled publishAttempted renderIndexes blockIndex)
            (lookupRosterSlotForBlock rosterDay rowIndex slotName renderIndexes)

renderReadOnlyBlockCells :: (?context :: ControllerContext) => [ShiftType] -> Bool -> Bool -> RosterDay -> Int -> RosterRenderIndexes -> Int -> RosterWeekSlotDefinition -> Html
renderReadOnlyBlockCells shiftTypes endTimesEnabled publishAttempted rosterDay rowIndex renderIndexes blockIndex slotName
    | rosterDay.isClosed = renderClosedBlockCells endTimesEnabled blockIndex
    | otherwise =
        maybe
            (renderEmptyBlockCells endTimesEnabled blockIndex)
            (renderReadOnlyExistingSlotBlockCells shiftTypes endTimesEnabled publishAttempted renderIndexes blockIndex)
            (lookupRosterSlotForBlock rosterDay rowIndex slotName renderIndexes)

lookupRosterSlotForBlock :: RosterDay -> Int -> RosterWeekSlotDefinition -> RosterRenderIndexes -> Maybe RosterSlot
lookupRosterSlotForBlock rosterDay rowIndex slotName renderIndexes =
    Map.lookup (coerce (get #id rosterDay), rowIndex, coerce (get #id slotName)) renderIndexes.rosterSlotByDayRowSlotName

renderEditableExistingSlotBlockCells :: (?context :: ControllerContext) => RosterAssignmentFilters -> [Staff] -> [ShiftType] -> Bool -> Bool -> RosterRenderIndexes -> Int -> RosterSlot -> Html
renderEditableExistingSlotBlockCells _assignmentFilters _staffMembers shiftTypes endTimesEnabled publishAttempted renderIndexes blockIndex slot =
    let display = buildExistingSlotDisplay shiftTypes publishAttempted renderIndexes slot
        target = ExistingRosterSlotTarget slot.id
        groupKey = rosterShiftGroupKey target
        cellCount = if endTimesEnabled then 4 else 3
     in mconcat
        [ profileExistingSlotCounters display endTimesEnabled cellCount
        , profileEditableLauncherCounters 1
        , if endTimesEnabled
            then renderEditableEndTimeSlotCells display target groupKey blockIndex slot
            else renderEditableNoEndTimeSlotCells display target groupKey blockIndex slot
        ]

renderEditableEndTimeSlotCells :: (?context :: ControllerContext) => ExistingSlotDisplay -> RosterSlotCellTarget -> Text -> Int -> RosterSlot -> Html
renderEditableEndTimeSlotCells display target groupKey blockIndex slot =
    renderEditableShiftUnit target groupKey slot 4
        [ ReadOnlyExistingSlotCell (classes [("slot-time-cell slot-start-time-cell", True), ("roster-block-start", blockIndex > 0), ("is-roster-shift-publish-required", display.displayMissingStartTime)]) display.displayShiftTypeColourKey (renderReadOnlyCell display.displayStartLabel) Nothing
        , ReadOnlyExistingSlotCell (classes [("slot-time-cell slot-end-time-cell", True), ("is-roster-shift-publish-required", display.displayMissingEndTime)]) display.displayShiftTypeColourKey (renderReadOnlyCell display.displayEndLabel) Nothing
        , ReadOnlyExistingSlotCell (classes [("slot-staff-cell position-relative", True), (renderConflictClass display.displayPrimaryConflict, True)]) display.displayShiftTypeColourKey (renderReadOnlyStaffCell display.displayStaffLabel display.displayPrimaryConflict) (Just (renderConflictMessage display.displayPrimaryConflict))
        , ReadOnlyExistingSlotCell (classes [("slot-shift-type-cell roster-block-end", True), ("is-shift-type-empty", not display.displayHasShiftType), ("is-shift-type-required", display.displayMissingShiftType)]) display.displayShiftTypeColourKey (renderReadOnlyCell display.displayShiftTypeLabel) Nothing
        ]

renderEditableNoEndTimeSlotCells :: (?context :: ControllerContext) => ExistingSlotDisplay -> RosterSlotCellTarget -> Text -> Int -> RosterSlot -> Html
renderEditableNoEndTimeSlotCells display target groupKey blockIndex slot =
    renderEditableShiftUnit target groupKey slot 3
        [ ReadOnlyExistingSlotCell (classes [("slot-time-cell", True), ("roster-block-start", blockIndex > 0), ("is-roster-shift-publish-required", display.displayMissingStartTime)]) display.displayShiftTypeColourKey (renderReadOnlyCell display.displayTimeLabel) Nothing
        , ReadOnlyExistingSlotCell (classes [("slot-staff-cell position-relative", True), (renderConflictClass display.displayPrimaryConflict, True)]) display.displayShiftTypeColourKey (renderReadOnlyStaffCell display.displayStaffLabel display.displayPrimaryConflict) (Just (renderConflictMessage display.displayPrimaryConflict))
        , ReadOnlyExistingSlotCell (classes [("slot-shift-type-cell roster-block-end", True), ("is-shift-type-empty", not display.displayHasShiftType), ("is-shift-type-required", display.displayMissingShiftType)]) display.displayShiftTypeColourKey (renderReadOnlyCell display.displayShiftTypeLabel) Nothing
        ]

-- Editable row-grid shifts are one modal launcher per shift, not one launcher per
-- visual cell. Inner cells are visual-only and align to the parent grid via CSS
-- subgrid, preserving the Start/End/Staff/Role layout without duplicating HTMX
-- attributes across every cell.
renderEditableShiftUnit :: (?context :: ControllerContext) => RosterSlotCellTarget -> Text -> RosterSlot -> Int -> [ReadOnlyExistingSlotCell] -> Html
renderEditableShiftUnit target groupKey slot gridSpan cells =
    withInteractionPointerSessionMarker groupKey rosterDragSessionKindName rosterMoveShiftIntentName [hsx|
        <div role="gridcell"
             class="roster-shift-unit roster-shift-launcher"
             style={rosterGridColumnSpanStyle gridSpan}
             data-roster-shift-colour={shiftUnitColour cells}
             data-roster-staff-id={maybe "" tshow slot.staffId}
             data-roster-slot-id={tshow slot.id}
             data-roster-shift-group-key={groupKey}
             data-roster-shift-launcher="true"
             tabindex="0"
             hx-get={pathTo (rosterSlotDialogAction target)}
             hx-target={"#" <> dialogOverlayMountId}
             hx-swap="innerHTML"
             hx-push-url="false">
            {forEach cells renderEditableShiftUnitCell}
        </div>
    |]

shiftUnitColour :: [ReadOnlyExistingSlotCell] -> Text
shiftUnitColour []       = ""
shiftUnitColour (cell:_) = cell.readOnlyCellColourKey

renderEditableShiftUnitCell :: ReadOnlyExistingSlotCell -> Html
renderEditableShiftUnitCell ReadOnlyExistingSlotCell { readOnlyCellClasses, readOnlyCellColourKey, readOnlyCellContent, readOnlyCellConflictAttrs = Just conflictMessage } = [hsx|
    <div class={"roster-shift-unit-cell " <> readOnlyCellClasses}
         title={conflictMessage}
         data-conflict-message={conflictMessage}
         data-roster-shift-colour={readOnlyCellColourKey}>
        {readOnlyCellContent}
    </div>
|]
renderEditableShiftUnitCell ReadOnlyExistingSlotCell { readOnlyCellClasses, readOnlyCellColourKey, readOnlyCellContent, readOnlyCellConflictAttrs = Nothing } = [hsx|
    <div class={"roster-shift-unit-cell " <> readOnlyCellClasses}
         data-roster-shift-colour={readOnlyCellColourKey}>
        {readOnlyCellContent}
    </div>
|]

renderReadOnlyExistingSlotBlockCells :: (?context :: ControllerContext) => [ShiftType] -> Bool -> Bool -> RosterRenderIndexes -> Int -> RosterSlot -> Html
renderReadOnlyExistingSlotBlockCells shiftTypes endTimesEnabled publishAttempted renderIndexes blockIndex slot =
    let display = buildExistingSlotDisplay shiftTypes publishAttempted renderIndexes slot
        cells = readOnlyExistingSlotCells display endTimesEnabled blockIndex
        cellCount = length cells
     in mconcat
        [ profileExistingSlotCounters display endTimesEnabled cellCount
        , profileRenderCounter "render.roster.readonly_cell" cellCount
        , profileRenderCounter "render.roster.readonly_slim_cell" cellCount
        , forEach cells renderReadOnlyExistingSlotCell
        ]

buildExistingSlotDisplay :: [ShiftType] -> Bool -> RosterRenderIndexes -> RosterSlot -> ExistingSlotDisplay
buildExistingSlotDisplay shiftTypes publishAttempted renderIndexes slot =
    let currentStartTime = optionalTimeOfDayToStorageValue slot.startTime
        currentEndTime = optionalTimeOfDayToStorageValue slot.endTime
        currentShiftType = findShiftTypeForSlot shiftTypes slot.shiftTypeId
     in ExistingSlotDisplay
        { displayStartLabel = renderTimePickerDisplayLabel "Start" currentStartTime
        , displayEndLabel = renderTimePickerDisplayLabel "End" currentEndTime
        , displayTimeLabel = renderTimePickerDisplayLabel "Time" currentStartTime
        , displayStaffLabel = fromMaybe "" (renderAssignedStaffLabel slot.staffId renderIndexes)
        , displayShiftTypeLabel = maybe "" renderShiftTypeOptionLabel currentShiftType
        , displayShiftTypeColourKey = shiftTypeBadgeColourKey currentShiftType
        , displayPrimaryConflict = primaryConflict (lookupConflicts (get #id slot) renderIndexes)
        , displayMissingStartTime = publishAttempted && isJust slot.staffId && isNothing slot.startTime
        , displayMissingEndTime = publishAttempted && isJust slot.staffId && isNothing slot.endTime
        , displayMissingShiftType = publishAttempted && isJust slot.staffId && isNothing slot.shiftTypeId
        , displayHasShiftType = isJust slot.shiftTypeId
        }

profileExistingSlotCounters :: ExistingSlotDisplay -> Bool -> Int -> Html
profileExistingSlotCounters display endTimesEnabled cellCount = mconcat
    [ profileRenderCounter "render.roster.existing_slot" 1
    , profileRenderCounter (if endTimesEnabled then "render.roster.existing_slot.end_times_enabled" else "render.roster.existing_slot.no_end_times") 1
    , profileRenderCounter "render.roster.grid_cell" cellCount
    , profileRenderCounter "render.roster.time_label" (if endTimesEnabled then 2 else 1)
    , profileRenderCounter "render.roster.staff_label" 1
    , profileRenderCounter "render.roster.shift_type_label" 1
    , profileRenderCounter "render.roster.conflict_cell" (if isJust display.displayPrimaryConflict then 1 else 0)
    , profileRenderCounter "render.roster.conflict_attr" (if isJust display.displayPrimaryConflict then 2 else 0)
    , profileRenderCounter "render.roster.publish_required_marker" (sum (map fromEnum [display.displayMissingStartTime, display.displayMissingEndTime, display.displayMissingShiftType]))
    ]

profileEditableLauncherCounters :: Int -> Html
profileEditableLauncherCounters launcherCount = mconcat
    [ profileRenderCounter "render.roster.shift_launcher" launcherCount
    , profileRenderCounter "render.roster.launcher_attr_bundle" launcherCount
    , profileRenderCounter "render.roster.launcher_hx_attr" (launcherCount * 4)
    , profileRenderCounter "render.roster.launcher_data_attr" (launcherCount * 5)
    ]

readOnlyExistingSlotCells :: ExistingSlotDisplay -> Bool -> Int -> [ReadOnlyExistingSlotCell]
readOnlyExistingSlotCells display True blockIndex =
    [ readOnlyTimeCell (classes [("slot-time-cell slot-start-time-cell", True), ("roster-block-start", blockIndex > 0), ("is-roster-shift-publish-required", display.displayMissingStartTime)]) display.displayShiftTypeColourKey display.displayStartLabel
    , readOnlyTimeCell (classes [("slot-time-cell slot-end-time-cell", True), ("is-roster-shift-publish-required", display.displayMissingEndTime)]) display.displayShiftTypeColourKey display.displayEndLabel
    , readOnlyStaffCell display
    , readOnlyShiftTypeCell display
    ]
readOnlyExistingSlotCells display False blockIndex =
    [ readOnlyTimeCell (classes [("slot-time-cell", True), ("roster-block-start", blockIndex > 0), ("is-roster-shift-publish-required", display.displayMissingStartTime)]) display.displayShiftTypeColourKey display.displayTimeLabel
    , readOnlyStaffCell display
    , readOnlyShiftTypeCell display
    ]

readOnlyTimeCell :: Text -> Text -> Text -> ReadOnlyExistingSlotCell
readOnlyTimeCell cellClasses colourKey label = ReadOnlyExistingSlotCell
    { readOnlyCellClasses = cellClasses
    , readOnlyCellColourKey = colourKey
    , readOnlyCellContent = renderReadOnlyCell label
    , readOnlyCellConflictAttrs = Nothing
    }

readOnlyStaffCell :: ExistingSlotDisplay -> ReadOnlyExistingSlotCell
readOnlyStaffCell display = ReadOnlyExistingSlotCell
    { readOnlyCellClasses = classes [("slot-staff-cell position-relative", True), (renderConflictClass display.displayPrimaryConflict, True)]
    , readOnlyCellColourKey = display.displayShiftTypeColourKey
    , readOnlyCellContent = renderReadOnlyStaffCell display.displayStaffLabel display.displayPrimaryConflict
    , readOnlyCellConflictAttrs = Just (renderConflictMessage display.displayPrimaryConflict)
    }

readOnlyShiftTypeCell :: ExistingSlotDisplay -> ReadOnlyExistingSlotCell
readOnlyShiftTypeCell display = ReadOnlyExistingSlotCell
    { readOnlyCellClasses = classes [("slot-shift-type-cell roster-block-end", True), ("is-shift-type-empty", not display.displayHasShiftType), ("is-shift-type-required", display.displayMissingShiftType)]
    , readOnlyCellColourKey = display.displayShiftTypeColourKey
    , readOnlyCellContent = renderReadOnlyCell display.displayShiftTypeLabel
    , readOnlyCellConflictAttrs = Nothing
    }

renderReadOnlyExistingSlotCell :: ReadOnlyExistingSlotCell -> Html
renderReadOnlyExistingSlotCell ReadOnlyExistingSlotCell { readOnlyCellClasses, readOnlyCellColourKey, readOnlyCellContent, readOnlyCellConflictAttrs = Just conflictMessage } = [hsx|
    <div role="gridcell"
         class={readOnlyCellClasses}
         title={conflictMessage}
         data-conflict-message={conflictMessage}
         data-roster-shift-colour={readOnlyCellColourKey}>
        {readOnlyCellContent}
    </div>
|]
renderReadOnlyExistingSlotCell ReadOnlyExistingSlotCell { readOnlyCellClasses, readOnlyCellColourKey, readOnlyCellContent, readOnlyCellConflictAttrs = Nothing } = [hsx|
    <div role="gridcell"
         class={readOnlyCellClasses}
         data-roster-shift-colour={readOnlyCellColourKey}>
        {readOnlyCellContent}
    </div>
|]

renderDayColumnRosterSlotCard :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterSlot -> Html
renderDayColumnRosterSlotCard RosterDayRenderModel { dayIsEditable, dayAssignmentFilters, dayStaffMembers, dayShiftTypes, dayRenderIndexes, dayRosterEndTimesEnabled, dayPublishAttempted } slot =
    renderDayColumnSlotCardContent dayIsEditable dayAssignmentFilters dayStaffMembers dayShiftTypes dayRosterEndTimesEnabled dayPublishAttempted dayRenderIndexes (ExistingRosterSlotTarget slot.id) slot.staffId slot.startTime slot.endTime slot.shiftTypeId (primaryConflict (lookupConflicts (get #id slot) dayRenderIndexes))

renderDayColumnCreateCard :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Maybe RosterSlotCellTarget -> Html
renderDayColumnCreateCard RosterDayRenderModel { dayIsEditable } rosterDay maybeTarget
    | not dayIsEditable || rosterDay.isClosed = mempty
    | otherwise = maybe mempty renderDayColumnCreateLauncherCard maybeTarget

renderDayColumnCreateLauncherCard :: (?context :: ControllerContext) => RosterSlotCellTarget -> Html
renderDayColumnCreateLauncherCard target =
    let groupKey = rosterShiftGroupKey target
     in [hsx|
        <article class="roster-shift-card roster-shift-card-empty roster-shift-card-create roster-shift-launcher roster-shift-create-plus-card"
                 data-roster-shift-group-key={groupKey}
                 data-roster-shift-launcher="true"
                 tabindex="0"
                 hx-get={pathTo (rosterSlotDialogAction target)}
                 hx-target={"#" <> dialogOverlayMountId}
                 hx-swap="innerHTML"
                 hx-push-url="false"
                 aria-label="Add shift">
            <span class="roster-shift-create-plus" aria-hidden="true">+</span>
            <span class="visually-hidden">Add shift</span>
        </article>
    |]

renderDayColumnSlotCard :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> Bool -> Bool -> RosterDay -> Int -> [RosterSlot] -> RosterRenderIndexes -> (Int, RosterWeekSlotDefinition) -> Html
renderDayColumnSlotCard isEditable assignmentFilters staffMembers shiftTypes endTimesEnabled publishAttempted rosterDay rowIndex rowSlots renderIndexes (_, slotName)
    | rosterDay.isClosed = [hsx|<div class="roster-shift-card roster-shift-card-closed"><span>Closed</span></div>|]
    | otherwise =
        case Map.lookup (coerce (get #id rosterDay), rowIndex, coerce (get #id slotName)) renderIndexes.rosterSlotByDayRowSlotName of
            Just slot ->
                renderDayColumnSlotCardContent isEditable assignmentFilters staffMembers shiftTypes endTimesEnabled publishAttempted renderIndexes (ExistingRosterSlotTarget slot.id) slot.staffId slot.startTime slot.endTime slot.shiftTypeId (primaryConflict (lookupConflicts (get #id slot) renderIndexes))
            Nothing -> [hsx|<div class="roster-shift-card roster-shift-card-empty"></div>|]

renderDayColumnSlotCardContent :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> Bool -> Bool -> RosterRenderIndexes -> RosterSlotCellTarget -> Maybe UUID -> Maybe TimeOfDay -> Maybe TimeOfDay -> Maybe UUID -> Maybe RosterConflict -> Html
renderDayColumnSlotCardContent isEditable _assignmentFilters _staffMembers shiftTypes endTimesEnabled publishAttempted renderIndexes target staffId startTime endTime shiftTypeId currentPrimaryConflict =
    let currentStartTime = optionalTimeOfDayToStorageValue startTime
        currentEndTime = optionalTimeOfDayToStorageValue endTime
        currentStaffLabel = fromMaybe "" (renderAssignedStaffLabel staffId renderIndexes)
        currentShiftType = findShiftTypeForSlot shiftTypes shiftTypeId
        rosterSlotDataId = case target of
            ExistingRosterSlotTarget slotId -> tshow slotId
            NewRosterSlotTarget {}          -> ""
        currentShiftTypeColourKey = shiftTypeBadgeColourKey currentShiftType
        missingStartTime = publishAttempted && isJust staffId && isNothing startTime
        missingEndTime = publishAttempted && isJust staffId && isNothing endTime
        missingShiftType = publishAttempted && isJust staffId && isNothing shiftTypeId
        groupKey = rosterShiftGroupKey target
        endTimeField =
            if endTimesEnabled
                then [hsx|
                    <div class={classes [("roster-shift-card-field roster-shift-card-time", True), ("is-roster-shift-publish-required", missingEndTime)]}>
                        {renderReadOnlyCell (renderTimePickerDisplayLabel "End" currentEndTime)}
                    </div>
                |]
                else mempty
     in [hsx|
        <article class={classes [("roster-shift-card", True), ("roster-shift-card-create", not (targetHasExistingSlot target)), ("roster-shift-launcher", isEditable)]}
                 data-roster-slot-id={rosterSlotDataId}
                 data-roster-staff-id={maybe "" tshow staffId}
                 data-roster-shift-colour={currentShiftTypeColourKey}
                 data-roster-shift-group-key={groupKey}
                 data-roster-shift-launcher={if isEditable then ("true" :: Text) else ""}
                 tabindex={if isEditable then ("0" :: Text) else ""}
                 hx-get={if isEditable then pathTo (rosterSlotDialogAction target) else ""}
                 hx-target={"#" <> dialogOverlayMountId}
                 hx-swap="innerHTML"
                 hx-push-url="false"
                 title={renderConflictMessage currentPrimaryConflict}
                 data-conflict-message={renderConflictMessage currentPrimaryConflict}>
            <div class={classes [("roster-shift-card-fields", True), ("has-end-times", endTimesEnabled)]}>
                <div class={classes [("roster-shift-card-field roster-shift-card-time", True), ("is-roster-shift-publish-required", missingStartTime)]}>
                    {renderReadOnlyCell (renderTimePickerDisplayLabel "Start" currentStartTime)}
                </div>
                {endTimeField}
                <div class={classes [("roster-shift-card-field roster-shift-card-staff", True), (renderConflictClass currentPrimaryConflict, True)]}>
                    {if targetHasExistingSlot target then renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict else renderReadOnlyCell "Add shift"}
                </div>
                <div class={classes [("roster-shift-card-field roster-shift-card-code", True), ("is-shift-type-required", missingShiftType)]}
                     data-roster-shift-colour={currentShiftTypeColourKey}>
                    {renderReadOnlyDayColumnShiftTypeBadge staffId currentShiftType missingShiftType}
                </div>
            </div>
        </article>
    |]

targetHasExistingSlot :: RosterSlotCellTarget -> Bool
targetHasExistingSlot ExistingRosterSlotTarget {} = True
targetHasExistingSlot NewRosterSlotTarget {}      = False

renderEmptyBlockCells :: (?context :: ControllerContext) => Bool -> Int -> Html
renderEmptyBlockCells =
    renderBlankBlockCells "render.roster.empty_block" "slot-empty-cell"

-- Create slots use the same single-launcher shape as existing editable shifts,
-- but keep unmerged visual empty cells until hover/focus/highlight reveals the
-- centered merged plus overlay.
renderCreateBlockCells :: (?context :: ControllerContext) => RosterAssignmentFilters -> [Staff] -> [ShiftType] -> Bool -> RosterDay -> Int -> Int -> RosterWeekSlotDefinition -> Html
renderCreateBlockCells _assignmentFilters _staffMembers _shiftTypes endTimesEnabled rosterDay rowIndex blockIndex slotName =
    let target = NewRosterSlotTarget rosterDay.id slotName.id rowIndex
        groupKey = rosterShiftGroupKey target
        gridSpan = slotColumnCount endTimesEnabled
        visualCellClasses = createShiftUnitVisualCellClasses endTimesEnabled blockIndex
        visualCellCount = length visualCellClasses
     in mconcat
        [ profileCreateSlotCounters endTimesEnabled visualCellCount
        , renderCreateShiftUnit target groupKey visualCellClasses gridSpan
        ]

profileCreateSlotCounters :: Bool -> Int -> Html
profileCreateSlotCounters endTimesEnabled cellCount = mconcat
    [ profileRenderCounter "render.roster.create_slot" 1
    , profileRenderCounter (if endTimesEnabled then "render.roster.create_slot.end_times_enabled" else "render.roster.create_slot.no_end_times") 1
    , profileRenderCounter "render.roster.grid_cell" cellCount
    , profileRenderCounter "render.roster.readonly_cell" cellCount
    , profileRenderCounter "render.roster.shift_launcher" 1
    , profileRenderCounter "render.roster.launcher_attr_bundle" 1
    , profileRenderCounter "render.roster.launcher_hx_attr" 4
    , profileRenderCounter "render.roster.launcher_data_attr" 2
    ]

createShiftUnitVisualCellClasses :: Bool -> Int -> [Text]
createShiftUnitVisualCellClasses True blockIndex =
    [ classes [("roster-shift-unit-cell slot-empty-cell", True), ("roster-block-start", blockIndex > 0)]
    , "roster-shift-unit-cell slot-empty-cell"
    , "roster-shift-unit-cell slot-empty-cell"
    , "roster-shift-unit-cell slot-empty-cell roster-block-end"
    ]
createShiftUnitVisualCellClasses False blockIndex =
    [ classes [("roster-shift-unit-cell slot-empty-cell slot-time-cell", True), ("roster-block-start", blockIndex > 0)]
    , "roster-shift-unit-cell slot-empty-cell slot-staff-cell position-relative"
    , "roster-shift-unit-cell slot-empty-cell slot-shift-type-cell roster-block-end is-shift-type-empty"
    ]

renderCreateShiftUnit :: (?context :: ControllerContext) => RosterSlotCellTarget -> Text -> [Text] -> Int -> Html
renderCreateShiftUnit target groupKey visualCellClasses gridSpan =
    withInteractionDropzoneMarker groupKey [hsx|
        <div role="gridcell"
             class="roster-shift-unit roster-shift-launcher roster-shift-create-unit"
             style={rosterGridColumnSpanStyle gridSpan}
             data-roster-shift-group-key={groupKey}
             data-roster-shift-launcher="true"
             tabindex="0"
             hx-get={pathTo (rosterSlotDialogAction target)}
             hx-target={"#" <> dialogOverlayMountId}
             hx-swap="innerHTML"
             hx-push-url="false">
            {forEach visualCellClasses renderCreateShiftUnitVisualCell}
            <div class="roster-shift-create-plus-overlay" aria-hidden="true">+</div>
        </div>
    |]

renderCreateShiftUnitVisualCell :: Text -> Html
renderCreateShiftUnitVisualCell cellClasses = [hsx|<div class={cellClasses}></div>|]

renderClosedBlockCells :: (?context :: ControllerContext) => Bool -> Int -> Html
renderClosedBlockCells =
    renderBlankBlockCells "render.roster.closed_block" "slot-closed-cell"

renderBlankBlockCells :: (?context :: ControllerContext) => Text -> Text -> Bool -> Int -> Html
renderBlankBlockCells counterName baseClass endTimesEnabled blockIndex =
    mconcat
        [ profileRenderCounter counterName 1
        , profileRenderCounter "render.roster.grid_cell" cellCount
        , forEach cellClasses renderBlankGridCell
        ]
    where
        cellCount = if endTimesEnabled then 4 else 3
        cellClasses =
            [ classes [(baseClass, True), ("roster-block-start", blockIndex > 0)]
            ] <> replicate (cellCount - 2) baseClass <> [baseClass <> " roster-block-end"]

renderBlankGridCell :: Text -> Html
renderBlankGridCell cellClasses = [hsx|<div role="gridcell" class={cellClasses}></div>|]

renderShiftTypeOptionLabel :: ShiftType -> Text
renderShiftTypeOptionLabel shiftType =
    if shiftType.isActive
        then shiftType.name
        else shiftType.name <> " (inactive)"

findShiftTypeForSlot :: [ShiftType] -> Maybe UUID -> Maybe ShiftType
findShiftTypeForSlot _ Nothing = Nothing
findShiftTypeForSlot shiftTypes (Just selectedShiftTypeId) =
    find (\shiftType -> coerce shiftType.id == selectedShiftTypeId) shiftTypes

shiftTypeBadgeColourKey :: Maybe ShiftType -> Text
shiftTypeBadgeColourKey =
    maybe "" normaliseShiftTypeBadgeColourKey

normaliseShiftTypeBadgeColourKey :: ShiftType -> Text
normaliseShiftTypeBadgeColourKey shiftType
    | shiftType.colourKey `elem` shiftTypeColourPaletteKeys = shiftType.colourKey
    | otherwise = ""

shiftTypeBadgeLabel :: Maybe UUID -> Maybe ShiftType -> Text
shiftTypeBadgeLabel staffId =
    maybe (if isJust staffId then "Role required" else "Role") renderShiftTypeOptionLabel

renderReadOnlyDayColumnShiftTypeBadge :: Maybe UUID -> Maybe ShiftType -> Bool -> Html
renderReadOnlyDayColumnShiftTypeBadge staffId selectedShiftType isPublishRequired = [hsx|
    <div class={classes [("app-dense-static slot-cell-static roster-shift-type-badge roster-shift-type-badge-readonly", True), ("is-empty", isNothing selectedShiftType), ("is-required", isPublishRequired), ("is-publish-required", isPublishRequired)]}
         data-roster-shift-colour={shiftTypeBadgeColourKey selectedShiftType}>
        <span class="roster-shift-type-badge-label">{shiftTypeBadgeLabel staffId selectedShiftType}</span>
    </div>
|]

renderReadOnlyStaffCell :: Text -> Maybe RosterConflict -> Html
renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict =
    mconcat
        [ [hsx|<div class="app-dense-static slot-cell-static">{currentStaffLabel}</div>|] ]

rosterSlotDialogAction :: RosterSlotCellTarget -> RosterWeeksController
rosterSlotDialogAction (ExistingRosterSlotTarget rosterSlotId) =
    EditRosterSlotDialogAction rosterSlotId
rosterSlotDialogAction (NewRosterSlotTarget rosterDayId rosterWeekSlotDefinitionId rowIndex) =
    NewRosterSlotDialogAction rosterDayId rosterWeekSlotDefinitionId rowIndex

rosterShiftGroupKey :: RosterSlotCellTarget -> Text
rosterShiftGroupKey (ExistingRosterSlotTarget rosterSlotId) =
    "existing:" <> tshow rosterSlotId
rosterShiftGroupKey (NewRosterSlotTarget rosterDayId rosterWeekSlotDefinitionId rowIndex) =
    "new:" <> tshow rosterDayId <> ":" <> tshow rosterWeekSlotDefinitionId <> ":" <> tshow rowIndex

renderReadOnlyCell :: Text -> Html
renderReadOnlyCell value = [hsx|
    <div class={classes [("app-dense-static slot-cell-static", True), ("app-muted", Text.null value)]}>{if Text.null value then " " else value}</div>
|]

renderAssignedStaffLabel :: Maybe UUID -> RosterRenderIndexes -> Maybe Text
renderAssignedStaffLabel Nothing _ = Nothing
renderAssignedStaffLabel (Just assignedStaffId) renderIndexes =
    staffDisplayName (Map.elems renderIndexes.rosterStaffById)
        <$> Map.lookup assignedStaffId renderIndexes.rosterStaffById

lookupConflicts :: Id RosterSlot -> RosterRenderIndexes -> [RosterConflict]
lookupConflicts slotId renderIndexes = Map.findWithDefault [] (coerce slotId) renderIndexes.rosterConflictsBySlotId

renderConflictClass :: Maybe RosterConflict -> Text
renderConflictClass Nothing = ""
renderConflictClass (Just conflict) =
    case conflict.conflictType of
        DuplicateAssignment           -> "conflict-critical"
        LeaveConflict                 -> "conflict-critical"
        LateToEarlyConflict           -> "conflict-critical"
        ShiftPreferenceDayUnavailable -> "conflict-preference"
        ShiftPreferenceSlotMismatch   -> "conflict-preference"
        IdealShiftThresholdExceeded   -> "conflict-ideal"

renderConflictMessage :: Maybe RosterConflict -> Text
renderConflictMessage Nothing         = ""
renderConflictMessage (Just conflict) = conflict.message
