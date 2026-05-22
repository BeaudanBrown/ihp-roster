module Web.View.RosterWeeks.Grid
    ( lastRowIndexForRows
    , renderRosterContentFragment
    , renderRosterContentFragmentOob
    , renderRosterLayout
    , renderRosterDaySectionFragment
    , renderRosterDaySectionFragmentOob
    , renderRowFragment
    , renderRowOob
    , compactDayColumnSlots
    , rowsForDay
    ) where

import Application.Helper.RosterWagePrediction
import Application.Helper.UserPreferences (rosterLayoutModeValue)
import Application.Helper.View (staffDisplayName)
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
import Web.RosterWeeks.Types
import Web.View.Prelude
import Web.View.RosterWeeks.Header (renderRosterGridHeader)
import Web.View.RosterWeeks.StaffSelfServicePanel (renderRosterStaffSelfServicePanelFragment)
import Web.View.RosterWeeks.StaffPanel (renderRosterStaffPanelFragment)

data RosterSlotCellTarget
    = ExistingRosterSlotTarget (Id RosterSlot)
    | NewRosterSlotTarget (Id RosterDay) (Id RosterWeekSlotDefinition) Int

renderRosterContentFragment :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterContentFragment =
    renderRosterContentFragmentWithSwap Nothing

renderRosterContentFragmentOob :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterContentFragmentOob =
    renderRosterContentFragmentWithSwap (Just "outerHTML")

renderRosterContentFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterGridRenderModel -> Html
renderRosterContentFragmentWithSwap maybeSwapOob gridModel = [hsx|
    <div id={rosterContentFragmentId}
         class={rosterContentColumnClasses gridModel}
         hx-swap-oob={maybeSwapOob}>
        {renderRosterContent gridModel}
    </div>
|]

renderRosterLayout :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterLayout gridModel@RosterGridRenderModel { gridRosterWeek, gridWeekOffset, gridPanelStaff, gridStaffSelfServicePanel } = [hsx|
    <div class="row g-4 align-items-start roster-layout">
        {renderRosterContentFragment gridModel}
        {forEach gridRosterWeek (\rosterWeek -> renderRosterStaffPanelFragment gridWeekOffset (coerce rosterWeek.rosterGroupId) gridPanelStaff)}
        {renderRosterStaffSelfServicePanelFragment gridStaffSelfServicePanel}
    </div>
|]

rosterContentColumnClasses :: (?context :: ControllerContext) => RosterGridRenderModel -> Text
rosterContentColumnClasses RosterGridRenderModel { gridStaffSelfServicePanel } =
    classes [("col-12", True), ("col-xl-8", hasSidePanel), ("col-xxl-10", hasSidePanel), ("mx-auto", not hasSidePanel), ("roster-layout-main", hasSidePanel)]
    where
        hasSidePanel = currentUserIsManager || isJust gridStaffSelfServicePanel

renderRosterContent :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterContent =
    renderRosterMainPanel

renderRosterMainPanel :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterMainPanel RosterGridRenderModel { gridRosterWeek, gridRosterDays, gridWeekOffset, gridRosterGroups, gridCurrentRosterGroup, gridAssignmentFilters, gridStaffMembers, gridStaffOptionStates, gridSlotNames, gridShiftTypes, gridWeekStartDate, gridAllSlots, gridSlotConflicts, gridRenderIndexes, gridViewCapabilities, gridRosterLayoutMode, gridShowShiftTypeHighlights, gridRosterEndTimesEnabled, gridRosterWagePrediction } =
    let dayModel =
            RosterDayRenderModel
                { dayIsEditable = rosterWeekIsEditable gridRosterWeek
                , daySlotNames = gridSlotNames
                , dayAssignmentFilters = gridAssignmentFilters
                , dayStaffMembers = gridStaffMembers
                , dayStaffOptionStates = gridStaffOptionStates
                , dayShiftTypes = gridShiftTypes
                , dayWeekStartDate = gridWeekStartDate
                , dayAllSlots = gridAllSlots
                , daySlotConflicts = gridSlotConflicts
                , dayRenderIndexes = gridRenderIndexes
                , dayRosterLayoutMode = gridRosterLayoutMode
                , dayRosterEndTimesEnabled = gridRosterEndTimesEnabled
                , dayRosterWagePrediction = gridRosterWagePrediction
                }
        slotColumnsAreEditable = gridViewCapabilities.canManageRosterColumns
        isDayColumnsLayout = rosterLayoutModeValue gridRosterLayoutMode == "day_columns"
        gridBody =
            if isDayColumnsLayout
                then renderRosterDayColumns dayModel gridRosterDays
                else renderRosterDayRowsGrid gridRosterEndTimesEnabled slotColumnsAreEditable gridRosterWeek gridSlotNames dayModel gridRosterDays
     in [hsx|
    <div class="app-panel overflow-hidden mb-5 mb-xl-0">
        {renderRosterGridHeader gridRosterWeek gridWeekOffset gridRosterGroups gridCurrentRosterGroup gridAssignmentFilters gridWeekStartDate gridViewCapabilities gridRosterLayoutMode gridShowShiftTypeHighlights gridRosterWagePrediction}
        <div class="roster-grid-frame"
             data-roster-layout={rosterLayoutModeValue gridRosterLayoutMode}
             data-roster-shift-type-highlights={if gridShowShiftTypeHighlights then ("true" :: Text) else "false"}
             data-roster-end-times={if gridRosterEndTimesEnabled then ("true" :: Text) else "false"}
             data-roster-column-editor={if slotColumnsAreEditable then ("available" :: Text) else "unavailable"}
             style={"--roster-slot-count:" <> tshow (max 1 (length gridSlotNames)) <> ";"}>
            {gridBody}
        </div>
    </div>
|]

