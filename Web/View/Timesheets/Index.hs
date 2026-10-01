{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.View.Timesheets.Index where

import Application.Helper.Controller (currentUserIsSuperAdmin,
                                      hasManagementMode, isWithinEditWindow,
                                      managerModePreferenceEnabled,
                                      managerModeToggleEnabled,
                                      managerModeToggleVisible)
import Application.Helper.FrontendContract.AppShell (EditTimesheetEntryDialog,
                                                     OpenRosterStaffEditDialog,
                                                     OpenTimesheetEntryDialog,
                                                     OpenTimesheetFiltersDialog)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionAttrs,
                                                             appShellActionByMarker,
                                                             defaultAppShellActionRoute,
                                                             renderAppShellActionLink)
import Application.Helper.FrontendContract.HorizontalScroll.Runtime
import Application.Helper.FrontendContract.Overlay.Runtime (dialogPointerDismissBlurAttrs)
import Application.Helper.FrontendContract.Surface.DSL (WireType (WireDay))
import qualified Application.Helper.FrontendContract.Surface.LinkedHighlight as SurfaceLinkedHighlight
import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceAction)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            SurfaceImpl,
                                                            defaultFrontendSurfaceActionRoute,
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceActionFormWithHiddenFields,
                                                            renderFrontendSurfaceActionLink,
                                                            renderFrontendSurfaceMount)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import Application.Helper.FrontendContract.Surface.Timesheets.SidePanel (timesheetSidePanelRenderAttrs)
import Application.Helper.FrontendContract.Surface.Timesheets.StaffPanel (TimesheetSidePanelTab (..),
                                                                          TimesheetStaffPanelSortKey (..),
                                                                          timesheetSidePanelTabAttrs,
                                                                          timesheetStaffPanelSortControlAttrs,
                                                                          timesheetStaffPanelSortRootAttrs,
                                                                          timesheetStaffPanelSortRowAttrs)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.RosterWagePrediction (formatMoneyAmount)
import Application.Helper.View.FilterSelection
import Application.VenueRole (parseVenueRole, venueRoleLabel)
import Application.VenueTime.Model
import Data.Fixed (Pico)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Web.Timesheets.Filters (TimesheetViewFilters (..),
                               activeTimesheetFilterCount,
                               emptyTimesheetViewFilters)
import Web.Timesheets.FrontendSurface (timesheetStaffCardsLinkedHighlight)
import Web.Timesheets.Paths (editTimesheetEntryUrl, newTimesheetEntryUrl,
                             timesheetWindowUrlWithFilters,
                             withTimesheetFilters)
import Web.Timesheets.WageEstimates
import Web.View.Prelude

data TimesheetStaffPanelEntry = TimesheetStaffPanelEntry
    { panelStaff         :: !Staff
    , panelStaffRole     :: !Text
    , panelEntryCount    :: !Int
    , panelApprovedCount :: !Int
    }

data IndexView = IndexView
    { entries                  :: [TimesheetEntry]
    , timingByEntryId          :: Map.Map UUID (Either TimesheetIntegrityError ValidatedTimesheetTiming)
    , staffMembers             :: [Staff]
    , shiftTypes               :: [ShiftType]
    , today                    :: Day
    , editWindowDays           :: Int
    , weekStartDate            :: Day
    , weekEndDate              :: Day
    , calendarRevision         :: Int
    , hideApproved             :: Bool
    , timesheetWageDisplayMode   :: WageDisplayModeEnum
    , wageEstimates            :: Maybe TimesheetWageEstimates
    , rosterGroups             :: [RosterGroup]
    , rosterGroupLabels        :: [RosterGroup]
    , viewFilters              :: TimesheetViewFilters
    , currentViewerStaffId     :: Maybe UUID
    , staffPanelEntries        :: [TimesheetStaffPanelEntry]
    , frontendSurfaceImpl      :: Maybe (SurfaceImpl Surface.TimesheetsSurface)
    }

timesheetsActionRoute :: Text -> FrontendSurfaceActionRoute
timesheetsActionRoute actionUrl =
    (defaultFrontendSurfaceActionRoute (actionUrl))

data TimesheetDayRenderModel = TimesheetDayRenderModel
    { dayEntries             :: [TimesheetEntry]
    , dayTimingByEntryId     :: Map.Map UUID (Either TimesheetIntegrityError ValidatedTimesheetTiming)
    , dayStaffMembers        :: [Staff]
    , dayShiftTypes          :: [ShiftType]
    , dayRosterGroups        :: [RosterGroup]
    , dayToday               :: Day
    , dayEditWindowDays      :: Int
    , dayWeekStartDate       :: Day
    , dayCalendarRevision    :: Int
    , dayViewFilters         :: TimesheetViewFilters
    , dayWageEstimates       :: Maybe TimesheetWageEstimates
    , dayOffset              :: Int
    }

timesheetWeekShellId :: Text
timesheetWeekShellId = surfaceDomTokenValue @Surface.TimesheetsSurface @Surface.TimesheetWeekShell

timesheetWeekToolbarId :: Text
timesheetWeekToolbarId = surfaceFragmentTargetId @Surface.TimesheetsSurface @Surface.TimesheetToolbar noSurfaceFields

timesheetDayColumnsId :: Text
timesheetDayColumnsId = surfaceFragmentTargetId @Surface.TimesheetsSurface @Surface.TimesheetDayColumns noSurfaceFields

instance View IndexView where
    html = renderTimesheetWeekShell

renderTimesheetWeekShell :: IndexView -> Html
renderTimesheetWeekShell view@IndexView { .. } =
    let mainPanel =
            renderAppPanel AppPanelConfig
                { appPanelTitle = Nothing
                , appPanelDescription = Nothing
                , appPanelHasActions = False
                , appPanelActions = mempty
                , appPanelHasCustomHeader = True
                , appPanelCustomHeader = renderTimesheetWeekToolbar view
                , appPanelClass = "overflow-hidden"
                , appPanelBodyClass = ""
                , appPanelBody = [hsx|
                    <div class="timesheet-week-frame app-horizontal-frame"
                         data-timesheet-layout="day_columns"
                         {...horizontalSnapAttrs (HorizontalSnapNearestItem ".timesheet-day-panel")}
                         {...horizontalDragAttrs (HorizontalDragConfig Nothing)}>
                        {renderTimesheetDayColumns view}
                    </div>
                |]
                }
        mainRegion =
            renderSidePanelMainRegion timesheetSidePanelRenderAttrs SidePanelRegionConfig
                { sidePanelRegionId = Just "timesheet-main-region"
                , sidePanelRegionClass = "col-12 col-xl-8 col-xxl-9 timesheet-layout-main"
                , sidePanelRegionExtraAttrs = []
                }
                mainPanel
        sidePanelLayout =
            renderSidePanelLayout timesheetSidePanelRenderAttrs SidePanelRegionConfig
                { sidePanelRegionId = Just "timesheet-side-panel-layout"
                , sidePanelRegionClass = "row g-4 align-items-start timesheet-side-panel-layout"
                , sidePanelRegionExtraAttrs = []
                }
                [hsx|
                    {mainRegion}
                    {renderTimesheetSidePanel view}
                |]
        page = renderAppPage (AppPageConfig
            { appPageTitle = "Timesheets"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageHelpTopic = Just (PageHelpTopicId "timesheets")
            , appPageWidthClass = ""
            , appPageBody = sidePanelLayout
            })
        pageWithFrontendSurface =
            case frontendSurfaceImpl of
                Nothing   -> page
                Just impl -> renderFrontendSurfaceMount impl page
     in [hsx|
    <section id={timesheetWeekShellId}
             hx-history-elt="true">
        {pageWithFrontendSurface}
    </section>
|]

