module Web.View.RosterWeeks.Header
    ( renderRosterGridHeader
    ) where

import Application.Helper.UserPreferences (rosterLayoutModeLabel,
                                           rosterLayoutModeValue,
                                           rosterLayoutModes)
import Data.Time.Calendar (Day)
import Web.RosterWeeks.Dom (rosterContentFragmentId, rosterWeekShellId)
import Web.RosterWeeks.Paths (rosterAssignmentFiltersUrl, rosterCopyWeekUrl,
                              rosterLayoutPreferenceUrl,
                              rosterShiftTypeHighlightsPreferenceUrl,
                              rosterWeekUrl)
import Web.RosterWeeks.Types (RosterAssignmentFilters (..),
                              RosterViewCapabilities (..))
import Web.View.Prelude
import Web.View.RosterWeeks.Overview (renderWeekOverviewDropdown)

renderRosterGridHeader :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> Day -> RosterViewCapabilities -> RosterLayoutModeEnum -> Bool -> Html
renderRosterGridHeader maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters weekStartDate viewCapabilities rosterLayoutMode showShiftTypeHighlights = [hsx|
    <div class="app-panel-header app-surface-toolbar roster-grid-header">
        <div class="app-surface-toolbar-side roster-grid-header-side roster-grid-header-side-left">
            {renderLiveToggle maybeRosterWeek viewCapabilities}
            {renderThisWeekButton}
        </div>
        <div class="app-surface-toolbar-center roster-grid-header-center">
            {renderRosterWeekControls weekOffset currentRosterGroup weekStartDate}
        </div>
        <div class="app-surface-toolbar-side app-surface-toolbar-side-right roster-grid-header-side roster-grid-header-side-right">
            {renderRosterWeekManagerControls weekOffset currentRosterGroup viewCapabilities}
            {renderRosterWeekMoreMenu maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters viewCapabilities rosterLayoutMode showShiftTypeHighlights}
        </div>
    </div>
|]

