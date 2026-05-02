module Web.View.RosterWeeks.Grid
    ( lastRowIndexForRows
    , renderRosterContentFragment
    , renderRosterContentFragmentOob
    , renderRosterDaySectionFragment
    , renderRosterDaySectionFragmentOob
    , renderRowFragment
    , renderRowOob
    , rowsForDay
    ) where

import Application.Helper.RosterWagePrediction
import Application.Helper.UserPreferences (rosterLayoutModeValue)
import Application.Helper.View (staffDisplayName)
import Data.Coerce (coerce)
import Data.List (find, nub, sort)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import qualified Data.Time.Calendar as Calendar
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.UUID (UUID)
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Types
import Web.View.Prelude
import Web.View.RosterWeeks.Header (renderRosterGridHeader)
import Web.View.RosterWeeks.StaffPanel (renderRosterStaffPanelFragment)

renderRosterContentFragment :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterContentFragment =
    renderRosterContentFragmentWithSwap Nothing

renderRosterContentFragmentOob :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterContentFragmentOob =
    renderRosterContentFragmentWithSwap (Just "outerHTML")

renderRosterContentFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterGridRenderModel -> Html
renderRosterContentFragmentWithSwap maybeSwapOob gridModel = [hsx|
    <div id={rosterContentFragmentId} hx-swap-oob={maybeSwapOob}>
        {renderRosterContent gridModel}
    </div>
|]

renderRosterContent :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterContent =
    renderRosterGrid

renderRosterGrid :: (?context :: ControllerContext) => RosterGridRenderModel -> Html
renderRosterGrid RosterGridRenderModel { gridRosterWeek, gridRosterDays, gridWeekOffset, gridRosterGroups, gridCurrentRosterGroup, gridAssignmentFilters, gridStaffMembers, gridStaffOptionStates, gridPanelStaff, gridSlotNames, gridShiftTypes, gridWeekStartDate, gridAllSlots, gridSlotConflicts, gridRenderIndexes, gridViewCapabilities, gridRosterLayoutMode, gridRosterEndTimesEnabled, gridRosterWagePrediction } =
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
                }
        slotColumnsAreEditable = gridViewCapabilities.canManageRosterColumns
        isDayColumnsLayout = rosterLayoutModeValue gridRosterLayoutMode == "day_columns"
        gridBody =
            if isDayColumnsLayout
                then renderRosterDayColumns dayModel gridRosterDays
                else renderRosterDayRowsGrid gridRosterEndTimesEnabled slotColumnsAreEditable gridRosterWeek gridSlotNames dayModel gridRosterDays
     in [hsx|
    <div class="row g-4 align-items-start roster-layout">
        <div class={classes [("col-12", True), ("col-xl-8", currentUserIsManager), ("col-xxl-9", currentUserIsManager), ("mx-auto", not currentUserIsManager), ("roster-layout-main", currentUserIsManager)]}>
            <div class="app-panel overflow-hidden mb-5 mb-xl-0">
                {renderRosterGridHeader gridRosterWeek gridWeekOffset gridRosterGroups gridCurrentRosterGroup gridAssignmentFilters gridWeekStartDate gridViewCapabilities gridRosterLayoutMode}
                {renderWagePredictionPanel gridRosterWagePrediction}
                <div class="roster-grid-frame"
                     data-roster-layout={rosterLayoutModeValue gridRosterLayoutMode}
                     data-roster-end-times={if gridRosterEndTimesEnabled then ("true" :: Text) else "false"}
                     data-roster-column-editor={if slotColumnsAreEditable then ("available" :: Text) else "unavailable"}
                     style={"--roster-slot-count:" <> tshow (max 1 (length gridSlotNames)) <> ";"}>
                    {gridBody}
                </div>
            </div>
        </div>
        {forEach gridRosterWeek (\rosterWeek -> renderRosterStaffPanelFragment gridWeekOffset (coerce rosterWeek.rosterGroupId) gridPanelStaff)}
    </div>
|]

