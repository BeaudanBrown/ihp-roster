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

renderRosterContentFragment :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterViewCapabilities -> Html
renderRosterContentFragment =
    renderRosterContentFragmentWithSwap Nothing

renderRosterContentFragmentOob :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterViewCapabilities -> Html
renderRosterContentFragmentOob =
    renderRosterContentFragmentWithSwap (Just "outerHTML")

renderRosterContentFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterViewCapabilities -> Html
renderRosterContentFragmentWithSwap maybeSwapOob rosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities = [hsx|
    <div id={rosterContentFragmentId} hx-swap-oob={maybeSwapOob}>
        {renderRosterContent rosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities}
    </div>
|]

renderRosterContent :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterViewCapabilities -> Html
renderRosterContent maybeRosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities =
    renderRosterGrid maybeRosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities

renderRosterGrid :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterViewCapabilities -> Html
renderRosterGrid maybeRosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities = [hsx|
    <div class="row g-4 align-items-start roster-layout">
        <div class={classes [("col-12", True), ("col-xl-8", currentUserIsManager), ("col-xxl-9", currentUserIsManager), ("mx-auto", not currentUserIsManager), ("roster-layout-main", currentUserIsManager)]}>
            <div class="app-panel overflow-hidden mb-5 mb-xl-0">
                {renderRosterGridHeader maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters weekStartDate viewCapabilities}
                <div class="table-responsive">
                    <table class="table table-bordered table-sm mb-0 align-middle roster-grid"
                           style={"--roster-slot-count:" <> tshow (max 1 (length slotNames)) <> ";"}>
                        {renderRosterGridColGroup slotNames}
                        <thead class="text-center text-uppercase fw-bold roster-grid-head">
                            <tr>
                                <th rowspan="2" class="py-2 roster-day-column">Day</th>
                                {forEach slotNames renderSlotHeaderGroup}
                            </tr>
                            <tr>
                                {forEach slotNames renderSlotSubHeaders}
                            </tr>
                        </thead>
                        <tbody>
                            {forEach rosterDays (renderRosterDay (rosterWeekIsEditable maybeRosterWeek) slotNames assignmentFilters staffMembers staffOptionStates weekStartDate allSlots slotConflicts renderIndexes)}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
        {forEach maybeRosterWeek (\rosterWeek -> renderRosterStaffPanelFragment weekOffset (coerce rosterWeek.rosterGroupId) panelStaff)}
    </div>
|]

renderRosterGridColGroup :: [SlotName] -> Html
renderRosterGridColGroup slotNames = [hsx|
    <colgroup>
        <col style={("width: var(--roster-day-share);" :: Text)} />
        {forEach slotNames renderRosterBlockColGroup}
    </colgroup>
|]

renderRosterBlockColGroup :: SlotName -> Html
renderRosterBlockColGroup _ =
    mconcat
        [ [hsx|<col style={("width: var(--roster-time-share);" :: Text)} />|]
        , [hsx|<col style={("width: var(--roster-staff-share);" :: Text)} />|]
        , [hsx|<col style={("width: var(--roster-note-share);" :: Text)} />|]
        ]

rosterWeekIsEditable :: (?context :: ControllerContext) => Maybe RosterWeek -> Bool
rosterWeekIsEditable maybeRosterWeek =
    currentUserIsManager && maybe False (not . (.isLive)) maybeRosterWeek

renderSlotHeaderGroup :: SlotName -> Html
renderSlotHeaderGroup slotName = [hsx|
    <th colspan="3" class="py-2 roster-block-header">{slotName.name}</th>
|]

renderSlotSubHeaders :: SlotName -> Html
renderSlotSubHeaders _ =
    mconcat
        [ [hsx|<th class="py-1 roster-subhead roster-col-time">Time</th>|]
        , [hsx|<th class="py-1 roster-subhead roster-col-staff">Staff</th>|]
        , [hsx|<th class="py-1 roster-subhead roster-col-code roster-block-end">Flag</th>|]
        ]

