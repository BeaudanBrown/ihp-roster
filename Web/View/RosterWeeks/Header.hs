module Web.View.RosterWeeks.Header
    ( renderRosterGridHeader
    ) where

import Application.Helper.RosterWagePrediction (RosterWagePrediction (..),
                                                 formatMoneyAmount)
import Application.Helper.UserPreferences (rosterLayoutModeLabel,
                                           rosterLayoutModeValue,
                                           rosterLayoutModes)
import Data.Time.Calendar (Day)
import Web.RosterWeeks.Dom (rosterContentFragmentId, rosterWeekShellId)
import Web.RosterWeeks.Paths (rosterAssignmentFiltersUrl, rosterCopyWeekUrl,
                              rosterLayoutPreferenceUrl,
                              rosterWageEstimatePreferenceUrl,
                              rosterWarningPreferenceUrl, rosterWeekUrl)
import Web.RosterWeeks.Types (RosterAssignmentFilters (..),
                              RosterViewCapabilities (..))
import Web.View.Prelude
import Web.View.RosterWeeks.Overview (renderRosterWeekLabel)

renderRosterGridHeader :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> Day -> RosterViewCapabilities -> RosterLayoutModeEnum -> Bool -> Maybe RosterWagePrediction -> Bool -> Bool -> Bool -> Html
renderRosterGridHeader maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters weekStartDate viewCapabilities rosterLayoutMode _rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings canToggleFullscreen =
    renderWeekToolbar WeekToolbarConfig
        { weekToolbarVariant = WeekToolbarRoster
        , weekToolbarAriaLabel = "Roster week controls"
        , weekToolbarExtraClass = "roster-grid-header"
        , weekToolbarPrimary = renderLiveToggle maybeRosterWeek viewCapabilities
        , weekToolbarReset = renderThisWeekButton
        , weekToolbarNavigation = renderRosterWeekControls weekOffset currentRosterGroup weekStartDate
        , weekToolbarSettings = mconcat
            [ when canToggleFullscreen renderRosterFullscreenToggle
            , renderRosterWeekMoreMenu maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters viewCapabilities rosterLayoutMode showWageEstimates showRosterWarnings
            ]
        , weekToolbarAuxiliary = renderRosterWeekWageSummary rosterWagePrediction
        }

renderRosterFullscreenToggle :: Html
renderRosterFullscreenToggle = [hsx|
    <button type="button"
            class="btn btn-outline-secondary btn-sm roster-fullscreen-toggle"
            data-roster-fullscreen-toggle="true"
            aria-pressed="false"
            aria-label="Expand roster"
            title="Expand roster">
        <i class="bi bi-fullscreen" aria-hidden="true"></i>
        <span class="visually-hidden" data-roster-fullscreen-toggle-label="true">Expand roster</span>
    </button>
|]

renderRosterWeekWageSummary :: (?context :: ControllerContext) => Maybe RosterWagePrediction -> Html
renderRosterWeekWageSummary Nothing = mempty
renderRosterWeekWageSummary (Just prediction)
    | not currentUserIsAdmin = mempty
    | otherwise = [hsx|
        <div class="roster-wage-summary" aria-label="Week wages estimate">
            <span class="roster-wage-summary-label">Wages:</span>
            <span class="roster-wage-summary-total">{formatMoneyAmount prediction.predictionWeekTotal}</span>
        </div>
    |]