renderTimesheetWeekToolbar :: (?context :: ControllerContext) => IndexView -> Html
renderTimesheetWeekToolbar =
    renderTimesheetWeekToolbarWithSwap Nothing

renderTimesheetWeekToolbarWithSwap :: (?context :: ControllerContext) => Maybe Text -> IndexView -> Html
renderTimesheetWeekToolbarWithSwap maybeSwapOob IndexView { weekStartDate, today, wageEstimates, viewFilters } = [hsx|
    <div id={timesheetWeekToolbarId}
         hx-swap-oob={maybeSwapOob}>
        {renderTimesheetWeekHeader weekStartDate today wageEstimates viewFilters}
    </div>
|]

renderTimesheetDayColumns :: (?context :: ControllerContext) => IndexView -> Html
renderTimesheetDayColumns =
    renderTimesheetDayColumnsWithSwap Nothing

renderTimesheetDayColumnsWithSwap :: (?context :: ControllerContext) => Maybe Text -> IndexView -> Html
renderTimesheetDayColumnsWithSwap maybeSwapOob view = [hsx|
    <div id={timesheetDayColumnsId}
         class="timesheet-day-columns app-horizontal-grid"
         style="--timesheet-day-count: 7;"
         hx-swap-oob={maybeSwapOob}>
        {forEach [0 .. 6] (renderDaySection . timesheetDayRenderModel view)}
    </div>
|]

renderTimesheetWeekNavigationLink :: Text -> Text -> Day -> TimesheetViewFilters -> Html
renderTimesheetWeekNavigationLink label url anchorDate filters =
    renderFrontendSurfaceActionLink
        ( TimesheetsAction.navigateTimesheetWeekAction
            (TimesheetsAction.navigateTimesheetWeekActionFields anchorDate (nonEmpty filters.filterStaffIds) (nonEmpty filters.filterRosterGroupIds) (nonEmpty filters.filterShiftTypeIds))
        )
        (timesheetsActionRoute url)
            { actionRouteStandardUrl = Just url
            , actionRouteExtraAttrs = [("class", weekNavigationButtonClass "")]
            }
        [hsx|{label}|]
  where
    nonEmpty []     = Nothing
    nonEmpty values = Just values

renderTimesheetWeekHeader :: (?context :: ControllerContext) => Day -> Day -> Maybe TimesheetWageEstimates -> TimesheetViewFilters -> Html
renderTimesheetWeekHeader weekStartDate today wageEstimates filters =
    renderWeekToolbar WeekToolbarConfig
        { weekToolbarVariant = WeekToolbarTimesheets
        , weekToolbarRootAttrs = []
        , weekToolbarAriaLabel = "Timesheet week controls"
        , weekToolbarExtraClass = "timesheet-week-header app-side-panel-header"
        , weekToolbarPrimary = mempty
        , weekToolbarReset = renderTimesheetWeekNavigationLink "This week" (timesheetWindowUrlWithFilters today filters) today filters
        , weekToolbarNavigation = renderWeekNavigationGroup WeekNavigationConfig
            { weekNavigationAriaLabel = "Timesheet week navigation"
            , weekNavigationExtraClass = ""
            , weekNavigationPrevious = renderTimesheetWeekNavigationLink "<" (timesheetWindowUrlWithFilters previousDate filters) previousDate filters
            , weekNavigationCurrentLabel = [hsx|{renderTimesheetWeekLabel weekStartDate}|]
            , weekNavigationLabelClass = ""
            , weekNavigationNext = renderTimesheetWeekNavigationLink ">" (timesheetWindowUrlWithFilters nextDate filters) nextDate filters
            }
        , weekToolbarSettings = renderSidePanelToggle timesheetSidePanelRenderAttrs
        , weekToolbarAuxiliary = renderTimesheetWeekWageEstimate wageEstimates
        }
  where
    previousDate = addDays (-7) weekStartDate
    nextDate = addDays 7 weekStartDate

renderTimesheetWeekWageEstimate :: (?context :: ControllerContext) => Maybe TimesheetWageEstimates -> Html
renderTimesheetWeekWageEstimate Nothing = mempty
renderTimesheetWeekWageEstimate (Just estimates) =
    renderTimesheetWageEstimateSummary "timesheet-wage-summary" estimates estimates.timesheetWeekVisibleEstimate estimates.timesheetWeekAllEstimate

renderTimesheetDayWageEstimate :: (?context :: ControllerContext) => Day -> Maybe TimesheetWageEstimates -> Html
renderTimesheetDayWageEstimate _ Nothing = mempty
renderTimesheetDayWageEstimate day (Just estimates) =
    let (visibleSummary, allSummary) = lookupTimesheetDayWageEstimates estimates day
     in renderTimesheetWageEstimateSummary "timesheet-day-wage-summary" estimates visibleSummary allSummary

renderTimesheetWageEstimateSummary :: (?context :: ControllerContext) => Text -> TimesheetWageEstimates -> TimesheetWageEstimateSummary -> TimesheetWageEstimateSummary -> Html
renderTimesheetWageEstimateSummary cssClass estimates visibleSummary allSummary = [hsx|
    <div class={cssClass} aria-label={timesheetWageEstimateLabel estimates.timesheetPayAudience}>
        <span class="timesheet-wage-estimate-label">{timesheetWageEstimateLabel estimates.timesheetPayAudience}</span>
        <span class="timesheet-wage-estimate-total">{renderAmounts estimates.timesheetWageDisplayMode visibleSummary allSummary}</span>
        {renderTimesheetWageEstimateAvailability estimates.timesheetWageDisplayMode visibleSummary allSummary}
        {renderTimesheetWageSourceWarning (relevantSummary estimates.timesheetWageDisplayMode visibleSummary allSummary)}
    </div>
|]
  where
    renderAmounts VisibleTimesheets visible _ = formatMoneyAmount visible.wageEstimateAmount
    renderAmounts AllTimesheets _ allEntries = formatMoneyAmount allEntries.wageEstimateAmount
    renderAmounts VisibleAndAllTimesheets visible allEntries = formatMoneyAmount visible.wageEstimateAmount <> " (" <> formatMoneyAmount allEntries.wageEstimateAmount <> ")"
    renderAmounts Hidden _ _ = ""
    relevantSummary VisibleTimesheets visible _          = visible
    relevantSummary AllTimesheets _ allEntries           = allEntries
    relevantSummary VisibleAndAllTimesheets _ allEntries = allEntries
    relevantSummary Hidden visible _                     = visible