renderRosterDay :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterDay -> Html
renderRosterDay isEditable slotNames assignmentFilters staffMembers staffOptionStates weekStartDate allSlots slotConflicts renderIndexes rosterDay =
    renderRosterDaySectionFragment isEditable slotNames assignmentFilters staffMembers staffOptionStates weekStartDate allSlots slotConflicts renderIndexes rosterDay

renderRosterDaySectionFragment :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterDay -> Html
renderRosterDaySectionFragment =
    renderRosterDaySectionFragmentWithSwap Nothing

renderRosterDaySectionFragmentOob :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterDay -> Html
renderRosterDaySectionFragmentOob =
    renderRosterDaySectionFragmentWithSwap (Just "outerHTML")

renderRosterDaySectionFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterDay -> Html
renderRosterDaySectionFragmentWithSwap maybeSwapOob isEditable slotNames assignmentFilters staffMembers staffOptionStates weekStartDate allSlots slotConflicts renderIndexes rosterDay = [hsx|
    <tbody id={rosterDaySectionDomId rosterDay.id}
           data-roster-day-section="true"
           hx-swap-oob={maybeSwapOob}>
        {renderDayRows isEditable slotNames assignmentFilters staffMembers staffOptionStates (Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate) rosterDay dayRows renderIndexes}
    </tbody>
|]
    where
        dayRows = Map.findWithDefault (rowsForDay rosterDay daySlots) (coerce (get #id rosterDay)) renderIndexes.rosterDayRowsByDayId
        daySlots = filter (\s -> s.rosterDayId == coerce (get #id rosterDay)) allSlots

rowsForDay :: RosterDay -> [RosterSlot] -> [(Int, [RosterSlot])]
rowsForDay rosterDay slots =
    map (\rowIndex -> (rowIndex, filter (\slot -> slot.rowIndex == rowIndex) slots)) visibleIndices
    where
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

renderDayRows :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> [(Int, [RosterSlot])] -> RosterRenderIndexes -> Html
renderDayRows isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay dayRows renderIndexes = [hsx|
    {forEach indexedRows (renderRow isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex renderIndexes)}
|]
    where
        rowCount = length dayRows
        lastRowIndex = lastRowIndexForRows dayRows
        indexedRows = zip [0 :: Int ..] dayRows

renderRow :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> Int -> Int -> RosterRenderIndexes -> (Int, (Int, [RosterSlot])) -> Html
renderRow isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex renderIndexes rowData =
    renderRowWithAttrs isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex renderIndexes rowData Nothing

renderRowFragment :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> Int -> Int -> RosterRenderIndexes -> (Int, (Int, [RosterSlot])) -> Html
renderRowFragment = renderRow

renderRowOob :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> Int -> Int -> RosterRenderIndexes -> (Int, (Int, [RosterSlot])) -> Html
renderRowOob isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex renderIndexes rowData =
    [hsx|<template>{renderRowWithAttrs isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex renderIndexes rowData (Just "outerHTML")}</template>|]

renderRowWithAttrs :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> Int -> Int -> RosterRenderIndexes -> (Int, (Int, [RosterSlot])) -> Maybe Text -> Html
renderRowWithAttrs isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex renderIndexes (rowPosition, (rowIndex, rowSlots)) maybeSwapOob = [hsx|
    <tr id={rosterRowDomIdText rosterDay.id rowIndex}
        data-roster-row="true"
        hx-swap-oob={maybeSwapOob}
        class={classes [("day-row", True), ("day-row-" <> tshow (get #dayOffset rosterDay), True), ("day-alt-dark", odd (get #dayOffset rosterDay)), ("day-alt-light", even (get #dayOffset rosterDay))]}>
        {renderDayLabel isEditable date rosterDay rowCount rowPosition lastRowIndex}
        {forEach (zip [0 :: Int ..] slotNames) (renderBlockCells isEditable assignmentFilters staffMembers staffOptionStates rosterDay rowIndex rowSlots renderIndexes)}
    </tr>
|]

renderDayLabel :: (?context :: ControllerContext) => Bool -> Day -> RosterDay -> Int -> Int -> Int -> Html
renderDayLabel isEditable date rosterDay rowCount rowPosition lastRowIndex
    | rowPosition == 0 = [hsx|
        <td class="fw-bold day-label day-label-stack" rowspan={tshow rowCount}>
            <div class="roster-day-label-stack" style={"--roster-day-label-rows:" <> tshow rowCount}>
                <div class="roster-day-label-row roster-day-label-row-primary">
                    <div class="roster-day-heading">{renderPrimaryDayLabel date}</div>
                </div>
                <div class="roster-day-label-row roster-day-label-row-controls">
                    {renderDayRowControls isEditable rosterDay lastRowIndex}
                </div>
                {renderClosedDayLabel rosterDay}
                {renderEmptyDayLabelRows rowCount (if rosterDay.isClosed then 3 else 2)}
            </div>
        </td>
    |]
    | otherwise = mempty

renderPrimaryDayLabel :: Day -> Html
renderPrimaryDayLabel date = [hsx|
    <div class="roster-day-date">{Text.pack (formatTime defaultTimeLocale "%a" date)} {Text.pack (formatTime defaultTimeLocale "%d/%m" date)}</div>
|]

renderClosedDayLabel :: RosterDay -> Html
renderClosedDayLabel rosterDay
    | rosterDay.isClosed = [hsx|
        <div class="roster-day-label-row roster-day-label-row-closed">
            <div class="roster-day-closed-label">CLOSED</div>
        </div>
    |]
    | otherwise = mempty

renderEmptyDayLabelRows :: Int -> Int -> Html
renderEmptyDayLabelRows rowCount consumedRows =
    mconcat (map (\_ -> [hsx|<div class="roster-day-label-row roster-day-label-row-empty" aria-hidden="true"></div>|]) [consumedRows + 1 .. rowCount])

renderDayRowControls :: (?context :: ControllerContext) => Bool -> RosterDay -> Int -> Html
renderDayRowControls isEditable rosterDay lastRowIndex =
    if isEditable
        then [hsx|
            <span class="roster-day-actions">
                {renderToggleClosedButton rosterDay}
                {when (not rosterDay.isClosed) (renderDeleteLastRowButton rosterDay lastRowIndex)}
                {when (not rosterDay.isClosed) (renderAddRowButton rosterDay)}
            </span>
        |]
        else [hsx|<span class="roster-day-actions-placeholder"></span>|]

renderToggleClosedButton :: (?context :: ControllerContext) => RosterDay -> Html
renderToggleClosedButton rosterDay =
    if currentUserIsManager
        then [hsx|
            <form method="POST"
                  action={ToggleRosterDayClosedAction rosterDay.id}
                  class="d-inline"
                  data-disable-javascript-submission="true"
                  hx-post={ToggleRosterDayClosedAction rosterDay.id}
                  hx-target={"#" <> rosterContentFragmentId}
                  hx-swap="outerHTML"
                  hx-push-url="false"
                  hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
                <button type="submit"
                        class={classes [("btn btn-sm roster-day-action roster-day-action-toggle", True), ("is-active", rosterDay.isClosed)]}
                        data-roster-day-closed-toggle="true"
                        title={if rosterDay.isClosed then ("Reopen day" :: Text) else ("Mark day closed" :: Text)}>
                    {if rosterDay.isClosed then ("open" :: Text) else ("close" :: Text)}
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
                  hx-target={"#" <> rosterContentFragmentId}
                  hx-swap="outerHTML"
                  hx-push-url="false"
                  hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
                <button type="submit"
                        class="btn btn-sm roster-day-action roster-day-action-add"
                        data-roster-day-add="true"
                        title="Add shift row">
                    +
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
                  hx-target={"#" <> rosterContentFragmentId}
                  hx-swap="outerHTML"
                  hx-push-url="false"
                  hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
                <button type="submit"
                        class="btn btn-sm roster-day-action roster-day-action-remove"
                        data-roster-day-remove="true"
                        title={if canDelete then ("Delete last shift row" :: Text) else ("Minimum day size reached" :: Text)}
                        disabled={not canDelete}>
                    -
                </button>
            </form>
        |]
        else [hsx|<span></span>|]

renderBlockCells :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> RosterDay -> Int -> [RosterSlot] -> RosterRenderIndexes -> (Int, SlotName) -> Html
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
    (\staff -> staffDisplayName (Map.elems renderIndexes.rosterStaffById) staff)
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