renderRosterWeekControls :: (?context :: ControllerContext) => Int -> RosterGroup -> Day -> Html
renderRosterWeekControls weekOffset currentRosterGroup weekStartDate = [hsx|
    <div class="btn-group app-week-nav-group roster-week-nav-group" role="group" aria-label="Roster week navigation">
        {renderWeekNavigationLink "bi-chevron-left" "Previous week" (rosterWeekUrl (weekOffset - 1) currentRosterGroup.id)}
        {renderWeekOverviewDropdown weekOffset currentRosterGroup.id weekStartDate}
        {renderWeekNavigationLink "bi-chevron-right" "Next week" (rosterWeekUrl (weekOffset + 1) currentRosterGroup.id)}
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

renderRosterWeekManagerControls :: (?context :: ControllerContext) => Int -> RosterGroup -> RosterViewCapabilities -> Html
renderRosterWeekManagerControls weekOffset currentRosterGroup viewCapabilities
    | not viewCapabilities.canCopyRosterWeek = mempty
    | otherwise = [hsx|
        <div class="d-flex flex-wrap gap-2 align-items-center" data-roster-week-controls="manager-actions">
            {renderCopyPreviousWeekForm weekOffset currentRosterGroup.id}
        </div>
    |]

renderWeekNavigationLink :: Text -> Text -> Text -> Html
renderWeekNavigationLink iconClass ariaLabel url =
    [hsx|
        <a href={url}
           class="btn btn-outline-secondary app-week-nav-button roster-week-nav-button roster-week-nav-arrow"
           aria-label={ariaLabel}
           title={ariaLabel}
           data-turbolinks="false"
           hx-get={url}
           hx-target={"#" <> rosterWeekShellId}
           hx-swap="outerHTML"
           hx-select={"#" <> rosterWeekShellId}
           hx-push-url="true"
           hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
            <i class={"bi " <> iconClass} aria-hidden="true"></i>
        </a>
    |]

renderLiveToggle :: (?context :: ControllerContext) => Maybe RosterWeek -> RosterViewCapabilities -> Html
renderLiveToggle (Just rosterWeek) viewCapabilities
    | viewCapabilities.canToggleRosterLive = renderLiveToggleForm rosterWeek
renderLiveToggle _ _ = mempty

renderThisWeekButton :: (?context :: ControllerContext) => Html
renderThisWeekButton =
    renderPartialNavigationLink
        PartialNavigationLink
            { partialNavigationLabel = "This week"
            , partialNavigationUrl = pathTo RosterWeeksAction
            , partialNavigationTargetId = rosterWeekShellId
            , partialNavigationSelectId = Just rosterWeekShellId
            , partialNavigationClass = "btn btn-outline-secondary app-week-nav-button"
            , partialNavigationSwap = "outerHTML"
            , partialNavigationSync = Just ("#" <> rosterWeekShellId <> ":replace")
            , partialNavigationPushUrl = True
            }

renderRosterWeekMoreMenu :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> RosterViewCapabilities -> RosterLayoutModeEnum -> Bool -> Html
renderRosterWeekMoreMenu maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters viewCapabilities rosterLayoutMode showShiftTypeHighlights =
    let menuTriggerId = rosterWeekMoreMenuId maybeRosterWeek currentRosterGroup.id
        divider = [hsx|<div class="dropdown-divider my-1"></div>|]
     in [hsx|
    <div class="dropdown">
        <button class="btn btn-outline-secondary"
                type="button"
                id={menuTriggerId}
                data-bs-toggle="dropdown"
                data-bs-auto-close="outside"
                aria-expanded="false"
                aria-label="Roster actions">
            <i class="bi bi-three-dots-vertical"></i>
        </button>
        <div class="dropdown-menu dropdown-menu-end p-2 app-action-menu" aria-labelledby={menuTriggerId}>
            <div class="px-1 pb-2">
                {renderRosterGroupSwitcher weekOffset rosterGroups currentRosterGroup}
            </div>
            <div class="dropdown-divider my-1"></div>
            {renderRosterLayoutMenuSection weekOffset currentRosterGroup.id rosterLayoutMode}
            {renderShiftTypeHighlightsMenuSection weekOffset currentRosterGroup.id showShiftTypeHighlights}
            {renderRosterColumnMenuSection maybeRosterWeek viewCapabilities}
            {renderRosterExportMenuSection viewCapabilities}
            {renderRosterAssignmentFiltersMenuSection weekOffset currentRosterGroup.id menuTriggerId assignmentFilters viewCapabilities}
            {when (shouldShowRosterWeekMenuDivider maybeRosterWeek viewCapabilities) divider}
        </div>
    </div>
|]

renderRosterLayoutMenuSection :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterLayoutModeEnum -> Html
renderRosterLayoutMenuSection weekOffset rosterGroupId selectedLayoutMode = [hsx|
    <form class="px-1 py-1"
          method="POST"
          action={rosterLayoutPreferenceUrl weekOffset rosterGroupId}
          data-disable-javascript-submission="true"
          hx-post={rosterLayoutPreferenceUrl weekOffset rosterGroupId}
          hx-target={"#" <> rosterContentFragmentId}
          hx-swap="outerHTML"
          hx-push-url="false"
          hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
        <div class="small text-uppercase fw-semibold app-muted px-1 pb-2">Roster layout</div>
        <div class="btn-group w-100 roster-layout-mode-group" role="group" aria-label="Roster layout">
            {forEach rosterLayoutModes (renderRosterLayoutModeOption selectedLayoutMode)}
        </div>
    </form>
    <div class="dropdown-divider my-1"></div>
|]

renderShiftTypeHighlightsMenuSection :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Bool -> Html
renderShiftTypeHighlightsMenuSection weekOffset rosterGroupId showShiftTypeHighlights = [hsx|
    <form class="px-1 py-1"
          method="POST"
          action={rosterShiftTypeHighlightsPreferenceUrl weekOffset rosterGroupId}
          data-disable-javascript-submission="true"
          hx-post={rosterShiftTypeHighlightsPreferenceUrl weekOffset rosterGroupId}
          hx-target={"#" <> rosterContentFragmentId}
          hx-swap="outerHTML"
          hx-push-url="false"
          hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
        <input type="hidden"
               id="roster-shift-type-highlights-value"
               name="showShiftTypeHighlights"
               value={if showShiftTypeHighlights then ("true" :: Text) else "false"} />
        <div class="form-check form-switch mb-0 px-1">
            <input type="checkbox"
                   id="roster-shift-type-highlights-toggle"
                   value="true"
                   class="form-check-input ms-0 me-2"
                   checked={showShiftTypeHighlights}
                   onchange="document.getElementById('roster-shift-type-highlights-value').value = this.checked ? 'true' : 'false'; this.form.requestSubmit()" />
            <label class="form-check-label small" for="roster-shift-type-highlights-toggle">Show shift type colours</label>
        </div>
    </form>
    <div class="dropdown-divider my-1"></div>
|]

renderRosterLayoutModeOption :: RosterLayoutModeEnum -> RosterLayoutModeEnum -> Html
renderRosterLayoutModeOption selectedLayoutMode layoutMode =
    let inputId = "roster-layout-mode-" <> rosterLayoutModeValue layoutMode
     in [hsx|
        <input type="radio"
               class="btn-check"
               name="rosterLayoutMode"
               id={inputId}
               value={rosterLayoutModeValue layoutMode}
               checked={rosterLayoutModeValue selectedLayoutMode == rosterLayoutModeValue layoutMode}
               onchange="this.form.requestSubmit()" />
        <label class="btn btn-outline-secondary btn-sm" for={inputId}>{rosterLayoutModeLabel layoutMode}</label>
    |]

renderRosterColumnMenuSection :: (?context :: ControllerContext) => Maybe RosterWeek -> RosterViewCapabilities -> Html
renderRosterColumnMenuSection maybeRosterWeek viewCapabilities
    | not viewCapabilities.canManageRosterColumns = mempty
    | not (shouldShowRosterSortForm maybeRosterWeek) = mempty
    | otherwise = [hsx|
        <div class="px-1 py-1">
            <div class="small text-uppercase fw-semibold app-muted px-1 pb-2">Roster columns</div>
            {renderRosterSortForm maybeRosterWeek}
        </div>
        <div class="dropdown-divider my-1"></div>
|]

shouldShowRosterSortForm :: Maybe RosterWeek -> Bool
shouldShowRosterSortForm (Just rosterWeek) = not rosterWeek.isLive
shouldShowRosterSortForm Nothing = False

renderRosterSortForm :: (?context :: ControllerContext) => Maybe RosterWeek -> Html
renderRosterSortForm (Just rosterWeek)
    | not rosterWeek.isLive = [hsx|
        <form method="POST"
              action={SortRosterWeekAction rosterWeek.id}
              class="mb-0"
              data-disable-javascript-submission="true"
              hx-post={SortRosterWeekAction rosterWeek.id}
              hx-target={"#" <> rosterContentFragmentId}
              hx-swap="none"
              hx-push-url="false"
              hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
            <button type="submit" class="btn btn-outline-secondary btn-sm w-100 text-start">
                <i class="bi bi-sort-down me-1" aria-hidden="true"></i>
                Sort shifts
            </button>
        </form>
    |]
renderRosterSortForm _ = mempty

renderRosterExportMenuSection :: RosterViewCapabilities -> Html
renderRosterExportMenuSection viewCapabilities
    | not viewCapabilities.canExportRosterImage = mempty
    | otherwise = [hsx|
        <div class="px-1 py-1">
            <div class="small text-uppercase fw-semibold app-muted px-1 pb-2">Share roster</div>
            <div class="d-grid gap-2">
                {renderRosterExportButton "jpg" "Export JPG"}
            </div>
        </div>
    |]

renderRosterExportButton :: Text -> Text -> Html
renderRosterExportButton format label = [hsx|
    <button type="button"
            class="btn btn-outline-secondary w-100 text-start roster-export-button"
            data-roster-export-format={format}>
        {label}
    </button>
|]

shouldShowRosterWeekMenuDivider :: Maybe RosterWeek -> RosterViewCapabilities -> Bool
shouldShowRosterWeekMenuDivider (Just rosterWeek) viewCapabilities =
    not rosterWeek.isLive && viewCapabilities.canManageAssignmentFilter
shouldShowRosterWeekMenuDivider Nothing _ = False

renderRosterAssignmentFiltersMenuSection :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Text -> RosterAssignmentFilters -> RosterViewCapabilities -> Html
renderRosterAssignmentFiltersMenuSection weekOffset rosterGroupId menuTriggerId filters viewCapabilities =
    if viewCapabilities.canManageAssignmentFilter
        then [hsx|
    <div class="dropdown-divider my-1"></div>
    <form class="px-1 py-1"
          method="POST"
          action={rosterAssignmentFiltersUrl weekOffset rosterGroupId}
          data-roster-filter-form="true"
          data-roster-filter-menu-trigger-id={menuTriggerId}
          data-disable-javascript-submission="true"
          hx-post={rosterAssignmentFiltersUrl weekOffset rosterGroupId}
          hx-target={"#" <> rosterContentFragmentId}
          hx-swap="outerHTML"
          hx-push-url="false"
          hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
        <div class="small text-uppercase fw-semibold app-muted px-1 pb-2">Hide from dropdowns</div>
        <div class="roster-assignment-filter-grid">
            {renderRosterAssignmentFilterToggle "hide-staff-at-ideal" "hideStaffAtIdealShifts" filters.hideStaffAtIdealShifts "At ideal shifts or greater"}
            {renderRosterAssignmentFilterToggle "hide-staff-unavailable" "hideStaffUnavailable" filters.hideStaffUnavailable "No preferred shifts that day"}
            {renderRosterAssignmentFilterToggle "hide-staff-on-leave" "hideStaffOnApprovedLeave" filters.hideStaffOnApprovedLeave "Approved unavailable period on this date"}
            {renderRosterAssignmentFilterToggle "hide-staff-assigned-today" "hideStaffAlreadyAssignedToday" filters.hideStaffAlreadyAssignedToday "Already assigned that day"}
        </div>
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

renderCopyPreviousWeekForm :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Html
renderCopyPreviousWeekForm weekOffset rosterGroupId = [hsx|
    <form method="POST"
          action={rosterCopyWeekUrl (weekOffset - 1) weekOffset rosterGroupId}
          data-disable-javascript-submission="true"
          hx-post={rosterCopyWeekUrl (weekOffset - 1) weekOffset rosterGroupId}
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
        Nothing         -> "roster-week-more-menu-group-" <> tshow rosterGroupId
