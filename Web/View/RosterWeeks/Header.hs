{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.Header
    ( renderRosterGridHeader
    ) where

import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            FrontendSurfaceFieldValue (..),
                                                            frontendSurfaceActionHtmxAttrPairs,
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceActionLink)
import Application.Helper.FrontendContract.Surface.Values (surfaceActionValue)
import Application.Helper.RosterWagePrediction (RosterWagePrediction (..),
                                                formatMoneyAmount)
import Application.Helper.Url (appendQueryParams)
import Application.Helper.UserPreferences (rosterLayoutModeLabel,
                                           rosterLayoutModeValue,
                                           rosterLayoutModes)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import qualified Data.Time.Calendar as Calendar
import Web.RosterWeeks.Dom (rosterContentFragmentId, rosterWeekShellId)
import Web.RosterWeeks.FrontendSurface (rosterDeleteShiftDropzoneRef,
                                        rosterLayoutModeActivationRef)
import Web.RosterWeeks.Paths (rosterAssignmentFiltersUrl, rosterCopyWeekUrl,
                              rosterDayTimelineUrl,
                              rosterWageEstimatePreferenceUrl,
                              rosterWarningPreferenceUrl, rosterWeekUrl)
import Web.RosterWeeks.Types (RosterAssignmentFilters (..),
                              RosterGridViewMode (..),
                              RosterViewCapabilities (..))
import Web.View.Prelude
import Web.View.RosterWeeks.Overview (renderRosterWeekLabel)

rosterActionRoute :: Text -> FrontendSurfaceActionRoute
rosterActionRoute actionUrl =
    FrontendSurfaceActionRoute
        { actionRouteUrl = actionUrl
        , actionRouteFields = []
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Nothing
        , actionRouteExtraAttrs = []
        }

rosterWeekShellSyncRoute :: Text -> FrontendSurfaceActionRoute
rosterWeekShellSyncRoute = rosterActionRoute

renderRosterGridHeader :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> Day -> RosterViewCapabilities -> RosterLayoutModeEnum -> Bool -> Maybe RosterWagePrediction -> Bool -> Bool -> Bool -> RosterGridViewMode -> Maybe Text -> Html
renderRosterGridHeader maybeRosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters weekStartDate viewCapabilities rosterLayoutMode _rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings canToggleFullscreen gridViewMode timelineTodayUrl =
    let toolbarHtml = renderWeekToolbar WeekToolbarConfig
            { weekToolbarVariant = WeekToolbarRoster
            , weekToolbarAriaLabel = "Roster week controls"
            , weekToolbarExtraClass = "roster-grid-header"
            , weekToolbarPrimary = renderLiveToggle maybeRosterWeek viewCapabilities
            , weekToolbarReset = renderThisWeekButton gridViewMode weekStartDate currentRosterGroup timelineTodayUrl
            , weekToolbarNavigation = renderRosterWeekControls weekOffset currentRosterGroup weekStartDate gridViewMode
            , weekToolbarSettings = mconcat
                [ when canToggleFullscreen renderRosterFullscreenToggle
                , renderRosterWeekMoreMenu maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters viewCapabilities rosterLayoutMode showWageEstimates showRosterWarnings gridViewMode
                ]
            , weekToolbarAuxiliary = renderRosterWeekWageSummary rosterWagePrediction
            }
        deleteDropzoneKey = "delete" :: Text
     in if currentUserIsManager && maybe False (not . (.isLive)) maybeRosterWeek
            then SurfaceInteraction.withFrontendSurfaceDropzoneRef rosterDeleteShiftDropzoneRef deleteDropzoneKey toolbarHtml
            else toolbarHtml

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

renderRosterWeekControls :: (?context :: ControllerContext) => Int -> RosterGroup -> Day -> RosterGridViewMode -> Html
renderRosterWeekControls weekOffset currentRosterGroup weekStartDate RosterWeekGridView =
    renderWeekNavigationGroup WeekNavigationConfig
        { weekNavigationAriaLabel = "Roster week navigation"
        , weekNavigationExtraClass = "roster-week-nav-group"
        , weekNavigationPrevious = renderWeekNavigationLink "bi-chevron-left" "Previous week" (rosterWeekUrl (weekOffset - 1) currentRosterGroup.id) (weekOffset - 1) currentRosterGroup.id
        , weekNavigationCurrentLabel = [hsx|{renderRosterWeekLabel weekStartDate}|]
        , weekNavigationLabelClass = "roster-week-nav-button roster-week-nav-label"
        , weekNavigationNext = renderWeekNavigationLink "bi-chevron-right" "Next week" (rosterWeekUrl (weekOffset + 1) currentRosterGroup.id) (weekOffset + 1) currentRosterGroup.id
        }
