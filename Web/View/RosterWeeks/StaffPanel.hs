{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.StaffPanel
    ( renderrosterStaffPanelLiveFragment
    , renderrosterStaffPanelLiveFragmentOob
    , renderrosterStaffPanelLiveFragmentWithSwap
    , renderRosterStaffPanelPlaceholder
    ) where

import Application.Helper.FrontendContract.AppShell (OpenRosterStaffCreateDialog,
                                                     OpenRosterStaffEditDialog,
                                                     OpenTrialStaffInvitationDialog)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             applyAppShellActionAttrs,
                                                             renderAppShellActionHtmxControl)
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.LinkedHighlight as SurfaceLinkedHighlight
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Roster.StaffPanel (RosterStaffPanelSortKey (..),
                                                                      RosterStaffPanelTab (..),
                                                                      rosterStaffPanelSortControlAttrs,
                                                                      rosterStaffPanelSortRootAttrs,
                                                                      rosterStaffPanelSortRowAttrs,
                                                                      rosterStaffPanelTabAttrs)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            renderFrontendSurfaceActionForm)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Profiling (profileHtmlComponent, profileRenderCounter)
import Application.Helper.Staff (isAdoptableTrialStaff)
import Application.Helper.View (staffDisplayName)
import Data.List (sortBy)
import qualified Data.Text as Text
import Web.RosterWeeks.Dom (rosterStaffPanelFragmentClasses,
                            rosterStaffPanelFragmentId,
                            rosterStaffPanelSettingsPaneId,
                            rosterStaffPanelSettingsTabId,
                            rosterStaffPanelStaffPaneId,
                            rosterStaffPanelStaffTabId)
import Web.RosterWeeks.FrontendSurface (rosterStaffDragSourceRef,
                                        rosterStaffLinkedHighlight)
import Web.RosterWeeks.Types (RosterStaffPanelEntry (..),
                              RosterStaffPanelRenderModel (..),
                              RosterStaffPanelScope (..))
import Web.View.Prelude
import Web.View.RosterWeeks.SettingsPanel (renderRosterSettingsPanel)

renderrosterStaffPanelLiveFragment :: (?context :: ControllerContext) => RosterStaffPanelRenderModel -> Html
renderrosterStaffPanelLiveFragment =
    renderrosterStaffPanelLiveFragmentWithSwap Nothing

renderrosterStaffPanelLiveFragmentOob :: (?context :: ControllerContext) => RosterStaffPanelRenderModel -> Html
renderrosterStaffPanelLiveFragmentOob =
    renderrosterStaffPanelLiveFragmentWithSwap (Just "outerHTML")

renderrosterStaffPanelLiveFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterStaffPanelRenderModel -> Html
renderrosterStaffPanelLiveFragmentWithSwap maybeSwapOob panelModel =
    if currentUserIsManager
        then profileHtmlComponent "render.roster.staff_panel_fragment" [hsx|
            <div id={rosterStaffPanelFragmentId}
                 class={Text.unwords rosterStaffPanelFragmentClasses}
                 hx-swap-oob={maybeSwapOob}>
                {renderRosterStaffPanel panelModel}
            </div>
        |]
        else mempty

renderRosterStaffPanel :: (?context :: ControllerContext) => RosterStaffPanelRenderModel -> Html
renderRosterStaffPanel panelModel@RosterStaffPanelRenderModel { staffPanelWeekOffset, staffPanelCurrentRosterGroup, staffPanelRosterGroups, staffPanelScope, staffPanelEntries } = profileHtmlComponent "render.roster.staff_panel_component" [hsx|
    {profileRenderCounter "render.roster.staff_panel" 1}
    {profileRenderCounter "render.roster.staff_panel_entry" (length staffPanelEntries)}
    {renderRosterStaffPanelShell
        (renderRosterStaffPanelTabs staffPanelContent settingsPanelContent)}
|]
    where
        hasMultipleRosterGroups = length staffPanelRosterGroups > 1
        panelStaffMembers = map (.staff) staffPanelEntries
        renderedPanelStaff = sortRosterStaffPanelEntries panelStaffMembers staffPanelEntries
        staffPanelContent = [hsx|
            {renderRosterStaffPanelHeader staffPanelWeekOffset staffPanelCurrentRosterGroup.id hasMultipleRosterGroups staffPanelScope}
            {renderRosterStaffPanelTable panelStaffMembers staffPanelWeekOffset staffPanelCurrentRosterGroup.id renderedPanelStaff}
        |]
        settingsPanelContent = renderRosterSettingsPanel panelModel