renderDayWagePrediction :: (?context :: ControllerContext) => Maybe RosterWagePrediction -> Day -> Html
renderDayWagePrediction Nothing _ = mempty
renderDayWagePrediction (Just prediction) date
    | not currentUserIsAdmin = mempty
    | otherwise =
        case lookupRosterWagePredictionDayByDate prediction date of
            Nothing -> mempty
            Just dayPrediction -> [hsx|
                <div class="roster-day-wage-total" aria-label="Predicted wages for day">
                    {formatMoneyAmount dayPrediction.predictionDayTotal}
                </div>
            |]

renderRosterDayRowsGrid :: (?context :: ControllerContext) => Bool -> Bool -> Maybe RosterWeek -> [RosterWeekSlotDefinition] -> RosterDayRenderModel -> [RosterDay] -> Html
renderRosterDayRowsGrid endTimesEnabled slotColumnsAreEditable maybeRosterWeek slotNames dayModel rosterDays = [hsx|
    <div class="roster-day-rail" aria-label="Roster days">
        <div class="roster-day-rail-head">
            <span class="roster-day-rail-head-label">Day</span>
            {renderRosterColumnEditStartButton slotColumnsAreEditable}
            {renderRosterColumnEditDoneButton slotColumnsAreEditable}
        </div>
        <div class="roster-day-rail-body">
            {forEach rosterDays (renderRosterDayRailSection dayModel)}
        </div>
    </div>
    <div class="roster-slots-scroller">
        <div class="roster-grid roster-slots-grid" role="grid" aria-label="Roster slots">
            <div class="roster-grid-head" role="rowgroup">
                <div class="roster-grid-header-row roster-grid-header-row-blocks" role="row">
                    {forEach (zip [0 :: Int ..] slotNames) (renderSlotHeaderGroup endTimesEnabled maybeRosterWeek slotColumnsAreEditable (length slotNames))}
                </div>
                <div class="roster-grid-header-row roster-grid-header-row-subheads" role="row">
                    {forEach slotNames (renderSlotSubHeaders endTimesEnabled)}
                </div>
            </div>
            {forEach rosterDays (renderRosterDay dayModel)}
        </div>
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
    "grid-column: span " <> tshow (slotColumnCount endTimesEnabled) <> ";"

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
        , [hsx|<div role="columnheader" class="roster-subhead roster-col-shift-type roster-block-end">Type</div>|]
        ]