renderRosterWeekControls weekOffset currentRosterGroup weekStartDate (RosterDayTimelineGridView dayOffset) =
    renderWeekNavigationGroup WeekNavigationConfig
        { weekNavigationAriaLabel = "Roster timeline day navigation"
        , weekNavigationExtraClass = "roster-week-nav-group roster-timeline-day-nav"
        , weekNavigationPrevious = renderWeekNavigationLink "bi-chevron-left" "Previous day" previousUrl previousWeekOffset currentRosterGroup.id
        , weekNavigationCurrentLabel = [hsx|{Text.pack (formatTime defaultTimeLocale "%a %d/%m" selectedDate)}|]
        , weekNavigationLabelClass = "roster-week-nav-button roster-week-nav-label"
        , weekNavigationNext = renderWeekNavigationLink "bi-chevron-right" "Next day" nextUrl nextWeekOffset currentRosterGroup.id
        }
    where
        clampedDayOffset = max 0 (min 6 dayOffset)
        selectedDate = Calendar.addDays (toInteger clampedDayOffset) weekStartDate
        (previousWeekOffset, previousDayOffset) = if clampedDayOffset <= 0 then (weekOffset - 1, 6) else (weekOffset, clampedDayOffset - 1)
        (nextWeekOffset, nextDayOffset) = if clampedDayOffset >= 6 then (weekOffset + 1, 0) else (weekOffset, clampedDayOffset + 1)
        previousUrl = rosterDayTimelineUrl previousWeekOffset currentRosterGroup.id previousDayOffset
        nextUrl = rosterDayTimelineUrl nextWeekOffset currentRosterGroup.id nextDayOffset