renderWagePredictionPanel :: (?context :: ControllerContext) => Maybe RosterWagePrediction -> Html
renderWagePredictionPanel Nothing = mempty
renderWagePredictionPanel (Just prediction)
    | not currentUserIsAdmin = mempty
    | otherwise = [hsx|
        <section class="roster-wage-prediction" aria-label="Predicted roster wages">
            <div class="roster-wage-prediction-summary">
                <div>
                    <div class="small text-uppercase fw-semibold app-muted">Predicted wages</div>
                    <div class="roster-wage-prediction-total">{formatMoneyAmount prediction.predictionWeekTotal}</div>
                </div>
                <div class="small app-muted roster-wage-prediction-note">
                    Admin estimate only. Uses rostered start/end, shift type, current pay rules, and a {tshow prediction.predictionBreakMinutes}-minute unpaid break for shifts over 6 hours.
                </div>
            </div>
            <div class="roster-wage-prediction-days">
                {forEach prediction.predictionDays renderWagePredictionDay}
            </div>
            {renderWagePredictionIncompleteNotice prediction}
        </section>
    |]

renderWagePredictionDay :: RosterWagePredictionDay -> Html
renderWagePredictionDay dayPrediction = [hsx|
    <div class="roster-wage-prediction-day">
        <span class="roster-wage-prediction-day-label">{formatDayShort dayPrediction.predictionDayDate}</span>
        <span class="roster-wage-prediction-day-total">{formatMoneyAmount dayPrediction.predictionDayTotal}</span>
    </div>
|]

renderWagePredictionIncompleteNotice :: RosterWagePrediction -> Html
renderWagePredictionIncompleteNotice prediction
    | prediction.predictionIncompleteShiftCount <= 0 = mempty
    | otherwise = [hsx|
        <div class="small text-warning-emphasis roster-wage-prediction-warning">
            {tshow prediction.predictionIncompleteShiftCount} staffed shifts are missing start time, end time, or shift type and are excluded.
        </div>
    |]

formatDayShort :: Day -> Text
formatDayShort day =
    Text.pack (formatTime defaultTimeLocale "%a" day)

renderRosterGridColGroup :: Bool -> [RosterWeekSlotDefinition] -> Html
renderRosterGridColGroup endTimesEnabled slotNames = [hsx|
    <colgroup>
        {forEach slotNames (renderRosterBlockColGroup endTimesEnabled)}
    </colgroup>
|]

renderRosterBlockColGroup :: Bool -> RosterWeekSlotDefinition -> Html
renderRosterBlockColGroup True _ =
    mconcat
        [ [hsx|<col style={("width: var(--roster-time-share);" :: Text)} />|]
        , [hsx|<col style={("width: var(--roster-time-share);" :: Text)} />|]
        , [hsx|<col style={("width: var(--roster-staff-share);" :: Text)} />|]
        , [hsx|<col style={("width: var(--roster-shift-type-share);" :: Text)} />|]
        ]
renderRosterBlockColGroup False _ =
    mconcat
        [ [hsx|<col style={("width: var(--roster-time-share);" :: Text)} />|]
        , [hsx|<col style={("width: var(--roster-staff-share);" :: Text)} />|]
        , [hsx|<col style={("width: var(--roster-note-share);" :: Text)} />|]
        ]

