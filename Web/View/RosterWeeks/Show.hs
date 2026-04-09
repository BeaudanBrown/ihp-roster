module Web.View.RosterWeeks.Show where

import Application.Helper.LiveUpdate (LiveUpdateScope (..))
import Application.Helper.View (staffDisplayName)
import Data.Coerce (coerce)
import Data.List (find, nub, sort)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes)
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
    , assignmentFilters  :: RosterAssignmentFilters
    , staffMembers       :: [Staff]
    , staffOptionStates  :: Map.Map (UUID, UUID) RosterAssignmentOptionState
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

data RosterAssignmentFilters = RosterAssignmentFilters
    { hideStaffAtIdealShifts      :: Bool
    , hideStaffUnavailable        :: Bool
    , hideStaffOnApprovedLeave    :: Bool
    , hideStaffAlreadyAssignedToday :: Bool
    }

data RosterAssignmentOptionState = RosterAssignmentOptionState
    { optionHidden                :: Bool
    , optionAssignedShiftCount    :: Int
    , optionHiddenByIdeal         :: Bool
    , optionHiddenByUnavailable   :: Bool
    , optionHiddenByLeave         :: Bool
    , optionHiddenByAssignedToday :: Bool
    }

minimumOpenRosterRows :: Int
minimumOpenRosterRows = 2

closedRosterDayRows :: Int
closedRosterDayRows = 3

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
        <div data-live-update-owner="true"
             data-live-update-feature="roster-group-config"
             data-live-updates-path="/live-updates"
             data-live-update-content-url={appendQueryParams (pathTo (ShowRosterWeekContentFragmentAction weekOffset)) [("rosterGroupId", tshow currentRosterGroup.id)]}
             data-live-update-client-enabled={isJust liveUpdateScope}
             data-live-update-client-id=""
             data-live-update-scope-kind={liveUpdateRosterGroupScopeKind <$> liveUpdateScope}
             data-live-update-venue-id={liveUpdateVenueId <$> liveUpdateScope}
             data-live-update-roster-group-id={liveUpdateRosterGroupIdText =<< liveUpdateScope}
             hidden="hidden"></div>
        {renderRosterContentFragment rosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts}
    </section>
|]

renderRosterWeekControls :: (?context :: ControllerContext) => Int -> RosterGroup -> Day -> Html
renderRosterWeekControls weekOffset currentRosterGroup weekStartDate = [hsx|
    <div class="d-flex justify-content-center">
        <div class="btn-group roster-week-nav-group" role="group" aria-label="Roster week navigation">
            {renderWeekNavigationLink "<" (rosterWeekPath (weekOffset - 1) currentRosterGroup.id)}
            {renderWeekDatePickerButton weekOffset currentRosterGroup.id weekStartDate}
            {renderWeekNavigationLink ">" (rosterWeekPath (weekOffset + 1) currentRosterGroup.id)}
        </div>
    </div>
|]

renderWeekDatePickerButton :: Int -> Id RosterGroup -> Day -> Html
renderWeekDatePickerButton weekOffset rosterGroupId weekStartDate = [hsx|
    <form class="mb-0" method="GET" action={pathTo (ShowRosterWeekAction weekOffset)}>
        <input type="hidden" name="rosterGroupId" value={tshow rosterGroupId}/>
        <label class="btn btn-outline-secondary mb-0 position-relative roster-week-nav-button roster-week-date-picker-button">
            <span>{renderRosterWeekRangeLabel weekStartDate}</span>
            <input type="date"
                   name="weekDate"
                   value={Text.pack (formatTime defaultTimeLocale "%Y-%m-%d" weekStartDate)}
                   class="position-absolute top-0 start-0 w-100 h-100 opacity-0 roster-week-date-picker-input"
                   onchange="this.form.requestSubmit()"
                   aria-label="Choose roster week" />
        </label>
    </form>
|]

renderRosterWeekRangeLabel :: Day -> Text
renderRosterWeekRangeLabel weekStartDate =
    let weekEndDate = Calendar.addDays 6 weekStartDate
        formatRangeDate date = Text.pack (formatTime defaultTimeLocale "%d/%m" date)
     in formatRangeDate weekStartDate <> " - " <> formatRangeDate weekEndDate

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
            , partialNavigationClass = "btn btn-outline-secondary roster-week-nav-button"
            , partialNavigationSwap = "outerHTML"
            , partialNavigationSync = Just ("#" <> rosterWeekShellId <> ":replace")
            , partialNavigationPushUrl = True
            }