renderRosterWeekControls :: (?context :: ControllerContext) => Int -> RosterGroup -> Day -> Html
renderRosterWeekControls weekOffset currentRosterGroup weekStartDate = [hsx|
    <div class="btn-group app-week-nav-group roster-week-nav-group" role="group" aria-label="Roster week navigation">
        {renderWeekNavigationLink "bi-chevron-left" "Previous week" (rosterWeekUrl (weekOffset - 1) currentRosterGroup.id)}
        <span class="btn btn-outline-secondary app-week-nav-button app-week-nav-label roster-week-nav-button roster-week-nav-label" aria-current="date">{renderRosterWeekLabel weekStartDate}</span>
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

renderRosterWeekMoreMenu :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> RosterViewCapabilities -> RosterLayoutModeEnum -> Bool -> Bool -> Html
renderRosterWeekMoreMenu maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters viewCapabilities rosterLayoutMode showWageEstimates showRosterWarnings =
    let menuTriggerId = rosterWeekMoreMenuId maybeRosterWeek currentRosterGroup.id
        divider = [hsx|<div class="dropdown-divider my-1"></div>|]
     in [hsx|
    <div class="dropdown" data-roster-week-controls="manager-actions">
        {renderAppSettingsMenuButton menuTriggerId "Roster settings"}
        <div class="dropdown-menu dropdown-menu-end p-2 app-action-menu" aria-labelledby={menuTriggerId}>
            <div class="px-1 pb-2">
                {renderRosterGroupSwitcher weekOffset rosterGroups currentRosterGroup}
            </div>
            <div class="dropdown-divider my-1"></div>
            {renderRosterWeekActionsMenuSection maybeRosterWeek weekOffset currentRosterGroup.id viewCapabilities}
            {renderRosterLayoutMenuSection weekOffset currentRosterGroup.id rosterLayoutMode}
            {renderRosterDisplayPreferencesMenuSection weekOffset currentRosterGroup.id viewCapabilities showWageEstimates showRosterWarnings}
            {renderRosterExportMenuSection maybeRosterWeek viewCapabilities}
            {renderRosterAssignmentFiltersMenuSection weekOffset currentRosterGroup.id menuTriggerId assignmentFilters viewCapabilities}
            {when (shouldShowRosterWeekMenuDivider maybeRosterWeek viewCapabilities) divider}
        </div>
    </div>
|]

renderRosterWeekActionsMenuSection :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> Id RosterGroup -> RosterViewCapabilities -> Html
renderRosterWeekActionsMenuSection maybeRosterWeek weekOffset rosterGroupId viewCapabilities
    | not (viewCapabilities.canCopyRosterWeek || shouldShowRosterSortForm maybeRosterWeek viewCapabilities) = mempty
    | otherwise = [hsx|
        <div class="px-1 py-1">
            <div class="small text-uppercase fw-semibold app-muted px-1 pb-2">Week actions</div>
            <div class="roster-week-action-grid">
                {renderRosterSortForm maybeRosterWeek viewCapabilities}
                {when viewCapabilities.canCopyRosterWeek (renderCopyPreviousWeekForm weekOffset rosterGroupId)}
            </div>
        </div>
        <div class="dropdown-divider my-1"></div>
    |]

renderRosterLayoutMenuSection :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterLayoutModeEnum -> Html
renderRosterLayoutMenuSection weekOffset rosterGroupId selectedLayoutMode = [hsx|
    <form class="px-1 py-1"
          method="POST"
          action={rosterLayoutPreferenceUrl weekOffset rosterGroupId}
          data-disable-javascript-submission="true"
          hx-post={rosterLayoutPreferenceUrl weekOffset rosterGroupId}
          hx-swap="none settle:0ms"
          hx-push-url="false"
          hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
        <div class="small text-uppercase fw-semibold app-muted px-1 pb-2">Roster layout</div>
        <div class="btn-group w-100 roster-layout-mode-group" role="group" aria-label="Roster layout">
            {forEach rosterLayoutModes (renderRosterLayoutModeOption selectedLayoutMode)}
        </div>
    </form>
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

renderRosterDisplayPreferencesMenuSection :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterViewCapabilities -> Bool -> Bool -> Html
renderRosterDisplayPreferencesMenuSection weekOffset rosterGroupId viewCapabilities showWageEstimates showRosterWarnings = [hsx|
    <div class="row g-2 px-1 pb-1">
        {when viewCapabilities.canManageRosterWarnings (renderRosterWarningPreferenceForm weekOffset rosterGroupId showRosterWarnings)}
        {renderRosterWageEstimatePreferenceForm weekOffset rosterGroupId viewCapabilities showWageEstimates}
    </div>
|]

renderRosterWarningPreferenceForm :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Bool -> Html
renderRosterWarningPreferenceForm weekOffset rosterGroupId showRosterWarnings = [hsx|
    <form class="col-6 mb-0"
          method="POST"
          action={rosterWarningPreferenceUrl weekOffset rosterGroupId}
          data-disable-javascript-submission="true"
          hx-post={rosterWarningPreferenceUrl weekOffset rosterGroupId}
          hx-swap="none"
          hx-push-url="false"
          hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
        <div class="roster-display-toggle">
            {renderRosterWarningToggle showRosterWarnings}
        </div>
    </form>
|]

renderRosterWageEstimatePreferenceForm :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterViewCapabilities -> Bool -> Html
renderRosterWageEstimatePreferenceForm weekOffset rosterGroupId viewCapabilities showWageEstimates
    | not viewCapabilities.canViewWageEstimates = mempty
    | otherwise = [hsx|
        <form class="col-6 mb-0"
              method="POST"
              action={rosterWageEstimatePreferenceUrl weekOffset rosterGroupId}
              data-disable-javascript-submission="true"
              hx-post={rosterWageEstimatePreferenceUrl weekOffset rosterGroupId}
              hx-swap="none"
              hx-push-url="false"
              hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
            <div class="roster-display-toggle">
                {renderRosterWageEstimateToggle showWageEstimates}
            </div>
        </form>
|]

renderRosterWarningToggle :: Bool -> Html
renderRosterWarningToggle showRosterWarnings =
    renderAppToggleButton $ (defaultAppToggleButtonConfig "show-roster-warnings" showRosterWarnings [hsx|<span class="small">{if showRosterWarnings then ("Warnings enabled" :: Text) else "Warnings disabled"}</span>|])
        { appToggleInputName = Just "showRosterWarnings"
        , appToggleInputValue = "true"
        , appToggleButtonClass = "btn-sm w-100 justify-content-start"
        , appToggleOnChange = Just "this.form.requestSubmit()"
        }

renderRosterWageEstimateToggle :: Bool -> Html
renderRosterWageEstimateToggle showWageEstimates =
    renderAppToggleButton $ (defaultAppToggleButtonConfig "show-wage-estimates" showWageEstimates [hsx|<span class="small">{if showWageEstimates then ("Wages enabled" :: Text) else "Wages disabled"}</span>|])
        { appToggleInputName = Just "showWageEstimates"
        , appToggleInputValue = "true"
        , appToggleButtonClass = "btn-sm w-100 justify-content-start"
        , appToggleOnChange = Just "this.form.requestSubmit()"
        }

shouldShowRosterSortForm :: Maybe RosterWeek -> RosterViewCapabilities -> Bool
shouldShowRosterSortForm (Just rosterWeek) viewCapabilities = viewCapabilities.canManageRosterColumns && not rosterWeek.isLive
shouldShowRosterSortForm Nothing _ = False

renderRosterSortForm :: (?context :: ControllerContext) => Maybe RosterWeek -> RosterViewCapabilities -> Html
renderRosterSortForm (Just rosterWeek) viewCapabilities
    | shouldShowRosterSortForm (Just rosterWeek) viewCapabilities = [hsx|
        <form method="POST"
              action={SortRosterWeekAction rosterWeek.id}
              class="mb-0 roster-week-action-form"
              data-disable-javascript-submission="true"
              hx-post={SortRosterWeekAction rosterWeek.id}
              hx-target={"#" <> rosterContentFragmentId}
              hx-swap="none"
              hx-push-url="false"
              hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
            <button type="submit" class="btn btn-outline-secondary btn-sm w-100 h-100 text-center">
                <i class="bi bi-sort-down me-1" aria-hidden="true"></i>
                Sort shifts
            </button>
        </form>
    |]
renderRosterSortForm _ _ = mempty

renderRosterExportMenuSection :: Maybe RosterWeek -> RosterViewCapabilities -> Html
renderRosterExportMenuSection maybeRosterWeek viewCapabilities
    | not viewCapabilities.canExportRosterImage = mempty
    | not (maybe False (.isLive) maybeRosterWeek) = mempty
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
    <form class="px-1 py-1"
          method="POST"
          action={rosterAssignmentFiltersUrl weekOffset rosterGroupId}
          data-roster-filter-form="true"
          data-roster-filter-menu-trigger-id={menuTriggerId}
          data-disable-javascript-submission="true"
          hx-post={rosterAssignmentFiltersUrl weekOffset rosterGroupId}
          hx-swap="none"
          hx-push-url="false"
          hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
        <div class="small text-uppercase fw-semibold app-muted px-1 pb-2">Enforce prevention</div>
        <div class="roster-assignment-filter-grid">
            {renderRosterAssignmentFilterToggle "hide-staff-at-ideal" "hideStaffAtIdealShifts" filters.hideStaffAtIdealShifts "Too many shifts"}
            {renderRosterAssignmentFilterToggle "hide-staff-unavailable" "hideStaffUnavailable" filters.hideStaffUnavailable "Regular day off"}
            {renderRosterAssignmentFilterToggle "hide-staff-on-leave" "hideStaffOnApprovedLeave" filters.hideStaffOnApprovedLeave "Unavailable"}
            {renderRosterAssignmentFilterToggle "hide-staff-assigned-today" "hideStaffAlreadyAssignedToday" filters.hideStaffAlreadyAssignedToday "Double shifts"}
        </div>
    </form>
|]
        else mempty

renderRosterAssignmentFilterToggle :: Text -> Text -> Bool -> Text -> Html
renderRosterAssignmentFilterToggle inputId fieldName isChecked label = [hsx|
    <div class="mb-2">
        {renderRosterAssignmentFilterToggleButton inputId fieldName isChecked label}
    </div>
|]

renderRosterAssignmentFilterToggleButton :: Text -> Text -> Bool -> Text -> Html
renderRosterAssignmentFilterToggleButton inputId fieldName isChecked label =
    renderAppToggleButton $ (defaultAppToggleButtonConfig inputId isChecked [hsx|<span class="small">{label}</span>|])
        { appToggleInputName = Just fieldName
        , appToggleInputValue = "true"
        , appToggleButtonClass = "btn-sm w-100 justify-content-start text-start"
        , appToggleOnChange = Just "this.form.requestSubmit()"
        }

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
          hx-confirm="This will overwrite the current week with the previous week's roster. Continue?"
          class="mb-0 roster-week-action-form">
        <button type="submit" class="btn btn-outline-primary btn-sm w-100 h-100 text-center">
            <i class="bi bi-copy me-1" aria-hidden="true"></i>
            Copy Previous Week
        </button>
    </form>
|]