renderTimesheetWageEstimateAvailability :: WageDisplayModeEnum -> TimesheetWageEstimateSummary -> TimesheetWageEstimateSummary -> Html
renderTimesheetWageEstimateAvailability mode visibleSummary allSummary =
    case mode of
        Hidden -> mempty
        VisibleTimesheets -> renderCount visibleSummary.wageEstimateUnavailableCount "filtered timesheet unavailable" "filtered timesheets unavailable"
        AllTimesheets -> renderCount allSummary.wageEstimateUnavailableCount "timesheet unavailable overall" "timesheets unavailable overall"
        VisibleAndAllTimesheets ->
            renderCount visibleSummary.wageEstimateUnavailableCount "filtered timesheet unavailable" "filtered timesheets unavailable"
                <> renderCount allSummary.wageEstimateUnavailableCount "timesheet unavailable overall" "timesheets unavailable overall"
  where
    renderCount :: Int -> Text -> Text -> Html
    renderCount 0 _ _ = mempty
    renderCount count singular plural = [hsx|<span class="timesheet-wage-unavailable" role="status">({tshow count} {if count == 1 then singular else plural})</span>|]

renderTimesheetWageSourceWarning :: (?context :: ControllerContext) => TimesheetWageEstimateSummary -> Html
renderTimesheetWageSourceWarning summary
    | not currentUserIsSuperAdmin || summary.wageEstimateSourceWarningCount == 0 = mempty
    | otherwise = [hsx|
        <span class="timesheet-wage-source-warning text-warning" role="status" title="Draft estimate uses wage sources requiring attention">
            Wage source warning
        </span>
    |]

renderTimesheetSidePanel :: (?context :: ControllerContext) => IndexView -> Html
renderTimesheetSidePanel view =
    renderSidePanelPanelRegion timesheetSidePanelRenderAttrs SidePanelRegionConfig
        { sidePanelRegionId = Nothing
        , sidePanelRegionClass = "col-12 col-xl-4 col-xxl-3 timesheet-side-panel"
        , sidePanelRegionExtraAttrs = []
        }
        ( renderSidePanelCard
            SidePanelCardConfig
                { sidePanelCardClass = "timesheet-side-panel-card"
                }
            (if hasManagementMode then renderManagerTimesheetSidePanel view else renderWorkerTimesheetSettings view)
        )

renderManagerTimesheetSidePanel :: (?context :: ControllerContext) => IndexView -> Html
renderManagerTimesheetSidePanel view = [hsx|
    {renderSidePanelTabs "Timesheet side panel" tabs}
    <div class="tab-content app-side-panel-tab-content timesheet-side-panel-tab-content">
        <div class="tab-pane show active app-side-panel-pane" id="timesheet-staff-pane" role="tabpanel" aria-labelledby="timesheet-staff-tab" tabindex="0">
            <div class="app-side-panel-content-header">
                <h2 class="h5 mb-0">Staff</h2>
            </div>
            {renderTimesheetStaffPanel view.staffMembers view.staffPanelEntries}
        </div>
        <div class="tab-pane app-side-panel-pane app-side-panel-settings-pane" id="timesheet-settings-pane" role="tabpanel" aria-labelledby="timesheet-settings-tab" tabindex="0">
            {renderTimesheetSettingsFragment Nothing view}
        </div>
    </div>
|]
  where
    tabs =
        [ SidePanelTabConfig "timesheet-staff-tab" "timesheet-staff-pane" "Staff" "bi bi-people" True "timesheet-side-panel-tab" (timesheetSidePanelTabAttrs TimesheetStaffTab)
        , SidePanelTabConfig "timesheet-settings-tab" "timesheet-settings-pane" "Settings" "bi bi-sliders" False "timesheet-side-panel-tab" (timesheetSidePanelTabAttrs TimesheetSettingsTab)
        ]

renderWorkerTimesheetSettings :: (?context :: ControllerContext) => IndexView -> Html
renderWorkerTimesheetSettings view = [hsx|
    <h2 class="h5">Settings</h2>
    {renderTimesheetSettingsFragment Nothing view}
|]

renderTimesheetSettingsFragment :: (?context :: ControllerContext) => Maybe Text -> IndexView -> Html
renderTimesheetSettingsFragment maybeSwapOob view = [hsx|
    <div id={surfaceFragmentTargetId @Surface.TimesheetsSurface @Surface.TimesheetSidePanelContent noSurfaceFields} hx-swap-oob={maybeSwapOob}>
        {renderTimesheetSettings view}
    </div>
|]

renderTimesheetSettings :: (?context :: ControllerContext) => IndexView -> Html
renderTimesheetSettings IndexView { weekStartDate, calendarRevision, hideApproved, timesheetWageDisplayMode, viewFilters } = [hsx|
    <div class="timesheet-settings-toggle-grid mb-2">
        {when managerModeToggleVisible (renderTimesheetManagerModePreferenceForm weekStartDate viewFilters)}
        {renderTimesheetShowApprovedPreferenceForm weekStartDate calendarRevision viewFilters hideApproved}
        {when canConfigureTimesheetWageEstimates (renderTimesheetWageDisplayModePreferenceForm weekStartDate calendarRevision viewFilters timesheetWageDisplayMode)}
    </div>
    {renderTimesheetFilterButtons weekStartDate viewFilters}
|]

renderTimesheetStaffPanel :: (?context :: ControllerContext) => [Staff] -> [TimesheetStaffPanelEntry] -> Html
renderTimesheetStaffPanel staffMembers entries = [hsx|
    <div class="app-side-panel-table-list">
        {renderTimesheetStaffContent Nothing staffMembers entries}
    </div>
|]

renderTimesheetStaffContent :: (?context :: ControllerContext) => Maybe Text -> [Staff] -> [TimesheetStaffPanelEntry] -> Html
renderTimesheetStaffContent maybeSwapOob staffMembers entries = [hsx|
        <table id={surfaceFragmentTargetId @Surface.TimesheetsSurface @Surface.TimesheetStaffContent noSurfaceFields}
               hx-swap-oob={maybeSwapOob} class="app-side-panel-table timesheet-staff-table" {...timesheetStaffPanelSortRootAttrs}>
            <thead class="app-side-panel-table-head"><tr>
                <th scope="col" aria-sort="none"><button type="button" class="app-side-panel-sort-button timesheet-staff-sort-button" {...timesheetStaffPanelSortControlAttrs TimesheetStaffSortByName}>Name</button></th>
                <th scope="col" class="app-side-panel-role-head" aria-sort="none"><button type="button" class="app-side-panel-sort-button timesheet-staff-sort-button" {...timesheetStaffPanelSortControlAttrs TimesheetStaffSortByRole}>Role</button></th>
                <th scope="col" class="app-side-panel-metric-head" aria-sort="none"><button type="button" class="app-side-panel-sort-button app-side-panel-sort-button-metric timesheet-staff-sort-button" {...timesheetStaffPanelSortControlAttrs TimesheetStaffSortByCount}>Entries</button></th>
                <th scope="col" class="app-side-panel-action-head"><span class="visually-hidden">Locate entries</span></th>
            </tr></thead>
            <tbody class="app-side-panel-table-body">{forEach (sortOn (Text.toCaseFold . staffDisplayName staffMembers . (.panelStaff)) entries) (renderTimesheetStaffPanelEntry staffMembers)}</tbody>
        </table>
|]