renderRosterContentFragment :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> Html
renderRosterContentFragment =
    renderRosterContentFragmentWithSwap Nothing

renderRosterContentFragmentOob :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> Html
renderRosterContentFragmentOob =
    renderRosterContentFragmentWithSwap (Just "outerHTML")

renderRosterContentFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> Html
renderRosterContentFragmentWithSwap maybeSwapOob rosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts = [hsx|
    <div id={rosterContentFragmentId} hx-swap-oob={maybeSwapOob}>
        {renderRosterContent rosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts}
    </div>
|]

renderRosterContent :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> Html
renderRosterContent Nothing rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts =
    renderRosterGrid Nothing rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts

renderRosterContent (Just rosterWeek) rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts =
    renderRosterGrid (Just rosterWeek) rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts

renderRosterGrid :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> Html
renderRosterGrid maybeRosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts = [hsx|
    <div class="row g-4 align-items-start roster-layout">
        <div class={classes [("col-12", True), ("col-xl-8", currentUserIsManager), ("col-xxl-9", currentUserIsManager), ("mx-auto", not currentUserIsManager), ("roster-layout-main", currentUserIsManager)]}>
            <div class="card shadow-sm mb-5 mb-xl-0">
                {renderRosterGridHeader maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters weekStartDate}
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
                        {forEach rosterDays (renderRosterDay (rosterWeekIsEditable maybeRosterWeek) slotNames assignmentFilters staffMembers staffOptionStates weekStartDate allSlots slotConflicts)}
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

renderRosterGridHeader :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> Day -> Html
renderRosterGridHeader maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters weekStartDate = [hsx|
    <div class="card-header d-flex justify-content-between align-items-center gap-3 py-3">
        <div class="d-flex flex-wrap gap-2 align-items-center">
            {renderLiveToggle maybeRosterWeek}
        </div>
        <div class="text-center flex-fill">
            {renderRosterWeekControls weekOffset currentRosterGroup weekStartDate}
        </div>
        <div class="d-flex flex-wrap gap-2 align-items-center ms-auto">
            {renderRosterWeekManagerControls weekOffset currentRosterGroup}
            {renderRosterWeekMoreMenu maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters}
        </div>
    </div>
|]

renderLiveToggle :: (?context :: ControllerContext) => Maybe RosterWeek -> Html
renderLiveToggle (Just rosterWeek) = renderLiveToggleForm rosterWeek
renderLiveToggle Nothing           = mempty

renderRosterWeekMoreMenu :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> Html
renderRosterWeekMoreMenu maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters =
    let divider = [hsx|<div class="dropdown-divider my-1"></div>|]
     in [hsx|
    <div class="dropdown">
        <button class="btn btn-outline-secondary"
                type="button"
                id={rosterWeekMoreMenuId maybeRosterWeek currentRosterGroup.id}
                data-bs-toggle="dropdown"
                aria-expanded="false"
                aria-label="Roster actions">
            <i class="bi bi-three-dots-vertical"></i>
        </button>
        <div class="dropdown-menu dropdown-menu-end p-2" aria-labelledby={rosterWeekMoreMenuId maybeRosterWeek currentRosterGroup.id}>
            <div class="px-1 pb-2">
                {renderRosterGroupSwitcher weekOffset rosterGroups currentRosterGroup}
            </div>
            {renderRosterAssignmentFiltersMenuSection weekOffset currentRosterGroup.id assignmentFilters}
            {when (shouldShowRosterWeekMenuDivider maybeRosterWeek) divider}
            {renderSyncSlotStructureButton maybeRosterWeek}
        </div>
    </div>
|]

shouldShowRosterWeekMenuDivider :: (?context :: ControllerContext) => Maybe RosterWeek -> Bool
shouldShowRosterWeekMenuDivider (Just rosterWeek) = currentUserIsManager && not rosterWeek.isLive
shouldShowRosterWeekMenuDivider Nothing = False

renderRosterAssignmentFiltersMenuSection :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterAssignmentFilters -> Html
renderRosterAssignmentFiltersMenuSection weekOffset rosterGroupId filters =
    if currentUserIsManager
        then [hsx|
    <div class="dropdown-divider my-1"></div>
    <form class="px-1 py-1"
          method="POST"
          action={appendQueryParams (pathTo (UpdateRosterAssignmentFiltersAction weekOffset)) [("rosterGroupId", tshow rosterGroupId)]}
          data-disable-javascript-submission="true"
          hx-post={appendQueryParams (pathTo (UpdateRosterAssignmentFiltersAction weekOffset)) [("rosterGroupId", tshow rosterGroupId)]}
          hx-target={"#" <> rosterContentFragmentId}
          hx-swap="outerHTML"
          hx-push-url="false"
          hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
        <div class="small text-uppercase fw-semibold text-body-secondary px-1 pb-2">Hide from dropdowns</div>
        {renderRosterAssignmentFilterToggle "hide-staff-at-ideal" "hideStaffAtIdealShifts" filters.hideStaffAtIdealShifts "At ideal shifts or greater"}
        {renderRosterAssignmentFilterToggle "hide-staff-unavailable" "hideStaffUnavailable" filters.hideStaffUnavailable "Day/date unavailable"}
        {renderRosterAssignmentFilterToggle "hide-staff-on-leave" "hideStaffOnApprovedLeave" filters.hideStaffOnApprovedLeave "Approved leave on this date"}
        {renderRosterAssignmentFilterToggle "hide-staff-assigned-today" "hideStaffAlreadyAssignedToday" filters.hideStaffAlreadyAssignedToday "Already assigned that day"}
    </form>
|]
        else mempty

renderRosterAssignmentFilterToggle :: Text -> Text -> Bool -> Text -> Html
renderRosterAssignmentFilterToggle inputId fieldName isChecked label = [hsx|
    <div class="form-check form-switch mb-2">
        <input type="checkbox"
               id={inputId}
               name={fieldName}
               value="true"
               class="form-check-input"
               checked={isChecked}
               onchange="this.form.requestSubmit()" />
        <label class="form-check-label small" for={inputId}>{label}</label>
    </div>
|]

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
            <div class="roster-staff-panel-header">
                <div>
                    <h2 class="h5 mb-1">Staff</h2>
                    <div class="roster-staff-panel-summary">{tshow (length panelStaff)} active staff</div>
                </div>
            </div>

            <div class="roster-staff-panel-list">
                <table class="roster-staff-table">
                    <thead class="roster-staff-table-head">
                        <tr>
                            <th scope="col" aria-sort="none">
                                <button type="button" class="roster-staff-sort-button" data-roster-staff-sort-key="name">
                                    Name
                                </button>
                            </th>
                            <th scope="col" class="roster-staff-role-head" aria-sort="none">
                                <button type="button" class="roster-staff-sort-button" data-roster-staff-sort-key="role">
                                    Role
                                </button>
                            </th>
                            <th scope="col" class="roster-staff-metric-head" aria-sort="none">
                                <button type="button" class="roster-staff-sort-button roster-staff-sort-button-metric" data-roster-staff-sort-key="shifts">
                                    Shifts
                                </button>
                            </th>
                            <th scope="col" class="roster-staff-action-head">Edit</th>
                        </tr>
                    </thead>
                    <tbody class="roster-staff-table-body">
                        {forEach panelStaff (renderRosterStaffPanelEntry panelStaffMembers weekOffset currentRosterGroupId)}
                    </tbody>
                </table>
            </div>
        </div>
    </div>
|]
    where
        panelStaffMembers = map (.staff) panelStaff