renderRosterDayRowsGrid :: (?context :: ControllerContext) => Bool -> Bool -> Maybe RosterWeek -> [RosterWeekSlotDefinition] -> RosterDayRenderModel -> [RosterDay] -> Html
renderRosterDayRowsGrid endTimesEnabled slotColumnsAreEditable maybeRosterWeek slotNames dayModel rosterDays = [hsx|
    <div class="roster-day-rail" aria-label="Roster days">
        <div class="roster-day-rail-head">
            <span class="roster-day-rail-head-label">Day</span>
            {renderRosterColumnEditDoneButton slotColumnsAreEditable}
        </div>
        <div class="roster-day-rail-body">
            {forEach rosterDays (renderRosterDayRailSection dayModel)}
        </div>
    </div>
    <div class="roster-slots-scroller">
        <table class="table table-bordered table-sm mb-0 align-middle roster-grid roster-slots-grid">
            {renderRosterGridColGroup endTimesEnabled slotNames}
            <thead class="text-center text-uppercase fw-bold roster-grid-head">
                <tr>
                    {forEach (zip [0 :: Int ..] slotNames) (renderSlotHeaderGroup endTimesEnabled maybeRosterWeek slotColumnsAreEditable (length slotNames))}
                </tr>
                <tr>
                    {forEach slotNames (renderSlotSubHeaders endTimesEnabled)}
                </tr>
            </thead>
            <tbody>
                {forEach rosterDays (renderRosterDay dayModel)}
            </tbody>
        </table>
    </div>
|]

rosterWeekIsEditable :: (?context :: ControllerContext) => Maybe RosterWeek -> Bool
rosterWeekIsEditable maybeRosterWeek =
    currentUserIsManager && maybe False (not . (.isLive)) maybeRosterWeek

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
renderSlotHeaderGroup endTimesEnabled _ False _ (_, slotName) = [hsx|
    <th colspan={tshow (slotColumnCount endTimesEnabled)} class="py-2 roster-block-header">{slotName.name}</th>
|]
renderSlotHeaderGroup endTimesEnabled (Just rosterWeek) True slotCount (slotIndex, slotName) = [hsx|
    <th colspan={tshow (slotColumnCount endTimesEnabled)} class="py-2 roster-block-header">
        <div class="d-flex align-items-center justify-content-center gap-2 roster-slot-column-header">
            <span class="roster-slot-column-name-static">{slotName.name}</span>
            <form method="POST"
                  action={UpdateRosterWeekSlotDefinitionAction slotName.id}
                  class="mb-0 roster-slot-column-name-form"
                  data-disable-javascript-submission="true"
                  hx-post={UpdateRosterWeekSlotDefinitionAction slotName.id}
                  hx-trigger="change delay:250ms"
                  hx-target={"#" <> rosterContentFragmentId}
                  hx-swap="none"
                  hx-push-url="false"
                  hx-sync={"#" <> rosterWeekShellId <> ":queue last"}>
                <input id={slotDefinitionInputId slotName.id}
                       type="text"
                       name="name"
                       value={slotName.name}
                       maxlength="120"
                       class="form-control form-control-sm text-center roster-slot-column-name-input"
                       aria-label="Roster column name"
                       data-roster-field-key={rosterSlotDefinitionFieldKey slotName.id}
                       required="required" />
            </form>
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
    </th>
|]
renderSlotHeaderGroup endTimesEnabled _ _ _ (_, slotName) = [hsx|
    <th colspan={tshow (slotColumnCount endTimesEnabled)} class="py-2 roster-block-header">{slotName.name}</th>
|]

slotColumnCount :: Bool -> Int
slotColumnCount True  = 4
slotColumnCount False = 3

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

slotDefinitionInputId :: Id RosterWeekSlotDefinition -> Text
slotDefinitionInputId slotDefinitionId =
    "roster-slot-definition-name-" <> tshow slotDefinitionId

rosterSlotDefinitionFieldKey :: Id RosterWeekSlotDefinition -> Text
rosterSlotDefinitionFieldKey slotDefinitionId =
    "slot-definition:" <> tshow slotDefinitionId <> ":name"

renderSlotSubHeaders :: Bool -> RosterWeekSlotDefinition -> Html
renderSlotSubHeaders True _ =
    mconcat
        [ [hsx|<th class="py-1 roster-subhead roster-col-time">Start</th>|]
        , [hsx|<th class="py-1 roster-subhead roster-col-time">End</th>|]
        , [hsx|<th class="py-1 roster-subhead roster-col-staff">Staff</th>|]
        , [hsx|<th class="py-1 roster-subhead roster-col-shift-type roster-block-end">Type</th>|]
        ]