renderTimesheetStaffPanelEntry :: (?context :: ControllerContext) => [Staff] -> TimesheetStaffPanelEntry -> Html
renderTimesheetStaffPanelEntry staffMembers entry =
    [hsx|
                <tr {...entryAttrs} class="app-side-panel-entry timesheet-staff-panel-entry" role="button" tabindex="0"
                    {...timesheetStaffPanelSortRowAttrs staffKey staffName roleLabel entry.panelEntryCount entry.panelApprovedCount}>
                    <th scope="row" class="app-side-panel-cell app-side-panel-name"><span class="app-side-panel-name-primary">{staffName}</span></th>
                    <td class="app-side-panel-cell app-side-panel-role">{roleLabel}</td>
                    <td class="app-side-panel-cell app-side-panel-metric"><span class="app-side-panel-count timesheet-staff-count-total">{entry.panelEntryCount}</span><span class="app-side-panel-count app-side-panel-count-secondary timesheet-staff-count-approved">({entry.panelApprovedCount})</span></td>
                    <td class="app-side-panel-cell app-side-panel-action">{locateButton}</td>
                </tr>
            |]
  where
    entryAttrs = SurfaceLinkedHighlight.frontendSurfaceLinkedHighlightSourceAttrs timesheetStaffCardsLinkedHighlight staffKey
        <> appShellActionAttrs (appShellActionByMarker @OpenRosterStaffEditDialog)
            (defaultAppShellActionRoute (pathTo (EditStaffAction entry.panelStaff.id)))
    staffKey = "staff:" <> tshow entry.panelStaff.id
    staffName = staffDisplayName staffMembers entry.panelStaff
    roleLabel = maybe (Text.toTitle (Text.replace "_" " " entry.panelStaffRole)) venueRoleLabel (parseVenueRole entry.panelStaffRole)
    locateButton =
        [hsx|
            <button {...(SurfaceLinkedHighlight.frontendSurfaceLinkedHighlightPinAttrs timesheetStaffCardsLinkedHighlight staffKey)} type="button" class="btn btn-sm btn-outline-secondary app-icon-button app-side-panel-locate-button timesheet-staff-locate-button"
                    aria-label={"Locate entries for " <> staffName} aria-pressed="false">
                {renderSidePanelLocateIcon}
            </button>
        |]

renderTimesheetManagerModePreferenceForm :: (?context :: ControllerContext) => Day -> TimesheetViewFilters -> Html
renderTimesheetManagerModePreferenceForm anchorDate filters = [hsx|
    <div class="timesheet-settings-toggle">
        <fieldset disabled={not managerModeToggleEnabled} class="mb-0">
            {managerModeForm}
        </fieldset>
        {managerModeExplanation}
    </div>
|]
  where
    fields = TimesheetsAction.toggleTimesheetManagerModeActionFields anchorDate managerModePreferenceEnabled (Just filters.filterShiftTypeIds)
    managerModeRoute =
        (timesheetsActionRoute (pathTo ToggleTimesheetManagerModeAction))
            { actionRouteStandardUrl = Just (pathTo ToggleTimesheetManagerModeAction) }
    managerModeExplanation
        | managerModeToggleEnabled = mempty
        | otherwise = [hsx|<p class="small app-muted mt-2 mb-0">Manager mode stays on because your account has no active linked Staff profile at this venue.</p>|]
    renderShiftFilter value = [hsx|<input type="hidden" name={surfaceFieldNameFrom @Surface.ShiftTypeFilterIds fields} value={tshow value} />|]
    managerModeForm =
        renderFrontendSurfaceActionForm
            (TimesheetsAction.toggleTimesheetManagerModeAction fields)
            managerModeRoute
            [hsx|
                <input type="hidden" name={surfaceFieldNameFrom @Surface.AnchorDate fields} value={surfaceWireText @'WireDay anchorDate} />
                {forEach filters.filterShiftTypeIds renderShiftFilter}
                {renderTimesheetToggleButton "timesheet-manager-mode-toggle" (surfaceToggleScalarField @Surface.ManagerModeEnabled fields True False) managerModePreferenceEnabled "Manager mode"}
            |]

renderTimesheetShowApprovedPreferenceForm :: Day -> Int -> TimesheetViewFilters -> Bool -> Html
renderTimesheetShowApprovedPreferenceForm anchorDate calendarRevision filters hideApproved =
    renderFrontendSurfaceActionForm
        (TimesheetsAction.toggleTimesheetHideApprovedAction fields)
        (timesheetsActionRoute (pathTo ToggleTimesheetHideApprovedAction))
            { actionRouteStandardUrl = Just (pathTo ToggleTimesheetHideApprovedAction)
            , actionRouteExtraAttrs = [("class", "mb-0")]
            }
        [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Surface.AnchorDate fields} value={surfaceWireText @'WireDay anchorDate} />
            <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision fields} value={tshow calendarRevision} />
            {renderTimesheetFilterHiddenFields fields filters}
            {renderTimesheetPreferenceToggle "timesheet-show-approved-toggle" (surfaceToggleScalarField @Surface.HideApproved fields False True) (not hideApproved) "Show approved"}
        |]
  where
    fields = TimesheetsAction.toggleTimesheetHideApprovedActionFields anchorDate calendarRevision hideApproved (Just filters.filterStaffIds) (Just filters.filterRosterGroupIds) (Just filters.filterShiftTypeIds)

renderTimesheetWageDisplayModePreferenceForm :: Day -> Int -> TimesheetViewFilters -> WageDisplayModeEnum -> Html
renderTimesheetWageDisplayModePreferenceForm anchorDate calendarRevision filters displayMode =
    renderFrontendSurfaceActionForm
        (TimesheetsAction.toggleTimesheetWageEstimatesAction fields)
        (timesheetsActionRoute (pathTo ToggleTimesheetWageEstimatesAction))
            { actionRouteStandardUrl = Just (pathTo ToggleTimesheetWageEstimatesAction)
            , actionRouteExtraAttrs = [("class", "mb-0")]
            }
        [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Surface.AnchorDate fields} value={surfaceWireText @'WireDay anchorDate} />
            <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision fields} value={tshow calendarRevision} />
            {renderTimesheetFilterHiddenFields fields filters}
            <label class="form-label small mb-1" for="timesheet-wage-display-mode">Estimated pay</label>
            <select id="timesheet-wage-display-mode" class="form-select form-select-sm" name={surfaceFieldNameFrom @Surface.TimesheetWageDisplayMode fields} onchange="this.form.requestSubmit();">
                {forEach wageDisplayModes renderModeOption}
            </select>
        |]
  where
    fields = TimesheetsAction.toggleTimesheetWageEstimatesActionFields anchorDate calendarRevision displayMode (Just filters.filterStaffIds) (Just filters.filterRosterGroupIds) (Just filters.filterShiftTypeIds)
    wageDisplayModes = [Hidden, VisibleTimesheets, AllTimesheets, VisibleAndAllTimesheets]
    renderModeOption mode = [hsx|<option value={inputValue mode} selected={mode == displayMode}>{wageDisplayModeLabel mode}</option>|]
    wageDisplayModeLabel Hidden = "Hidden" :: Text
    wageDisplayModeLabel VisibleTimesheets = "Filtered timesheets"
    wageDisplayModeLabel AllTimesheets = "All timesheets"
    wageDisplayModeLabel VisibleAndAllTimesheets = "Filtered timesheets (all timesheets)"