renderRosterStaffPanelEntry :: [Staff] -> Int -> Id RosterGroup -> RosterStaffPanelEntry -> Html
renderRosterStaffPanelEntry panelStaffMembers weekOffset currentRosterGroupId entry =
    let
        staffDisplayLabel = staffDisplayName panelStaffMembers entry.staff
        staffRoleLabel = humanizeStaffRole entry.userRole
     in
        [hsx|
            <tr class="roster-staff-panel-entry"
                data-roster-staff-name={staffDisplayLabel}
                data-roster-staff-role={staffRoleLabel}
                data-roster-staff-assigned={tshow entry.assignedShiftCount}
                data-roster-staff-ideal={tshow entry.staff.idealShiftsPerWeek}>
                <th scope="row" class="roster-staff-cell roster-staff-name">
                    <div class="roster-staff-name-primary">{staffDisplayLabel}</div>
                </th>
                <td class="roster-staff-cell roster-staff-role">{staffRoleLabel}</td>
                <td class="roster-staff-cell roster-staff-shifts">{renderShiftSummary entry}</td>
                <td class="roster-staff-cell roster-staff-action">
                    <button type="button"
                       class="btn btn-sm btn-outline-secondary roster-staff-edit-button"
                       hx-get={appendQueryParams (pathTo (EditStaffAction entry.staff.id)) [("weekOffset", tshow weekOffset), ("rosterGroupId", tshow currentRosterGroupId)]}
                       hx-target={"#" <> htmxModalMountId}
                       hx-swap="innerHTML"
                       hx-push-url="false">
                        Edit
                    </button>
                </td>
            </tr>
        |]

