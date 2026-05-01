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

import Application.Helper.View (staffDisplayName)
import Data.Coerce (coerce)
import Data.List (nub, sort)
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
renderRosterGrid RosterGridRenderModel { gridRosterWeek, gridRosterDays, gridWeekOffset, gridRosterGroups, gridCurrentRosterGroup, gridAssignmentFilters, gridStaffMembers, gridStaffOptionStates, gridPanelStaff, gridSlotNames, gridWeekStartDate, gridAllSlots, gridSlotConflicts, gridRenderIndexes, gridViewCapabilities } =
    let dayModel =
            RosterDayRenderModel
                { dayIsEditable = rosterWeekIsEditable gridRosterWeek
                , daySlotNames = gridSlotNames
                , dayAssignmentFilters = gridAssignmentFilters
                , dayStaffMembers = gridStaffMembers
                , dayStaffOptionStates = gridStaffOptionStates
                , dayWeekStartDate = gridWeekStartDate
                , dayAllSlots = gridAllSlots
                , daySlotConflicts = gridSlotConflicts
                , dayRenderIndexes = gridRenderIndexes
                }
        slotColumnsAreEditable = rosterWeekIsEditable gridRosterWeek
     in [hsx|
    <div class="row g-4 align-items-start roster-layout">
        <div class={classes [("col-12", True), ("col-xl-8", currentUserIsManager), ("col-xxl-9", currentUserIsManager), ("mx-auto", not currentUserIsManager), ("roster-layout-main", currentUserIsManager)]}>
            <div class="app-panel overflow-hidden mb-5 mb-xl-0">
                {renderRosterGridHeader gridRosterWeek gridWeekOffset gridRosterGroups gridCurrentRosterGroup gridAssignmentFilters gridWeekStartDate gridViewCapabilities}
                <div class="roster-grid-frame"
                     style={"--roster-slot-count:" <> tshow (max 1 (length gridSlotNames)) <> ";"}>
                    <div class="roster-day-rail" aria-label="Roster days">
                        <div class="roster-day-rail-head">Day</div>
                        <div class="roster-day-rail-body">
                            {forEach gridRosterDays (renderRosterDayRailSection dayModel)}
                        </div>
                    </div>
                    <div class="roster-slots-scroller">
                        {renderSlotColumnToolbar gridRosterWeek slotColumnsAreEditable}
                        <table class="table table-bordered table-sm mb-0 align-middle roster-grid roster-slots-grid">
                            {renderRosterGridColGroup gridSlotNames}
                            <thead class="text-center text-uppercase fw-bold roster-grid-head">
                                <tr>
                                    {forEach gridSlotNames (renderSlotHeaderGroup gridRosterWeek slotColumnsAreEditable (length gridSlotNames))}
                                </tr>
                                <tr>
                                    {forEach gridSlotNames renderSlotSubHeaders}
                                </tr>
                            </thead>
                            <tbody>
                                {forEach gridRosterDays (renderRosterDay dayModel)}
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>
        {forEach gridRosterWeek (\rosterWeek -> renderRosterStaffPanelFragment gridWeekOffset (coerce rosterWeek.rosterGroupId) gridPanelStaff)}
    </div>
|]

renderRosterGridColGroup :: [RosterWeekSlotDefinition] -> Html
renderRosterGridColGroup slotNames = [hsx|
    <colgroup>
        {forEach slotNames renderRosterBlockColGroup}
    </colgroup>
|]

renderRosterBlockColGroup :: RosterWeekSlotDefinition -> Html
renderRosterBlockColGroup _ =
    mconcat
        [ [hsx|<col style={("width: var(--roster-time-share);" :: Text)} />|]
        , [hsx|<col style={("width: var(--roster-staff-share);" :: Text)} />|]
        , [hsx|<col style={("width: var(--roster-note-share);" :: Text)} />|]
        ]

