{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.SettingsPanel
    ( renderRosterGroupSwitcher
    , renderRosterOwnLiveShiftHighlightPreferenceForm
    , renderRosterSettingsPanel
    ) where

import Application.Helper.FrontendContract.Surface.DSL (WireType (WireDay))
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Roster.ImageExport (rosterImageExportFilename,
                                                                       rosterPngImageExportTriggerAttrs)
import Application.Helper.FrontendContract.Surface.Roster (RosterImageExportStyle (..))
import qualified Application.Helper.FrontendContract.Surface.Roster.Intent as RosterIntent
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceActionLink)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Url (appendQueryParams)
import Application.Helper.UserPreferences (rosterLayoutModeIsDayColumns,
                                           rosterLayoutModeLabel,
                                           rosterLayoutModeValue,
                                           rosterLayoutModes)
import Application.RosterNotification (RosterNotificationAudience (..),
                                       RosterNotificationPanelData (..),
                                       RosterNotificationRunSummary (..))
import Data.Time.Calendar (addDays)
import Web.RosterWeeks.Dom (rosterEmailButtonId, rosterWeekShellId)
import Web.RosterWeeks.FrontendSurface (rosterLayoutModeActivationRef)
import Web.RosterWeeks.Paths (rosterAssignmentFiltersUrl, rosterCopyWeekUrl,
                              rosterOwnLiveShiftHighlightPreferenceUrl,
                              rosterWageEstimatePreferenceUrl,
                              rosterWarningPreferenceUrl, rosterWindowBaseUrl,
                              rosterWindowUrl)
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
renderRosterSettingsPanel RosterStaffPanelRenderModel { staffPanelRosterWeek, staffPanelWeekOffset, staffPanelWeekStartDate, staffPanelCalendarRevision, staffPanelRosterGroups, staffPanelCurrentRosterGroup, staffPanelAssignmentFilters, staffPanelViewCapabilities, staffPanelRosterLayoutMode, staffPanelShowWageEstimates, staffPanelShowRosterWarnings, staffPanelHighlightOwnLiveShifts, staffPanelViewMode, staffPanelNotificationPanelData } = [hsx|
    <div class="roster-settings-panel">
        {when (length staffPanelRosterGroups > 1) $ renderRosterSettingsSection "bi-people" "Roster group" (renderRosterGroupSwitcher staffPanelWeekStartDate staffPanelRosterGroups staffPanelCurrentRosterGroup)}
        {renderRosterSettingsSection "bi-layout-split" "Roster layout" (renderRosterLayoutSection staffPanelWeekStartDate staffPanelCurrentRosterGroup.id staffPanelRosterLayoutMode staffPanelViewMode)}
        {when (staffPanelViewCapabilities.canManageRosterWarnings || staffPanelViewCapabilities.canViewWageEstimates) $
            renderRosterSettingsSection "bi-eye" "Display" (renderRosterDisplayPreferencesSection staffPanelWeekStartDate staffPanelCurrentRosterGroup.id staffPanelViewCapabilities staffPanelShowWageEstimates staffPanelShowRosterWarnings staffPanelHighlightOwnLiveShifts)}
        {when staffPanelViewCapabilities.canManageAssignmentFilter $
            renderRosterSettingsSection "bi-shield-check" "Prevent assignment" (renderRosterAssignmentFiltersSection staffPanelWeekStartDate staffPanelCurrentRosterGroup.id staffPanelAssignmentFilters)}
        {when (staffPanelViewCapabilities.canCopyRosterWeek || shouldShowRosterSortForm staffPanelRosterWeek staffPanelViewCapabilities) $
            renderRosterSettingsSection "bi-lightning-charge" "Week actions" (renderRosterWeekActions staffPanelRosterWeek staffPanelWeekOffset staffPanelWeekStartDate staffPanelCalendarRevision staffPanelCurrentRosterGroup.id staffPanelViewCapabilities)}
        {when (isJust staffPanelNotificationPanelData || shouldShowRosterExport staffPanelRosterWeek staffPanelViewCapabilities staffPanelRosterLayoutMode staffPanelViewMode) $
            renderRosterSettingsSection "bi-share" "Share roster" (renderRosterShareSection staffPanelRosterWeek staffPanelCurrentRosterGroup staffPanelWeekStartDate staffPanelCalendarRevision staffPanelNotificationPanelData staffPanelViewCapabilities staffPanelRosterLayoutMode staffPanelViewMode)}
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

renderRosterGroupSwitcher :: Day -> [RosterGroup] -> RosterGroup -> Html
renderRosterGroupSwitcher anchorDate rosterGroups currentRosterGroup = [hsx|
    <form class="mb-0" method="GET" action={rosterWindowBaseUrl anchorDate}>
        <label class="visually-hidden" for="roster-group-switch">Roster group</label>
        <input type="hidden" name={surfaceFieldNameFrom @Surface.AnchorDate fields} value={surfaceWireText @'WireDay anchorDate}/>
        <select id="roster-group-switch"
                class="form-select form-select-sm"
                name={surfaceFieldNameFrom @Surface.RosterGroupId fields}
                onchange="this.form.submit()">
            {forEach rosterGroups (renderRosterGroupSwitchOption currentRosterGroup.id)}
        </select>
    </form>
|]
  where
    fields :: ActionFields RosterAction.NavigateRosterWeekActionOperation
    fields =
        RosterAction.navigateRosterWeekActionFields
            anchorDate
            (unpackId currentRosterGroup.id)

renderRosterGroupSwitchOption :: Id RosterGroup -> RosterGroup -> Html
renderRosterGroupSwitchOption selectedRosterGroupId rosterGroup = [hsx|
    <option value={tshow rosterGroup.id} selected={rosterGroup.id == selectedRosterGroupId}>
        {rosterGroup.name}
    </option>
|]

renderRosterLayoutSection :: (?context :: ControllerContext) => Day -> Id RosterGroup -> RosterLayoutModeEnum -> RosterGridViewMode -> Html
renderRosterLayoutSection anchorDate rosterGroupId _selectedLayoutMode (RosterDayTimelineGridView _) = [hsx|
    <a class="btn btn-outline-secondary btn-sm w-100" href={rosterWindowUrl anchorDate rosterGroupId} data-turbolinks="false">Week grid</a>
|]
renderRosterLayoutSection _anchorDate _rosterGroupId selectedLayoutMode RosterWeekGridView = [hsx|
    <div class="btn-group w-100 roster-layout-mode-group" role="group" aria-label="Roster layout">
        {forEach rosterLayoutModes (renderRosterLayoutModeOption selectedLayoutMode)}
    </div>
|]

renderRosterLayoutModeOption :: RosterLayoutModeEnum -> RosterLayoutModeEnum -> Html
renderRosterLayoutModeOption selectedLayoutMode layoutMode =
    let inputId = "roster-layout-mode-" <> rosterLayoutModeValue layoutMode
        layoutValue = rosterLayoutModeValue layoutMode
        fields :: IntentFields RosterIntent.SetRosterLayoutModeIntentOperation
        fields = RosterIntent.setRosterLayoutModeIntentFields layoutMode
        inputHtml = [hsx|
            <input type="radio"
                   class="btn-check"
                   name={surfaceFieldNameFrom @Surface.RosterLayoutMode fields}
                   id={inputId}
                   value={layoutValue}
                   checked={selectedLayoutMode == layoutMode} />
        |]
     in [hsx|
        {SurfaceInteraction.withFrontendSurfaceActivationRef rosterLayoutModeActivationRef inputHtml}
        <label class="btn btn-outline-secondary btn-sm" for={inputId}>{rosterLayoutModeLabel layoutMode}</label>
    |]

renderRosterDisplayPreferencesSection :: (?context :: ControllerContext) => Day -> Id RosterGroup -> RosterViewCapabilities -> Bool -> Bool -> Bool -> Html
renderRosterDisplayPreferencesSection anchorDate rosterGroupId viewCapabilities showWageEstimates showRosterWarnings highlightOwnLiveShifts = [hsx|
    <div class="roster-settings-toggle-grid">
        {when viewCapabilities.canManageRosterWarnings (renderRosterWarningPreferenceForm anchorDate rosterGroupId showRosterWarnings)}
        {renderRosterWageEstimatePreferenceForm anchorDate rosterGroupId viewCapabilities showWageEstimates}
        {renderRosterOwnLiveShiftHighlightPreferenceForm anchorDate rosterGroupId highlightOwnLiveShifts}
    </div>
|]

renderRosterOwnLiveShiftHighlightPreferenceForm :: (?context :: ControllerContext) => Day -> Id RosterGroup -> Bool -> Html
renderRosterOwnLiveShiftHighlightPreferenceForm anchorDate rosterGroupId highlightOwnLiveShifts =
    renderFrontendSurfaceActionForm
        (RosterAction.toggleRosterOwnLiveShiftHighlightAction fields)
        (rosterWeekShellSyncRoute (rosterOwnLiveShiftHighlightPreferenceUrl anchorDate rosterGroupId))
            { actionRouteStandardUrl = Just (rosterOwnLiveShiftHighlightPreferenceUrl anchorDate rosterGroupId)
            , actionRouteExtraAttrs = [("class", "mb-0")]
            }
        [hsx|<div class="roster-display-toggle">{renderRosterOwnLiveShiftHighlightToggle fields highlightOwnLiveShifts}</div>|]
  where
    fields = RosterAction.toggleRosterOwnLiveShiftHighlightActionFields highlightOwnLiveShifts

renderRosterWarningPreferenceForm :: (?context :: ControllerContext) => Day -> Id RosterGroup -> Bool -> Html
renderRosterWarningPreferenceForm anchorDate rosterGroupId showRosterWarnings =
    renderFrontendSurfaceActionForm
        (RosterAction.toggleRosterWarningsAction fields)
        (rosterWeekShellSyncRoute (rosterWarningPreferenceUrl anchorDate rosterGroupId))
            { actionRouteStandardUrl = Just (rosterWarningPreferenceUrl anchorDate rosterGroupId)
            , actionRouteExtraAttrs = [("class", "mb-0")]
            }
        [hsx|<div class="roster-display-toggle">{renderRosterWarningToggle fields showRosterWarnings}</div>|]
  where
    fields = RosterAction.toggleRosterWarningsActionFields showRosterWarnings

renderRosterWageEstimatePreferenceForm :: (?context :: ControllerContext) => Day -> Id RosterGroup -> RosterViewCapabilities -> Bool -> Html
renderRosterWageEstimatePreferenceForm anchorDate rosterGroupId viewCapabilities showWageEstimates
    | not viewCapabilities.canViewWageEstimates = mempty
    | otherwise =
        renderFrontendSurfaceActionForm
            (RosterAction.toggleRosterWageEstimatesAction fields)
            (rosterWeekShellSyncRoute (rosterWageEstimatePreferenceUrl anchorDate rosterGroupId))
                { actionRouteStandardUrl = Just (rosterWageEstimatePreferenceUrl anchorDate rosterGroupId)
                , actionRouteExtraAttrs = [("class", "mb-0")]
                }
            [hsx|<div class="roster-display-toggle">{renderRosterWageEstimateToggle fields showWageEstimates}</div>|]
  where
    fields = RosterAction.toggleRosterWageEstimatesActionFields showWageEstimates

renderRosterOwnLiveShiftHighlightToggle :: ActionFields RosterAction.ToggleRosterOwnLiveShiftHighlightActionOperation -> Bool -> Html
renderRosterOwnLiveShiftHighlightToggle fields highlightOwnLiveShifts =
    renderAppToggleButton $
        ( defaultAppToggleStateButtonConfig
            "highlight-own-live-shifts"
            (surfaceToggleScalarField @Surface.HighlightOwnLiveShifts fields True False)
            highlightOwnLiveShifts
            [hsx|<span class="small">Own shifts highlighted</span>|]
            [hsx|<span class="small">Own shifts not highlighted</span>|]
        )
            { appToggleButtonClass = "btn-sm w-100 justify-content-start"
            , appToggleSubmitPolicy = ToggleSubmitImmediate
            }

renderRosterWarningToggle :: ActionFields RosterAction.ToggleRosterWarningsActionOperation -> Bool -> Html
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

renderRosterWageEstimateToggle :: ActionFields RosterAction.ToggleRosterWageEstimatesActionOperation -> Bool -> Html
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

renderRosterAssignmentFiltersSection :: (?context :: ControllerContext) => Day -> Id RosterGroup -> RosterAssignmentFilters -> Html
renderRosterAssignmentFiltersSection anchorDate rosterGroupId filters =
    renderFrontendSurfaceActionForm
        (RosterAction.toggleRosterAssignmentFiltersAction fields)
        (rosterWeekShellSyncRoute (rosterAssignmentFiltersUrl anchorDate rosterGroupId))
            { actionRouteStandardUrl = Just (rosterAssignmentFiltersUrl anchorDate rosterGroupId)
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

renderRosterWeekActions :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> Day -> Int -> Id RosterGroup -> RosterViewCapabilities -> Html
renderRosterWeekActions maybeRosterWeek weekOffset anchorDate calendarRevision rosterGroupId viewCapabilities = [hsx|
    <div class="roster-week-action-grid">
        {renderRosterSortForm maybeRosterWeek anchorDate calendarRevision rosterGroupId viewCapabilities}
        {when viewCapabilities.canCopyRosterWeek (renderCopyPreviousWeekForm anchorDate calendarRevision rosterGroupId)}
    </div>
|]

shouldShowRosterSortForm :: Maybe RosterWeek -> RosterViewCapabilities -> Bool
shouldShowRosterSortForm (Just rosterWeek) viewCapabilities = viewCapabilities.canManageRosterColumns && not rosterWeek.isLive
shouldShowRosterSortForm Nothing _ = False

renderRosterSortForm :: (?context :: ControllerContext) => Maybe RosterWeek -> Day -> Int -> Id RosterGroup -> RosterViewCapabilities -> Html
renderRosterSortForm (Just rosterWeek) anchorDate calendarRevision rosterGroupId viewCapabilities
    | shouldShowRosterSortForm (Just rosterWeek) viewCapabilities =
        renderFrontendSurfaceActionForm
            (RosterAction.sortRosterWeekAction (RosterAction.sortRosterWeekActionFields calendarRevision))
            (rosterWeekShellSyncRoute sortUrl)
                { actionRouteStandardUrl = Just sortUrl
                , actionRouteExtraAttrs = [("class", "mb-0 roster-week-action-form")]
                }
            [hsx|
                <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision (RosterAction.sortRosterWeekActionFields calendarRevision)} value={tshow calendarRevision} />
                <button type="submit" class="btn btn-outline-secondary btn-sm w-100 h-100 text-center roster-week-action-button">
                    <i class="bi bi-sort-down me-1" aria-hidden="true"></i>
                    Sort shifts
                </button>
            |]
  where
    sortUrl = appendQueryParams (pathTo SortRosterWeekAction) [("anchorDate", tshow anchorDate), ("rosterGroupId", tshow rosterGroupId)]
renderRosterSortForm _ _ _ _ _ = mempty

renderCopyPreviousWeekForm :: (?context :: ControllerContext) => Day -> Int -> Id RosterGroup -> Html
renderCopyPreviousWeekForm anchorDate calendarRevision rosterGroupId =
    renderFrontendSurfaceActionForm
        (RosterAction.copyRosterWeekAction (RosterAction.copyRosterWeekActionFields calendarRevision Nothing Nothing))
        (rosterWeekShellSyncRoute (rosterCopyWeekUrl (addDays (-7) anchorDate) anchorDate rosterGroupId))
            { actionRouteCustomHtmx =
                [ FrontendSurfaceCustomHtmxAttrs "copy-roster-week-custom-htmx" [("hx-confirm", "This will overwrite the current week with the previous week's roster. Continue?")]
                ]
            , actionRouteStandardUrl = Just (rosterCopyWeekUrl (addDays (-7) anchorDate) anchorDate rosterGroupId)
            , actionRouteExtraAttrs = [("class", "mb-0 roster-week-action-form")]
            }
        [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision (RosterAction.copyRosterWeekActionFields calendarRevision Nothing Nothing)} value={tshow calendarRevision} />
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
        && not (rosterLayoutModeIsDayColumns rosterLayoutMode)

renderRosterShareSection :: (?context :: ControllerContext) => Maybe RosterWeek -> RosterGroup -> Day -> Int -> Maybe RosterNotificationPanelData -> RosterViewCapabilities -> RosterLayoutModeEnum -> RosterGridViewMode -> Html
renderRosterShareSection maybeRosterWeek rosterGroup weekStartDate calendarRevision notificationPanelData viewCapabilities rosterLayoutMode viewMode = [hsx|
    <div class="d-grid gap-2">
        {renderRosterEmailAction rosterGroup.id weekStartDate calendarRevision notificationPanelData}
        {when (shouldShowRosterExport maybeRosterWeek viewCapabilities rosterLayoutMode viewMode) (renderRosterExportSection rosterGroup.name weekStartDate)}
    </div>
|]

renderRosterEmailAction :: (?context :: ControllerContext) => Id RosterGroup -> Day -> Int -> Maybe RosterNotificationPanelData -> Html
renderRosterEmailAction rosterGroupId windowStart calendarRevision (Just RosterNotificationPanelData { panelNotificationAudience = audience, panelLatestNotificationRun = latestRun })
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
            (RosterAction.showRosterNotificationConfirmationAction (RosterAction.showRosterNotificationConfirmationActionFields (unpackId rosterGroupId) windowStart windowEnd calendarRevision))
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
        actionUrl = pathTo ShowRosterNotificationConfirmationAction
        windowEnd = addDays 7 windowStart
renderRosterEmailAction _ _ _ _ = mempty

renderRosterExportSection :: Text -> Day -> Html
renderRosterExportSection rosterGroupName weekStartDate = [hsx|
    <div class="d-flex gap-2">
        {renderRosterExportButton RosterImageExportColour "Export colour PNG"}
        {renderRosterExportButton RosterImageExportPrint "Export print PNG"}
    </div>
|]
  where
    renderRosterExportButton :: RosterImageExportStyle -> Text -> Html
    renderRosterExportButton exportStyle label = [hsx|
        <button type="button"
                class="btn btn-outline-secondary btn-sm flex-fill roster-export-button"
                {...rosterPngImageExportTriggerAttrs exportStyle (rosterImageExportFilename exportStyle rosterGroupName weekStartDate)}>
            <i class="bi bi-download me-1" aria-hidden="true"></i>
            {label}
        </button>
    |]