humanizeStaffRole :: Text -> Text
humanizeStaffRole "venue_admin" = "Venue Admin"
humanizeStaffRole "venue_owner" = "Venue Owner"
humanizeStaffRole "manager" = "Manager"
humanizeStaffRole "worker" = "Worker"
humanizeStaffRole other = Text.toTitle (Text.replace "_" " " other)

renderShiftSummary :: RosterStaffPanelEntry -> Html
renderShiftSummary entry = [hsx|
    <span class="roster-staff-shifts-actual">{tshow entry.assignedShiftCount}</span>
    <span class="roster-staff-shifts-ideal">({tshow entry.staff.idealShiftsPerWeek})</span>
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
        , [hsx|<th class="py-1 roster-subhead roster-col-code roster-block-end">Flag</th>|]
        ]

renderRosterDay :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterDay -> Html
renderRosterDay isEditable slotNames assignmentFilters staffMembers staffOptionStates weekStartDate allSlots slotConflicts rosterDay =
    renderRosterDaySectionFragment isEditable slotNames assignmentFilters staffMembers staffOptionStates weekStartDate allSlots slotConflicts rosterDay

renderRosterDaySectionFragment :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterDay -> Html
renderRosterDaySectionFragment =
    renderRosterDaySectionFragmentWithSwap Nothing

renderRosterDaySectionFragmentOob :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterDay -> Html
renderRosterDaySectionFragmentOob =
    renderRosterDaySectionFragmentWithSwap (Just "outerHTML")

renderRosterDaySectionFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterDay -> Html
renderRosterDaySectionFragmentWithSwap maybeSwapOob isEditable slotNames assignmentFilters staffMembers staffOptionStates weekStartDate allSlots slotConflicts rosterDay = [hsx|
    <tbody id={rosterDaySectionDomId rosterDay.id}
           data-roster-day-section="true"
           hx-swap-oob={maybeSwapOob}>
        {renderDayRows isEditable slotNames assignmentFilters staffMembers staffOptionStates (Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate) rosterDay daySlots slotConflicts}
    </tbody>
|]
    where
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

renderDayRows :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> Html
renderDayRows isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay slots slotConflicts = [hsx|
    {forEach indexedRows (renderRow isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex slotConflicts)}
|]
    where
        dayRows = rowsForDay rosterDay slots
        rowCount = length dayRows
        lastRowIndex = lastRowIndexForRows dayRows
        indexedRows = zip [0 :: Int ..] dayRows

renderRow :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> Int -> Int -> [(Id RosterSlot, [RosterConflict])] -> (Int, (Int, [RosterSlot])) -> Html
renderRow isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex slotConflicts rowData =
    renderRowWithAttrs isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex slotConflicts rowData Nothing

renderRowFragment :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> Int -> Int -> [(Id RosterSlot, [RosterConflict])] -> (Int, (Int, [RosterSlot])) -> Html
renderRowFragment = renderRow

renderRowOob :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> Int -> Int -> [(Id RosterSlot, [RosterConflict])] -> (Int, (Int, [RosterSlot])) -> Html
renderRowOob isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex slotConflicts rowData =
    [hsx|<template>{renderRowWithAttrs isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex slotConflicts rowData (Just "outerHTML")}</template>|]