rosterWeekIsEditable :: (?context :: ControllerContext) => Maybe RosterWeek -> Bool
rosterWeekIsEditable maybeRosterWeek =
    currentUserIsManager && maybe False (not . (.isLive)) maybeRosterWeek

renderSlotColumnToolbar :: (?context :: ControllerContext) => Maybe RosterWeek -> Bool -> Html
renderSlotColumnToolbar (Just rosterWeek) True = [hsx|
    <div class="d-flex justify-content-end align-items-center gap-2 px-2 py-2 roster-slot-column-toolbar">
        <form method="POST"
              action={CreateRosterWeekSlotDefinitionAction rosterWeek.id}
              class="d-flex align-items-center gap-2 mb-0"
              data-disable-javascript-submission="true"
              hx-post={CreateRosterWeekSlotDefinitionAction rosterWeek.id}
              hx-target={"#" <> rosterContentFragmentId}
              hx-swap="none"
              hx-push-url="false"
              hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
            <input id={newSlotDefinitionInputId rosterWeek.id}
                   type="text"
                   name="name"
                   maxlength="120"
                   class="form-control form-control-sm roster-slot-column-name-input"
                   aria-label="New column name"
                   placeholder="Column name"
                   required="required" />
            <button type="submit"
                    class="btn btn-sm btn-outline-primary"
                    aria-label="Add roster column"
                    title="Add roster column">
                <i class="bi bi-plus-lg" aria-hidden="true"></i>
            </button>
        </form>
    </div>
|]
renderSlotColumnToolbar _ _ = mempty

renderSlotHeaderGroup :: (?context :: ControllerContext) => Maybe RosterWeek -> Bool -> Int -> RosterWeekSlotDefinition -> Html
renderSlotHeaderGroup _ False _ slotName = [hsx|
    <th colspan="3" class="py-2 roster-block-header">{slotName.name}</th>
|]
renderSlotHeaderGroup (Just _rosterWeek) True slotCount slotName = [hsx|
    <th colspan="3" class="py-2 roster-block-header">
        <div class="d-flex align-items-center justify-content-center gap-2 roster-slot-column-header">
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
                       class="form-control form-control-sm text-center roster-slot-column-name-input slot-cell-input"
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
                  hx-sync={"#" <> rosterWeekShellId <> ":replace"}
                  hx-confirm="Remove this roster column from the draft week? Any assignments in the column will be removed.">
                <input type="hidden" name="_method" value="DELETE" />
                <button type="submit"
                        class="btn btn-sm btn-outline-danger roster-slot-column-delete"
                        aria-label="Remove roster column"
                        title="Remove roster column"
                        disabled={slotCount <= 1}>
                    <i class="bi bi-trash" aria-hidden="true"></i>
                </button>
            </form>
        </div>
    </th>
|]
renderSlotHeaderGroup _ _ _ slotName = [hsx|
    <th colspan="3" class="py-2 roster-block-header">{slotName.name}</th>
|]

newSlotDefinitionInputId :: Id RosterWeek -> Text
newSlotDefinitionInputId rosterWeekId =
    "new-roster-slot-definition-" <> tshow rosterWeekId

slotDefinitionInputId :: Id RosterWeekSlotDefinition -> Text
slotDefinitionInputId slotDefinitionId =
    "roster-slot-definition-name-" <> tshow slotDefinitionId

rosterSlotDefinitionFieldKey :: Id RosterWeekSlotDefinition -> Text
rosterSlotDefinitionFieldKey slotDefinitionId =
    "slot-definition:" <> tshow slotDefinitionId <> ":name"

