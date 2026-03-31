module Web.View.RosterWeeks.Show where

import Application.Helper.LiveUpdate (LiveUpdateScope (..))
import Data.Coerce (coerce)
import Data.List (find, nub, sort)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import qualified Data.Time.Calendar as Calendar
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.UUID (UUID)
import Web.View.Prelude

data ShowView = ShowView
    { rosterWeek         :: Maybe RosterWeek
    , rosterDays         :: [RosterDay]
    , weekOffset         :: Int
    , rosterGroups       :: [RosterGroup]
    , currentRosterGroup :: RosterGroup
    , weekStartDate      :: Day
    , weekEndDate        :: Day
    , staffMembers       :: [Staff]
    , panelStaff         :: [RosterStaffPanelEntry]
    , slotNames          :: [SlotName]
    , allSlots           :: [RosterSlot]
    , slotConflicts      :: [(Id RosterSlot, [RosterConflict])]
    , liveUpdateScope    :: Maybe LiveUpdateScope
    }

data RosterStaffPanelEntry = RosterStaffPanelEntry
    { staff              :: Staff
    , assignedShiftCount :: Int
    , userRole           :: Text
    }

rosterWeekShellId :: Text
rosterWeekShellId = "roster-week-shell"

rosterContentFragmentId :: Text
rosterContentFragmentId = "roster-content"

rosterStaffPanelFragmentId :: Text
rosterStaffPanelFragmentId = "roster-staff-panel-fragment"

rosterDaySectionDomId :: Id RosterDay -> Text
rosterDaySectionDomId rosterDayId = "roster-day-section-" <> tshow rosterDayId

instance View ShowView where
    html = renderRosterWeekShell

renderRosterWeekShell :: ShowView -> Html
renderRosterWeekShell ShowView { .. } = [hsx|
    <section id={rosterWeekShellId}
             hx-history-elt="true"
             data-live-update-owner="true"
             data-live-update-feature="roster"
             data-live-updates-path="/live-updates"
             data-live-update-content-url={appendQueryParams (pathTo (ShowRosterWeekContentFragmentAction weekOffset)) [("rosterGroupId", tshow currentRosterGroup.id)]}
             data-live-update-staff-panel-url={appendQueryParams (pathTo (ShowRosterWeekStaffPanelFragmentAction weekOffset)) [("rosterGroupId", tshow currentRosterGroup.id)]}
             data-live-update-client-enabled={isJust liveUpdateScope}
             data-live-update-client-id=""
             data-live-update-scope-kind={liveUpdateScopeKind <$> liveUpdateScope}
             data-live-update-venue-id={liveUpdateVenueId <$> liveUpdateScope}
             data-live-update-roster-group-id={liveUpdateRosterGroupIdText =<< liveUpdateScope}
             data-live-update-week-offset={liveUpdateWeekOffsetText =<< liveUpdateScope}>
        <div class="d-flex flex-column flex-xl-row justify-content-between align-items-xl-center gap-3 mb-4">
            <div>
                <h1 class="mb-0">Roster Starting {formatDateDisplay weekStartDate}</h1>
                <div class="small app-muted mt-1">Roster group: <span class="fw-semibold">{currentRosterGroup.name}</span></div>
            </div>
            {renderRosterWeekControls weekOffset rosterGroups currentRosterGroup}
        </div>

        {renderRosterContentFragment rosterWeek rosterDays weekOffset rosterGroups currentRosterGroup staffMembers panelStaff slotNames weekStartDate allSlots slotConflicts}
    </section>
|]

renderRosterWeekControls :: (?context :: ControllerContext) => Int -> [RosterGroup] -> RosterGroup -> Html
renderRosterWeekControls weekOffset rosterGroups currentRosterGroup = [hsx|
    <div class="d-flex flex-wrap gap-2 align-items-center justify-content-xl-end">
        <div class="btn-group" role="group" aria-label="Roster week navigation">
            {renderWeekNavigationLink "<" (rosterWeekPath (weekOffset - 1) currentRosterGroup.id)}
            {renderWeekNavigationLink "this week" (appendQueryParams (pathTo RosterWeeksAction) [("rosterGroupId", tshow currentRosterGroup.id)])}
            {renderWeekNavigationLink ">" (rosterWeekPath (weekOffset + 1) currentRosterGroup.id)}
        </div>
        {when currentUserIsManager (renderRosterWeekManagerControls weekOffset currentRosterGroup)}
    </div>
|]