renderSlotSubHeaders False _ =
    mconcat
        [ [hsx|<th class="py-1 roster-subhead roster-col-time">Time</th>|]
        , [hsx|<th class="py-1 roster-subhead roster-col-staff">Staff</th>|]
        , [hsx|<th class="py-1 roster-subhead roster-col-code roster-block-end">Flag</th>|]
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
    <tbody id={rosterDaySectionDomId rosterDay.id}
           data-roster-day-section="true"
           hx-swap-oob={maybeSwapOob}>
        {renderDayRows dayModel (Calendar.addDays (toInteger (get #dayOffset rosterDay)) dayWeekStartDate) rosterDay dayRows}
    </tbody>
|]
    where
        dayRows = Map.findWithDefault (rowsForDay rosterDay daySlots) (coerce (get #id rosterDay)) dayRenderIndexes.rosterDayRowsByDayId
        daySlots = filter (\s -> s.rosterDayId == coerce (get #id rosterDay)) dayAllSlots

renderRosterDayRailSection :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Html
renderRosterDayRailSection RosterDayRenderModel { dayIsEditable, dayWeekStartDate, dayAllSlots, dayRenderIndexes } rosterDay =
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
                    <div class="roster-day-heading">{renderPrimaryDayLabel date}</div>
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
renderRosterDayColumnWithSwap maybeSwapOob dayModel@RosterDayRenderModel { dayIsEditable, dayWeekStartDate, dayAllSlots, dayRenderIndexes } rosterDay =
    let daySlots = filter (\s -> s.rosterDayId == coerce (get #id rosterDay)) dayAllSlots
        dayRows = Map.findWithDefault (rowsForDay rosterDay daySlots) (coerce (get #id rosterDay)) dayRenderIndexes.rosterDayRowsByDayId
        rowCount = length dayRows
        lastRowIndex = lastRowIndexForRows dayRows
        date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) dayWeekStartDate
        rowModel =
            RosterRowRenderModel
                { rowIsEditable = dayIsEditable
                , rowSlotNames = dayModel.daySlotNames
                , rowAssignmentFilters = dayModel.dayAssignmentFilters
                , rowStaffMembers = dayModel.dayStaffMembers
                , rowStaffOptionStates = dayModel.dayStaffOptionStates
                , rowShiftTypes = dayModel.dayShiftTypes
                , rowDate = date
                , rowRosterDay = rosterDay
                , rowCount
                , rowLastRowIndex = lastRowIndex
                , rowRenderIndexes = dayRenderIndexes
                , rowRosterLayoutMode = dayModel.dayRosterLayoutMode
                , rowRosterEndTimesEnabled = dayModel.dayRosterEndTimesEnabled
                }
     in [hsx|
        <section id={rosterDaySectionDomId rosterDay.id}
                 data-roster-day-section="true"
                 hx-swap-oob={maybeSwapOob}
                 class={classes [("roster-day-column", True), ("day-alt-dark", odd (get #dayOffset rosterDay)), ("day-alt-light", even (get #dayOffset rosterDay))]}>
            <header class="roster-day-column-header">
                <div class="roster-day-heading">{renderPrimaryDayLabel date}</div>
                {renderDayRowControls dayIsEditable rosterDay lastRowIndex}
            </header>
            <div class="roster-day-column-body">
                {forEach (zip [0 :: Int ..] dayRows) (\rowData -> renderDayColumnRow rowModel rowData Nothing)}
            </div>
        </section>
    |]

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
        existingIndices = slots |> map (.rowIndex) |> nub |> sort
        visibleIndices
            | rosterDay.isClosed = [0 .. closedRosterDayRows - 1]
            | otherwise =
                let highestIndex = case existingIndices of
                        [] -> minimumOpenRosterRows - 1
                        _  -> max (minimumOpenRosterRows - 1) (fromMaybe (minimumOpenRosterRows - 1) (last existingIndices))
                 in [0 .. highestIndex]

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
    <tr id={rosterRowDomIdText rowRosterDay.id rowIndex}
        data-roster-row="true"
        hx-swap-oob={maybeSwapOob}
        class={classes [("day-row", True), ("day-row-" <> tshow (get #dayOffset rowRosterDay), True), ("day-alt-dark", odd (get #dayOffset rowRosterDay)), ("day-alt-light", even (get #dayOffset rowRosterDay))]}>
        {forEach (zip [0 :: Int ..] rowSlotNames) (renderBlockCells rowIsEditable rowAssignmentFilters rowStaffMembers rowStaffOptionStates rowShiftTypes rowRosterEndTimesEnabled rowRosterDay rowIndex rowSlots rowRenderIndexes)}
    </tr>
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
renderBlockCells isEditable assignmentFilters staffMembers staffOptionStates shiftTypes endTimesEnabled rosterDay rowIndex rowSlots renderIndexes (blockIndex, slotName)
    | rosterDay.isClosed = renderClosedBlockCells endTimesEnabled blockIndex
    | otherwise =
    case Map.lookup (coerce (get #id rosterDay), rowIndex, coerce (get #id slotName)) renderIndexes.rosterSlotByDayRowSlotName of
        Just slot ->
            let currentStartTime = optionalTimeOfDayToStorageValue slot.startTime
                currentEndTime = optionalTimeOfDayToStorageValue slot.endTime
                currentNote = fromMaybe "" slot.note
                currentPrimaryConflict = primaryConflict (lookupConflicts (get #id slot) renderIndexes)
                currentStaffLabel = fromMaybe "" (renderAssignedStaffLabel slot.staffId renderIndexes)
                currentShiftTypeLabel = fromMaybe "" (renderShiftTypeLabelForSlot shiftTypes slot.shiftTypeId)
             in if endTimesEnabled
                then [hsx|
                <td class={classes [("slot-time-cell", True), ("slot-start-time-cell", True), ("roster-block-start", blockIndex > 0)]}>
                    {if isEditable then renderEditableTimeCell "startTime" "Select roster slot start time" "Start" slot.id currentStartTime else renderReadOnlyCell (renderTimePickerDisplayLabel "Start" currentStartTime)}
                </td>

                <td class="slot-time-cell slot-end-time-cell">
                    {if isEditable then renderEditableTimeCell "endTime" "Select roster slot end time" "End" slot.id currentEndTime else renderReadOnlyCell (renderTimePickerDisplayLabel "End" currentEndTime)}
                </td>

                <td class={classes [("slot-staff-cell position-relative", True), (renderConflictClass currentPrimaryConflict, True)]}
                    title={renderConflictMessage currentPrimaryConflict}
                    data-conflict-message={renderConflictMessage currentPrimaryConflict}>
                    {if isEditable then renderEditableStaffCell assignmentFilters slot.id slot.staffId staffMembers staffOptionStates currentPrimaryConflict else renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict}
                </td>

                <td class="slot-shift-type-cell roster-block-end">
                    {if isEditable then renderEditableShiftTypeCell slot.id slot.shiftTypeId shiftTypes else renderReadOnlyCell currentShiftTypeLabel}
                </td>
            |]
                else [hsx|
                <td class={classes [("slot-time-cell", True), ("roster-block-start", blockIndex > 0)]}>
                    {if isEditable then renderEditableTimeCell "startTime" "Select roster slot time" "Time" slot.id currentStartTime else renderReadOnlyCell (renderTimePickerDisplayLabel "Time" currentStartTime)}
                </td>

                <td class={classes [("slot-staff-cell position-relative", True), (renderConflictClass currentPrimaryConflict, True)]}
                    title={renderConflictMessage currentPrimaryConflict}
                    data-conflict-message={renderConflictMessage currentPrimaryConflict}>
                    {if isEditable then renderEditableStaffCell assignmentFilters slot.id slot.staffId staffMembers staffOptionStates currentPrimaryConflict else renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict}
                </td>

                <td class="slot-note-cell roster-block-end">
                    {if isEditable then renderEditableNoteCell slot.id currentNote else renderReadOnlyCell currentNote}
                </td>
            |]
        Nothing ->
            renderEmptyBlockCells endTimesEnabled blockIndex

renderDayColumnSlotCard :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [ShiftType] -> Bool -> RosterDay -> Int -> [RosterSlot] -> RosterRenderIndexes -> (Int, RosterWeekSlotDefinition) -> Html
renderDayColumnSlotCard isEditable assignmentFilters staffMembers staffOptionStates shiftTypes endTimesEnabled rosterDay rowIndex rowSlots renderIndexes (_, slotName)
    | rosterDay.isClosed = [hsx|<div class="roster-shift-card roster-shift-card-closed"><span>Closed</span></div>|]
    | otherwise =
        case Map.lookup (coerce (get #id rosterDay), rowIndex, coerce (get #id slotName)) renderIndexes.rosterSlotByDayRowSlotName of
            Just slot ->
                let currentStartTime = optionalTimeOfDayToStorageValue slot.startTime
                    currentEndTime = optionalTimeOfDayToStorageValue slot.endTime
                    currentNote = fromMaybe "" slot.note
                    currentPrimaryConflict = primaryConflict (lookupConflicts (get #id slot) renderIndexes)
                    currentStaffLabel = fromMaybe "" (renderAssignedStaffLabel slot.staffId renderIndexes)
                    currentShiftTypeLabel = fromMaybe "" (renderShiftTypeLabelForSlot shiftTypes slot.shiftTypeId)
                    endTimeField =
                        if endTimesEnabled
                            then [hsx|
                                <div class="roster-shift-card-field roster-shift-card-time">
                                    {if isEditable then renderEditableTimeCell "endTime" "Select roster slot end time" "End" slot.id currentEndTime else renderReadOnlyCell (renderTimePickerDisplayLabel "End" currentEndTime)}
                                </div>
                            |]
                            else mempty
                    codeField
                        | endTimesEnabled =
                            if isEditable then renderEditableShiftTypeCell slot.id slot.shiftTypeId shiftTypes else renderReadOnlyCell currentShiftTypeLabel
                        | isEditable = renderEditableNoteCell slot.id currentNote
                        | otherwise = renderReadOnlyCell currentNote
                 in [hsx|
                    <article class={classes [("roster-shift-card", True), (renderConflictClass currentPrimaryConflict, True)]}
                             title={renderConflictMessage currentPrimaryConflict}
                             data-conflict-message={renderConflictMessage currentPrimaryConflict}>
                        <div class="roster-shift-card-title">{slotName.name}</div>
                        <div class={classes [("roster-shift-card-fields", True), ("has-end-times", endTimesEnabled)]}>
                            <div class="roster-shift-card-field roster-shift-card-time">
                                {if isEditable then renderEditableTimeCell "startTime" "Select roster slot start time" "Start" slot.id currentStartTime else renderReadOnlyCell (renderTimePickerDisplayLabel "Start" currentStartTime)}
                            </div>
                            {endTimeField}
                            <div class="roster-shift-card-field roster-shift-card-staff">
                                {if isEditable then renderEditableStaffCell assignmentFilters slot.id slot.staffId staffMembers staffOptionStates currentPrimaryConflict else renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict}
                            </div>
                            <div class="roster-shift-card-field roster-shift-card-code">
                                {codeField}
                            </div>
                        </div>
                    </article>
                |]
            Nothing -> [hsx|<div class="roster-shift-card roster-shift-card-empty"></div>|]

renderEmptyBlockCells :: Bool -> Int -> Html
renderEmptyBlockCells True blockIndex =
    mconcat
        [ [hsx|<td class={classes [("slot-empty-cell", True), ("roster-block-start", blockIndex > 0)]}></td>|]
        , [hsx|<td class="slot-empty-cell"></td>|]
        , [hsx|<td class="slot-empty-cell"></td>|]
        , [hsx|<td class="slot-empty-cell roster-block-end"></td>|]
        ]
renderEmptyBlockCells False blockIndex =
    mconcat
        [ [hsx|<td class={classes [("slot-empty-cell", True), ("roster-block-start", blockIndex > 0)]}></td>|]
        , [hsx|<td class="slot-empty-cell"></td>|]
        , [hsx|<td class="slot-empty-cell roster-block-end"></td>|]
        ]

renderClosedBlockCells :: Bool -> Int -> Html
renderClosedBlockCells True blockIndex =
    mconcat
        [ [hsx|<td class={classes [("slot-closed-cell", True), ("roster-block-start", blockIndex > 0)]}></td>|]
        , [hsx|<td class="slot-closed-cell"></td>|]
        , [hsx|<td class="slot-closed-cell"></td>|]
        , [hsx|<td class="slot-closed-cell roster-block-end"></td>|]
        ]
renderClosedBlockCells False blockIndex =
    mconcat
        [ [hsx|<td class={classes [("slot-closed-cell", True), ("roster-block-start", blockIndex > 0)]}></td>|]
        , [hsx|<td class="slot-closed-cell"></td>|]
        , [hsx|<td class="slot-closed-cell roster-block-end"></td>|]
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

renderShiftTypeLabelForSlot :: [ShiftType] -> Maybe UUID -> Maybe Text
renderShiftTypeLabelForSlot _ Nothing = Nothing
renderShiftTypeLabelForSlot shiftTypes (Just selectedShiftTypeId) =
    renderShiftTypeOptionLabel <$> find (\shiftType -> coerce shiftType.id == selectedShiftTypeId) shiftTypes

renderEditableTimeCell :: Text -> Text -> Text -> Id RosterSlot -> Text -> Html
renderEditableTimeCell fieldName ariaLabel emptyLabel rosterSlotId currentValue =
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
                   data-roster-field-key={rosterFieldKey rosterSlotId fieldName}
                   hx-post={UpdateRosterSlotAction rosterSlotId}
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

renderEditableStaffCell :: RosterAssignmentFilters -> Id RosterSlot -> Maybe UUID -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Maybe RosterConflict -> Html
renderEditableStaffCell _ rosterSlotId selectedStaffId staffMembers staffOptionStates currentPrimaryConflict = [hsx|
    <form class="m-0 slot-cell-form">
        <select name="staffId"
                class="form-select form-select-sm slot-cell-input slot-staff-input"
                data-roster-field-key={rosterFieldKey rosterSlotId "staffId"}
                hx-post={UpdateRosterSlotAction rosterSlotId}
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
            Map.lookup (coerce rosterSlotId, coerce (get #id staff)) staffOptionStates
        visibleStaffMembers = filter selectedOrVisible staffMembers

renderEditableShiftTypeCell :: Id RosterSlot -> Maybe UUID -> [ShiftType] -> Html
renderEditableShiftTypeCell rosterSlotId selectedShiftTypeId shiftTypes = [hsx|
    <form class="m-0 slot-cell-form">
        <select name="shiftTypeId"
                class="form-select form-select-sm slot-cell-input slot-shift-type-input"
                data-roster-field-key={rosterFieldKey rosterSlotId "shiftTypeId"}
                hx-post={UpdateRosterSlotAction rosterSlotId}
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

renderEditableNoteCell :: Id RosterSlot -> Text -> Html
renderEditableNoteCell rosterSlotId currentNote = [hsx|
    <form class="m-0 slot-cell-form">
        <input type="text"
               name="note"
               value={currentNote}
               placeholder=""
               class="form-control form-control-sm slot-note-input slot-cell-input"
               maxlength="2"
               data-roster-field-key={rosterFieldKey rosterSlotId "note"}
               hx-post={UpdateRosterSlotAction rosterSlotId}
               hx-trigger="input changed delay:1200ms"
               hx-include="closest form"
               hx-sync={"#" <> rosterWeekShellId <> ":queue last"}
               hx-swap="none" />
    </form>
|]

rosterFieldKey :: Id RosterSlot -> Text -> Text
rosterFieldKey rosterSlotId fieldName = tshow rosterSlotId <> ":" <> fieldName

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