renderRosterGroupSwitcher :: Int -> [RosterGroup] -> RosterGroup -> Html
renderRosterGroupSwitcher weekOffset rosterGroups currentRosterGroup
    | length rosterGroups <= 1 = mempty
    | otherwise = [hsx|
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

renderWeekNavigationLink :: Text -> Text -> Text -> Int -> Id RosterGroup -> Html
renderWeekNavigationLink iconClass ariaLabel url targetWeekOffset rosterGroupId =
    renderFrontendSurfaceActionLink
        (surfaceActionValue @Surface.RosterSurface @Surface.NavigateRosterWeek)
        (rosterWeekShellSyncRoute url)
            { actionRouteFields =
                [ FrontendSurfaceFieldValue "weekOffset" (tshow targetWeekOffset)
                , FrontendSurfaceFieldValue "rosterGroupId" (tshow rosterGroupId)
                ]
            , actionRouteStandardUrl = Just url
            , actionRouteExtraAttrs =
                [ ("class", weekNavigationButtonClass "roster-week-nav-button roster-week-nav-arrow")
                , ("aria-label", ariaLabel)
                , ("title", ariaLabel)
                , ("data-turbolinks", "false")
                , ("hx-select", "#" <> rosterWeekShellId)
                ]
            }
        [hsx|<i class={"bi " <> iconClass} aria-hidden="true"></i>|]

renderLiveToggle :: (?context :: ControllerContext) => Maybe RosterWeek -> RosterViewCapabilities -> Html
renderLiveToggle (Just rosterWeek) viewCapabilities
    | viewCapabilities.canToggleRosterLive = renderLiveToggleForm rosterWeek
renderLiveToggle _ _ = mempty

renderThisWeekButton :: (?context :: ControllerContext) => RosterGridViewMode -> Day -> RosterGroup -> Maybe Text -> Html
renderThisWeekButton gridViewMode _weekStartDate currentRosterGroup timelineTodayUrl =
    renderPartialNavigationLink
        PartialNavigationLink
            { partialNavigationLabel = resetLabel
            , partialNavigationUrl = thisWeekUrl
            , partialNavigationTargetId = rosterWeekShellId
            , partialNavigationSelectId = Just rosterWeekShellId
            , partialNavigationClass = weekNavigationButtonClass ""
            , partialNavigationSwap = "outerHTML"
            , partialNavigationSync = Just ("#" <> rosterWeekShellId <> ":replace")
            , partialNavigationPushUrl = True
            }
    where
        resetLabel = case gridViewMode of
            RosterDayTimelineGridView _ -> "Today"
            RosterWeekGridView          -> "This week"
        thisWeekUrl = case gridViewMode of
            RosterDayTimelineGridView _ -> fromMaybe (appendQueryParams (pathTo RosterWeeksAction) [("rosterGroupId", tshow currentRosterGroup.id), ("rosterView", "timeline")]) timelineTodayUrl
            RosterWeekGridView -> pathTo RosterWeeksAction

renderRosterWeekMoreMenu :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> RosterViewCapabilities -> RosterLayoutModeEnum -> Bool -> Bool -> RosterGridViewMode -> Html
renderRosterWeekMoreMenu maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters viewCapabilities rosterLayoutMode showWageEstimates showRosterWarnings gridViewMode =
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
            {renderRosterLayoutMenuSection weekOffset currentRosterGroup.id rosterLayoutMode gridViewMode}
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

renderRosterLayoutMenuSection :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterLayoutModeEnum -> RosterGridViewMode -> Html
renderRosterLayoutMenuSection weekOffset rosterGroupId _selectedLayoutMode (RosterDayTimelineGridView _) = [hsx|
    <div class="px-1 py-1">
        <div class="small text-uppercase fw-semibold app-muted px-1 pb-2">Roster view</div>
        <a class="btn btn-outline-secondary btn-sm w-100" href={rosterWeekUrl weekOffset rosterGroupId} data-turbolinks="false">Week grid</a>
    </div>
|]
renderRosterLayoutMenuSection _weekOffset _rosterGroupId selectedLayoutMode RosterWeekGridView = [hsx|
    <div class="px-1 py-1">
        <div class="small text-uppercase fw-semibold app-muted px-1 pb-2">Roster layout</div>
        <div class="btn-group w-100 roster-layout-mode-group" role="group" aria-label="Roster layout">
            {forEach rosterLayoutModes (renderRosterLayoutModeOption selectedLayoutMode)}
        </div>
    </div>
|]

renderRosterLayoutModeOption :: RosterLayoutModeEnum -> RosterLayoutModeEnum -> Html
renderRosterLayoutModeOption selectedLayoutMode layoutMode =
    let inputId = "roster-layout-mode-" <> rosterLayoutModeValue layoutMode
        layoutValue = rosterLayoutModeValue layoutMode
        inputHtml = [hsx|
            <input type="radio"
                   class="btn-check"
                   name="rosterLayoutMode"
                   id={inputId}
                   value={layoutValue}
                   checked={rosterLayoutModeValue selectedLayoutMode == layoutValue} />
        |]
     in [hsx|
        {SurfaceInteraction.withFrontendSurfaceActivationRef rosterLayoutModeActivationRef inputHtml}
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
renderRosterWarningPreferenceForm weekOffset rosterGroupId showRosterWarnings =
    renderFrontendSurfaceActionForm
        (surfaceActionValue @Surface.RosterSurface @Surface.ToggleRosterWarnings)
        (rosterWeekShellSyncRoute (rosterWarningPreferenceUrl weekOffset rosterGroupId))
            { actionRouteStandardUrl = Just (rosterWarningPreferenceUrl weekOffset rosterGroupId)
            , actionRouteExtraAttrs = [("class", "col-6 mb-0"), ("data-disable-javascript-submission", "true")]
            }
        [hsx|
            <div class="roster-display-toggle">
                {renderRosterWarningToggle showRosterWarnings}
            </div>
        |]

renderRosterWageEstimatePreferenceForm :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterViewCapabilities -> Bool -> Html
renderRosterWageEstimatePreferenceForm weekOffset rosterGroupId viewCapabilities showWageEstimates
    | not viewCapabilities.canViewWageEstimates = mempty
    | otherwise =
        renderFrontendSurfaceActionForm
            (surfaceActionValue @Surface.RosterSurface @Surface.ToggleRosterWageEstimates)
            (rosterWeekShellSyncRoute (rosterWageEstimatePreferenceUrl weekOffset rosterGroupId))
                { actionRouteStandardUrl = Just (rosterWageEstimatePreferenceUrl weekOffset rosterGroupId)
                , actionRouteExtraAttrs = [("class", "col-6 mb-0"), ("data-disable-javascript-submission", "true")]
                }
            [hsx|
                <div class="roster-display-toggle">
                    {renderRosterWageEstimateToggle showWageEstimates}
                </div>
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
    | shouldShowRosterSortForm (Just rosterWeek) viewCapabilities =
        renderFrontendSurfaceActionForm
            (surfaceActionValue @Surface.RosterSurface @Surface.SortRosterWeek)
            (rosterWeekShellSyncRoute (pathTo (SortRosterWeekAction rosterWeek.id)))
                { actionRouteStandardUrl = Just (pathTo (SortRosterWeekAction rosterWeek.id))
                , actionRouteExtraAttrs = [("class", "mb-0 roster-week-action-form"), ("data-disable-javascript-submission", "true")]
                }
            [hsx|
                <button type="submit" class="btn btn-outline-secondary btn-sm w-100 h-100 text-center roster-week-action-button">
                    <i class="bi bi-sort-down me-1" aria-hidden="true"></i>
                    Sort shifts
                </button>
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
        then renderFrontendSurfaceActionForm
            (surfaceActionValue @Surface.RosterSurface @Surface.ToggleRosterAssignmentFilters)
            (rosterWeekShellSyncRoute (rosterAssignmentFiltersUrl weekOffset rosterGroupId))
                { actionRouteStandardUrl = Just (rosterAssignmentFiltersUrl weekOffset rosterGroupId)
                , actionRouteExtraAttrs =
                    [ ("class", "px-1 py-1")
                    , ("data-roster-filter-form", "true")
                    , ("data-roster-filter-menu-trigger-id", menuTriggerId)
                    , ("data-disable-javascript-submission", "true")
                    ]
                }
            [hsx|
                <div class="small text-uppercase fw-semibold app-muted px-1 pb-2">Enforce prevention</div>
                <div class="roster-assignment-filter-grid">
                    {renderRosterAssignmentFilterToggle "hide-staff-at-ideal" "hideStaffAtIdealShifts" filters.hideStaffAtIdealShifts "Too many shifts"}
                    {renderRosterAssignmentFilterToggle "hide-staff-unavailable" "hideStaffUnavailable" filters.hideStaffUnavailable "Regular day off"}
                    {renderRosterAssignmentFilterToggle "hide-staff-on-leave" "hideStaffOnApprovedLeave" filters.hideStaffOnApprovedLeave "Unavailable"}
                    {renderRosterAssignmentFilterToggle "hide-staff-assigned-today" "hideStaffAlreadyAssignedToday" filters.hideStaffAlreadyAssignedToday "Double shifts"}
                </div>
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
renderCopyPreviousWeekForm weekOffset rosterGroupId =
    renderFrontendSurfaceActionForm
        (surfaceActionValue @Surface.RosterSurface @Surface.CopyRosterWeek)
        (rosterWeekShellSyncRoute (rosterCopyWeekUrl (weekOffset - 1) weekOffset rosterGroupId))
            { actionRouteCustomHtmx =
                [ FrontendSurfaceCustomHtmxAttrs "copy-roster-week-custom-htmx" [("hx-confirm", "This will overwrite the current week with the previous week's roster. Continue?")]
                ]
            , actionRouteStandardUrl = Just (rosterCopyWeekUrl (weekOffset - 1) weekOffset rosterGroupId)
            , actionRouteExtraAttrs = [("class", "mb-0 roster-week-action-form"), ("data-disable-javascript-submission", "true")]
            }
        [hsx|
            <button type="submit" class="btn btn-outline-primary btn-sm w-100 h-100 text-center roster-week-action-button">
                <i class="bi bi-copy me-1" aria-hidden="true"></i>
                Copy Previous Week
            </button>
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
        , appToggleInputExtraAttrs =
            frontendSurfaceActionHtmxAttrPairs
                (surfaceActionValue @Surface.RosterSurface @Surface.ToggleRosterWeekLiveStatus)
                (rosterWeekShellSyncRoute (pathTo (ToggleRosterWeekLiveStatusAction rosterWeek.id)))
                    { actionRouteFields = [FrontendSurfaceFieldValue "isLive" (boolParam rosterWeek.isLive)]
                    }
                <> [("hx-trigger", "change"), ("hx-include", "closest form")]
        }

liveToggleInputId :: Id RosterWeek -> Text
liveToggleInputId rosterWeekId = "roster-live-toggle-" <> tshow rosterWeekId

rosterWeekMoreMenuId :: Maybe RosterWeek -> Id RosterGroup -> Text
rosterWeekMoreMenuId maybeRosterWeek rosterGroupId =
    case maybeRosterWeek of
        Just rosterWeek -> "roster-week-more-menu-" <> tshow rosterWeek.id
        Nothing         -> "roster-week-more-menu-group-" <> tshow rosterGroupId