renderTimesheetFilterHiddenFields fields filters =
    renderValues (surfaceFieldNameFrom @Surface.StaffFilterIds fields) filters.filterStaffIds
        <> renderValues (surfaceFieldNameFrom @Surface.RosterGroupFilterIds fields) filters.filterRosterGroupIds
        <> renderValues (surfaceFieldNameFrom @Surface.ShiftTypeFilterIds fields) filters.filterShiftTypeIds
  where
    renderValues fieldName values = forEach values (\value -> [hsx|<input type="hidden" name={fieldName} value={tshow value} />|])

renderTimesheetFilterButtons :: Day -> TimesheetViewFilters -> Html
renderTimesheetFilterButtons anchorDate filters = [hsx|
    <div class="d-flex gap-2 flex-wrap">
        {openButton}
        {clearButton}
    </div>
|]
  where
    count = activeTimesheetFilterCount filters
    label = if count == 0 then "Filters" else "Filters · " <> tshow count
    openButton = renderAppShellActionLink (appShellActionByMarker @OpenTimesheetFiltersDialog)
        ((defaultAppShellActionRoute modalUrl) { appShellActionRouteExtraAttrs = [("class", "btn btn-outline-secondary"), ("id", "timesheet-filters-button")] })
        [hsx|{label}|]
    clearButton = if count == 0 then [hsx|<button type="button" class="btn btn-outline-secondary" disabled>Clear filters</button>|]
        else renderTimesheetWeekNavigationLink "Clear filters" (timesheetWindowUrlWithFilters anchorDate emptyTimesheetViewFilters) anchorDate emptyTimesheetViewFilters
    modalUrl = withTimesheetFilters filters (pathTo (ShowTimesheetFiltersAction (tshow anchorDate)))

newtype TimesheetFiltersView = TimesheetFiltersView { filtersIndexView :: IndexView }

instance View TimesheetFiltersView where
    html TimesheetFiltersView { filtersIndexView = view } =
        renderPageDialogModal (timesheetWindowUrlWithFilters view.weekStartDate view.viewFilters) (timesheetFiltersDialogConfig PageOverlayForm view)

renderTimesheetFiltersDialog :: (?context :: ControllerContext) => IndexView -> Html
renderTimesheetFiltersDialog view =
    renderDialogOverlay (timesheetFiltersDialogConfig HtmxOverlayForm view)

timesheetFiltersDialogConfig :: (?context :: ControllerContext) => OverlayFormMode -> IndexView -> DialogOverlayConfig
timesheetFiltersDialogConfig mode view =
    defaultDialogOverlayConfig "Filters" (renderTimesheetFilterForm mode view)
        [dialogOverlayCloseButton "Cancel", dialogOverlaySubmitButton "Apply" "timesheet-filters-form"]

renderTimesheetFilterForm :: (?context :: ControllerContext) => OverlayFormMode -> IndexView -> Html
renderTimesheetFilterForm mode IndexView { weekStartDate = anchorDate, viewFilters = filters, staffMembers, shiftTypes, rosterGroups } =
    renderForm [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Surface.AnchorDate fields} value={tshow anchorDate} />
            {when hasManagementMode (renderFilterSelectionSection "Staff" (surfaceFieldNameFrom @Surface.StaffFilterIds fields) False (map tshow filters.filterStaffIds) staffOptions)}
            {renderFilterSelectionSection "Shift types" (surfaceFieldNameFrom @Surface.ShiftTypeFilterIds fields) (not hasManagementMode) (map tshow filters.filterShiftTypeIds) shiftOptions}
            {when (hasManagementMode && length rosterGroups > 1) (renderFilterSelectionSection "Roster groups" (surfaceFieldNameFrom @Surface.RosterGroupFilterIds fields) False (map tshow filters.filterRosterGroupIds) groupOptions)}
        |]
  where
    updateUrl = timesheetWindowUrlWithFilters anchorDate emptyTimesheetViewFilters
    renderForm body = case mode of
        HtmxOverlayForm -> renderFrontendSurfaceActionForm
            (TimesheetsAction.updateTimesheetFiltersAction fields)
            ((timesheetsActionRoute updateUrl) { actionRouteStandardUrl = Just updateUrl, actionRouteExtraAttrs = [("id", "timesheet-filters-form"), ("class", "accordion")] }) body
        PageOverlayForm -> [hsx|<form id="timesheet-filters-form" class="accordion" method="GET" action={updateUrl}>{body}</form>|]
    fields = TimesheetsAction.updateTimesheetFiltersActionFields anchorDate (Just filters.filterStaffIds) (Just filters.filterRosterGroupIds) (Just filters.filterShiftTypeIds)
    staffOptions = [FilterSelectionOption (tshow staff.id) (staff.firstName <> " " <> staff.lastName) (not staff.isActive || isJust staff.archivedAt) | staff <- staffMembers]
    shiftOptions = [FilterSelectionOption (tshow shift.id) shift.name (not shift.isActive || isJust shift.archivedAt) | shift <- shiftTypes]
    groupOptions = [FilterSelectionOption (tshow group.id) group.name (not group.isActive || isJust group.archivedAt) | group <- rosterGroups]

renderTimesheetPreferenceToggle :: Text -> ToggleFieldBinding -> Bool -> Text -> Html
renderTimesheetPreferenceToggle inputId binding isChecked label = [hsx|
    <div class="timesheet-settings-toggle">
        {renderTimesheetToggleButton inputId binding isChecked label}
    </div>
|]

renderTimesheetToggleButton :: Text -> ToggleFieldBinding -> Bool -> Text -> Html
renderTimesheetToggleButton inputId binding isChecked label =
    renderAppToggleButton $
        (defaultAppToggleButtonConfig inputId binding isChecked [hsx|<span class="small">{label}</span>|])
            { appToggleButtonClass = "btn-sm w-100 justify-content-start"
            , appToggleSubmitPolicy = ToggleSubmitImmediate
            }

renderTimesheetWeekLabel :: Day -> Text
renderTimesheetWeekLabel weekStartDate =
    "Week of " <> Text.pack (formatTime defaultTimeLocale "%-d %b" weekStartDate)