renderSlotSubHeaders False _ =
    mconcat
        [ [hsx|<div role="columnheader" class="roster-subhead roster-col-time">Time</div>|]
        , [hsx|<div role="columnheader" class="roster-subhead roster-col-staff">Staff</div>|]
        , [hsx|<div role="columnheader" class="roster-subhead roster-col-code roster-block-end">Type</div>|]
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
renderRosterDaySectionFragmentWithSwap maybeSwapOob dayModel@RosterDayRenderModel { dayWeekStartDate, dayAllSlots, dayRenderIndexes } rosterDay = [hsx|
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
renderRosterDayRailSection RosterDayRenderModel { dayIsEditable, dayWeekStartDate, dayAllSlots, dayRenderIndexes, dayRosterWagePrediction } rosterDay =
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
                        {renderPrimaryDayLabel date}
                        {renderDayWagePrediction dayRosterWagePrediction date}
                    </div>
                </div>
                <div class="roster-day-label-row roster-day-label-row-controls">
                    {renderDayRowControls dayIsEditable rosterDay lastRowIndex}
                </div>
                {renderEmptyDayLabelRows rowCount 2}
            </div>
        </div>
    |]

renderRosterDayColumns :: (?context :: ControllerContext) => RosterDayRenderModel -> [RosterDay] -> Html
renderRosterDayColumns dayModel rosterDays = [hsx|
    <div class="roster-day-columns" style={"--roster-day-count:" <> tshow (max 1 (length rosterDays)) <> ";"}>
        {forEach rosterDays (renderRosterDayColumn dayModel)}
    </div>
|]

renderRosterDayColumn :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Html
renderRosterDayColumn =
    renderRosterDayColumnWithSwap Nothing

renderRosterDayColumnWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterDayRenderModel -> RosterDay -> Html
renderRosterDayColumnWithSwap maybeSwapOob dayModel@RosterDayRenderModel { dayIsEditable, dayWeekStartDate, dayAllSlots, dayRenderIndexes, dayRosterWagePrediction } rosterDay =
    let daySlots = filter (\s -> s.rosterDayId == coerce (get #id rosterDay)) dayAllSlots
        dayRows = Map.findWithDefault (rowsForDay rosterDay daySlots) (coerce (get #id rosterDay)) dayRenderIndexes.rosterDayRowsByDayId
        rowCount = length dayRows
        lastRowIndex = lastRowIndexForRows dayRows
        date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) dayWeekStartDate
        compactSlots = compactDayColumnSlots dayModel.daySlotNames daySlots
        maybeCreateTarget = firstAvailableDayColumnTarget dayModel.daySlotNames rosterDay daySlots
     in [hsx|
        <section id={rosterDaySectionDomId rosterDay.id}
                 data-roster-day-section="true"
                 hx-swap-oob={maybeSwapOob}
                 class={classes [("roster-day-column", True), ("day-alt-dark", odd (get #dayOffset rosterDay)), ("day-alt-light", even (get #dayOffset rosterDay))]}>
            <header class="roster-day-column-header">
                <div class="roster-day-heading">
                    {renderPrimaryDayLabel date}
                    {renderDayWagePrediction dayRosterWagePrediction date}
                </div>
                {renderDayColumnHeaderControls dayIsEditable rosterDay}
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
renderDayColumnRow RosterRowRenderModel { rowIsEditable, rowSlotNames, rowAssignmentFilters, rowStaffMembers, rowStaffOptionStates, rowShiftTypes, rowRosterDay, rowRenderIndexes, rowRosterEndTimesEnabled } (_, (rowIndex, rowSlots)) maybeSwapOob = [hsx|
    <div id={rosterRowDomIdText rowRosterDay.id rowIndex}
         data-roster-row="true"
         hx-swap-oob={maybeSwapOob}
         class={classes [("roster-day-column-row", True), ("day-row-" <> tshow (get #dayOffset rowRosterDay), True)]}>
        {forEach (zip [0 :: Int ..] rowSlotNames) (renderDayColumnSlotCard rowIsEditable rowAssignmentFilters rowStaffMembers rowStaffOptionStates rowShiftTypes rowRosterEndTimesEnabled rowRosterDay rowIndex rowSlots rowRenderIndexes)}
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
renderDayRows RosterDayRenderModel { dayIsEditable, daySlotNames, dayAssignmentFilters, dayStaffMembers, dayStaffOptionStates, dayShiftTypes, dayRenderIndexes, dayRosterLayoutMode, dayRosterEndTimesEnabled } date rosterDay dayRows =
    let rowModel =
            RosterRowRenderModel
                { rowIsEditable = dayIsEditable
                , rowSlotNames = daySlotNames
                , rowAssignmentFilters = dayAssignmentFilters
                , rowStaffMembers = dayStaffMembers
                , rowStaffOptionStates = dayStaffOptionStates
                , rowShiftTypes = dayShiftTypes
                , rowDate = date
                , rowRosterDay = rosterDay
                , rowCount
                , rowLastRowIndex = lastRowIndex
                , rowRenderIndexes = dayRenderIndexes
                , rowRosterLayoutMode = dayRosterLayoutMode
                , rowRosterEndTimesEnabled = dayRosterEndTimesEnabled
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
renderRowWithAttrs RosterRowRenderModel { rowIsEditable, rowSlotNames, rowAssignmentFilters, rowStaffMembers, rowStaffOptionStates, rowShiftTypes, rowRosterDay, rowRenderIndexes, rowRosterEndTimesEnabled } (_, (rowIndex, rowSlots)) maybeSwapOob = [hsx|
    <div id={rosterRowDomIdText rowRosterDay.id rowIndex}
         role="row"
         data-roster-row="true"
         hx-swap-oob={maybeSwapOob}
         class={classes [("day-row", True), ("day-row-" <> tshow (get #dayOffset rowRosterDay), True), ("day-alt-dark", odd (get #dayOffset rowRosterDay)), ("day-alt-light", even (get #dayOffset rowRosterDay))]}>
        {forEach (zip [0 :: Int ..] rowSlotNames) (renderBlockCells rowIsEditable rowAssignmentFilters rowStaffMembers rowStaffOptionStates rowShiftTypes rowRosterEndTimesEnabled rowRosterDay rowIndex rowSlots rowRenderIndexes)}
    </div>
|]

renderPrimaryDayLabel :: Day -> Html
renderPrimaryDayLabel date = [hsx|
    <div class="roster-day-date">{Text.pack (formatTime defaultTimeLocale "%a" date)} {Text.pack (formatTime defaultTimeLocale "%d/%m" date)}</div>
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
                        class={classes [("btn btn-sm roster-day-action roster-day-action-toggle", True), ("is-active", rosterDay.isClosed)]}
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
                        class="btn btn-sm roster-day-action roster-day-action-add"
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
                        class="btn btn-sm roster-day-action roster-day-action-remove"
                        aria-label={if canDelete then ("Delete last shift row" :: Text) else ("Minimum day size reached" :: Text)}
                        data-roster-day-remove="true"
                        title={if canDelete then ("Delete last shift row" :: Text) else ("Minimum day size reached" :: Text)}
                        disabled={not canDelete}>
                    <i class="bi bi-dash-lg" aria-hidden="true"></i>
                </button>
            </form>
        |]
        else [hsx|<span></span>|]

renderBlockCells :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [ShiftType] -> Bool -> RosterDay -> Int -> [RosterSlot] -> RosterRenderIndexes -> (Int, RosterWeekSlotDefinition) -> Html
renderBlockCells isEditable assignmentFilters staffMembers staffOptionStates shiftTypes endTimesEnabled rosterDay rowIndex rowSlots renderIndexes (blockIndex, slotName) =
    if rosterDay.isClosed
        then renderClosedBlockCells endTimesEnabled blockIndex
        else
            maybe
                (if isEditable
                    then renderCreateBlockCells assignmentFilters staffMembers staffOptionStates shiftTypes endTimesEnabled rosterDay rowIndex blockIndex slotName
                    else renderEmptyBlockCells endTimesEnabled blockIndex)
                (renderExistingSlotBlockCells isEditable assignmentFilters staffMembers staffOptionStates shiftTypes endTimesEnabled renderIndexes blockIndex)
                (Map.lookup (coerce (get #id rosterDay), rowIndex, coerce (get #id slotName)) renderIndexes.rosterSlotByDayRowSlotName)

renderExistingSlotBlockCells :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [ShiftType] -> Bool -> RosterRenderIndexes -> Int -> RosterSlot -> Html
renderExistingSlotBlockCells isEditable assignmentFilters staffMembers staffOptionStates shiftTypes endTimesEnabled renderIndexes blockIndex slot =
    let currentStartTime = optionalTimeOfDayToStorageValue slot.startTime
        currentEndTime = optionalTimeOfDayToStorageValue slot.endTime
        currentPrimaryConflict = primaryConflict (lookupConflicts (get #id slot) renderIndexes)
        currentStaffLabel = fromMaybe "" (renderAssignedStaffLabel slot.staffId renderIndexes)
        currentShiftType = findShiftTypeForSlot shiftTypes slot.shiftTypeId
        currentShiftTypeLabel = fromMaybe "" (renderShiftTypeOptionLabel <$> currentShiftType)
    in
    if endTimesEnabled
        then [hsx|
            <div role="gridcell"
                 class={classes [("slot-time-cell", True), ("slot-start-time-cell", True), ("roster-block-start", blockIndex > 0)]}
                 data-roster-staff-id={maybe "" tshow slot.staffId}
                 data-roster-slot-id={tshow slot.id}>
                {if isEditable then renderEditableTimeCell "startTime" "Select roster slot start time" "Start" (ExistingRosterSlotTarget slot.id) currentStartTime else renderReadOnlyCell (renderTimePickerDisplayLabel "Start" currentStartTime)}
            </div>

            <div role="gridcell"
                 class="slot-time-cell slot-end-time-cell"
                 data-roster-staff-id={maybe "" tshow slot.staffId}
                 data-roster-slot-id={tshow slot.id}>
                {if isEditable then renderEditableTimeCell "endTime" "Select roster slot end time" "End" (ExistingRosterSlotTarget slot.id) currentEndTime else renderReadOnlyCell (renderTimePickerDisplayLabel "End" currentEndTime)}
            </div>

            <div role="gridcell"
                 class={classes [("slot-staff-cell position-relative", True), (renderConflictClass currentPrimaryConflict, True)]}
                 title={renderConflictMessage currentPrimaryConflict}
                 data-conflict-message={renderConflictMessage currentPrimaryConflict}
                 data-roster-staff-id={maybe "" tshow slot.staffId}
                 data-roster-slot-id={tshow slot.id}>
                {if isEditable then renderEditableStaffCell assignmentFilters (ExistingRosterSlotTarget slot.id) slot.staffId staffMembers staffOptionStates currentPrimaryConflict else renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict}
            </div>

            <div role="gridcell"
                 class={classes [("slot-shift-type-cell roster-block-end", True), ("is-shift-type-empty", isNothing slot.shiftTypeId), ("is-shift-type-required", isJust slot.staffId && isNothing slot.shiftTypeId)]}
                 data-roster-shift-colour={shiftTypeBadgeColourKey currentShiftType}
                 data-roster-staff-id={maybe "" tshow slot.staffId}
                 data-roster-slot-id={tshow slot.id}>
                {if isEditable then renderEditableShiftTypeCell (ExistingRosterSlotTarget slot.id) slot.shiftTypeId shiftTypes else renderReadOnlyCell currentShiftTypeLabel}
            </div>
        |]
        else [hsx|
            <div role="gridcell"
                 class={classes [("slot-time-cell", True), ("roster-block-start", blockIndex > 0)]}
                 data-roster-staff-id={maybe "" tshow slot.staffId}
                 data-roster-slot-id={tshow slot.id}>
                {if isEditable then renderEditableTimeCell "startTime" "Select roster slot time" "Time" (ExistingRosterSlotTarget slot.id) currentStartTime else renderReadOnlyCell (renderTimePickerDisplayLabel "Time" currentStartTime)}
            </div>

            <div role="gridcell"
                 class={classes [("slot-staff-cell position-relative", True), (renderConflictClass currentPrimaryConflict, True)]}
                 title={renderConflictMessage currentPrimaryConflict}
                 data-conflict-message={renderConflictMessage currentPrimaryConflict}
                 data-roster-staff-id={maybe "" tshow slot.staffId}
                 data-roster-slot-id={tshow slot.id}>
                {if isEditable then renderEditableStaffCell assignmentFilters (ExistingRosterSlotTarget slot.id) slot.staffId staffMembers staffOptionStates currentPrimaryConflict else renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict}
            </div>

            <div role="gridcell"
                 class={classes [("slot-shift-type-cell roster-block-end", True), ("is-shift-type-empty", isNothing slot.shiftTypeId), ("is-shift-type-required", isJust slot.staffId && isNothing slot.shiftTypeId)]}
                 data-roster-shift-colour={shiftTypeBadgeColourKey currentShiftType}
                 data-roster-staff-id={maybe "" tshow slot.staffId}
                 data-roster-slot-id={tshow slot.id}>
                {if isEditable then renderEditableShiftTypeCell (ExistingRosterSlotTarget slot.id) slot.shiftTypeId shiftTypes else renderReadOnlyCell currentShiftTypeLabel}
            </div>
        |]

renderDayColumnRosterSlotCard :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterSlot -> Html
renderDayColumnRosterSlotCard RosterDayRenderModel { dayIsEditable, dayAssignmentFilters, dayStaffMembers, dayStaffOptionStates, dayShiftTypes, dayRenderIndexes, dayRosterEndTimesEnabled } slot =
    renderDayColumnSlotCardContent dayIsEditable dayAssignmentFilters dayStaffMembers dayStaffOptionStates dayShiftTypes dayRosterEndTimesEnabled dayRenderIndexes (ExistingRosterSlotTarget slot.id) slot.staffId slot.startTime slot.endTime slot.shiftTypeId (primaryConflict (lookupConflicts (get #id slot) dayRenderIndexes))

renderDayColumnCreateCard :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Maybe RosterSlotCellTarget -> Html
renderDayColumnCreateCard RosterDayRenderModel { dayIsEditable, dayAssignmentFilters, dayStaffMembers, dayStaffOptionStates, dayShiftTypes, dayRosterEndTimesEnabled } rosterDay maybeTarget
    | not dayIsEditable || rosterDay.isClosed = mempty
    | otherwise =
        case maybeTarget of
            Nothing -> mempty
            Just target ->
                renderDayColumnSlotCardContent True dayAssignmentFilters dayStaffMembers dayStaffOptionStates dayShiftTypes dayRosterEndTimesEnabled emptyRenderIndexes target Nothing Nothing Nothing Nothing Nothing
  where
    emptyRenderIndexes =
        RosterRenderIndexes
            { rosterDayById = Map.empty
            , rosterDayRowsByDayId = Map.empty
            , rosterSlotByDayRowSlotName = Map.empty
            , rosterStaffById = Map.empty
            , rosterConflictsBySlotId = Map.empty
            }

renderDayColumnSlotCard :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [ShiftType] -> Bool -> RosterDay -> Int -> [RosterSlot] -> RosterRenderIndexes -> (Int, RosterWeekSlotDefinition) -> Html
renderDayColumnSlotCard isEditable assignmentFilters staffMembers staffOptionStates shiftTypes endTimesEnabled rosterDay rowIndex rowSlots renderIndexes (_, slotName)
    | rosterDay.isClosed = [hsx|<div class="roster-shift-card roster-shift-card-closed"><span>Closed</span></div>|]
    | otherwise =
        case Map.lookup (coerce (get #id rosterDay), rowIndex, coerce (get #id slotName)) renderIndexes.rosterSlotByDayRowSlotName of
            Just slot ->
                renderDayColumnSlotCardContent isEditable assignmentFilters staffMembers staffOptionStates shiftTypes endTimesEnabled renderIndexes (ExistingRosterSlotTarget slot.id) slot.staffId slot.startTime slot.endTime slot.shiftTypeId (primaryConflict (lookupConflicts (get #id slot) renderIndexes))
            Nothing -> [hsx|<div class="roster-shift-card roster-shift-card-empty"></div>|]

renderDayColumnSlotCardContent :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [ShiftType] -> Bool -> RosterRenderIndexes -> RosterSlotCellTarget -> Maybe UUID -> Maybe TimeOfDay -> Maybe TimeOfDay -> Maybe UUID -> Maybe RosterConflict -> Html
renderDayColumnSlotCardContent isEditable assignmentFilters staffMembers staffOptionStates shiftTypes endTimesEnabled renderIndexes target staffId startTime endTime shiftTypeId currentPrimaryConflict =
    let currentStartTime = optionalTimeOfDayToStorageValue startTime
        currentEndTime = optionalTimeOfDayToStorageValue endTime
        currentStaffLabel = fromMaybe "" (renderAssignedStaffLabel staffId renderIndexes)
        currentShiftType = findShiftTypeForSlot shiftTypes shiftTypeId
        rosterSlotDataId = case target of
            ExistingRosterSlotTarget slotId -> tshow slotId
            NewRosterSlotTarget {} -> ""
        endTimeField =
            if endTimesEnabled
                then [hsx|
                    <div class="roster-shift-card-field roster-shift-card-time">
                        {if isEditable then renderEditableTimeCell "endTime" "Select roster slot end time" "End" target currentEndTime else renderReadOnlyCell (renderTimePickerDisplayLabel "End" currentEndTime)}
                    </div>
                |]
                else mempty
        codeField
            | isEditable = renderEditableDayColumnShiftTypeBadge target staffId shiftTypeId currentShiftType shiftTypes
            | otherwise = renderReadOnlyDayColumnShiftTypeBadge staffId currentShiftType
     in [hsx|
        <article class={classes [("roster-shift-card", True), ("roster-shift-card-create", not (targetHasExistingSlot target))]}
                 data-roster-slot-id={rosterSlotDataId}
                 data-roster-staff-id={maybe "" tshow staffId}
                 title={renderConflictMessage currentPrimaryConflict}
                 data-conflict-message={renderConflictMessage currentPrimaryConflict}>
            <div class={classes [("roster-shift-card-fields", True), ("has-end-times", endTimesEnabled)]}>
                <div class="roster-shift-card-field roster-shift-card-time">
                    {if isEditable then renderEditableTimeCell "startTime" "Select roster slot start time" "Start" target currentStartTime else renderReadOnlyCell (renderTimePickerDisplayLabel "Start" currentStartTime)}
                </div>
                {endTimeField}
                <div class={classes [("roster-shift-card-field roster-shift-card-staff", True), (renderConflictClass currentPrimaryConflict, True)]}>
                    {if isEditable then renderEditableStaffCell assignmentFilters target staffId staffMembers staffOptionStates currentPrimaryConflict else renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict}
                </div>
                <div class="roster-shift-card-field roster-shift-card-code"
                     data-roster-shift-colour={shiftTypeBadgeColourKey currentShiftType}>
                    {codeField}
                </div>
            </div>
        </article>
    |]

targetHasExistingSlot :: RosterSlotCellTarget -> Bool
targetHasExistingSlot ExistingRosterSlotTarget {} = True
targetHasExistingSlot NewRosterSlotTarget {}      = False

renderEmptyBlockCells :: Bool -> Int -> Html
renderEmptyBlockCells True blockIndex =
    mconcat
        [ [hsx|<div role="gridcell" class={classes [("slot-empty-cell", True), ("roster-block-start", blockIndex > 0)]}></div>|]
        , [hsx|<div role="gridcell" class="slot-empty-cell"></div>|]
        , [hsx|<div role="gridcell" class="slot-empty-cell"></div>|]
        , [hsx|<div role="gridcell" class="slot-empty-cell roster-block-end"></div>|]
        ]
renderEmptyBlockCells False blockIndex =
    mconcat
        [ [hsx|<div role="gridcell" class={classes [("slot-empty-cell", True), ("roster-block-start", blockIndex > 0)]}></div>|]
        , [hsx|<div role="gridcell" class="slot-empty-cell"></div>|]
        , [hsx|<div role="gridcell" class="slot-empty-cell roster-block-end"></div>|]
        ]

renderCreateBlockCells :: (?context :: ControllerContext) => RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [ShiftType] -> Bool -> RosterDay -> Int -> Int -> RosterWeekSlotDefinition -> Html
renderCreateBlockCells assignmentFilters staffMembers staffOptionStates shiftTypes True rosterDay rowIndex blockIndex slotName =
    let target = NewRosterSlotTarget rosterDay.id slotName.id rowIndex
     in mconcat
        [ [hsx|<div role="gridcell" class={classes [("slot-time-cell", True), ("slot-start-time-cell", True), ("roster-block-start", blockIndex > 0)]}>{renderEditableTimeCell "startTime" "Select roster slot start time" "Start" target ""}</div>|]
        , [hsx|<div role="gridcell" class="slot-time-cell slot-end-time-cell">{renderEditableTimeCell "endTime" "Select roster slot end time" "End" target ""}</div>|]
        , [hsx|<div role="gridcell" class="slot-staff-cell position-relative">{renderEditableStaffCell assignmentFilters target Nothing staffMembers staffOptionStates Nothing}</div>|]
        , [hsx|<div role="gridcell" class="slot-shift-type-cell roster-block-end is-shift-type-empty" data-roster-shift-colour="default">{renderEditableShiftTypeCell target Nothing shiftTypes}</div>|]
        ]
renderCreateBlockCells assignmentFilters staffMembers staffOptionStates shiftTypes False rosterDay rowIndex blockIndex slotName =
    let target = NewRosterSlotTarget rosterDay.id slotName.id rowIndex
     in mconcat
        [ [hsx|<div role="gridcell" class={classes [("slot-time-cell", True), ("roster-block-start", blockIndex > 0)]}>{renderEditableTimeCell "startTime" "Select roster slot time" "Time" target ""}</div>|]
        , [hsx|<div role="gridcell" class="slot-staff-cell position-relative">{renderEditableStaffCell assignmentFilters target Nothing staffMembers staffOptionStates Nothing}</div>|]
        , [hsx|<div role="gridcell" class="slot-shift-type-cell roster-block-end is-shift-type-empty" data-roster-shift-colour="default">{renderEditableShiftTypeCell target Nothing shiftTypes}</div>|]
        ]

renderClosedBlockCells :: Bool -> Int -> Html
renderClosedBlockCells True blockIndex =
    mconcat
        [ [hsx|<div role="gridcell" class={classes [("slot-closed-cell", True), ("roster-block-start", blockIndex > 0)]}></div>|]
        , [hsx|<div role="gridcell" class="slot-closed-cell"></div>|]
        , [hsx|<div role="gridcell" class="slot-closed-cell"></div>|]
        , [hsx|<div role="gridcell" class="slot-closed-cell roster-block-end"></div>|]
        ]
renderClosedBlockCells False blockIndex =
    mconcat
        [ [hsx|<div role="gridcell" class={classes [("slot-closed-cell", True), ("roster-block-start", blockIndex > 0)]}></div>|]
        , [hsx|<div role="gridcell" class="slot-closed-cell"></div>|]
        , [hsx|<div role="gridcell" class="slot-closed-cell roster-block-end"></div>|]
        ]

renderStaffOption :: [Staff] -> Maybe UUID -> Maybe RosterAssignmentOptionState -> Staff -> Html
renderStaffOption staffMembers selectedStaffId maybeOptionState staff = [hsx|
    <option value={tshow (get #id staff)} selected={Just (coerce (get #id staff)) == selectedStaffId}>
        {renderStaffOptionLabel staffMembers staff maybeOptionState}
    </option>
|]

renderStaffOptionLabel :: [Staff] -> Staff -> Maybe RosterAssignmentOptionState -> Text
renderStaffOptionLabel staffMembers staff maybeOptionState =
    case maybeOptionState of
        Nothing -> baseLabel
        Just _  -> baseLabel
    where
        baseLabel = staffDisplayName staffMembers staff

renderRosterShiftTypeOption :: Maybe UUID -> ShiftType -> Html
renderRosterShiftTypeOption selectedShiftTypeId shiftType = [hsx|
    <option value={tshow (get #id shiftType)} selected={Just (coerce (get #id shiftType)) == selectedShiftTypeId}>
        {renderShiftTypeOptionLabel shiftType}
    </option>
|]

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
shiftTypeBadgeColourKey maybeShiftType =
    fromMaybe "default" (fmap (.colourKey) maybeShiftType)

shiftTypeBadgeLabel :: Maybe UUID -> Maybe ShiftType -> Text
shiftTypeBadgeLabel staffId maybeShiftType =
    fromMaybe (if isJust staffId then "Type required" else "Type") (renderShiftTypeOptionLabel <$> maybeShiftType)

renderEditableDayColumnShiftTypeBadge :: RosterSlotCellTarget -> Maybe UUID -> Maybe UUID -> Maybe ShiftType -> [ShiftType] -> Html
renderEditableDayColumnShiftTypeBadge target staffId selectedShiftTypeId selectedShiftType shiftTypes = [hsx|
    <form class={classes [("m-0 slot-cell-form roster-shift-type-badge roster-shift-type-badge-editable", True), ("is-empty", isNothing selectedShiftTypeId), ("is-required", isJust staffId && isNothing selectedShiftTypeId)]}
          data-roster-shift-colour={shiftTypeBadgeColourKey selectedShiftType}>
        <select name="shiftTypeId"
                class="form-select form-select-sm slot-cell-input slot-shift-type-input roster-shift-type-badge-select"
                aria-label="Shift type"
                data-roster-field-key={rosterFieldKey target "shiftTypeId"}
                hx-post={rosterSlotTargetAction target}
                hx-trigger="change"
                hx-include="closest form"
                hx-sync={"#" <> rosterWeekShellId <> ":queue last"}
                hx-swap="none">
            <option value="">{shiftTypeBadgeLabel staffId Nothing}</option>
            {forEach visibleShiftTypes (renderRosterShiftTypeOption selectedShiftTypeId)}
        </select>
    </form>
|]
    where
        selectedOrActive shiftType =
            let shiftTypeId = coerce (get #id shiftType)
             in shiftType.isActive || Just shiftTypeId == selectedShiftTypeId
        visibleShiftTypes = filter selectedOrActive shiftTypes

renderReadOnlyDayColumnShiftTypeBadge :: Maybe UUID -> Maybe ShiftType -> Html
renderReadOnlyDayColumnShiftTypeBadge staffId selectedShiftType = [hsx|
    <div class={classes [("slot-cell-static roster-shift-type-badge roster-shift-type-badge-readonly", True), ("is-empty", isNothing selectedShiftType), ("is-required", isJust staffId && isNothing selectedShiftType)]}
         data-roster-shift-colour={shiftTypeBadgeColourKey selectedShiftType}>
        <span class="roster-shift-type-badge-label">{shiftTypeBadgeLabel staffId selectedShiftType}</span>
    </div>
|]

renderEditableTimeCell :: Text -> Text -> Text -> RosterSlotCellTarget -> Text -> Html
renderEditableTimeCell fieldName ariaLabel emptyLabel target currentValue =
    let pickerConfig =
            (defaultTimePickerConfig fieldName currentValue "06:00" "04:45" False)
                { timePickerShowStepButtons = False
                , timePickerEmptyLabel = emptyLabel
                , timePickerFieldClasses = ["m-0", "d-flex", "align-items-center", "slot-cell-form"]
                , timePickerControlClasses = ["roster-time-picker-control"]
                , timePickerTriggerClasses = ["btn-sm", "slot-time-trigger"]
                , timePickerAriaLabel = ariaLabel
                }
        inputHtml = [hsx|
            <input type="hidden"
                   name={fieldName}
                   value={currentValue}
                   class="slot-time-input slot-cell-input js-time-picker-input"
                   data-roster-field-key={rosterFieldKey target fieldName}
                   hx-post={rosterSlotTargetAction target}
                   hx-trigger="change"
                   hx-include="closest form"
                   hx-sync={"#" <> rosterWeekShellId <> ":queue last"}
                   hx-swap="none" />
        |]
    in [hsx|
    <form class="m-0">
        {renderTimePickerFieldWithInput pickerConfig inputHtml}
    </form>
|]

renderEditableStaffCell :: RosterAssignmentFilters -> RosterSlotCellTarget -> Maybe UUID -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Maybe RosterConflict -> Html
renderEditableStaffCell _ target selectedStaffId staffMembers staffOptionStates currentPrimaryConflict = [hsx|
    <form class="m-0 slot-cell-form">
        <select name="staffId"
                class="form-select form-select-sm slot-cell-input slot-staff-input"
                data-roster-field-key={rosterFieldKey target "staffId"}
                hx-post={rosterSlotTargetAction target}
                hx-trigger="change"
                hx-include="closest form"
                hx-sync={"#" <> rosterWeekShellId <> ":queue last"}
                hx-swap="none">
            <option value=""></option>
            {forEach visibleStaffMembers (\staff -> renderStaffOption staffMembers selectedStaffId (optionStateForStaff staff) staff)}
        </select>
    </form>
|]
    where
        selectedOrVisible staff =
            let staffId = coerce (get #id staff)
                isSelected = Just staffId == selectedStaffId
             in isSelected || maybe True (not . (.optionHidden)) (optionStateForStaff staff)
        optionStateForStaff staff =
            case target of
                ExistingRosterSlotTarget rosterSlotId ->
                    Map.lookup (coerce rosterSlotId, coerce (get #id staff)) staffOptionStates
                NewRosterSlotTarget {} ->
                    Nothing
        visibleStaffMembers = filter selectedOrVisible staffMembers

renderEditableShiftTypeCell :: RosterSlotCellTarget -> Maybe UUID -> [ShiftType] -> Html
renderEditableShiftTypeCell target selectedShiftTypeId shiftTypes = [hsx|
    <form class="m-0 slot-cell-form">
        <select name="shiftTypeId"
                class="form-select form-select-sm slot-cell-input slot-shift-type-input"
                data-roster-field-key={rosterFieldKey target "shiftTypeId"}
                hx-post={rosterSlotTargetAction target}
                hx-trigger="change"
                hx-include="closest form"
                hx-sync={"#" <> rosterWeekShellId <> ":queue last"}
                hx-swap="none">
            <option value="">Type</option>
            {forEach visibleShiftTypes (renderRosterShiftTypeOption selectedShiftTypeId)}
        </select>
    </form>
|]
    where
        selectedOrActive shiftType =
            let shiftTypeId = coerce (get #id shiftType)
             in shiftType.isActive || Just shiftTypeId == selectedShiftTypeId
        visibleShiftTypes = filter selectedOrActive shiftTypes

renderReadOnlyStaffCell :: Text -> Maybe RosterConflict -> Html
renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict =
    mconcat
        [ [hsx|<div class="slot-cell-static">{currentStaffLabel}</div>|] ]

rosterSlotTargetAction :: RosterSlotCellTarget -> RosterWeeksController
rosterSlotTargetAction (ExistingRosterSlotTarget rosterSlotId) =
    UpdateRosterSlotAction rosterSlotId
rosterSlotTargetAction (NewRosterSlotTarget rosterDayId rosterWeekSlotDefinitionId rowIndex) =
    CreateRosterSlotAction rosterDayId rosterWeekSlotDefinitionId rowIndex

rosterFieldKey :: RosterSlotCellTarget -> Text -> Text
rosterFieldKey (ExistingRosterSlotTarget rosterSlotId) fieldName =
    tshow rosterSlotId <> ":" <> fieldName
rosterFieldKey (NewRosterSlotTarget rosterDayId rosterWeekSlotDefinitionId rowIndex) fieldName =
    tshow rosterDayId <> ":" <> tshow rosterWeekSlotDefinitionId <> ":" <> tshow rowIndex <> ":" <> fieldName

renderReadOnlyCell :: Text -> Html
renderReadOnlyCell value = [hsx|
    <div class={classes [("slot-cell-static", True), ("app-muted", Text.null value)]}>{if Text.null value then " " else value}</div>
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