renderLiveToggleForm :: RosterWeek -> Html
renderLiveToggleForm rosterWeek = [hsx|
    <form method="POST"
          action={ToggleRosterWeekLiveStatusAction rosterWeek.id}
          class="mb-0">
        {renderLiveToggleButton rosterWeek}
    </form>
|]

renderLiveToggleButton :: RosterWeek -> Html
renderLiveToggleButton rosterWeek =
    renderAppToggleButton $ (defaultAppToggleButtonConfig (liveToggleInputId rosterWeek.id) rosterWeek.isLive [hsx|<span class="fw-semibold">Live</span>|])
        { appToggleInputName = Just "isLive"
        , appToggleInputValue = "true"
        , appToggleButtonClass = "app-week-live-toggle"
        , appToggleRoleSwitch = True
        , appToggleHxPost = Just (pathTo (ToggleRosterWeekLiveStatusAction rosterWeek.id))
        , appToggleHxTrigger = Just "change"
        , appToggleHxInclude = Just "closest form"
        , appToggleHxTarget = Just ("#" <> rosterContentFragmentId)
        , appToggleHxSwap = Just "outerHTML"
        , appToggleHxPushUrl = Just "false"
        , appToggleHxSync = Just ("#" <> rosterWeekShellId <> ":replace")
        }

liveToggleInputId :: Id RosterWeek -> Text
liveToggleInputId rosterWeekId = "roster-live-toggle-" <> tshow rosterWeekId

rosterWeekMoreMenuId :: Maybe RosterWeek -> Id RosterGroup -> Text
rosterWeekMoreMenuId maybeRosterWeek rosterGroupId =
    case maybeRosterWeek of
        Just rosterWeek -> "roster-week-more-menu-" <> tshow rosterWeek.id
        Nothing         -> "roster-week-more-menu-group-" <> tshow rosterGroupId