renderRosterStaffPanelPlaceholder :: Bool -> Html
renderRosterStaffPanelPlaceholder hasMultipleRosterGroups =
    renderRosterStaffPanelShell $ renderRosterStaffPanelTabs
        [hsx|
            {renderRosterStaffPanelPlaceholderHeader hasMultipleRosterGroups}
            {renderRosterStaffPanelPlaceholderTable}
        |]
        mempty

renderRosterStaffPanelShell :: Html -> Html
renderRosterStaffPanelShell body = [hsx|
    <div class="app-panel roster-staff-panel">
        <div class="app-panel-body">
            {body}
        </div>
    </div>
|]

renderRosterStaffPanelTabs :: Html -> Html -> Html
renderRosterStaffPanelTabs staffContent settingsContent = [hsx|
    <div class="nav nav-pills roster-staff-panel-tabs" role="tablist" aria-label="Roster side panel">
        <button class="nav-link active roster-staff-panel-tab"
                id={rosterStaffPanelStaffTabId}
                type="button"
                role="tab"
                data-bs-toggle="tab"
                data-bs-target={"#" <> rosterStaffPanelStaffPaneId}
                aria-controls={rosterStaffPanelStaffPaneId}
                aria-selected="true"
                {...rosterStaffPanelTabAttrs RosterStaffTab}>
            <i class="bi bi-people" aria-hidden="true"></i>
            <span>Staff</span>
        </button>
        <button class="nav-link roster-staff-panel-tab"
                id={rosterStaffPanelSettingsTabId}
                type="button"
                role="tab"
                data-bs-toggle="tab"
                data-bs-target={"#" <> rosterStaffPanelSettingsPaneId}
                aria-controls={rosterStaffPanelSettingsPaneId}
                aria-selected="false"
                {...rosterStaffPanelTabAttrs RosterSettingsTab}>
            <i class="bi bi-sliders" aria-hidden="true"></i>
            <span>Settings</span>
        </button>
    </div>
    <div class="tab-content roster-staff-panel-tab-content">
        <div class="tab-pane fade show active roster-staff-panel-pane"
             id={rosterStaffPanelStaffPaneId}
             role="tabpanel"
             aria-labelledby={rosterStaffPanelStaffTabId}
             tabindex="0">
            {staffContent}
        </div>
        <div class="tab-pane fade roster-staff-panel-pane roster-staff-panel-settings-pane"
             id={rosterStaffPanelSettingsPaneId}
             role="tabpanel"
             aria-labelledby={rosterStaffPanelSettingsTabId}
             tabindex="0">
            {settingsContent}
        </div>
    </div>
|]

renderRosterStaffPanelHeader :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Bool -> RosterStaffPanelScope -> Html
renderRosterStaffPanelHeader weekOffset currentRosterGroupId hasMultipleRosterGroups panelScope = [hsx|
    <div class="roster-staff-panel-header">
        <div>
            <h2 class="h5 mb-0">Staff</h2>
        </div>
        <div class="d-flex flex-wrap align-items-center justify-content-end gap-2 roster-staff-panel-header-actions">
            {renderOpenRosterStaffCreateDialogButton weekOffset currentRosterGroupId}
            {when hasMultipleRosterGroups (renderStaffScopeToggle weekOffset currentRosterGroupId panelScope)}
        </div>
    </div>
|]

rosterStaffOverlayRoute :: Text -> AppShellActionRoute
rosterStaffOverlayRoute actionUrl =
    AppShellActionRoute
        { appShellActionRouteUrl = actionUrl
        , appShellActionRouteFields = []
        , appShellActionRouteCustomHtmx = []
        , appShellActionRouteStandardUrl = Nothing
        , appShellActionRouteExtraAttrs = []
        }