renderRowWithAttrs :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> Int -> Int -> [(Id RosterSlot, [RosterConflict])] -> (Int, (Int, [RosterSlot])) -> Maybe Text -> Html
renderRowWithAttrs isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex slotConflicts (rowPosition, (rowIndex, rowSlots)) maybeSwapOob = [hsx|
    <tr id={rosterRowDomIdText rosterDay.id rowIndex}
        data-roster-row="true"
        hx-swap-oob={maybeSwapOob}
        class={classes [("day-row", True), ("day-row-" <> tshow (get #dayOffset rosterDay), True), ("day-alt-dark", odd (get #dayOffset rosterDay)), ("day-alt-light", even (get #dayOffset rosterDay))]}>
        {renderDayLabel isEditable date rosterDay rowCount rowPosition lastRowIndex}
        {forEach (zip [0 :: Int ..] slotNames) (renderBlockCells isEditable assignmentFilters staffMembers staffOptionStates rosterDay rowIndex rowSlots slotConflicts)}
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

renderBlockCells :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> RosterDay -> Int -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> (Int, SlotName) -> Html
renderBlockCells isEditable assignmentFilters staffMembers staffOptionStates rosterDay rowIndex rowSlots slotConflicts (blockIndex, slotName)
    | rosterDay.isClosed = renderClosedBlockCells blockIndex
    | otherwise =
    case find (\slot -> slot.slotNameId == coerce (get #id slotName)) rowSlots of
        Just slot ->
            let currentStartTime = optionalTimeOfDayToStorageValue slot.startTime
                currentNote = fromMaybe "" slot.note
                currentPrimaryConflict = primaryConflict (lookupConflicts (get #id slot) slotConflicts)
                currentStaffLabel = fromMaybe "" (renderAssignedStaffLabel slot.staffId staffMembers)
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
        Just optionState ->
            let reasonLabels = catMaybes
                    [ if optionState.optionHiddenByIdeal then Just "ideal reached" else Nothing
                    , if optionState.optionHiddenByUnavailable then Just "unavailable" else Nothing
                    , if optionState.optionHiddenByLeave then Just "on leave" else Nothing
                    , if optionState.optionHiddenByAssignedToday then Just "already assigned today" else Nothing
                    ]
             in if null reasonLabels
                    then baseLabel
                    else baseLabel <> " [" <> Text.intercalate ", " reasonLabels <> "]"
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
                , timePickerAriaLabel = "Select schedule slot time"
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
        {renderConflictBadge currentPrimaryConflict}
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

renderAssignedStaffLabel :: Maybe UUID -> [Staff] -> Maybe Text
renderAssignedStaffLabel Nothing _ = Nothing
renderAssignedStaffLabel (Just assignedStaffId) staffMembers =
    (\staff -> staffDisplayName staffMembers staff)
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
          hx-confirm="This will overwrite the current week with the previous week's schedule. Continue?">
        <button type="submit" class="btn btn-outline-primary">Copy Previous Week</button>
    </form>
|]

renderSyncSlotStructureButton :: (?context :: ControllerContext) => Maybe RosterWeek -> Html
renderSyncSlotStructureButton maybeRosterWeek =
    case maybeRosterWeek of
        Just rosterWeek | currentUserIsManager && not rosterWeek.isLive -> [hsx|
            <form method="POST"
                  action={SyncRosterWeekSlotStructureAction rosterWeek.id}
                  data-disable-javascript-submission="true"
                  hx-post={SyncRosterWeekSlotStructureAction rosterWeek.id}
                  hx-target={"#" <> rosterContentFragmentId}
                  hx-swap="outerHTML"
                  hx-push-url="false"
                  hx-sync={"#" <> rosterWeekShellId <> ":replace"}
                  hx-confirm="Sync this draft week to the current slot template? Existing matching slots keep their data; removed slots are dropped and new slots start empty.">
                <button type="submit" class="btn btn-outline-secondary w-100 text-start">Sync Slots</button>
            </form>
        |]
        _ -> mempty

renderLiveToggleForm :: RosterWeek -> Html
renderLiveToggleForm rosterWeek = [hsx|
    <form method="POST"
          action={ToggleRosterWeekLiveStatusAction rosterWeek.id}
          class="form-check form-switch d-flex align-items-center gap-2 mb-0">
        <input type="checkbox"
               id={liveToggleInputId rosterWeek.id}
               name="isLive"
               value="true"
               class="form-check-input mt-0"
               hx-post={ToggleRosterWeekLiveStatusAction rosterWeek.id}
               hx-trigger="change"
               hx-include="closest form"
               hx-target={"#" <> rosterContentFragmentId}
               hx-swap="outerHTML"
               hx-push-url="false"
               hx-sync={"#" <> rosterWeekShellId <> ":replace"}
               checked={rosterWeek.isLive} />
        <label class="form-check-label fw-semibold" for={liveToggleInputId rosterWeek.id}>
            Live
        </label>
    </form>
|]

liveToggleInputId :: Id RosterWeek -> Text
liveToggleInputId rosterWeekId = "roster-live-toggle-" <> tshow rosterWeekId

rosterWeekMoreMenuId :: Maybe RosterWeek -> Id RosterGroup -> Text
rosterWeekMoreMenuId maybeRosterWeek rosterGroupId =
    case maybeRosterWeek of
        Just rosterWeek -> "roster-week-more-menu-" <> tshow rosterWeek.id
        Nothing -> "roster-week-more-menu-group-" <> tshow rosterGroupId

liveUpdateScopeKind :: LiveUpdateScope -> Text
liveUpdateScopeKind RosterWeekScope {}    = "roster_week"
liveUpdateScopeKind RosterGroupConfigScope {} = "roster_group_config"
liveUpdateScopeKind AdminSlotNamesScope {} = "admin_slot_names"
liveUpdateScopeKind AdminInvitesScope {} = "admin_invites"
liveUpdateScopeKind LeaveRequestsScope {} = "leave_requests"
liveUpdateScopeKind TimesheetWeekScope {} = "timesheet_week"

liveUpdateRosterGroupScopeKind :: LiveUpdateScope -> Maybe Text
liveUpdateRosterGroupScopeKind RosterWeekScope {}        = Just "roster_group_config"
liveUpdateRosterGroupScopeKind RosterGroupConfigScope {} = Just "roster_group_config"
liveUpdateRosterGroupScopeKind AdminSlotNamesScope {}    = Nothing
liveUpdateRosterGroupScopeKind AdminInvitesScope {}      = Nothing
liveUpdateRosterGroupScopeKind LeaveRequestsScope {}     = Nothing
liveUpdateRosterGroupScopeKind TimesheetWeekScope {}     = Nothing

liveUpdateVenueId :: LiveUpdateScope -> Text
liveUpdateVenueId RosterWeekScope { venueId }    = tshow venueId
liveUpdateVenueId RosterGroupConfigScope { venueId } = tshow venueId
liveUpdateVenueId AdminSlotNamesScope { venueId } = tshow venueId
liveUpdateVenueId AdminInvitesScope { venueId } = tshow venueId
liveUpdateVenueId LeaveRequestsScope { venueId } = tshow venueId
liveUpdateVenueId TimesheetWeekScope { venueId } = tshow venueId

liveUpdateRosterGroupIdText :: LiveUpdateScope -> Maybe Text
liveUpdateRosterGroupIdText RosterWeekScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText RosterGroupConfigScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText AdminSlotNamesScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText AdminInvitesScope {} = Nothing
liveUpdateRosterGroupIdText LeaveRequestsScope {} = Nothing
liveUpdateRosterGroupIdText TimesheetWeekScope {} = Nothing

liveUpdateWeekOffsetText :: LiveUpdateScope -> Maybe Text
liveUpdateWeekOffsetText RosterWeekScope { weekOffset } = Just (tshow weekOffset)
liveUpdateWeekOffsetText RosterGroupConfigScope {} = Nothing
liveUpdateWeekOffsetText AdminSlotNamesScope {} = Nothing
liveUpdateWeekOffsetText AdminInvitesScope {} = Nothing
liveUpdateWeekOffsetText LeaveRequestsScope {} = Nothing
liveUpdateWeekOffsetText TimesheetWeekScope { weekOffset } = Just (tshow weekOffset)

rosterWeekPath :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Text
rosterWeekPath weekOffset rosterGroupId =
    appendQueryParams (pathTo (ShowRosterWeekAction weekOffset)) [("rosterGroupId", tshow rosterGroupId)]
