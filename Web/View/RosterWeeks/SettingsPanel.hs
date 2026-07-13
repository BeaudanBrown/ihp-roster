{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.SettingsPanel
    ( renderRosterSettingsPanel
    ) where

import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            renderFrontendSurfaceActionForm)
import Application.Helper.FrontendContract.Surface.Values (surfaceActionValue)
import Application.Helper.UserPreferences (rosterLayoutModeLabel,
                                           rosterLayoutModeValue,
                                           rosterLayoutModes)
import Web.RosterWeeks.Dom (rosterWeekShellId)
import Web.RosterWeeks.FrontendSurface (rosterLayoutModeActivationRef)
import Web.RosterWeeks.Paths (rosterAssignmentFiltersUrl, rosterCopyWeekUrl,
                              rosterWageEstimatePreferenceUrl,
                              rosterWarningPreferenceUrl, rosterWeekUrl)
import Web.RosterWeeks.Types (RosterAssignmentFilters (..),
                              RosterGridViewMode (..),
                              RosterStaffPanelRenderModel (..),
                              RosterViewCapabilities (..))
import Web.View.Prelude

rosterWeekShellSyncRoute :: Text -> FrontendSurfaceActionRoute
rosterWeekShellSyncRoute actionUrl =
    FrontendSurfaceActionRoute
        { actionRouteUrl = actionUrl
        , actionRouteFields = []
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Nothing
        , actionRouteExtraAttrs = []
        }

renderRosterSettingsPanel :: (?context :: ControllerContext) => RosterStaffPanelRenderModel -> Html
renderRosterSettingsPanel RosterStaffPanelRenderModel { staffPanelRosterWeek, staffPanelWeekOffset, staffPanelRosterGroups, staffPanelCurrentRosterGroup, staffPanelAssignmentFilters, staffPanelViewCapabilities, staffPanelRosterLayoutMode, staffPanelShowWageEstimates, staffPanelShowRosterWarnings, staffPanelViewMode } = [hsx|
    <div class="roster-settings-panel">
        {when (length staffPanelRosterGroups > 1) $ renderRosterSettingsSection "bi-people" "Roster group" (renderRosterGroupSwitcher staffPanelWeekOffset staffPanelRosterGroups staffPanelCurrentRosterGroup)}
        {renderRosterSettingsSection "bi-layout-split" "Roster layout" (renderRosterLayoutSection staffPanelWeekOffset staffPanelCurrentRosterGroup.id staffPanelRosterLayoutMode staffPanelViewMode)}
        {when (staffPanelViewCapabilities.canManageRosterWarnings || staffPanelViewCapabilities.canViewWageEstimates) $
            renderRosterSettingsSection "bi-eye" "Display" (renderRosterDisplayPreferencesSection staffPanelWeekOffset staffPanelCurrentRosterGroup.id staffPanelViewCapabilities staffPanelShowWageEstimates staffPanelShowRosterWarnings)}
        {when staffPanelViewCapabilities.canManageAssignmentFilter $
            renderRosterSettingsSection "bi-shield-check" "Prevent assignment" (renderRosterAssignmentFiltersSection staffPanelWeekOffset staffPanelCurrentRosterGroup.id staffPanelAssignmentFilters)}
        {when (staffPanelViewCapabilities.canCopyRosterWeek || shouldShowRosterSortForm staffPanelRosterWeek staffPanelViewCapabilities) $
            renderRosterSettingsSection "bi-lightning-charge" "Week actions" (renderRosterWeekActions staffPanelRosterWeek staffPanelWeekOffset staffPanelCurrentRosterGroup.id staffPanelViewCapabilities)}
        {when (shouldShowRosterExport staffPanelRosterWeek staffPanelViewCapabilities) $
            renderRosterSettingsSection "bi-share" "Share roster" renderRosterExportSection}
    </div>
|]

renderRosterSettingsSection :: Text -> Text -> Html -> Html
renderRosterSettingsSection iconClass title body = [hsx|
    <section class="roster-settings-section">
        <h3 class="roster-settings-section-title">
            <i class={"bi " <> iconClass} aria-hidden="true"></i>
            <span>{title}</span>
        </h3>
        <div class="roster-settings-section-body">{body}</div>
    </section>
|]