renderOpenRosterStaffCreateDialogButton :: Int -> Id RosterGroup -> Html
renderOpenRosterStaffCreateDialogButton weekOffset currentRosterGroupId =
    renderAppShellActionHtmxControl
        (appShellActionByMarker @OpenRosterStaffCreateDialog)
        (rosterStaffOverlayRoute (appendQueryParams (pathTo NewStaffAction) [("weekOffset", tshow weekOffset), ("rosterGroupId", tshow currentRosterGroupId)]))
        [hsx|<button type="button" class="btn btn-sm btn-outline-primary">Add trial staff</button>|]

renderRosterStaffPanelPlaceholderHeader :: Bool -> Html
renderRosterStaffPanelPlaceholderHeader hasMultipleRosterGroups = [hsx|
    <div class="roster-staff-panel-header" aria-hidden="true">
        <div>
            <h2 class="h5 mb-0 roster-staff-panel-placeholder-title">
                <span class="app-lazy-surface-bar app-lazy-surface-bar-title roster-staff-panel-placeholder-title-bar"></span>
            </h2>
        </div>
        <div class="d-flex flex-wrap align-items-center justify-content-end gap-2 roster-staff-panel-header-actions">
            <div class="app-lazy-surface-button-placeholder"></div>
            {when hasMultipleRosterGroups renderRosterStaffPanelTogglePlaceholder}
        </div>
    </div>
|]

renderRosterStaffPanelTogglePlaceholder :: Html
renderRosterStaffPanelTogglePlaceholder = [hsx|
    <div class="app-lazy-surface-toggle-placeholder"></div>
|]

data RosterStaffPanelColumn
    = RosterStaffNameColumn
    | RosterStaffRoleColumn
    | RosterStaffShiftsColumn
    | RosterStaffActionColumn
    deriving (Eq, Show)

rosterStaffPanelColumns :: [RosterStaffPanelColumn]
rosterStaffPanelColumns =
    [ RosterStaffNameColumn
    , RosterStaffRoleColumn
    , RosterStaffShiftsColumn
    , RosterStaffActionColumn
    ]

renderRosterStaffPanelTable :: [Staff] -> Int -> Id RosterGroup -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanelTable panelStaffMembers weekOffset currentRosterGroupId renderedPanelStaff = [hsx|
    <div class="roster-staff-panel-list">
        <table class="roster-staff-table" {...rosterStaffPanelSortRootAttrs}>
            <thead class="roster-staff-table-head">
                <tr>{forEach rosterStaffPanelColumns renderRosterStaffPanelHeaderCell}</tr>
            </thead>
            <tbody class="roster-staff-table-body">
                {forEach renderedPanelStaff (renderRosterStaffPanelEntry panelStaffMembers weekOffset currentRosterGroupId)}
            </tbody>
        </table>
    </div>
|]

renderRosterStaffPanelPlaceholderTable :: Html
renderRosterStaffPanelPlaceholderTable = [hsx|
    <div class="roster-staff-panel-list" aria-hidden="true">
        <table class="roster-staff-table">
            <thead class="roster-staff-table-head">
                <tr>{forEach rosterStaffPanelColumns renderRosterStaffPanelSkeletonHeaderCell}</tr>
            </thead>
            <tbody class="roster-staff-table-body">
                {forEach rosterStaffPanelSkeletonRows renderRosterStaffPanelSkeletonRow}
            </tbody>
        </table>
    </div>
|]

rosterStaffPanelSkeletonRows :: [Int]
rosterStaffPanelSkeletonRows = [1, 2, 3, 4, 5, 6]

renderRosterStaffPanelHeaderCell :: RosterStaffPanelColumn -> Html
renderRosterStaffPanelHeaderCell RosterStaffNameColumn = [hsx|
    <th scope="col" aria-sort="none">
        <button type="button" class="roster-staff-sort-button" {...rosterStaffPanelSortControlAttrs RosterStaffSortByName}>
            Name
        </button>
    </th>
|]
renderRosterStaffPanelHeaderCell RosterStaffRoleColumn = [hsx|
    <th scope="col" class="roster-staff-role-head" aria-sort="none">
        <button type="button" class="roster-staff-sort-button" {...rosterStaffPanelSortControlAttrs RosterStaffSortByRole}>
            Role
        </button>
    </th>
|]
renderRosterStaffPanelHeaderCell RosterStaffShiftsColumn = [hsx|
    <th scope="col" class="roster-staff-metric-head" aria-sort="none">
        <button type="button" class="roster-staff-sort-button roster-staff-sort-button-metric" {...rosterStaffPanelSortControlAttrs RosterStaffSortByShifts}>
            Shifts
        </button>
    </th>
|]
renderRosterStaffPanelHeaderCell RosterStaffActionColumn = [hsx|
    <th scope="col" class="roster-staff-action-head">
        <span class="visually-hidden">Locate shifts</span>
    </th>
|]

