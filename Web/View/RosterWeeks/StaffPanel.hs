{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.StaffPanel
    ( renderrosterStaffPanelLiveFragment
    , renderrosterStaffPanelLiveFragmentWithSwap
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
import Application.Helper.FrontendContract.Surface.Roster (RosterStaffScopeValue (..))
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Roster.SidePanel (rosterSidePanelRenderAttrs)
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
import Application.VenueRole (parseVenueRole, venueRoleLabel)
import Data.List (sortBy)
import qualified Data.Text as Text
import Web.RosterWeeks.Dom (rosterStaffPanelFragmentClasses,
                            rosterStaffPanelFragmentId,
                            rosterStaffPanelSettingsPaneId,
                            rosterStaffPanelSettingsTabId,
                            rosterStaffPanelStaffPaneId,
                            rosterStaffPanelStaffTabId,
                            rosterStaffPanelTemplatesPaneId,
                            rosterStaffPanelTemplatesTabId)
import Web.RosterWeeks.FrontendSurface (rosterStaffDragSourceRef,
                                        rosterStaffLinkedHighlight)
import Web.RosterWeeks.Paths (rosterWeekStaffPanelFragmentUrl)
import Web.RosterWeeks.Types (RosterStaffPanelEntry (..),
                              RosterStaffPanelRenderModel (..),
                              RosterStaffPanelScope (..))
import Web.View.Prelude
import Web.View.RosterWeeks.SettingsPanel (renderRosterSettingsPanel)
import Web.View.RosterWeeks.TemplatePanel (renderRosterTemplateLibraryFragment)

renderrosterStaffPanelLiveFragment :: (?context :: ControllerContext) => RosterStaffPanelRenderModel -> Html
renderrosterStaffPanelLiveFragment =
    renderrosterStaffPanelLiveFragmentWithSwap Nothing


renderrosterStaffPanelLiveFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> RosterStaffPanelRenderModel -> Html
renderrosterStaffPanelLiveFragmentWithSwap maybeSwapOob panelModel =
    if currentUserIsManager
        then profileHtmlComponent "render.roster.staff_panel_fragment" $
            renderSidePanelPanelRegion rosterSidePanelRenderAttrs SidePanelRegionConfig
                { sidePanelRegionId = Just rosterStaffPanelFragmentId
                , sidePanelRegionClass = Text.unwords rosterStaffPanelFragmentClasses
                , sidePanelRegionExtraAttrs = maybe [] (\swap -> [("hx-swap-oob", swap)]) maybeSwapOob
                }
                (renderRosterStaffPanel panelModel)
        else mempty

renderRosterStaffPanel :: (?context :: ControllerContext) => RosterStaffPanelRenderModel -> Html
renderRosterStaffPanel panelModel@RosterStaffPanelRenderModel { staffPanelCurrentRosterGroup, staffPanelRosterGroups, staffPanelScope, staffPanelEntries } = profileHtmlComponent "render.roster.staff_panel_component" [hsx|
    {profileRenderCounter "render.roster.staff_panel" 1}
    {profileRenderCounter "render.roster.staff_panel_entry" (length staffPanelEntries)}
    {renderRosterStaffPanelShell
        (renderRosterStaffPanelTabs (isJust templatePanelContent) staffPanelContent (fromMaybe mempty templatePanelContent) settingsPanelContent)}
|]
    where
        hasMultipleRosterGroups = length staffPanelRosterGroups > 1
        panelStaffMembers = map (.staff) staffPanelEntries
        renderedPanelStaff = sortRosterStaffPanelEntries panelStaffMembers staffPanelEntries
        staffPanelContent = [hsx|
            {renderRosterStaffPanelHeader panelModel.staffPanelWeekStartDate staffPanelCurrentRosterGroup.id hasMultipleRosterGroups staffPanelScope}
            {renderRosterStaffPanelTable panelStaffMembers panelModel.staffPanelWeekStartDate staffPanelCurrentRosterGroup.id renderedPanelStaff}
        |]
        templatePanelContent = do
            templateUserId <- panelModel.staffPanelTemplateUserId
            templateLibrary <- panelModel.staffPanelTemplateLibrary
            pure (renderRosterTemplateLibraryFragment templateUserId panelModel.staffPanelWeekStartDate panelModel.staffPanelCalendarRevision staffPanelCurrentRosterGroup panelModel.staffPanelRosterWeek templateLibrary)
        settingsPanelContent = renderRosterSettingsPanel panelModel


renderRosterStaffPanelShell :: Html -> Html
renderRosterStaffPanelShell =
    renderSidePanelCard SidePanelCardConfig
        { sidePanelCardClass = "roster-staff-panel"
        }

renderRosterStaffPanelTabs :: Bool -> Html -> Html -> Html -> Html
renderRosterStaffPanelTabs showTemplates staffContent templateContent settingsContent = [hsx|
    {renderSidePanelTabs "Roster side panel" tabs}
    <div class="tab-content app-side-panel-tab-content roster-staff-panel-tab-content">
        <div class="tab-pane show active app-side-panel-pane roster-staff-panel-pane"
             id={rosterStaffPanelStaffPaneId}
             role="tabpanel"
             aria-labelledby={rosterStaffPanelStaffTabId}
             tabindex="0">
            {staffContent}
        </div>
        {when showTemplates (renderRosterTemplatesPane templateContent)}
        <div class="tab-pane app-side-panel-pane app-side-panel-settings-pane roster-staff-panel-pane roster-staff-panel-settings-pane"
             id={rosterStaffPanelSettingsPaneId}
             role="tabpanel"
             aria-labelledby={rosterStaffPanelSettingsTabId}
             tabindex="0">
            {settingsContent}
        </div>
    </div>
|]
  where
    tabs =
        [ SidePanelTabConfig rosterStaffPanelStaffTabId rosterStaffPanelStaffPaneId "Staff" "bi bi-people" True "roster-staff-panel-tab" (rosterStaffPanelTabAttrs RosterStaffTab)
        ]
            <> [SidePanelTabConfig rosterStaffPanelTemplatesTabId rosterStaffPanelTemplatesPaneId "Templates" "bi bi-collection" False "roster-staff-panel-tab" (rosterStaffPanelTabAttrs RosterTemplatesTab) | showTemplates]
            <> [SidePanelTabConfig rosterStaffPanelSettingsTabId rosterStaffPanelSettingsPaneId "Settings" "bi bi-sliders" False "roster-staff-panel-tab" (rosterStaffPanelTabAttrs RosterSettingsTab)]

renderRosterTemplatesPane :: Html -> Html
renderRosterTemplatesPane templateContent = [hsx|
    <div class="tab-pane app-side-panel-pane roster-staff-panel-pane roster-template-panel-pane"
         id={rosterStaffPanelTemplatesPaneId}
         role="tabpanel"
         aria-labelledby={rosterStaffPanelTemplatesTabId}
         tabindex="0">
        {templateContent}
    </div>
|]

renderRosterStaffPanelHeader :: (?context :: ControllerContext) => Day -> Id RosterGroup -> Bool -> RosterStaffPanelScope -> Html
renderRosterStaffPanelHeader anchorDate currentRosterGroupId hasMultipleRosterGroups panelScope = [hsx|
    <div class="app-side-panel-content-header roster-staff-panel-header">
        <div>
            <h2 class="h5 mb-0">Staff</h2>
        </div>
        <div class="app-side-panel-content-header-actions roster-staff-panel-header-actions">
            {renderOpenRosterStaffCreateDialogButton anchorDate currentRosterGroupId}
            {when hasMultipleRosterGroups (renderStaffScopeToggle anchorDate currentRosterGroupId panelScope)}
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

renderOpenRosterStaffCreateDialogButton :: Day -> Id RosterGroup -> Html
renderOpenRosterStaffCreateDialogButton anchorDate currentRosterGroupId =
    renderAppShellActionHtmxControl
        (appShellActionByMarker @OpenRosterStaffCreateDialog)
        (rosterStaffOverlayRoute (appendQueryParams (pathTo NewStaffAction) [("anchorDate", tshow anchorDate), ("rosterGroupId", tshow currentRosterGroupId)]))
        [hsx|<button type="button" class="btn btn-sm btn-outline-primary">Add trial staff</button>|]



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

renderRosterStaffPanelTable :: [Staff] -> Day -> Id RosterGroup -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanelTable panelStaffMembers anchorDate currentRosterGroupId renderedPanelStaff = [hsx|
    <div class="app-side-panel-table-list roster-staff-panel-list">
        <table class="app-side-panel-table roster-staff-table" {...rosterStaffPanelSortRootAttrs}>
            <thead class="app-side-panel-table-head roster-staff-table-head">
                <tr>{forEach rosterStaffPanelColumns renderRosterStaffPanelHeaderCell}</tr>
            </thead>
            <tbody class="app-side-panel-table-body roster-staff-table-body">
                {forEach renderedPanelStaff (renderRosterStaffPanelEntry panelStaffMembers anchorDate currentRosterGroupId)}
            </tbody>
        </table>
    </div>
|]



renderRosterStaffPanelHeaderCell :: RosterStaffPanelColumn -> Html
renderRosterStaffPanelHeaderCell RosterStaffNameColumn = [hsx|
    <th scope="col" aria-sort="none">
        <button type="button" class="app-side-panel-sort-button roster-staff-sort-button" {...rosterStaffPanelSortControlAttrs RosterStaffSortByName}>
            Name
        </button>
    </th>
|]
renderRosterStaffPanelHeaderCell RosterStaffRoleColumn = [hsx|
    <th scope="col" class="app-side-panel-role-head roster-staff-role-head" aria-sort="none">
        <button type="button" class="app-side-panel-sort-button roster-staff-sort-button" {...rosterStaffPanelSortControlAttrs RosterStaffSortByRole}>
            Role
        </button>
    </th>
|]
renderRosterStaffPanelHeaderCell RosterStaffShiftsColumn = [hsx|
    <th scope="col" class="app-side-panel-metric-head roster-staff-metric-head" aria-sort="none">
        <button type="button" class="app-side-panel-sort-button app-side-panel-sort-button-metric roster-staff-sort-button roster-staff-sort-button-metric" {...rosterStaffPanelSortControlAttrs RosterStaffSortByShifts}>
            Shifts
        </button>
    </th>
|]
renderRosterStaffPanelHeaderCell RosterStaffActionColumn = [hsx|
    <th scope="col" class="app-side-panel-action-head roster-staff-action-head">
        <span class="visually-hidden">Locate shifts</span>
    </th>
|]





sortRosterStaffPanelEntries :: [Staff] -> [RosterStaffPanelEntry] -> [RosterStaffPanelEntry]
sortRosterStaffPanelEntries panelStaffMembers =
    sortBy \left right ->
        compare (sortName left) (sortName right)
            <> compare (get #id left.staff) (get #id right.staff)
    where
        sortName entry = Text.toCaseFold (staffDisplayName panelStaffMembers entry.staff)

renderStaffScopeToggle :: (?context :: ControllerContext) => Day -> Id RosterGroup -> RosterStaffPanelScope -> Html
renderStaffScopeToggle anchorDate currentRosterGroupId panelScope =
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
    actionUrl = rosterWeekStaffPanelFragmentUrl anchorDate currentRosterGroupId
    fields = RosterAction.toggleRosterStaffScopeActionFields (if panelScope == RosterStaffPanelAllVenue then RosterStaffAllVenue else RosterStaffCurrentGroup)

renderStaffScopeToggleButton :: ActionFields RosterAction.ToggleRosterStaffScopeActionOperation -> Id RosterGroup -> RosterStaffPanelScope -> Html
renderStaffScopeToggleButton fields currentRosterGroupId panelScope =
    renderAppToggleButton $
        ( defaultAppToggleButtonConfig
            (staffScopeToggleInputId currentRosterGroupId)
            (surfaceToggleScalarField @Surface.StaffScope fields RosterStaffAllVenue RosterStaffCurrentGroup)
            (panelScope == RosterStaffPanelAllVenue)
            [hsx|<span class="small fw-semibold">Show all staff</span>|]
        )
            { appToggleButtonClass = "btn-sm"
            , appToggleRoleSwitch = True
            , appToggleSubmitPolicy = ToggleSubmitImmediate
            }


staffScopeToggleInputId :: Id RosterGroup -> Text
staffScopeToggleInputId rosterGroupId = "roster-staff-scope-toggle-" <> tshow rosterGroupId

renderRosterStaffPanelEntry :: [Staff] -> Day -> Id RosterGroup -> RosterStaffPanelEntry -> Html
renderRosterStaffPanelEntry panelStaffMembers anchorDate currentRosterGroupId entry =
    let
        staffDisplayLabel = staffDisplayName panelStaffMembers entry.staff
        staffRoleLabel = humanizeStaffRole entry.userRole
     in [hsx|
        {profileRenderCounter "render.roster.staff_panel_entry_render" 1}
        {renderRosterStaffPanelEntryRow anchorDate currentRosterGroupId staffDisplayLabel staffRoleLabel entry}
    |]

renderRosterStaffPanelEntryRow :: Day -> Id RosterGroup -> Text -> Text -> RosterStaffPanelEntry -> Html
renderRosterStaffPanelEntryRow anchorDate currentRosterGroupId staffDisplayLabel staffRoleLabel entry =
    let staffKey = "staff:" <> tshow entry.staff.id
     in SurfaceInteraction.withFrontendSurfaceSourceRef rosterStaffDragSourceRef staffKey $
        SurfaceLinkedHighlight.withFrontendSurfaceLinkedHighlightSource rosterStaffLinkedHighlight staffKey $
            applyAppShellActionAttrs
                (appShellActionByMarker @OpenRosterStaffEditDialog)
                (rosterStaffOverlayRoute (appendQueryParams (pathTo (EditStaffAction entry.staff.id)) [("anchorDate", tshow anchorDate), ("rosterGroupId", tshow currentRosterGroupId)]))
                [hsx|
                    <tr class="app-side-panel-entry roster-staff-panel-entry"
                    {...rosterStaffPanelSortRowAttrs staffKey staffDisplayLabel staffRoleLabel entry.assignedShiftCount entry.staff.idealShiftsPerWeek}
                    aria-disabled="false"
                    role="button"
                    tabindex="0">
                    {forEach rosterStaffPanelColumns (renderRosterStaffPanelEntryCell anchorDate currentRosterGroupId staffDisplayLabel staffRoleLabel entry)}
                </tr>
            |]

renderRosterStaffPanelEntryCell :: Day -> Id RosterGroup -> Text -> Text -> RosterStaffPanelEntry -> RosterStaffPanelColumn -> Html
renderRosterStaffPanelEntryCell anchorDate currentRosterGroupId staffDisplayLabel _ entry RosterStaffNameColumn = [hsx|
    <th scope="row" class="app-side-panel-cell app-side-panel-name roster-staff-cell roster-staff-name">
        <div class="app-side-panel-name-primary roster-staff-name-primary d-inline-flex align-items-center gap-2">
            <span>{staffDisplayLabel}</span>
            {renderStaffPayConfigurationWarning entry}
            {renderTrialStaffInviteButton anchorDate currentRosterGroupId staffDisplayLabel entry}
        </div>
    </th>
|]
renderRosterStaffPanelEntryCell _ _ _ staffRoleLabel _ RosterStaffRoleColumn = [hsx|
    <td class="app-side-panel-cell app-side-panel-role roster-staff-cell roster-staff-role">{staffRoleLabel}</td>
|]
renderRosterStaffPanelEntryCell _ _ _ _ entry RosterStaffShiftsColumn = [hsx|
    <td class="app-side-panel-cell app-side-panel-metric roster-staff-cell roster-staff-shifts">{renderShiftSummary entry}</td>
|]
renderRosterStaffPanelEntryCell _ _ staffDisplayLabel _ entry RosterStaffActionColumn =
    let locateButton =
            SurfaceLinkedHighlight.withFrontendSurfaceLinkedHighlightPin rosterStaffLinkedHighlight ("staff:" <> tshow entry.staff.id) [hsx|
                <button type="button"
                        class="btn btn-sm btn-outline-secondary app-icon-button app-side-panel-locate-button roster-staff-locate-button"
                        aria-label={"Locate shifts for " <> staffDisplayLabel}
                        aria-pressed="false">
                    {renderSidePanelLocateIcon}
                </button>
            |]
     in [hsx|
        <td class="app-side-panel-cell app-side-panel-action roster-staff-cell roster-staff-action">{locateButton}</td>
    |]

renderStaffPayConfigurationWarning :: (?context :: ControllerContext) => RosterStaffPanelEntry -> Html
renderStaffPayConfigurationWarning entry
    | not currentUserIsManager || not entry.staffPayConfigurationRequired = mempty
    | otherwise = [hsx|<span class="text-warning small" role="img" tabindex="0" title={warningText} aria-label={warningText}>(!)</span>|]
  where
    warningText :: Text
    warningText = "Pay configuration required. A venue admin must choose a default pay rate or “No Timesheets (roster only).”"

renderTrialStaffInviteButton :: Day -> Id RosterGroup -> Text -> RosterStaffPanelEntry -> Html
renderTrialStaffInviteButton anchorDate currentRosterGroupId staffDisplayLabel entry
    | not (isAdoptableTrialStaff entry.staff) = mempty
    | otherwise =
        renderAppShellActionHtmxControl
            (appShellActionByMarker @OpenTrialStaffInvitationDialog)
            (rosterStaffOverlayRoute (appendQueryParams (pathTo (NewTrialStaffInvitationAction entry.staff.id)) [("anchorDate", tshow anchorDate), ("rosterGroupId", tshow currentRosterGroupId)]))
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
humanizeStaffRole "trial" = "TRIAL"
humanizeStaffRole value =
    maybe (Text.toTitle (Text.replace "_" " " value)) venueRoleLabel (parseVenueRole value)

renderShiftSummary :: RosterStaffPanelEntry -> Html
renderShiftSummary entry = [hsx|
    <span class="app-side-panel-count roster-staff-shifts-actual">{tshow entry.assignedShiftCount}</span>
    <span class="app-side-panel-count app-side-panel-count-secondary roster-staff-shifts-ideal">({tshow entry.staff.idealShiftsPerWeek})</span>
|]
