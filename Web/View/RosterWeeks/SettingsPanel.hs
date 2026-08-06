{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.SettingsPanel
    ( renderRosterSettingsPanel
    ) where

import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Roster.ImageExport (rosterImageExportFilename,
                                                                       rosterJpgImageExportTriggerAttrs)
import qualified Application.Helper.FrontendContract.Surface.Roster.Intent as RosterIntent
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceActionLink)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.UserPreferences (rosterLayoutModeLabel,
                                           rosterLayoutModeValue,
                                           rosterLayoutModes)
import Application.RosterNotification (RosterNotificationAudience (..),
                                       RosterNotificationPanelData (..),
                                       RosterNotificationRunSummary (..))
import Web.RosterWeeks.Dom (rosterEmailButtonId, rosterWeekShellId)
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
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Nothing
        , actionRouteExtraAttrs = []
        }

renderRosterSettingsPanel :: (?context :: ControllerContext) => RosterStaffPanelRenderModel -> Html
renderRosterSettingsPanel RosterStaffPanelRenderModel { staffPanelRosterWeek, staffPanelWeekOffset, staffPanelWeekStartDate, staffPanelRosterGroups, staffPanelCurrentRosterGroup, staffPanelAssignmentFilters, staffPanelViewCapabilities, staffPanelRosterLayoutMode, staffPanelShowWageEstimates, staffPanelShowRosterWarnings, staffPanelViewMode, staffPanelNotificationPanelData } = [hsx|
    <div class="roster-settings-panel">
        {when (length staffPanelRosterGroups > 1) $ renderRosterSettingsSection "bi-people" "Roster group" (renderRosterGroupSwitcher staffPanelWeekOffset staffPanelRosterGroups staffPanelCurrentRosterGroup)}
        {renderRosterSettingsSection "bi-layout-split" "Roster layout" (renderRosterLayoutSection staffPanelWeekOffset staffPanelCurrentRosterGroup.id staffPanelRosterLayoutMode staffPanelViewMode)}
        {when (staffPanelViewCapabilities.canManageRosterWarnings || staffPanelViewCapabilities.canViewWageEstimates) $
            renderRosterSettingsSection "bi-eye" "Display" (renderRosterDisplayPreferencesSection staffPanelWeekOffset staffPanelCurrentRosterGroup.id staffPanelViewCapabilities staffPanelShowWageEstimates staffPanelShowRosterWarnings)}
        {when staffPanelViewCapabilities.canManageAssignmentFilter $
            renderRosterSettingsSection "bi-shield-check" "Prevent assignment" (renderRosterAssignmentFiltersSection staffPanelWeekOffset staffPanelCurrentRosterGroup.id staffPanelAssignmentFilters)}
        {when (staffPanelViewCapabilities.canCopyRosterWeek || shouldShowRosterSortForm staffPanelRosterWeek staffPanelViewCapabilities) $
            renderRosterSettingsSection "bi-lightning-charge" "Week actions" (renderRosterWeekActions staffPanelRosterWeek staffPanelWeekOffset staffPanelCurrentRosterGroup.id staffPanelViewCapabilities)}
        {when (isJust staffPanelNotificationPanelData || shouldShowRosterExport staffPanelRosterWeek staffPanelViewCapabilities staffPanelRosterLayoutMode staffPanelViewMode) $
            renderRosterSettingsSection "bi-share" "Share roster" (renderRosterShareSection staffPanelRosterWeek staffPanelCurrentRosterGroup.name staffPanelWeekStartDate staffPanelNotificationPanelData staffPanelViewCapabilities staffPanelRosterLayoutMode staffPanelViewMode)}
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
        <input type="hidden" name={surfaceFieldNameFrom @Surface.WeekOffset fields} value={tshow weekOffset}/>
        <select id="roster-group-switch"
                class="form-select form-select-sm"
                name={surfaceFieldNameFrom @Surface.RosterGroupId fields}
                onchange="this.form.submit()">
            {forEach rosterGroups (renderRosterGroupSwitchOption currentRosterGroup.id)}
        </select>
    </form>
|]
  where
    fields :: SurfaceActionFields Surface.RosterSurface Surface.NavigateRosterWeek
    fields =
        RosterAction.navigateRosterWeekActionFields
            weekOffset
            (unpackId currentRosterGroup.id)

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
        fields :: SurfaceIntentFields Surface.RosterSurface Surface.SetRosterLayoutMode
        fields = RosterIntent.setRosterLayoutModeIntentFields layoutValue
        inputHtml = [hsx|
            <input type="radio"
                   class="btn-check"
                   name={surfaceFieldNameFrom @Surface.RosterLayoutMode fields}
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
        (RosterAction.toggleRosterWarningsAction fields)
        (rosterWeekShellSyncRoute (rosterWarningPreferenceUrl weekOffset rosterGroupId))
            { actionRouteStandardUrl = Just (rosterWarningPreferenceUrl weekOffset rosterGroupId)
            , actionRouteExtraAttrs = [("class", "mb-0")]
            }
        [hsx|<div class="roster-display-toggle">{renderRosterWarningToggle fields showRosterWarnings}</div>|]
  where
    fields = RosterAction.toggleRosterWarningsActionFields showRosterWarnings

renderRosterWageEstimatePreferenceForm :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterViewCapabilities -> Bool -> Html
renderRosterWageEstimatePreferenceForm weekOffset rosterGroupId viewCapabilities showWageEstimates
    | not viewCapabilities.canViewWageEstimates = mempty
    | otherwise =
        renderFrontendSurfaceActionForm
            (RosterAction.toggleRosterWageEstimatesAction fields)
            (rosterWeekShellSyncRoute (rosterWageEstimatePreferenceUrl weekOffset rosterGroupId))
                { actionRouteStandardUrl = Just (rosterWageEstimatePreferenceUrl weekOffset rosterGroupId)
                , actionRouteExtraAttrs = [("class", "mb-0")]
                }
            [hsx|<div class="roster-display-toggle">{renderRosterWageEstimateToggle fields showWageEstimates}</div>|]
  where
    fields = RosterAction.toggleRosterWageEstimatesActionFields showWageEstimates

renderRosterWarningToggle :: SurfaceActionFields Surface.RosterSurface Surface.ToggleRosterWarnings -> Bool -> Html
renderRosterWarningToggle fields showRosterWarnings =
    renderAppToggleButton $
        ( defaultAppToggleStateButtonConfig
            "show-roster-warnings"
            (surfaceToggleScalarField @Surface.ShowRosterWarnings fields True False)
            showRosterWarnings
            [hsx|<span class="small">Warnings enabled</span>|]
            [hsx|<span class="small">Warnings disabled</span>|]
        )
            { appToggleButtonClass = "btn-sm w-100 justify-content-start"
            , appToggleSubmitPolicy = ToggleSubmitImmediate
            }

renderRosterWageEstimateToggle :: SurfaceActionFields Surface.RosterSurface Surface.ToggleRosterWageEstimates -> Bool -> Html
renderRosterWageEstimateToggle fields showWageEstimates =
    renderAppToggleButton $
        ( defaultAppToggleStateButtonConfig
            "show-wage-estimates"
            (surfaceToggleScalarField @Surface.ShowWageEstimates fields True False)
            showWageEstimates
            [hsx|<span class="small">Wages enabled</span>|]
            [hsx|<span class="small">Wages disabled</span>|]
        )
            { appToggleButtonClass = "btn-sm w-100 justify-content-start"
            , appToggleSubmitPolicy = ToggleSubmitImmediate
            }

renderRosterAssignmentFiltersSection :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterAssignmentFilters -> Html
renderRosterAssignmentFiltersSection weekOffset rosterGroupId filters =
    renderFrontendSurfaceActionForm
        (RosterAction.toggleRosterAssignmentFiltersAction fields)
        (rosterWeekShellSyncRoute (rosterAssignmentFiltersUrl weekOffset rosterGroupId))
            { actionRouteStandardUrl = Just (rosterAssignmentFiltersUrl weekOffset rosterGroupId)
            , actionRouteExtraAttrs =
                [ ("class", "mb-0")
                , ("data-roster-filter-form", "true")
                ]
            }
        [hsx|
            <div class="roster-assignment-filter-grid">
                {renderRosterAssignmentFilterToggle "hide-staff-at-ideal" (surfaceToggleScalarField @Surface.HideStaffAtIdealShifts fields True False) filters.hideStaffAtIdealShifts "Too many shifts"}
                {renderRosterAssignmentFilterToggle "hide-staff-unavailable" (surfaceToggleScalarField @Surface.HideStaffUnavailable fields True False) filters.hideStaffUnavailable "Regular day off"}
                {renderRosterAssignmentFilterToggle "hide-staff-on-leave" (surfaceToggleScalarField @Surface.HideStaffOnApprovedLeave fields True False) filters.hideStaffOnApprovedLeave "Unavailable"}
                {renderRosterAssignmentFilterToggle "hide-staff-assigned-today" (surfaceToggleScalarField @Surface.HideStaffAlreadyAssignedToday fields True False) filters.hideStaffAlreadyAssignedToday "Double shifts"}
            </div>
        |]
  where
    fields =
        RosterAction.toggleRosterAssignmentFiltersActionFields
            filters.hideStaffAtIdealShifts
            filters.hideStaffUnavailable
            filters.hideStaffOnApprovedLeave
            filters.hideStaffAlreadyAssignedToday

renderRosterAssignmentFilterToggle :: Text -> ToggleFieldBinding -> Bool -> Text -> Html
renderRosterAssignmentFilterToggle inputId binding isChecked label = [hsx|
    <div>
        {renderRosterAssignmentFilterToggleButton inputId binding isChecked label}
    </div>
|]

renderRosterAssignmentFilterToggleButton :: Text -> ToggleFieldBinding -> Bool -> Text -> Html
renderRosterAssignmentFilterToggleButton inputId binding isChecked label =
    renderAppToggleButton $
        (defaultAppToggleButtonConfig inputId binding isChecked [hsx|<span class="small">{label}</span>|])
            { appToggleButtonClass = "btn-sm w-100 justify-content-start text-start"
            , appToggleSubmitPolicy = ToggleSubmitImmediate
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
            (RosterAction.sortRosterWeekAction RosterAction.sortRosterWeekActionFields)
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
        (RosterAction.copyRosterWeekAction (RosterAction.copyRosterWeekActionFields Nothing Nothing))
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

shouldShowRosterExport :: Maybe RosterWeek -> RosterViewCapabilities -> RosterLayoutModeEnum -> RosterGridViewMode -> Bool
shouldShowRosterExport maybeRosterWeek viewCapabilities rosterLayoutMode viewMode =
    viewCapabilities.canExportRosterImage
        && maybe False (.isLive) maybeRosterWeek
        && viewMode == RosterWeekGridView
        && rosterLayoutModeValue rosterLayoutMode == "day_rows"

renderRosterShareSection :: (?context :: ControllerContext) => Maybe RosterWeek -> Text -> Day -> Maybe RosterNotificationPanelData -> RosterViewCapabilities -> RosterLayoutModeEnum -> RosterGridViewMode -> Html
renderRosterShareSection maybeRosterWeek rosterGroupName weekStartDate notificationPanelData viewCapabilities rosterLayoutMode viewMode = [hsx|
    <div class="d-grid gap-2">
        {renderRosterEmailAction maybeRosterWeek notificationPanelData}
        {when (shouldShowRosterExport maybeRosterWeek viewCapabilities rosterLayoutMode viewMode) (renderRosterExportSection rosterGroupName weekStartDate)}
    </div>
|]

renderRosterEmailAction :: (?context :: ControllerContext) => Maybe RosterWeek -> Maybe RosterNotificationPanelData -> Html
renderRosterEmailAction (Just rosterWeek) (Just RosterNotificationPanelData { panelNotificationAudience = audience, panelLatestNotificationRun = latestRun })
    | maybe False ((> 0) . (.summaryInProgressCount)) latestRun = [hsx|
        <button id={rosterEmailButtonId} type="button" class="btn btn-outline-primary btn-sm w-100" disabled="disabled" title="Roster email delivery is in progress">
            <i class="bi bi-envelope me-1" aria-hidden="true"></i>
            Email roster
        </button>
        <p class="small app-muted mb-0">Roster email delivery is in progress.</p>
    |]
    | null audience.audienceRecipients = [hsx|
        <button id={rosterEmailButtonId} type="button" class="btn btn-outline-primary btn-sm w-100" disabled="disabled" title="No eligible recipients">
            <i class="bi bi-envelope me-1" aria-hidden="true"></i>
            Email roster
        </button>
        <p class="small app-muted mb-0">No eligible recipients are assigned to this roster group.</p>
    |]
    | otherwise =
        renderFrontendSurfaceActionLink
            (RosterAction.showRosterNotificationConfirmationAction (RosterAction.showRosterNotificationConfirmationActionFields (unpackId rosterWeek.id)))
            (rosterWeekShellSyncRoute actionUrl)
                { actionRouteStandardUrl = Just actionUrl
                , actionRouteExtraAttrs =
                    [ ("id", rosterEmailButtonId)
                    , ("class", "btn btn-outline-primary btn-sm w-100")
                    ]
                }
            [hsx|
                <i class="bi bi-envelope me-1" aria-hidden="true"></i>
                Email roster
            |]
      where
        actionUrl = pathTo (ShowRosterNotificationConfirmationAction rosterWeek.id)
renderRosterEmailAction _ _ = mempty

renderRosterExportSection :: Text -> Day -> Html
renderRosterExportSection rosterGroupName weekStartDate = [hsx|
    <button type="button"
            class="btn btn-outline-secondary btn-sm w-100 roster-export-button"
            {...rosterJpgImageExportTriggerAttrs (rosterImageExportFilename rosterGroupName weekStartDate)}>
        <i class="bi bi-download me-1" aria-hidden="true"></i>
        Export JPG
    </button>
|]