renderRosterStaffPanelSkeletonHeaderCell :: RosterStaffPanelColumn -> Html
renderRosterStaffPanelSkeletonHeaderCell column = [hsx|
    <th scope="col" class={rosterStaffPanelColumnHeaderClass column}>
        <div class={classes [("app-lazy-surface-bar", True), ("app-lazy-surface-cell-narrow", column == RosterStaffActionColumn)]}></div>
    </th>
|]

renderRosterStaffPanelSkeletonRow :: Int -> Html
renderRosterStaffPanelSkeletonRow rowIndex = [hsx|
    <tr class="roster-staff-panel-entry">
        {forEach rosterStaffPanelColumns (renderRosterStaffPanelSkeletonCell rowIndex)}
    </tr>
|]

renderRosterStaffPanelSkeletonCell :: Int -> RosterStaffPanelColumn -> Html
renderRosterStaffPanelSkeletonCell rowIndex column =
    case column of
        RosterStaffNameColumn -> [hsx|
            <th scope="row" class="roster-staff-cell roster-staff-name">
                <div class={classes [("app-lazy-surface-bar", True), ("app-lazy-surface-bar-short", rowIndex `mod` 3 == 0)]}></div>
            </th>
        |]
        RosterStaffRoleColumn -> [hsx|
            <td class="roster-staff-cell roster-staff-role">
                <div class="app-lazy-surface-bar app-lazy-surface-bar-muted"></div>
            </td>
        |]
        RosterStaffShiftsColumn -> [hsx|
            <td class="roster-staff-cell roster-staff-shifts">
                <div class="app-lazy-surface-bar app-lazy-surface-cell-narrow"></div>
            </td>
        |]
        RosterStaffActionColumn -> [hsx|
            <td class="roster-staff-cell roster-staff-action">
                <div class="app-lazy-surface-icon-placeholder roster-staff-locate-button-placeholder"></div>
            </td>
        |]

rosterStaffPanelColumnHeaderClass :: RosterStaffPanelColumn -> Text
rosterStaffPanelColumnHeaderClass RosterStaffNameColumn = ""
rosterStaffPanelColumnHeaderClass RosterStaffRoleColumn = "roster-staff-role-head"
rosterStaffPanelColumnHeaderClass RosterStaffShiftsColumn = "roster-staff-metric-head"
rosterStaffPanelColumnHeaderClass RosterStaffActionColumn = "roster-staff-action-head"