renderRosterGroupSwitcher :: Int -> [RosterGroup] -> RosterGroup -> Html
renderRosterGroupSwitcher weekOffset rosterGroups currentRosterGroup = [hsx|
    <form class="d-flex align-items-center gap-2 mb-0" method="GET" action={pathTo (ShowRosterWeekAction weekOffset)}>
        <label class="visually-hidden" for="roster-group-switch">Roster group</label>
        <input type="hidden" name="weekOffset" value={tshow weekOffset}/>
        <select id="roster-group-switch"
                class="form-select form-select-sm"
                name="rosterGroupId"
                onchange="this.form.submit()">
            {forEach rosterGroups (renderRosterGroupSwitchOption currentRosterGroup.id)}
        </select>
    </form>
|]

renderRosterGroupSwitchOption :: Id RosterGroup -> RosterGroup -> Html
renderRosterGroupSwitchOption selectedRosterGroupId rosterGroup = [hsx|
    <option value={tshow rosterGroup.id} selected={rosterGroup.id == selectedRosterGroupId}>
        {rosterGroup.name}
    </option>
|]

renderRosterWeekManagerControls :: (?context :: ControllerContext) => Int -> RosterGroup -> Html
renderRosterWeekManagerControls weekOffset currentRosterGroup = [hsx|
    <div class="d-flex flex-wrap gap-2 align-items-center" data-roster-week-controls="manager-actions">
        {renderCopyPreviousWeekForm weekOffset currentRosterGroup.id}
    </div>
|]

renderWeekNavigationLink :: Text -> Text -> Html
renderWeekNavigationLink label url =
    renderPartialNavigationLink
        PartialNavigationLink
            { partialNavigationLabel = label
            , partialNavigationUrl = url
            , partialNavigationTargetId = rosterWeekShellId
            , partialNavigationSelectId = Just rosterWeekShellId
            , partialNavigationClass = "btn btn-outline-secondary"
            , partialNavigationSwap = "outerHTML"
            , partialNavigationSync = Just ("#" <> rosterWeekShellId <> ":replace")
            , partialNavigationPushUrl = True
            }

renderRosterContentFragment :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> [Staff] -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> Html
renderRosterContentFragment =
    renderRosterContentFragmentWithSwap Nothing

renderRosterContentFragmentOob :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> [Staff] -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> Html
renderRosterContentFragmentOob =
    renderRosterContentFragmentWithSwap (Just "outerHTML")

renderRosterContentFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> [Staff] -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> Html
renderRosterContentFragmentWithSwap maybeSwapOob rosterWeek rosterDays weekOffset rosterGroups currentRosterGroup staffMembers panelStaff slotNames weekStartDate allSlots slotConflicts = [hsx|
    <div id={rosterContentFragmentId} hx-swap-oob={maybeSwapOob}>
        {renderRosterContent rosterWeek rosterDays weekOffset rosterGroups currentRosterGroup staffMembers panelStaff slotNames weekStartDate allSlots slotConflicts}
    </div>
|]

renderRosterContent :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> [Staff] -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> Html
renderRosterContent Nothing rosterDays weekOffset rosterGroups currentRosterGroup staffMembers panelStaff slotNames weekStartDate allSlots slotConflicts =
    renderRosterGrid Nothing rosterDays weekOffset rosterGroups currentRosterGroup staffMembers panelStaff slotNames weekStartDate allSlots slotConflicts