renderRosterGroupSwitcher :: Int -> [RosterGroup] -> RosterGroup -> Html
renderRosterGroupSwitcher weekOffset rosterGroups currentRosterGroup = [hsx|
    <form class="mb-0" method="GET" action={pathTo (ShowRosterWeekAction weekOffset)}>
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

renderRosterLayoutSection :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterLayoutModeEnum -> RosterGridViewMode -> Html
renderRosterLayoutSection weekOffset rosterGroupId _selectedLayoutMode (RosterDayTimelineGridView _) = [hsx|
    <a class="btn btn-outline-secondary btn-sm w-100" href={rosterWeekUrl weekOffset rosterGroupId} data-turbolinks="false">Week grid</a>
|]
renderRosterLayoutSection _weekOffset _rosterGroupId selectedLayoutMode RosterWeekGridView = [hsx|
    <div class="btn-group w-100 roster-layout-mode-group" role="group" aria-label="Roster layout">
        {forEach rosterLayoutModes (renderRosterLayoutModeOption selectedLayoutMode)}
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

renderRosterDisplayPreferencesSection :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterViewCapabilities -> Bool -> Bool -> Html
renderRosterDisplayPreferencesSection weekOffset rosterGroupId viewCapabilities showWageEstimates showRosterWarnings = [hsx|
    <div class="roster-settings-toggle-grid">
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
            , actionRouteExtraAttrs = [("class", "mb-0")]
            }
        [hsx|<div class="roster-display-toggle">{renderRosterWarningToggle showRosterWarnings}</div>|]

renderRosterWageEstimatePreferenceForm :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterViewCapabilities -> Bool -> Html
renderRosterWageEstimatePreferenceForm weekOffset rosterGroupId viewCapabilities showWageEstimates
    | not viewCapabilities.canViewWageEstimates = mempty
    | otherwise =
        renderFrontendSurfaceActionForm
            (surfaceActionValue @Surface.RosterSurface @Surface.ToggleRosterWageEstimates)
            (rosterWeekShellSyncRoute (rosterWageEstimatePreferenceUrl weekOffset rosterGroupId))
                { actionRouteStandardUrl = Just (rosterWageEstimatePreferenceUrl weekOffset rosterGroupId)
                , actionRouteExtraAttrs = [("class", "mb-0")]
                }
            [hsx|<div class="roster-display-toggle">{renderRosterWageEstimateToggle showWageEstimates}</div>|]

renderRosterWarningToggle :: Bool -> Html
renderRosterWarningToggle showRosterWarnings =
    renderAppToggleButton $ (defaultAppToggleStateButtonConfig "show-roster-warnings" showRosterWarnings [hsx|<span class="small">Warnings enabled</span>|] [hsx|<span class="small">Warnings disabled</span>|])
        { appToggleInputName = Just "showRosterWarnings"
        , appToggleInputValue = "true"
        , appToggleButtonClass = "btn-sm w-100 justify-content-start"
        , appToggleOnChange = Just "this.form.requestSubmit()"
        }

renderRosterWageEstimateToggle :: Bool -> Html
renderRosterWageEstimateToggle showWageEstimates =
    renderAppToggleButton $ (defaultAppToggleStateButtonConfig "show-wage-estimates" showWageEstimates [hsx|<span class="small">Wages enabled</span>|] [hsx|<span class="small">Wages disabled</span>|])
        { appToggleInputName = Just "showWageEstimates"
        , appToggleInputValue = "true"
        , appToggleButtonClass = "btn-sm w-100 justify-content-start"
        , appToggleOnChange = Just "this.form.requestSubmit()"
        }

renderRosterAssignmentFiltersSection :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterAssignmentFilters -> Html
renderRosterAssignmentFiltersSection weekOffset rosterGroupId filters =
    renderFrontendSurfaceActionForm
        (surfaceActionValue @Surface.RosterSurface @Surface.ToggleRosterAssignmentFilters)
        (rosterWeekShellSyncRoute (rosterAssignmentFiltersUrl weekOffset rosterGroupId))
            { actionRouteStandardUrl = Just (rosterAssignmentFiltersUrl weekOffset rosterGroupId)
            , actionRouteExtraAttrs =
                [ ("class", "mb-0")
                , ("data-roster-filter-form", "true")
                ]
            }
        [hsx|
            <div class="roster-assignment-filter-grid">
                {renderRosterAssignmentFilterToggle "hide-staff-at-ideal" "hideStaffAtIdealShifts" filters.hideStaffAtIdealShifts "Too many shifts"}
                {renderRosterAssignmentFilterToggle "hide-staff-unavailable" "hideStaffUnavailable" filters.hideStaffUnavailable "Regular day off"}
                {renderRosterAssignmentFilterToggle "hide-staff-on-leave" "hideStaffOnApprovedLeave" filters.hideStaffOnApprovedLeave "Unavailable"}
                {renderRosterAssignmentFilterToggle "hide-staff-assigned-today" "hideStaffAlreadyAssignedToday" filters.hideStaffAlreadyAssignedToday "Double shifts"}
            </div>
        |]

renderRosterAssignmentFilterToggle :: Text -> Text -> Bool -> Text -> Html
renderRosterAssignmentFilterToggle inputId fieldName isChecked label = [hsx|
    <div>{renderRosterAssignmentFilterToggleButton inputId fieldName isChecked label}</div>
|]

renderRosterAssignmentFilterToggleButton :: Text -> Text -> Bool -> Text -> Html
renderRosterAssignmentFilterToggleButton inputId fieldName isChecked label =
    renderAppToggleButton $ (defaultAppToggleButtonConfig inputId isChecked [hsx|<span class="small">{label}</span>|])
        { appToggleInputName = Just fieldName
        , appToggleInputValue = "true"
        , appToggleButtonClass = "btn-sm w-100 justify-content-start text-start"
        , appToggleOnChange = Just "this.form.requestSubmit()"
        }

renderRosterWeekActions :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> Id RosterGroup -> RosterViewCapabilities -> Html
renderRosterWeekActions maybeRosterWeek weekOffset rosterGroupId viewCapabilities = [hsx|
    <div class="roster-week-action-grid">
        {renderRosterSortForm maybeRosterWeek viewCapabilities}
        {when viewCapabilities.canCopyRosterWeek (renderCopyPreviousWeekForm weekOffset rosterGroupId)}
    </div>
|]

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
                , actionRouteExtraAttrs = [("class", "mb-0 roster-week-action-form")]
                }
            [hsx|
                <button type="submit" class="btn btn-outline-secondary btn-sm w-100 h-100 text-center roster-week-action-button">
                    <i class="bi bi-sort-down me-1" aria-hidden="true"></i>
                    Sort shifts
                </button>
            |]
renderRosterSortForm _ _ = mempty

renderCopyPreviousWeekForm :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Html
renderCopyPreviousWeekForm weekOffset rosterGroupId =
    renderFrontendSurfaceActionForm
        (surfaceActionValue @Surface.RosterSurface @Surface.CopyRosterWeek)
        (rosterWeekShellSyncRoute (rosterCopyWeekUrl (weekOffset - 1) weekOffset rosterGroupId))
            { actionRouteCustomHtmx =
                [ FrontendSurfaceCustomHtmxAttrs "copy-roster-week-custom-htmx" [("hx-confirm", "This will overwrite the current week with the previous week's roster. Continue?")]
                ]
            , actionRouteStandardUrl = Just (rosterCopyWeekUrl (weekOffset - 1) weekOffset rosterGroupId)
            , actionRouteExtraAttrs = [("class", "mb-0 roster-week-action-form")]
            }
        [hsx|
            <button type="submit" class="btn btn-outline-primary btn-sm w-100 h-100 text-center roster-week-action-button">
                <i class="bi bi-copy me-1" aria-hidden="true"></i>
                Copy Previous Week
            </button>
        |]

shouldShowRosterExport :: Maybe RosterWeek -> RosterViewCapabilities -> Bool
shouldShowRosterExport maybeRosterWeek viewCapabilities =
    viewCapabilities.canExportRosterImage && maybe False (.isLive) maybeRosterWeek

renderRosterExportSection :: Html
renderRosterExportSection = [hsx|
    <button type="button"
            class="btn btn-outline-secondary btn-sm w-100 roster-export-button"
            data-roster-export-format="jpg">
        <i class="bi bi-download me-1" aria-hidden="true"></i>
        Export JPG
    </button>
|]