sortRosterStaffPanelEntries :: [Staff] -> [RosterStaffPanelEntry] -> [RosterStaffPanelEntry]
sortRosterStaffPanelEntries panelStaffMembers =
    sortBy \left right ->
        compare (sortName left) (sortName right)
            <> compare (get #id left.staff) (get #id right.staff)
    where
        sortName entry = Text.toCaseFold (staffDisplayName panelStaffMembers entry.staff)

renderStaffScopeToggle :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterStaffPanelScope -> Html
renderStaffScopeToggle weekOffset currentRosterGroupId panelScope =
    renderFrontendSurfaceActionForm
        (RosterAction.toggleRosterStaffScopeAction fields)
        FrontendSurfaceActionRoute
            { actionRouteUrl = actionUrl
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just actionUrl
            , actionRouteExtraAttrs = [("class", "mb-0 roster-staff-scope-toggle")]
            }
        [hsx|
            <input type="hidden" name="rosterGroupId" value={tshow currentRosterGroupId} />
            {renderStaffScopeToggleButton fields currentRosterGroupId panelScope}
        |]
  where
    actionUrl = pathTo (ShowRosterWeekStaffPanelFragmentAction weekOffset)
    fields = RosterAction.toggleRosterStaffScopeActionFields (if panelScope == RosterStaffPanelAllVenue then "all" else "group")

renderStaffScopeToggleButton :: SurfaceActionFields Surface.RosterSurface Surface.ToggleRosterStaffScope -> Id RosterGroup -> RosterStaffPanelScope -> Html
renderStaffScopeToggleButton fields currentRosterGroupId panelScope =
    renderAppToggleButton $
        ( defaultAppToggleButtonConfig
            (staffScopeToggleInputId currentRosterGroupId)
            (surfaceToggleScalarField @Surface.StaffScope fields "all" "group")
            (panelScope == RosterStaffPanelAllVenue)
            [hsx|<span class="small fw-semibold">Show all staff</span>|]
        )
            { appToggleButtonClass = "btn-sm"
            , appToggleRoleSwitch = True
            , appToggleSubmitPolicy = ToggleSubmitImmediate
            }

staffPanelTargetSelector :: Text
staffPanelTargetSelector = "#" <> rosterStaffPanelFragmentId

staffScopeToggleInputId :: Id RosterGroup -> Text
staffScopeToggleInputId rosterGroupId = "roster-staff-scope-toggle-" <> tshow rosterGroupId

renderRosterStaffPanelEntry :: [Staff] -> Int -> Id RosterGroup -> RosterStaffPanelEntry -> Html
renderRosterStaffPanelEntry panelStaffMembers weekOffset currentRosterGroupId entry =
    let
        staffDisplayLabel = staffDisplayName panelStaffMembers entry.staff
        staffRoleLabel = humanizeStaffRole entry.userRole
     in [hsx|
        {profileRenderCounter "render.roster.staff_panel_entry_render" 1}
        {renderRosterStaffPanelEntryRow weekOffset currentRosterGroupId staffDisplayLabel staffRoleLabel entry}
    |]

renderRosterStaffPanelEntryRow :: Int -> Id RosterGroup -> Text -> Text -> RosterStaffPanelEntry -> Html
renderRosterStaffPanelEntryRow weekOffset currentRosterGroupId staffDisplayLabel staffRoleLabel entry =
    let staffKey = "staff:" <> tshow entry.staff.id
     in SurfaceInteraction.withFrontendSurfaceSourceRef rosterStaffDragSourceRef staffKey $
        SurfaceLinkedHighlight.withFrontendSurfaceLinkedHighlightSource rosterStaffLinkedHighlight staffKey $
            applyAppShellActionAttrs
                (appShellActionByMarker @OpenRosterStaffEditDialog)
                (rosterStaffOverlayRoute (appendQueryParams (pathTo (EditStaffAction entry.staff.id)) [("weekOffset", tshow weekOffset), ("rosterGroupId", tshow currentRosterGroupId)]))
                [hsx|
                    <tr class="roster-staff-panel-entry"
                    {...rosterStaffPanelSortRowAttrs staffKey staffDisplayLabel staffRoleLabel entry.assignedShiftCount entry.staff.idealShiftsPerWeek}
                    aria-disabled="false"
                    role="button"
                    tabindex="0">
                    {forEach rosterStaffPanelColumns (renderRosterStaffPanelEntryCell weekOffset currentRosterGroupId staffDisplayLabel staffRoleLabel entry)}
                </tr>
            |]

renderRosterStaffPanelEntryCell :: Int -> Id RosterGroup -> Text -> Text -> RosterStaffPanelEntry -> RosterStaffPanelColumn -> Html
renderRosterStaffPanelEntryCell weekOffset currentRosterGroupId staffDisplayLabel _ entry RosterStaffNameColumn = [hsx|
    <th scope="row" class="roster-staff-cell roster-staff-name">
        <div class="roster-staff-name-primary d-inline-flex align-items-center gap-2">
            <span>{staffDisplayLabel}</span>
            {renderStaffPayConfigurationWarning entry}
            {renderTrialStaffInviteButton weekOffset currentRosterGroupId staffDisplayLabel entry}
        </div>
    </th>
|]
renderRosterStaffPanelEntryCell _ _ _ staffRoleLabel _ RosterStaffRoleColumn = [hsx|
    <td class="roster-staff-cell roster-staff-role">{staffRoleLabel}</td>
|]
renderRosterStaffPanelEntryCell _ _ _ _ entry RosterStaffShiftsColumn = [hsx|
    <td class="roster-staff-cell roster-staff-shifts">{renderShiftSummary entry}</td>
|]
renderRosterStaffPanelEntryCell _ _ staffDisplayLabel _ entry RosterStaffActionColumn =
    let locateButton =
            SurfaceLinkedHighlight.withFrontendSurfaceLinkedHighlightPin rosterStaffLinkedHighlight ("staff:" <> tshow entry.staff.id) [hsx|
                <button type="button"
                        class="btn btn-sm btn-outline-secondary app-icon-button roster-staff-locate-button"
                        aria-label={"Locate shifts for " <> staffDisplayLabel}
                        aria-pressed="false">
                    <svg aria-hidden="true" viewBox="0 0 24 24" width="16" height="16">
                        <path d="M12 5.25c-4.55 0-8.2 3.95-9.55 6.15a1.15 1.15 0 0 0 0 1.2c1.35 2.2 5 6.15 9.55 6.15s8.2-3.95 9.55-6.15a1.15 1.15 0 0 0 0-1.2c-1.35-2.2-5-6.15-9.55-6.15Zm0 11a4.25 4.25 0 1 1 0-8.5 4.25 4.25 0 0 1 0 8.5Zm0-1.75a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z" fill="currentColor"></path>
                    </svg>
                </button>
            |]
     in [hsx|
        <td class="roster-staff-cell roster-staff-action">{locateButton}</td>
    |]

renderStaffPayConfigurationWarning :: (?context :: ControllerContext) => RosterStaffPanelEntry -> Html
renderStaffPayConfigurationWarning entry
    | not currentUserIsManager || not entry.staffPayConfigurationRequired = mempty
    | otherwise = [hsx|<span class="text-warning small" role="img" tabindex="0" title={warningText} aria-label={warningText}>(!)</span>|]
  where
    warningText :: Text
    warningText = "Pay configuration required. A venue admin must choose a default pay rate or “No Timesheets (roster only).”"

renderTrialStaffInviteButton :: Int -> Id RosterGroup -> Text -> RosterStaffPanelEntry -> Html
renderTrialStaffInviteButton weekOffset currentRosterGroupId staffDisplayLabel entry
    | not (isAdoptableTrialStaff entry.staff) = mempty
    | otherwise =
        renderAppShellActionHtmxControl
            (appShellActionByMarker @OpenTrialStaffInvitationDialog)
            (rosterStaffOverlayRoute (appendQueryParams (pathTo (NewTrialStaffInvitationAction entry.staff.id)) [("weekOffset", tshow weekOffset), ("rosterGroupId", tshow currentRosterGroupId)]))
                { appShellActionRouteExtraAttrs = [("hx-trigger", "click consume")]
                }
            [hsx|
                <button class="btn btn-sm btn-outline-secondary app-icon-button roster-staff-invite-button"
                        type="button"
                        title={"Invite " <> staffDisplayLabel}
                        aria-label={"Invite " <> staffDisplayLabel}>
                    <i class="bi bi-envelope" aria-hidden="true"></i>
                    <span class="visually-hidden">Invite {staffDisplayLabel}</span>
                </button>
            |]

humanizeStaffRole :: Text -> Text
humanizeStaffRole "venue_admin" = "Venue Admin"
humanizeStaffRole "venue_owner" = "Venue Owner"
humanizeStaffRole "manager"     = "Manager"
humanizeStaffRole "supervisor"  = "Supervisor"
humanizeStaffRole "worker"      = "Worker"
humanizeStaffRole "trial"       = "TRIAL"
humanizeStaffRole other         = Text.toTitle (Text.replace "_" " " other)

renderShiftSummary :: RosterStaffPanelEntry -> Html
renderShiftSummary entry = [hsx|
    <span class="roster-staff-shifts-actual">{tshow entry.assignedShiftCount}</span>
    <span class="roster-staff-shifts-ideal">({tshow entry.staff.idealShiftsPerWeek})</span>
|]