renderRosterContent (Just rosterWeek) rosterDays weekOffset rosterGroups currentRosterGroup staffMembers panelStaff slotNames weekStartDate allSlots slotConflicts =
    renderRosterGrid (Just rosterWeek) rosterDays weekOffset rosterGroups currentRosterGroup staffMembers panelStaff slotNames weekStartDate allSlots slotConflicts

renderRosterGrid :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> [Staff] -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> Html
renderRosterGrid maybeRosterWeek rosterDays weekOffset rosterGroups currentRosterGroup staffMembers panelStaff slotNames weekStartDate allSlots slotConflicts = [hsx|
    <div class="row g-4 align-items-start roster-layout">
        <div class={classes [("col-12", True), ("col-xl-8", currentUserIsManager), ("col-xxl-9", currentUserIsManager), ("mx-auto", not currentUserIsManager), ("roster-layout-main", currentUserIsManager)]}>
            <div class="card shadow-sm mb-5 mb-xl-0">
                {renderRosterGridHeader maybeRosterWeek weekOffset rosterGroups currentRosterGroup}
                <div class="table-responsive">
                    <table class="table table-bordered table-sm mb-0 align-middle roster-grid">
                        <thead class="text-center text-uppercase fw-bold roster-grid-head">
                            <tr>
                                <th rowspan="2" class="py-2 roster-day-column">Day / Date</th>
                                {forEach slotNames renderSlotHeaderGroup}
                            </tr>
                            <tr>
                                {forEach slotNames renderSlotSubHeaders}
                            </tr>
                        </thead>
                        {forEach rosterDays (renderRosterDay (rosterWeekIsEditable maybeRosterWeek) slotNames staffMembers weekStartDate allSlots slotConflicts)}
                    </table>
                </div>
            </div>
        </div>
        {forEach maybeRosterWeek (\rosterWeek -> renderRosterStaffPanelFragment weekOffset (coerce rosterWeek.rosterGroupId) panelStaff)}
    </div>
|]

renderRosterGridHeader :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> [RosterGroup] -> RosterGroup -> Html
renderRosterGridHeader maybeRosterWeek weekOffset rosterGroups currentRosterGroup = [hsx|
    <div class="card-header d-flex justify-content-between align-items-center gap-3 py-3">
        {renderRosterGroupSwitcher weekOffset rosterGroups currentRosterGroup}
        {renderLiveToggle maybeRosterWeek}
    </div>
|]

renderLiveToggle :: (?context :: ControllerContext) => Maybe RosterWeek -> Html
renderLiveToggle (Just rosterWeek) = renderLiveToggleForm rosterWeek
renderLiveToggle Nothing           = mempty

rosterWeekIsEditable :: (?context :: ControllerContext) => Maybe RosterWeek -> Bool
rosterWeekIsEditable maybeRosterWeek =
    currentUserIsManager && maybe False (not . (.isLive)) maybeRosterWeek

renderRosterStaffPanelFragment :: (?context :: ControllerContext) => Int -> Id RosterGroup -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanelFragment =
    renderRosterStaffPanelFragmentWithSwap Nothing

renderRosterStaffPanelFragmentOob :: (?context :: ControllerContext) => Int -> Id RosterGroup -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanelFragmentOob =
    renderRosterStaffPanelFragmentWithSwap (Just "outerHTML")

renderRosterStaffPanelFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Int -> Id RosterGroup -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanelFragmentWithSwap maybeSwapOob weekOffset currentRosterGroupId panelStaff =
    if currentUserIsManager
        then [hsx|
            <div id={rosterStaffPanelFragmentId}
                 class="col-12 col-xl-4 col-xxl-3 roster-layout-side"
                 hx-swap-oob={maybeSwapOob}>
                {renderRosterStaffPanel weekOffset currentRosterGroupId panelStaff}
            </div>
        |]
        else mempty