timesheetDayRenderModel :: IndexView -> Int -> TimesheetDayRenderModel
timesheetDayRenderModel IndexView { entries, timingByEntryId, staffMembers, shiftTypes, rosterGroupLabels, today, editWindowDays, weekStartDate, calendarRevision, viewFilters, wageEstimates } dayOffset =
    TimesheetDayRenderModel
        { dayEntries = entries
        , dayTimingByEntryId = timingByEntryId
        , dayStaffMembers = staffMembers
        , dayShiftTypes = shiftTypes
        , dayRosterGroups = rosterGroupLabels
        , dayToday = today
        , dayEditWindowDays = editWindowDays
        , dayWeekStartDate = weekStartDate
        , dayCalendarRevision = calendarRevision
        , dayViewFilters = viewFilters
        , dayWageEstimates = wageEstimates
        , dayOffset
        }

renderDaySection :: (?context :: ControllerContext) => TimesheetDayRenderModel -> Html
renderDaySection =
    renderDaySectionWithSwap Nothing

renderDaySectionWithSwap :: (?context :: ControllerContext) => Maybe Text -> TimesheetDayRenderModel -> Html
renderDaySectionWithSwap maybeSwapOob model@TimesheetDayRenderModel { dayEntries, dayWeekStartDate, dayWageEstimates, dayOffset } = [hsx|
    <section id={timesheetDaySectionDomId dayDate}
             class="timesheet-day-panel app-horizontal-panel"
             data-timesheet-operational-date={surfaceWireText @'WireDay dayDate}
             hx-swap-oob={maybeSwapOob}>
        <header class="timesheet-day-header">
            {renderNewEntryOverlayLink newEntryUrl weekdayLabel weekdayShortLabel dayDate}
        </header>

        {renderTimesheetDayWageEstimate dayDate dayWageEstimates}

        <div class="timesheet-day-body">
            {renderDayEntries model dayEntriesForDate}
        </div>
    </section>
|]
    where
        dayDate = addDays (toInteger dayOffset) dayWeekStartDate
        dayEntriesForDate = filter ((== dayDate) . timesheetEntryOperationalDate) dayEntries
        weekdayLabel = Text.pack (formatTime defaultTimeLocale "%A" dayDate)
        weekdayShortLabel = Text.pack (formatTime defaultTimeLocale "%a" dayDate)
        newEntryUrl = withTimesheetFilters model.dayViewFilters (newTimesheetEntryUrl dayDate dayDate Nothing)

renderNewEntryOverlayLink :: Text -> Text -> Text -> Day -> Html
renderNewEntryOverlayLink newEntryUrl weekdayLabel weekdayShortLabel dayDate =
    renderAppShellActionLink
        (appShellActionByMarker @OpenTimesheetEntryDialog)
        ((defaultAppShellActionRoute (newEntryUrl))
            { appShellActionRouteExtraAttrs = [ ("class", "timesheet-day-add-bar")
                , ("data-timesheet-day-add", "true")
                , ("aria-label", "Add timesheet entry for " <> weekdayLabel <> " " <> formatDateCompact dayDate)
                ]
            })
        [hsx|
            <span class="timesheet-day-add-plus">+</span>
            <span class="timesheet-day-add-label">{weekdayShortLabel} {formatDateCompact dayDate}</span>
        |]

timesheetDaySectionDomId :: Day -> Text
timesheetDaySectionDomId operationalDate =
    surfaceFragmentTargetId @Surface.TimesheetsSurface @Surface.TimesheetDaySection
        (surfaceField @Surface.OperationalDate operationalDate &: noSurfaceFields)

renderDayEntries :: (?context :: ControllerContext) => TimesheetDayRenderModel -> [TimesheetEntry] -> Html
renderDayEntries model dayEntries
    | null dayEntries = [hsx|<p class="timesheet-day-empty app-muted mb-0">{if activeTimesheetFilterCount model.dayViewFilters > 0 then "No timesheets match your filters" else "No entries for this day." :: Text}</p>|]
    | otherwise = [hsx|
        <div class="timesheet-entry-list">
            {forEach dayEntries (renderEntryCard model)}
        </div>
    |]

renderEntryCard :: (?context :: ControllerContext) => TimesheetDayRenderModel -> TimesheetEntry -> Html
renderEntryCard model@TimesheetDayRenderModel { dayTimingByEntryId, dayToday, dayEditWindowDays, dayCalendarRevision } entry =
    renderTimesheetCard
        model
        entry
        timingOutcome
        "timesheet-entry-card"
        Nothing
        (renderEntryCardOverlayLink entry canEdit editUrl)
        (renderApprovalAction entry timingOutcome dayCalendarRevision model.dayViewFilters)
  where
    timingOutcome = Map.findWithDefault (Left (TimesheetTimingInvalid BoundaryShiftShapeInvalid)) (unpackId entry.id) dayTimingByEntryId
    canEdit = hasManagementMode || isWithinEditWindow dayToday (timesheetEntryOperationalDate entry) dayEditWindowDays
    editUrl = withTimesheetFilters model.dayViewFilters (editTimesheetEntryUrl (get #id entry) (timesheetEntryOperationalDate entry) Nothing)

renderTimesheetCard :: (?context :: ControllerContext) => TimesheetDayRenderModel -> TimesheetEntry -> Either TimesheetIntegrityError ValidatedTimesheetTiming -> Text -> Maybe Text -> Html -> Html -> Html
renderTimesheetCard TimesheetDayRenderModel { dayStaffMembers, dayShiftTypes, dayRosterGroups } entry timingOutcome cardClass rosterPrefillId cardOverlay cardAction =
    card
  where
    card = [hsx|
        <article {...(SurfaceLinkedHighlight.frontendSurfaceLinkedHighlightMemberAttrs timesheetStaffCardsLinkedHighlight ("staff:" <> tshow entry.staffId) Nothing)} class={cardClass}
                 data-timesheet-entry-approved={boolParam entry.isApproved}
                 data-timesheet-roster-prefill-id={rosterPrefillId}>
            {cardOverlay}
            <div class="timesheet-entry-main">
                <div class="timesheet-entry-identity">
                    <div class="timesheet-entry-staff-name">{staffName}</div>
                    <div class="timesheet-entry-shift-type">{shiftTypeLabel}</div>
                </div>

                <div class="timesheet-entry-time">
                    <div class="timesheet-entry-time-range">{timingRange}</div>
                    {timingMeta}
                </div>

                <div class="timesheet-entry-actions">
                    {cardAction}
                </div>
            </div>

            {renderEntryComments entry}
            {renderTimesheetShapeBar defaultTimesheetTimelineScale timingOutcome}
        </article>
    |]
    staffName = case find (\staff -> unpackId (get #id staff) == entry.staffId) dayStaffMembers of
        Just staff -> staff.firstName <> " " <> staff.lastName
        Nothing    -> "Unknown" :: Text
    timingRange = case timingOutcome of
        Left _ -> "Timing unavailable"
        Right timing -> renderCompactTimeRange (timesheetTimingStartTime timing) (timesheetTimingEndTime timing)
    timingMeta = case timingOutcome of
        Left _ -> [hsx|<div class="timesheet-entry-meta text-warning" data-timesheet-timing-issue="true">Timing needs repair</div>|]
        Right timing -> [hsx|
            <div class="timesheet-entry-meta">Shift: {renderDuration timing}</div>
            <div class="timesheet-entry-meta timesheet-entry-break-meta">Break: <span class="timesheet-entry-break-summary">{renderBreakSummary timing}</span></div>
        |]
    shiftTypeLabel = shiftTypeName <> " - " <> rosterGroupName
    shiftTypeName = case find (\shiftType -> unpackId (get #id shiftType) == entry.shiftTypeId) dayShiftTypes of
        Just shiftType -> shiftType.name
        Nothing        -> "Shift"
    rosterGroupName = case entry.rosterGroupClassification of
        NoRosterGroup -> "No roster group"
        InRosterGroup -> case entry.rosterGroupId >>= \groupId -> find ((== groupId) . unpackId . (.id)) dayRosterGroups of
            Just rosterGroup -> rosterGroup.name
            Nothing          -> "Roster group"

renderEntryCardOverlayLink :: TimesheetEntry -> Bool -> Text -> Html
renderEntryCardOverlayLink entry canEdit editUrl
    | canEdit =
        renderAppShellActionLink
            (appShellActionByMarker @EditTimesheetEntryDialog)
            ((defaultAppShellActionRoute (editUrl))
                { appShellActionRouteExtraAttrs = dialogPointerDismissBlurAttrs <> [ ("class", "timesheet-entry-card-link")
                    , ("aria-label", "Edit timesheet entry for " <> tshow (timesheetEntryOperationalDate entry))
                    ]
                })
            mempty
    | otherwise = mempty

renderEntryComments :: (?context :: ControllerContext) => TimesheetEntry -> Html
renderEntryComments entry =
    let staffComment = renderComment "Staff comment" entry.staffComment
        managerNote =
            if hasManagementMode
                then renderComment "Manager note" entry.managerNote
                else mempty
     in if isNothing entry.staffComment && (not hasManagementMode || isNothing entry.managerNote)
            then mempty
            else [hsx|<div class="timesheet-entry-comments">{staffComment}{managerNote}</div>|]

renderComment :: Text -> Maybe Text -> Html
renderComment label maybeComment =
    case maybeComment >>= nonEmptyText of
        Nothing -> mempty
        Just comment -> [hsx|
            <div class="timesheet-entry-comment">
                <span class="timesheet-entry-comment-label">{label}</span>
                <span class="timesheet-entry-comment-text">{comment}</span>
            </div>
        |]

renderApprovalAction :: (?context :: ControllerContext) => TimesheetEntry -> Either TimesheetIntegrityError ValidatedTimesheetTiming -> Int -> TimesheetViewFilters -> Html
renderApprovalAction entry timingOutcome calendarRevision staffFilterId
    | not hasManagementMode && entry.isApproved = [hsx|
        <button type="button"
                class="btn btn-sm btn-success timesheet-approval-toggle"
                disabled>
            Approved
        </button>
    |]
    | not hasManagementMode = mempty
    | entry.isApproved =
        renderTimesheetApprovalForm
            (TimesheetsAction.unapproveTimesheetEntryAction unapproveFields)
            (pathTo (UnapproveTimesheetEntryAction entry.id))
            [hsx|<button type="submit" class="btn btn-sm btn-success timesheet-approval-toggle">Approved</button>|]
    | timingIsInvalid = [hsx|
        <button type="button" class="btn btn-sm btn-outline-secondary timesheet-approval-toggle" disabled>Repair timing</button>
    |]
    | otherwise =
        renderTimesheetApprovalForm
            (TimesheetsAction.approveTimesheetEntryAction approveFields)
            (pathTo (ApproveTimesheetEntryAction entry.id))
            [hsx|<button type="submit" class="btn btn-sm btn-outline-success timesheet-approval-toggle">Approve</button>|]
  where
    timingIsInvalid = case timingOutcome of
        Left _  -> True
        Right _ -> False
    approveFields = TimesheetsAction.approveTimesheetEntryActionFields (timesheetEntryOperationalDate entry) calendarRevision (Just staffFilterId.filterStaffIds) (Just staffFilterId.filterRosterGroupIds) (Just staffFilterId.filterShiftTypeIds)
    unapproveFields = TimesheetsAction.unapproveTimesheetEntryActionFields (timesheetEntryOperationalDate entry) calendarRevision (Just staffFilterId.filterStaffIds) (Just staffFilterId.filterRosterGroupIds) (Just staffFilterId.filterShiftTypeIds)

renderTimesheetApprovalForm :: FrontendSurfaceAction -> Text -> Html -> Html
renderTimesheetApprovalForm action actionUrl button =
    renderFrontendSurfaceActionFormWithHiddenFields
        action
        (timesheetsActionRoute actionUrl)
            { actionRouteStandardUrl = Just actionUrl
            , actionRouteExtraAttrs = [("class", "timesheet-entry-action-form")]
            }
        [hsx|
            {button}
        |]

renderBreakSummary :: ValidatedTimesheetTiming -> Text
renderBreakSummary timing =
    case (timesheetTimingBreakStartTime timing, timesheetTimingBreakEndTime timing) of
        (Nothing, Nothing) -> "None"
        (Just breakStart, Just breakEnd) -> renderCompactTimeRange breakStart breakEnd
        _ -> "Invalid"

renderCompactTimeRange :: TimeOfDay -> TimeOfDay -> Text
renderCompactTimeRange startTime endTime =
    case (stripMeridiem startLabel, stripMeridiem endLabel) of
        (Just (startClock, startMeridiem), Just (endClock, endMeridiem))
            | startMeridiem == endMeridiem -> startClock <> "–" <> endClock <> " " <> endMeridiem
        _ -> startLabel <> "–" <> endLabel
    where
        startLabel = storageTimeToDisplayLabel (timeOfDayToStorageValue startTime)
        endLabel = storageTimeToDisplayLabel (timeOfDayToStorageValue endTime)

stripMeridiem :: Text -> Maybe (Text, Text)
stripMeridiem label =
    case Text.stripSuffix " AM" label of
        Just clock -> Just (clock, "AM")
        Nothing -> case Text.stripSuffix " PM" label of
            Just clock -> Just (clock, "PM")
            Nothing    -> Nothing

renderDuration :: ValidatedTimesheetTiming -> Html
renderDuration timing =
    let totalSeconds = max 0 (floor (timesheetTimingPaidElapsedSeconds timing) :: Int)
        (hours, afterHours) = totalSeconds `divMod` (60 * 60)
        (minutes, seconds) = afterHours `divMod` 60
        secondsSuffix = if seconds > 0 then " " <> tshow seconds <> "s" else ""
     in [hsx|{show hours}h {show minutes}m{secondsSuffix}|]

formatDateCompact :: Day -> Text
formatDateCompact day =
    Text.pack (formatTime defaultTimeLocale "%d/%m" day)

data TimesheetTimelineScale = TimesheetTimelineScale
    { scaleStartMinutes :: Int
    , scaleEndMinutes   :: Int
    , midnightOffset    :: Int
    }

data TimesheetShapeSegment = TimesheetShapeSegment
    { segmentLeft  :: Double
    , segmentWidth :: Double
    , segmentClass :: Text
    }

data TimesheetShapeMarker = TimesheetShapeMarker
    { markerLabel   :: Text
    , markerMinutes :: Int
    , markerClass   :: Text
    , markerHasLine :: Bool
    }

defaultTimesheetTimelineScale :: TimesheetTimelineScale
defaultTimesheetTimelineScale =
    TimesheetTimelineScale
        { scaleStartMinutes = 6 * 60
        , scaleEndMinutes = 30 * 60
        , midnightOffset = 24 * 60
        }

renderTimesheetShapeBar :: TimesheetTimelineScale -> Either TimesheetIntegrityError ValidatedTimesheetTiming -> Html
renderTimesheetShapeBar scale timingOutcome =
    let segments = maybe [] (timesheetShapeSegments scale) (either (const Nothing) Just timingOutcome)
        markers = timesheetShapeMarkers scale
    in if null segments
        then mempty
        else [hsx|
            <div class="timesheet-shape">
                <div class="timesheet-shape-bar">
                    <div class="timesheet-shape-track"></div>
                    {forEach (filter markerHasLine markers) (renderTimesheetShapeMarkerLine scale)}
                    {forEach segments renderTimesheetShapeSegment}
                </div>
                <div class="timesheet-shape-labels">
                    {forEach markers (renderTimesheetShapeMarkerLabel scale)}
                </div>
            </div>
        |]

timesheetShapeMarkers :: TimesheetTimelineScale -> [TimesheetShapeMarker]
timesheetShapeMarkers scale =
    [ TimesheetShapeMarker "6am" (scaleStartMinutes scale) "timesheet-shape-marker-start" False
    , TimesheetShapeMarker "7pm" (19 * 60) "timesheet-shape-marker-pay-crossover" True
    , TimesheetShapeMarker "12am" (midnightOffset scale) "timesheet-shape-marker-midnight" True
    , TimesheetShapeMarker "6am" (scaleEndMinutes scale) "timesheet-shape-marker-end" False
    ]

timesheetShapeSegments :: TimesheetTimelineScale -> ValidatedTimesheetTiming -> [TimesheetShapeSegment]
timesheetShapeSegments scale timing =
    let shiftStartMinutes = scaleMinuteValue scale (timesheetTimingStartTime timing)
        shiftSegments =
            buildSegments
                "timesheet-shape-segment-shift"
                scale
                (shiftStartMinutes, shiftStartMinutes + elapsedMinutes (timesheetTimingElapsedSeconds timing))
        breakSegments =
            case (authoritativeBreakStartsAt boundaries, authoritativeBreakEndsAt boundaries) of
                (Just breakStart, Just breakEnd) ->
                    let breakStartMinutes = shiftStartMinutes + elapsedMinutes (diffUTCTime breakStart (authoritativeStartsAt boundaries))
                     in buildSegments
                            "timesheet-shape-segment-break"
                            scale
                            (breakStartMinutes, breakStartMinutes + elapsedMinutes (diffUTCTime breakEnd breakStart))
                _ -> []
        boundaries = timesheetTimingBoundaries timing
     in shiftSegments <> breakSegments

buildSegments :: Text -> TimesheetTimelineScale -> (Double, Double) -> [TimesheetShapeSegment]
buildSegments cssClass scale (startMinutes, endMinutes)
    | endMinutes <= startMinutes = []
    | endMinutes <= scaleEnd = [mkSegment cssClass scale startMinutes endMinutes]
    | otherwise =
        [ mkSegment cssClass scale startMinutes scaleEnd
        , mkSegment cssClass scale scaleStart (endMinutes - 1440)
        ]
  where
    scaleStart = fromIntegral (scaleStartMinutes scale)
    scaleEnd = fromIntegral (scaleEndMinutes scale)

mkSegment :: Text -> TimesheetTimelineScale -> Double -> Double -> TimesheetShapeSegment
mkSegment cssClass scale startMinutes endMinutes =
    let total = fromIntegral (scaleEndMinutes scale - scaleStartMinutes scale) :: Double
        left = ((startMinutes - fromIntegral (scaleStartMinutes scale)) / total) * 100
        width = ((endMinutes - startMinutes) / total) * 100
    in TimesheetShapeSegment { segmentLeft = left, segmentWidth = width, segmentClass = cssClass }

scaleMinuteValue :: TimesheetTimelineScale -> TimeOfDay -> Double
scaleMinuteValue scale timeOfDay =
    let minuteValue = timeOfDayToMinutes timeOfDay
    in if minuteValue < fromIntegral (scaleStartMinutes scale) then minuteValue + 1440 else minuteValue

timeOfDayToMinutes :: TimeOfDay -> Double
timeOfDayToMinutes TimeOfDay { todHour, todMin, todSec } =
    fromIntegral (todHour * 60 + todMin) + realToFrac (todSec :: Pico) / 60

elapsedMinutes :: NominalDiffTime -> Double
elapsedMinutes seconds = realToFrac seconds / 60

timesheetMarkerLeft :: TimesheetTimelineScale -> Int -> Double
timesheetMarkerLeft scale minutes =
    let total = fromIntegral (scaleEndMinutes scale - scaleStartMinutes scale) :: Double
    in (fromIntegral (minutes - scaleStartMinutes scale) / total) * 100

timesheetMarkerStyle :: TimesheetTimelineScale -> Int -> Text
timesheetMarkerStyle scale minutes = "--timesheet-marker-left: " <> tshow (timesheetMarkerLeft scale minutes) <> "%;"

renderTimesheetShapeMarkerLine :: TimesheetTimelineScale -> TimesheetShapeMarker -> Html
renderTimesheetShapeMarkerLine scale marker = [hsx|
    <div class={"timesheet-shape-marker-line " <> markerClass marker}
         style={timesheetMarkerStyle scale (markerMinutes marker)}></div>
|]

renderTimesheetShapeMarkerLabel :: TimesheetTimelineScale -> TimesheetShapeMarker -> Html
renderTimesheetShapeMarkerLabel scale marker = [hsx|
    <span class={"timesheet-shape-marker-label " <> markerClass marker}
          style={timesheetMarkerStyle scale (markerMinutes marker)}>{markerLabel marker}</span>
|]

renderTimesheetShapeSegment :: TimesheetShapeSegment -> Html
renderTimesheetShapeSegment segment = [hsx|
    <div class={"timesheet-shape-segment " <> segmentClass segment}
         style={"left:" <> tshow (segmentLeft segment) <> "%;width:" <> tshow (segmentWidth segment) <> "%;"}></div>
|]