renderSlotSubHeaders :: RosterWeekSlotDefinition -> Html
renderSlotSubHeaders _ =
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
renderDayRows RosterDayRenderModel { dayIsEditable, daySlotNames, dayAssignmentFilters, dayStaffMembers, dayStaffOptionStates, dayRenderIndexes } date rosterDay dayRows =
    let rowModel =
            RosterRowRenderModel
                { rowIsEditable = dayIsEditable
                , rowSlotNames = daySlotNames
                , rowAssignmentFilters = dayAssignmentFilters
                , rowStaffMembers = dayStaffMembers
                , rowStaffOptionStates = dayStaffOptionStates
                , rowDate = date
                , rowRosterDay = rosterDay
                , rowCount
                , rowLastRowIndex = lastRowIndex
                , rowRenderIndexes = dayRenderIndexes
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
renderRowWithAttrs RosterRowRenderModel { rowIsEditable, rowSlotNames, rowAssignmentFilters, rowStaffMembers, rowStaffOptionStates, rowRosterDay, rowRenderIndexes } (_, (rowIndex, rowSlots)) maybeSwapOob = [hsx|
    <tr id={rosterRowDomIdText rowRosterDay.id rowIndex}
        data-roster-row="true"
        hx-swap-oob={maybeSwapOob}
        class={classes [("day-row", True), ("day-row-" <> tshow (get #dayOffset rowRosterDay), True), ("day-alt-dark", odd (get #dayOffset rowRosterDay)), ("day-alt-light", even (get #dayOffset rowRosterDay))]}>
        {forEach (zip [0 :: Int ..] rowSlotNames) (renderBlockCells rowIsEditable rowAssignmentFilters rowStaffMembers rowStaffOptionStates rowRosterDay rowIndex rowSlots rowRenderIndexes)}
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

renderBlockCells :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> RosterDay -> Int -> [RosterSlot] -> RosterRenderIndexes -> (Int, RosterWeekSlotDefinition) -> Html
renderBlockCells isEditable assignmentFilters staffMembers staffOptionStates rosterDay rowIndex rowSlots renderIndexes (blockIndex, slotName)
    | rosterDay.isClosed = renderClosedBlockCells blockIndex
    | otherwise =
    case Map.lookup (coerce (get #id rosterDay), rowIndex, coerce (get #id slotName)) renderIndexes.rosterSlotByDayRowSlotName of
        Just slot ->
            let currentStartTime = optionalTimeOfDayToStorageValue slot.startTime
                currentNote = fromMaybe "" slot.note
                currentPrimaryConflict = primaryConflict (lookupConflicts (get #id slot) renderIndexes)
                currentStaffLabel = fromMaybe "" (renderAssignedStaffLabel slot.staffId renderIndexes)
             in [hsx|
                <td class={classes [("slot-time-cell", True), ("roster-block-start", blockIndex > 0)]}>
                    {if isEditable then renderEditableTimeCell slot.id currentStartTime else renderReadOnlyCell (renderTimePickerDisplayLabel "Time" currentStartTime)}
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
            mconcat
                [ [hsx|<td class={classes [("slot-empty-cell", True), ("roster-block-start", blockIndex > 0)]}></td>|]
                , [hsx|<td class="slot-empty-cell"></td>|]
                , [hsx|<td class="slot-empty-cell roster-block-end"></td>|]
                ]

renderClosedBlockCells :: Int -> Html
renderClosedBlockCells blockIndex =
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

renderEditableTimeCell :: Id RosterSlot -> Text -> Html
renderEditableTimeCell rosterSlotId currentStartTime =
    let pickerConfig =
            (defaultTimePickerConfig "startTime" currentStartTime "06:00" "23:45" False)
                { timePickerShowStepButtons = False
                , timePickerEmptyLabel = "Time"
                , timePickerFieldClasses = ["m-0", "d-flex", "align-items-center", "slot-cell-form"]
                , timePickerControlClasses = ["roster-time-picker-control"]
                , timePickerTriggerClasses = ["btn-sm", "slot-time-trigger"]
                , timePickerAriaLabel = "Select roster slot time"
                }
        inputHtml = [hsx|
            <input type="hidden"
                   name="startTime"
                   value={currentStartTime}
                   class="slot-time-input slot-cell-input js-time-picker-input"
                   data-roster-field-key={rosterFieldKey rosterSlotId "startTime"}
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