renderRosterStaffPanel :: Int -> Id RosterGroup -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanel weekOffset currentRosterGroupId panelStaff = [hsx|
    <div class="app-panel roster-staff-panel">
        <div class="app-panel-body">
            <h2 class="h5 mb-3">Staff</h2>

            <div class="roster-staff-table">
                <div class="roster-staff-table-head">
                    <div>Name</div>
                    <div>Shifts (Ideal)</div>
                    <div class="roster-staff-action-head">Action</div>
                </div>
            </div>

            <div class="roster-staff-panel-list roster-staff-table-body">
                {forEach panelStaff (renderRosterStaffPanelEntry weekOffset currentRosterGroupId)}
            </div>
        </div>
    </div>
|]

renderRosterStaffPanelEntry :: Int -> Id RosterGroup -> RosterStaffPanelEntry -> Html
renderRosterStaffPanelEntry weekOffset currentRosterGroupId entry = [hsx|
    <section class="roster-staff-panel-entry">
        <div class="roster-staff-cell roster-staff-name">
            <span class="roster-staff-name-primary">{entry.staff.firstName} {entry.staff.lastName}</span>
        </div>
        <div class="roster-staff-cell roster-staff-shifts">{renderShiftSummary entry}</div>
        <div class="roster-staff-cell roster-staff-action">
            <button type="button"
               class="btn btn-sm btn-outline-secondary"
               hx-get={appendQueryParams (pathTo (EditStaffAction entry.staff.id)) [("weekOffset", tshow weekOffset), ("rosterGroupId", tshow currentRosterGroupId)]}
               hx-target={"#" <> htmxModalMountId}
               hx-swap="innerHTML"
               hx-push-url="false">
                Edit
            </button>
        </div>
    </section>
|]

renderShiftSummary :: RosterStaffPanelEntry -> Html
renderShiftSummary entry =
    case entry.staff.idealShiftsPerWeek of
        Just shifts -> [hsx|
            <span class="roster-shift-summary-primary">{tshow entry.assignedShiftCount}</span>
            <span class="roster-shift-summary-divider">/</span>
            <span class="roster-shift-summary-secondary">{tshow shifts}</span>
        |]
        Nothing     -> [hsx|
            <span class="roster-shift-summary-primary">{tshow entry.assignedShiftCount}</span>
            <span class="roster-shift-summary-divider">/</span>
            <span class="roster-shift-summary-secondary">-</span>
        |]

renderSlotHeaderGroup :: SlotName -> Html
renderSlotHeaderGroup slotName = [hsx|
    <th colspan="3" class="py-2 roster-block-header">{slotName.name}</th>
|]

renderSlotSubHeaders :: SlotName -> Html
renderSlotSubHeaders _ =
    mconcat
        [ [hsx|<th class="py-1 roster-subhead roster-col-time">Time</th>|]
        , [hsx|<th class="py-1 roster-subhead roster-col-staff">Staff</th>|]
        , [hsx|<th class="py-1 roster-subhead roster-col-code roster-block-end">Note</th>|]
        ]

renderRosterDay :: (?context :: ControllerContext) => Bool -> [SlotName] -> [Staff] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterDay -> Html
renderRosterDay isEditable slotNames staffMembers weekStartDate allSlots slotConflicts rosterDay =
    renderRosterDaySectionFragment isEditable slotNames staffMembers weekStartDate allSlots slotConflicts rosterDay

renderRosterDaySectionFragment :: (?context :: ControllerContext) => Bool -> [SlotName] -> [Staff] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterDay -> Html
renderRosterDaySectionFragment =
    renderRosterDaySectionFragmentWithSwap Nothing

renderRosterDaySectionFragmentOob :: (?context :: ControllerContext) => Bool -> [SlotName] -> [Staff] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterDay -> Html
renderRosterDaySectionFragmentOob =
    renderRosterDaySectionFragmentWithSwap (Just "outerHTML")

renderRosterDaySectionFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Bool -> [SlotName] -> [Staff] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterDay -> Html
renderRosterDaySectionFragmentWithSwap maybeSwapOob isEditable slotNames staffMembers weekStartDate allSlots slotConflicts rosterDay = [hsx|
    <tbody id={rosterDaySectionDomId rosterDay.id}
           data-roster-day-section="true"
           hx-swap-oob={maybeSwapOob}>
        {renderDayRows isEditable slotNames staffMembers (Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate) rosterDay daySlots slotConflicts}
    </tbody>
|]
    where
        daySlots = filter (\s -> s.rosterDayId == coerce (get #id rosterDay)) allSlots

rowsForDay :: [RosterSlot] -> [(Int, [RosterSlot])]
rowsForDay slots =
    case slots |> map (.rowIndex) |> nub |> sort of
        [] -> [(-1, [])]
        indices -> map (\rowIndex -> (rowIndex, filter (\slot -> slot.rowIndex == rowIndex) slots)) indices

lastRowIndexForRows :: [(Int, [RosterSlot])] -> Int
lastRowIndexForRows dayRows = maybe (-1) fst (last dayRows)

renderDayRows :: (?context :: ControllerContext) => Bool -> [SlotName] -> [Staff] -> Day -> RosterDay -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> Html
renderDayRows isEditable slotNames staffMembers date rosterDay slots slotConflicts = [hsx|
    {forEach indexedRows (renderRow isEditable slotNames staffMembers date rosterDay rowCount lastRowIndex slotConflicts)}
|]
    where
        dayRows = rowsForDay slots
        rowCount = length dayRows
        lastRowIndex = lastRowIndexForRows dayRows
        indexedRows = zip [0 :: Int ..] dayRows

renderRow :: (?context :: ControllerContext) => Bool -> [SlotName] -> [Staff] -> Day -> RosterDay -> Int -> Int -> [(Id RosterSlot, [RosterConflict])] -> (Int, (Int, [RosterSlot])) -> Html
renderRow isEditable slotNames staffMembers date rosterDay rowCount lastRowIndex slotConflicts rowData =
    renderRowWithAttrs isEditable slotNames staffMembers date rosterDay rowCount lastRowIndex slotConflicts rowData Nothing

renderRowFragment :: (?context :: ControllerContext) => Bool -> [SlotName] -> [Staff] -> Day -> RosterDay -> Int -> Int -> [(Id RosterSlot, [RosterConflict])] -> (Int, (Int, [RosterSlot])) -> Html
renderRowFragment = renderRow

renderRowOob :: (?context :: ControllerContext) => Bool -> [SlotName] -> [Staff] -> Day -> RosterDay -> Int -> Int -> [(Id RosterSlot, [RosterConflict])] -> (Int, (Int, [RosterSlot])) -> Html
renderRowOob isEditable slotNames staffMembers date rosterDay rowCount lastRowIndex slotConflicts rowData =
    [hsx|<template>{renderRowWithAttrs isEditable slotNames staffMembers date rosterDay rowCount lastRowIndex slotConflicts rowData (Just "outerHTML")}</template>|]

renderRowWithAttrs :: (?context :: ControllerContext) => Bool -> [SlotName] -> [Staff] -> Day -> RosterDay -> Int -> Int -> [(Id RosterSlot, [RosterConflict])] -> (Int, (Int, [RosterSlot])) -> Maybe Text -> Html
renderRowWithAttrs isEditable slotNames staffMembers date rosterDay rowCount lastRowIndex slotConflicts (rowPosition, (rowIndex, rowSlots)) maybeSwapOob = [hsx|
    <tr id={rosterRowDomIdText rosterDay.id rowIndex}
        data-roster-row="true"
        hx-swap-oob={maybeSwapOob}
        class={classes [("day-row", True), ("day-row-" <> tshow (get #dayOffset rosterDay), True), ("day-alt-dark", odd (get #dayOffset rosterDay)), ("day-alt-light", even (get #dayOffset rosterDay))]}>
        {renderDayLabel isEditable date rosterDay rowCount rowPosition lastRowIndex}
        {forEach (zip [0 :: Int ..] slotNames) (renderBlockCells isEditable staffMembers rosterDay.id rowIndex rowSlots slotConflicts)}
    </tr>
|]

rosterRowDomIdText :: Id RosterDay -> Int -> Text
rosterRowDomIdText rosterDayId rowIndex = "roster-row-" <> tshow rosterDayId <> "-" <> tshow rowIndex

renderDayLabel :: (?context :: ControllerContext) => Bool -> Day -> RosterDay -> Int -> Int -> Int -> Html
renderDayLabel isEditable date rosterDay rowCount rowPosition lastRowIndex
    | rowPosition == 0 = [hsx|
        <td class="fw-bold day-label day-label-stack" rowspan={tshow rowCount}>
            <div class="roster-day-label-stack" style={"--roster-day-label-rows:" <> tshow rowCount}>
                <div class="roster-day-label-row roster-day-label-row-primary">
                    <div class="roster-day-heading">
                        <div class="small app-muted">{Text.pack (formatTime defaultTimeLocale "%a" date)}</div>
                        {renderDayRowControls isEditable rosterDay lastRowIndex}
                    </div>
                </div>
                {renderSecondaryDayLabel rowCount date}
                {renderEmptyDayLabelRows rowCount}
            </div>
        </td>
    |]
    | otherwise = mempty

renderSecondaryDayLabel :: Int -> Day -> Html
renderSecondaryDayLabel rowCount date
    | rowCount > 1 = [hsx|
        <div class="roster-day-label-row roster-day-label-row-secondary">
            <div class="roster-day-date">{formatDateDisplay date}</div>
        </div>
    |]
    | otherwise = mempty

renderEmptyDayLabelRows :: Int -> Html
renderEmptyDayLabelRows rowCount =
    mconcat (map (\_ -> [hsx|<div class="roster-day-label-row roster-day-label-row-empty" aria-hidden="true"></div>|]) [3 .. rowCount])

renderDayRowControls :: (?context :: ControllerContext) => Bool -> RosterDay -> Int -> Html
renderDayRowControls isEditable rosterDay lastRowIndex =
    if isEditable
        then [hsx|
            <span class="roster-day-actions">
                {renderDeleteLastRowButton rosterDay lastRowIndex}
                {renderAddRowButton rosterDay}
            </span>
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
renderDeleteLastRowButton _ rowIndex | rowIndex < 0 = [hsx|<span></span>|]
renderDeleteLastRowButton rosterDay _ =
    if currentUserIsManager
        then [hsx|
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
                        title="Delete last shift row">
                    -
                </button>
            </form>
        |]
        else [hsx|<span></span>|]

renderBlockCells :: (?context :: ControllerContext) => Bool -> [Staff] -> Id RosterDay -> Int -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> (Int, SlotName) -> Html
renderBlockCells isEditable staffMembers rosterDayId rowIndex rowSlots slotConflicts (blockIndex, slotName) =
    case find (\slot -> slot.slotNameId == coerce (get #id slotName)) rowSlots of
        Just slot ->
            let currentStartTime = optionalTimeOfDayToStorageValue slot.startTime
                currentStartTimeLabel = if Text.null currentStartTime then "Select time" else storageTimeToDisplayLabel currentStartTime
                currentNote = fromMaybe "" slot.note
                currentPrimaryConflict = primaryConflict (lookupConflicts (get #id slot) slotConflicts)
                currentStaffLabel = fromMaybe "" (renderAssignedStaffLabel slot.staffId staffMembers)
             in [hsx|
                <td class={classes [("slot-time-cell", True), ("roster-block-start", blockIndex > 0)]}>
                    {if isEditable then renderEditableTimeCell slot.id currentStartTime currentStartTimeLabel else renderReadOnlyCell currentStartTimeLabel}
                </td>

                <td class={classes [("slot-staff-cell position-relative", True), (renderConflictClass currentPrimaryConflict, True)]}
                    title={renderConflictMessage currentPrimaryConflict}
                    data-conflict-message={renderConflictMessage currentPrimaryConflict}>
                    {if isEditable then renderEditableStaffCell slot.id slot.staffId staffMembers currentPrimaryConflict else renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict}
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

renderStaffOption :: Maybe UUID -> Staff -> Html
renderStaffOption selectedStaffId staff = [hsx|
    <option value={tshow (get #id staff)} selected={Just (coerce (get #id staff)) == selectedStaffId}>
        {staff.lastName}, {staff.firstName}
    </option>
|]

renderEditableTimeCell :: Id RosterSlot -> Text -> Text -> Html
renderEditableTimeCell rosterSlotId currentStartTime currentStartTimeLabel = [hsx|
    <form class="m-0 d-flex align-items-center gap-1 slot-cell-form" data-time-picker-field="true">
        <input type="hidden"
               name="startTime"
               value={currentStartTime}
               class="slot-time-input slot-cell-input js-time-picker-input"
               hx-post={UpdateRosterSlotAction rosterSlotId}
               hx-trigger="change"
               hx-include="closest form"
               hx-sync={"#" <> rosterWeekShellId <> ":queue last"}
               hx-swap="none" />
        <button type="button"
                class="btn btn-sm slot-time-trigger js-time-picker-trigger">
            <span class={classes [("js-time-picker-label", True), ("app-muted", Text.null currentStartTime)]}>{currentStartTimeLabel}</span>
        </button>
    </form>
|]

renderEditableStaffCell :: Id RosterSlot -> Maybe UUID -> [Staff] -> Maybe RosterConflict -> Html
renderEditableStaffCell rosterSlotId selectedStaffId staffMembers currentPrimaryConflict = [hsx|
    <form class="m-0 slot-cell-form">
        <select name="staffId"
                class="form-select form-select-sm slot-cell-input slot-staff-input"
                hx-post={UpdateRosterSlotAction rosterSlotId}
                hx-trigger="change"
                hx-include="closest form"
                hx-sync={"#" <> rosterWeekShellId <> ":queue last"}
                hx-swap="none">
            <option value=""></option>
            {forEach staffMembers (renderStaffOption selectedStaffId)}
        </select>
        {renderConflictBadge currentPrimaryConflict}
    </form>
|]

renderReadOnlyStaffCell :: Text -> Maybe RosterConflict -> Html
renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict =
    mconcat
        [ [hsx|<div class="slot-cell-static">{currentStaffLabel}</div>|]
        , renderConflictBadge currentPrimaryConflict
        ]

renderEditableNoteCell :: Id RosterSlot -> Text -> Html
renderEditableNoteCell rosterSlotId currentNote = [hsx|
    <form class="m-0 slot-cell-form">
        <input type="text"
               name="note"
               value={currentNote}
               placeholder=""
               class="form-control form-control-sm slot-note-input slot-cell-input"
               hx-post={UpdateRosterSlotAction rosterSlotId}
               hx-trigger="change"
               hx-include="closest form"
               hx-sync={"#" <> rosterWeekShellId <> ":queue last"}
               hx-swap="none" />
    </form>
|]

renderReadOnlyCell :: Text -> Html
renderReadOnlyCell value = [hsx|
    <div class={classes [("slot-cell-static", True), ("app-muted", Text.null value)]}>{if Text.null value then " " else value}</div>
|]

renderAssignedStaffLabel :: Maybe UUID -> [Staff] -> Maybe Text
renderAssignedStaffLabel Nothing _ = Nothing
renderAssignedStaffLabel (Just assignedStaffId) staffMembers =
    (\staff -> staff.lastName <> ", " <> staff.firstName)
        <$> find (\staff -> coerce (get #id staff) == assignedStaffId) staffMembers

lookupConflicts :: Id RosterSlot -> [(Id RosterSlot, [RosterConflict])] -> [RosterConflict]
lookupConflicts slotId slotConflicts = fromMaybe [] (lookup slotId slotConflicts)

renderConflictClass :: Maybe RosterConflict -> Text
renderConflictClass Nothing = ""
renderConflictClass (Just conflict) =
    case conflict.severity of
        CriticalConflict -> "conflict-critical"
        AdvisoryConflict -> "conflict-advisory"

renderConflictMessage :: Maybe RosterConflict -> Text
renderConflictMessage Nothing         = ""
renderConflictMessage (Just conflict) = conflict.message

renderConflictBadge :: Maybe RosterConflict -> Html
renderConflictBadge Nothing = [hsx|<span></span>|]
renderConflictBadge (Just conflict) = [hsx|
    <span class={classes [("badge", True), ("position-absolute", True), ("top-0", True), ("end-0", True), ("translate-middle", True), ("bg-danger", conflict.severity == CriticalConflict), ("bg-warning text-dark", conflict.severity == AdvisoryConflict)]}
          title={conflict.message}>
        !
    </span>
|]

renderCopyPreviousWeekForm :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Html
renderCopyPreviousWeekForm weekOffset rosterGroupId = [hsx|
    <form method="POST"
          action={appendQueryParams (pathTo (CopyRosterWeekAction (weekOffset - 1) weekOffset)) [("rosterGroupId", tshow rosterGroupId)]}
          data-disable-javascript-submission="true"
          hx-post={appendQueryParams (pathTo (CopyRosterWeekAction (weekOffset - 1) weekOffset)) [("rosterGroupId", tshow rosterGroupId)]}
          hx-target={"#" <> rosterContentFragmentId}
          hx-swap="outerHTML"
          hx-push-url="false"
          hx-sync={"#" <> rosterWeekShellId <> ":replace"}
          hx-confirm="This will overwrite the current week with the previous week's roster. Continue?">
        <button type="submit" class="btn btn-outline-primary">Copy Previous Week</button>
    </form>
|]

renderLiveToggleForm :: RosterWeek -> Html
renderLiveToggleForm rosterWeek = [hsx|
    <form method="POST"
          action={ToggleRosterWeekLiveStatusAction rosterWeek.id}
          class="form-check form-switch d-flex align-items-center gap-2 mb-0"
          hx-post={ToggleRosterWeekLiveStatusAction rosterWeek.id}
          hx-trigger="change from:input"
          hx-target={"#" <> rosterContentFragmentId}
          hx-swap="outerHTML"
          hx-push-url="false"
          hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
        <input type="checkbox"
               id={liveToggleInputId rosterWeek.id}
               class="form-check-input mt-0"
               checked={rosterWeek.isLive} />
        <label class="form-check-label fw-semibold" for={liveToggleInputId rosterWeek.id}>
            Live
        </label>
    </form>
|]

liveToggleInputId :: Id RosterWeek -> Text
liveToggleInputId rosterWeekId = "roster-live-toggle-" <> tshow rosterWeekId

liveUpdateScopeKind :: LiveUpdateScope -> Text
liveUpdateScopeKind RosterWeekScope {}    = "roster_week"
liveUpdateScopeKind LeaveRequestsScope {} = "leave_requests"
liveUpdateScopeKind TimesheetWeekScope {} = "timesheet_week"

liveUpdateVenueId :: LiveUpdateScope -> Text
liveUpdateVenueId RosterWeekScope { venueId }    = tshow venueId
liveUpdateVenueId LeaveRequestsScope { venueId } = tshow venueId
liveUpdateVenueId TimesheetWeekScope { venueId } = tshow venueId

liveUpdateRosterGroupIdText :: LiveUpdateScope -> Maybe Text
liveUpdateRosterGroupIdText RosterWeekScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText LeaveRequestsScope {} = Nothing
liveUpdateRosterGroupIdText TimesheetWeekScope {} = Nothing

liveUpdateWeekOffsetText :: LiveUpdateScope -> Maybe Text
liveUpdateWeekOffsetText RosterWeekScope { weekOffset } = Just (tshow weekOffset)
liveUpdateWeekOffsetText LeaveRequestsScope {} = Nothing
liveUpdateWeekOffsetText TimesheetWeekScope { weekOffset } = Just (tshow weekOffset)

rosterWeekPath :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Text
rosterWeekPath weekOffset rosterGroupId =
    appendQueryParams (pathTo (ShowRosterWeekAction weekOffset)) [("rosterGroupId", tshow rosterGroupId)]
