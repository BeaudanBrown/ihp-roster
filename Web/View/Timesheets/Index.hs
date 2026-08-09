{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.View.Timesheets.Index where

import Application.Helper.Controller (currentVenueId, isWithinEditWindow)
import Application.Helper.FrontendContract.AppShell (EditTimesheetEntryDialog,
                                                     OpenRosterStaffEditDialog,
                                                     OpenTimesheetEntryDialog)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             applyAppShellActionAttrs,
                                                             renderAppShellActionLink)
import Application.Helper.FrontendContract.HorizontalScroll.Runtime
import Application.Helper.FrontendContract.Surface.DSL (WireType (WireDay))
import qualified Application.Helper.FrontendContract.Surface.LinkedHighlight as SurfaceLinkedHighlight
import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceAction)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            SurfaceImpl,
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
import Application.Helper.Url (appendQueryParams)
import Application.PayAssignment (StaffPayAssignment (..),
                                  staffAssignmentAllowsTimesheets)
import Application.VenueRole (parseVenueRole, venueRoleLabel)
import Application.VenueTime.Model
import Data.Fixed (Pico)
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays)
import Data.Time.Clock (NominalDiffTime, diffUTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.UUID (UUID)
import Web.Timesheets.FrontendSurface (timesheetStaffCardsLinkedHighlight)
import Web.Timesheets.Paths (createTimesheetEntryFromSuggestionUrl,
                             editTimesheetEntryUrl,
                             newTimesheetEntryFromSuggestionUrl,
                             newTimesheetEntryUrl, timesheetWindowUrl)
import Web.Timesheets.Suggestion
import Web.View.Prelude

data TimesheetStaffPanelEntry = TimesheetStaffPanelEntry
    { panelStaff         :: !Staff
    , panelStaffRole     :: !Text
    , panelEntryCount    :: !Int
    , panelApprovedCount :: !Int
    }

data IndexView = IndexView
    { entries                  :: [TimesheetEntry]
    , suggestions              :: [TimesheetSuggestion]
    , staffMembers             :: [Staff]
    , shiftTypes               :: [ShiftType]
    , today                    :: Day
    , editWindowDays           :: Int
    , weekOffset               :: Int
    , weekStartDate            :: Day
    , weekEndDate              :: Day
    , calendarRevision         :: Int
    , hideApproved             :: Bool
    , showTimesheetSuggestions :: Bool
    , selectedStaffFilterId    :: Maybe UUID
    , currentViewerStaffId     :: Maybe UUID
    , staffPanelEntries        :: [TimesheetStaffPanelEntry]
    , frontendSurfaceImpl      :: Maybe (SurfaceImpl Surface.TimesheetsSurface)
    }

timesheetsActionRoute :: Text -> FrontendSurfaceActionRoute
timesheetsActionRoute actionUrl =
    FrontendSurfaceActionRoute
        { actionRouteUrl = actionUrl
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Nothing
        , actionRouteExtraAttrs = []
        }

data TimesheetDayRenderModel = TimesheetDayRenderModel
    { dayEntries          :: [TimesheetEntry]
    , daySuggestions      :: [TimesheetSuggestion]
    , dayStaffMembers     :: [Staff]
    , dayShiftTypes       :: [ShiftType]
    , dayToday            :: Day
    , dayEditWindowDays   :: Int
    , dayWeekOffset       :: Int
    , dayWeekStartDate    :: Day
    , dayCalendarRevision :: Int
    , dayStaffFilterId    :: Maybe UUID
    , dayOffset           :: Int
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
renderTimesheetWeekToolbarWithSwap maybeSwapOob IndexView { weekOffset, weekStartDate, today, hideApproved, showTimesheetSuggestions, selectedStaffFilterId, staffMembers } = [hsx|
    <div id={timesheetWeekToolbarId}
         hx-swap-oob={maybeSwapOob}>
        {renderTimesheetWeekHeader weekOffset weekStartDate today hideApproved showTimesheetSuggestions selectedStaffFilterId staffMembers}
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

renderTimesheetWeekNavigationLink :: Text -> Text -> Day -> Maybe UUID -> Html
renderTimesheetWeekNavigationLink label url anchorDate selectedStaffFilterId =
    renderFrontendSurfaceActionLink
        ( TimesheetsAction.navigateTimesheetWeekAction
            (TimesheetsAction.navigateTimesheetWeekActionFields anchorDate selectedStaffFilterId)
        )
        (timesheetsActionRoute url)
            { actionRouteStandardUrl = Just url
            , actionRouteExtraAttrs = [("class", weekNavigationButtonClass "")]
            }
        [hsx|{label}|]

renderTimesheetWeekHeader :: (?context :: ControllerContext) => Int -> Day -> Day -> Bool -> Bool -> Maybe UUID -> [Staff] -> Html
renderTimesheetWeekHeader _weekOffset weekStartDate today hideApproved showTimesheetSuggestions selectedStaffFilterId staffMembers =
    renderWeekToolbar WeekToolbarConfig
        { weekToolbarVariant = WeekToolbarTimesheets
        , weekToolbarAriaLabel = "Timesheet week controls"
        , weekToolbarExtraClass = "timesheet-week-header app-side-panel-header"
        , weekToolbarPrimary = mempty
        , weekToolbarReset = renderTimesheetWeekNavigationLink "This week" (timesheetWindowUrl today selectedStaffFilterId) today selectedStaffFilterId
        , weekToolbarNavigation = renderWeekNavigationGroup WeekNavigationConfig
            { weekNavigationAriaLabel = "Timesheet week navigation"
            , weekNavigationExtraClass = ""
            , weekNavigationPrevious = renderTimesheetWeekNavigationLink "<" (timesheetWindowUrl previousDate selectedStaffFilterId) previousDate selectedStaffFilterId
            , weekNavigationCurrentLabel = [hsx|{renderTimesheetWeekLabel weekStartDate}|]
            , weekNavigationLabelClass = ""
            , weekNavigationNext = renderTimesheetWeekNavigationLink ">" (timesheetWindowUrl nextDate selectedStaffFilterId) nextDate selectedStaffFilterId
            }
        , weekToolbarSettings = renderSidePanelToggle timesheetSidePanelRenderAttrs
        , weekToolbarAuxiliary = mempty
        }
  where
    previousDate = addDays (-7) weekStartDate
    nextDate = addDays 7 weekStartDate

renderTimesheetSidePanel :: (?context :: ControllerContext) => IndexView -> Html
renderTimesheetSidePanel = renderTimesheetSidePanelWithSwap Nothing

renderTimesheetSidePanelWithSwap :: (?context :: ControllerContext) => Maybe Text -> IndexView -> Html
renderTimesheetSidePanelWithSwap maybeSwapOob view =
    renderSidePanelPanelRegion timesheetSidePanelRenderAttrs SidePanelRegionConfig
        { sidePanelRegionId = Just "timesheet-side-panel-content"
        , sidePanelRegionClass = "col-12 col-xl-4 col-xxl-3 timesheet-side-panel"
        , sidePanelRegionExtraAttrs = maybe [] (\swap -> [("hx-swap-oob", swap)]) maybeSwapOob
        }
        ( renderSidePanelCard
            SidePanelCardConfig
                { sidePanelCardClass = "timesheet-side-panel-card"
                , sidePanelCardBodyClass = "app-side-panel-scroll-body"
                }
            (if currentUserIsManager then renderManagerTimesheetSidePanel view else renderWorkerTimesheetSettings view)
        )

renderManagerTimesheetSidePanel :: (?context :: ControllerContext) => IndexView -> Html
renderManagerTimesheetSidePanel view = [hsx|
    {renderSidePanelTabs "Timesheet side panel" tabs}
    <div class="tab-content app-side-panel-tab-content timesheet-side-panel-tab-content">
        <div class="tab-pane show active app-side-panel-pane" id="timesheet-staff-pane" role="tabpanel" aria-labelledby="timesheet-staff-tab" tabindex="0">
            <div class="app-side-panel-content-header">
                <h2 class="h5 mb-0">Staff</h2>
            </div>
            {renderTimesheetStaffPanel view.weekOffset view.staffMembers view.staffPanelEntries}
        </div>
        <div class="tab-pane app-side-panel-pane app-side-panel-settings-pane" id="timesheet-settings-pane" role="tabpanel" aria-labelledby="timesheet-settings-tab" tabindex="0">
            {renderTimesheetSettings view}
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
    {renderTimesheetSettings view}
|]

renderTimesheetSettings :: (?context :: ControllerContext) => IndexView -> Html
renderTimesheetSettings IndexView { weekOffset, weekStartDate, calendarRevision, hideApproved, showTimesheetSuggestions, selectedStaffFilterId, staffMembers } = [hsx|
    <div class="timesheet-settings-toggle-grid mb-2">
        {renderTimesheetHideApprovedPreferenceForm weekStartDate calendarRevision selectedStaffFilterId hideApproved}
        {renderTimesheetShowSuggestionsPreferenceForm weekStartDate calendarRevision selectedStaffFilterId showTimesheetSuggestions}
    </div>
    {when currentUserIsManager (renderTimesheetStaffFilterForm weekStartDate selectedStaffFilterId staffMembers)}
|]

renderTimesheetStaffPanel :: (?context :: ControllerContext) => Int -> [Staff] -> [TimesheetStaffPanelEntry] -> Html
renderTimesheetStaffPanel weekOffset staffMembers entries = [hsx|
    <div class="app-side-panel-table-list">
        <table class="app-side-panel-table timesheet-staff-table" {...timesheetStaffPanelSortRootAttrs}>
            <thead class="app-side-panel-table-head"><tr>
                <th scope="col" aria-sort="none"><button type="button" class="app-side-panel-sort-button timesheet-staff-sort-button" {...timesheetStaffPanelSortControlAttrs TimesheetStaffSortByName}>Name</button></th>
                <th scope="col" class="app-side-panel-role-head" aria-sort="none"><button type="button" class="app-side-panel-sort-button timesheet-staff-sort-button" {...timesheetStaffPanelSortControlAttrs TimesheetStaffSortByRole}>Role</button></th>
                <th scope="col" class="app-side-panel-metric-head" aria-sort="none"><button type="button" class="app-side-panel-sort-button app-side-panel-sort-button-metric timesheet-staff-sort-button" {...timesheetStaffPanelSortControlAttrs TimesheetStaffSortByCount}>Entries</button></th>
                <th scope="col" class="app-side-panel-action-head"><span class="visually-hidden">Locate entries</span></th>
            </tr></thead>
            <tbody class="app-side-panel-table-body">{forEach (sortOn (Text.toCaseFold . staffDisplayName staffMembers . (.panelStaff)) entries) (renderTimesheetStaffPanelEntry weekOffset staffMembers)}</tbody>
        </table>
    </div>
|]

renderTimesheetStaffPanelEntry :: (?context :: ControllerContext) => Int -> [Staff] -> TimesheetStaffPanelEntry -> Html
renderTimesheetStaffPanelEntry weekOffset staffMembers entry =
    SurfaceLinkedHighlight.withFrontendSurfaceLinkedHighlightSource timesheetStaffCardsLinkedHighlight staffKey $
        applyAppShellActionAttrs
            (appShellActionByMarker @OpenRosterStaffEditDialog)
            AppShellActionRoute
                { appShellActionRouteUrl = appendQueryParams (pathTo (EditStaffAction entry.panelStaff.id)) [("weekOffset", tshow weekOffset)]
                , appShellActionRouteFields = []
                , appShellActionRouteCustomHtmx = []
                , appShellActionRouteStandardUrl = Nothing
                , appShellActionRouteExtraAttrs = []
                }
            [hsx|
                <tr class="app-side-panel-entry timesheet-staff-panel-entry" role="button" tabindex="0"
                    {...timesheetStaffPanelSortRowAttrs staffKey staffName roleLabel entry.panelEntryCount entry.panelApprovedCount}>
                    <th scope="row" class="app-side-panel-cell app-side-panel-name"><span class="app-side-panel-name-primary">{staffName}</span></th>
                    <td class="app-side-panel-cell app-side-panel-role">{roleLabel}</td>
                    <td class="app-side-panel-cell app-side-panel-metric"><span class="app-side-panel-count timesheet-staff-count-total">{entry.panelEntryCount}</span><span class="app-side-panel-count app-side-panel-count-secondary timesheet-staff-count-approved">({entry.panelApprovedCount})</span></td>
                    <td class="app-side-panel-cell app-side-panel-action">{locateButton}</td>
                </tr>
            |]
  where
    staffKey = "staff:" <> tshow entry.panelStaff.id
    staffName = staffDisplayName staffMembers entry.panelStaff
    roleLabel = maybe (Text.toTitle (Text.replace "_" " " entry.panelStaffRole)) venueRoleLabel (parseVenueRole entry.panelStaffRole)
    locateButton =
        SurfaceLinkedHighlight.withFrontendSurfaceLinkedHighlightPin timesheetStaffCardsLinkedHighlight staffKey [hsx|
            <button type="button" class="btn btn-sm btn-outline-secondary app-icon-button app-side-panel-locate-button timesheet-staff-locate-button"
                    aria-label={"Locate entries for " <> staffName} aria-pressed="false">
                <i class="bi bi-eye" aria-hidden="true"></i>
            </button>
        |]

renderTimesheetHideApprovedPreferenceForm :: Day -> Int -> Maybe UUID -> Bool -> Html
renderTimesheetHideApprovedPreferenceForm anchorDate calendarRevision selectedStaffFilterId hideApproved =
    renderFrontendSurfaceActionForm
        (TimesheetsAction.toggleTimesheetHideApprovedAction fields)
        (timesheetsActionRoute (pathTo ToggleTimesheetHideApprovedAction))
            { actionRouteStandardUrl = Just (pathTo ToggleTimesheetHideApprovedAction)
            , actionRouteExtraAttrs = [("class", "mb-0")]
            }
        [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Surface.AnchorDate fields} value={surfaceWireText @'WireDay anchorDate} />
            <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision fields} value={tshow calendarRevision} />
            {renderOptionalStaffFilterField (surfaceFieldNameFrom @Surface.StaffFilterId fields) selectedStaffFilterId}
            {renderTimesheetPreferenceToggle "timesheet-hide-approved-toggle" (surfaceToggleScalarField @Surface.HideApproved fields True False) hideApproved "Hide approved"}
        |]
  where
    fields = TimesheetsAction.toggleTimesheetHideApprovedActionFields anchorDate calendarRevision hideApproved selectedStaffFilterId

renderTimesheetShowSuggestionsPreferenceForm :: Day -> Int -> Maybe UUID -> Bool -> Html
renderTimesheetShowSuggestionsPreferenceForm anchorDate calendarRevision selectedStaffFilterId showTimesheetSuggestions =
    renderFrontendSurfaceActionForm
        (TimesheetsAction.toggleTimesheetShowSuggestionsAction fields)
        (timesheetsActionRoute (pathTo ToggleTimesheetShowSuggestionsAction))
            { actionRouteStandardUrl = Just (pathTo ToggleTimesheetShowSuggestionsAction)
            , actionRouteExtraAttrs = [("class", "mb-0")]
            }
        [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Surface.AnchorDate fields} value={surfaceWireText @'WireDay anchorDate} />
            <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision fields} value={tshow calendarRevision} />
            {renderOptionalStaffFilterField (surfaceFieldNameFrom @Surface.StaffFilterId fields) selectedStaffFilterId}
            {renderTimesheetPreferenceToggle "timesheet-show-suggestions-toggle" (surfaceToggleScalarField @Surface.ShowTimesheetSuggestions fields True False) showTimesheetSuggestions "Show suggestions"}
        |]
  where
    fields = TimesheetsAction.toggleTimesheetShowSuggestionsActionFields anchorDate calendarRevision showTimesheetSuggestions selectedStaffFilterId

renderOptionalStaffFilterField :: Text -> Maybe UUID -> Html
renderOptionalStaffFilterField fieldName selectedStaffFilterId =
    forEach selectedStaffFilterId \staffFilterId -> [hsx|
        <input type="hidden" name={fieldName} value={tshow staffFilterId} />
    |]

renderTimesheetStaffFilterForm :: (?context :: ControllerContext) => Day -> Maybe UUID -> [Staff] -> Html
renderTimesheetStaffFilterForm anchorDate selectedStaffFilterId staffMembers =
    renderFrontendSurfaceActionForm
        (TimesheetsAction.updateTimesheetFiltersAction fields)
        (timesheetsActionRoute updateUrl)
            { actionRouteStandardUrl = Just updateUrl
            , actionRouteExtraAttrs = [("class", "px-1 py-1")]
            }
        [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Surface.AnchorDate fields} value={surfaceWireText @'WireDay anchorDate} />
            {renderTimesheetStaffFilter fields selectedStaffFilterId staffMembers}
        |]
  where
    updateUrl = timesheetWindowUrl anchorDate Nothing
    fields = TimesheetsAction.updateTimesheetFiltersActionFields anchorDate selectedStaffFilterId

renderTimesheetStaffFilter :: ActionFields TimesheetsAction.UpdateTimesheetFiltersActionOperation -> Maybe UUID -> [Staff] -> Html
renderTimesheetStaffFilter fields selectedStaffFilterId staffMembers = [hsx|
    <div class="mt-3">
        <label for="timesheet-staff-filter" class="form-label small mb-1">Staff</label>
        <select id="timesheet-staff-filter"
                name={surfaceFieldNameFrom @Surface.StaffFilterId fields}
                class="form-select form-select-sm"
                onchange="this.form.requestSubmit();">
            <option value="" selected={isNothing selectedStaffFilterId}>All staff</option>
            {forEach (filter staffCanProduceTimesheets staffMembers) renderOption}
        </select>
    </div>
|]
    where
        staffCanProduceTimesheets staff =
            staffAssignmentAllowsTimesheets
                (StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId)
        renderOption staff =
            let staffId = unpackId (get #id staff)
             in [hsx|
                <option value={tshow staffId} selected={selectedStaffFilterId == Just staffId}>
                    {staff.firstName} {staff.lastName}
                </option>
            |]

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
timesheetDayRenderModel IndexView { entries, suggestions, staffMembers, shiftTypes, today, editWindowDays, weekOffset, weekStartDate, calendarRevision, selectedStaffFilterId } dayOffset =
    TimesheetDayRenderModel
        { dayEntries = entries
        , daySuggestions = suggestions
        , dayStaffMembers = staffMembers
        , dayShiftTypes = shiftTypes
        , dayToday = today
        , dayEditWindowDays = editWindowDays
        , dayWeekOffset = weekOffset
        , dayWeekStartDate = weekStartDate
        , dayCalendarRevision = calendarRevision
        , dayStaffFilterId = selectedStaffFilterId
        , dayOffset
        }

renderDaySection :: (?context :: ControllerContext) => TimesheetDayRenderModel -> Html
renderDaySection =
    renderDaySectionWithSwap Nothing

renderDaySectionWithSwap :: (?context :: ControllerContext) => Maybe Text -> TimesheetDayRenderModel -> Html
renderDaySectionWithSwap maybeSwapOob model@TimesheetDayRenderModel { dayEntries, daySuggestions, dayWeekStartDate, dayWeekOffset, dayStaffFilterId, dayOffset } = [hsx|
    <section id={timesheetDaySectionDomId dayDate}
             class="timesheet-day-panel app-horizontal-panel"
             data-timesheet-operational-date={surfaceWireText @'WireDay dayDate}
             hx-swap-oob={maybeSwapOob}>
        <header class="timesheet-day-header">
            {renderNewEntryOverlayLink newEntryUrl weekdayLabel weekdayShortLabel dayDate}
        </header>

        <div class="timesheet-day-body">
            {renderDayEntries model dayEntriesForDate suggestionsForDate}
        </div>
    </section>
|]
    where
        dayDate = addDays (toInteger dayOffset) dayWeekStartDate
        dayEntriesForDate = filter ((== dayDate) . timesheetEntryWorkedOn) dayEntries
        suggestionsForDate = filter ((== dayDate) . timesheetSuggestionWorkedOn) daySuggestions
        weekdayLabel = Text.pack (formatTime defaultTimeLocale "%A" dayDate)
        weekdayShortLabel = Text.pack (formatTime defaultTimeLocale "%a" dayDate)
        newEntryUrl = newTimesheetEntryUrl dayDate dayDate dayStaffFilterId

renderNewEntryOverlayLink :: Text -> Text -> Text -> Day -> Html
renderNewEntryOverlayLink newEntryUrl weekdayLabel weekdayShortLabel dayDate =
    renderAppShellActionLink
        (appShellActionByMarker @OpenTimesheetEntryDialog)
        AppShellActionRoute
            { appShellActionRouteUrl = newEntryUrl
            , appShellActionRouteFields = []
            , appShellActionRouteCustomHtmx = []
            , appShellActionRouteStandardUrl = Nothing
            , appShellActionRouteExtraAttrs =
                [ ("class", "timesheet-day-add-bar")
                , ("data-timesheet-day-add", "true")
                , ("aria-label", "Add timesheet entry for " <> weekdayLabel <> " " <> formatDateCompact dayDate)
                ]
            }
        [hsx|
            <span class="timesheet-day-add-plus">+</span>
            <span class="timesheet-day-add-label">{weekdayShortLabel} {formatDateCompact dayDate}</span>
        |]

timesheetDaySectionDomId :: Day -> Text
timesheetDaySectionDomId operationalDate =
    surfaceFragmentTargetId @Surface.TimesheetsSurface @Surface.TimesheetDaySection
        (surfaceField @Surface.OperationalDate operationalDate &: noSurfaceFields)

renderDayEntries :: (?context :: ControllerContext) => TimesheetDayRenderModel -> [TimesheetEntry] -> [TimesheetSuggestion] -> Html
renderDayEntries model dayEntries daySuggestions
    | null dayEntries && null daySuggestions = [hsx|<p class="timesheet-day-empty app-muted mb-0">No entries for this day.</p>|]
    | otherwise = [hsx|
        <div class="timesheet-entry-list">
            {forEach daySuggestions (renderSuggestionCard model)}
            {forEach dayEntries (renderEntryCard model)}
        </div>
    |]

renderSuggestionCard :: (?context :: ControllerContext) => TimesheetDayRenderModel -> TimesheetSuggestion -> Html
renderSuggestionCard model@TimesheetDayRenderModel { dayWeekOffset, dayCalendarRevision, dayStaffFilterId } suggestion =
    renderTimesheetCard
        model
        suggestedEntry
        "timesheet-entry-card timesheet-suggestion-card"
        (Just (tshow suggestion.suggestionRosterSlotId))
        (renderSuggestionCardOverlayLink (timesheetSuggestionWorkedOn suggestion) editUrl)
        (renderSuggestionCreateAction createUrl action)
  where
    suggestedEntry = newTimesheetEntryFromSuggestion (unpackId currentVenueId) suggestion
    stateFields = TimesheetsAction.createTimesheetEntryFromSuggestionActionFields (timesheetSuggestionWorkedOn suggestion) dayCalendarRevision dayStaffFilterId
    createUrl =
        let baseUrl = createTimesheetEntryFromSuggestionUrl suggestion.suggestionRosterSlotId (timesheetSuggestionWorkedOn suggestion) dayStaffFilterId
         in if currentUserIsManager then appendQueryParams baseUrl [("approveSuggestion", "true")] else baseUrl
    editUrl = newTimesheetEntryFromSuggestionUrl suggestion.suggestionRosterSlotId (timesheetSuggestionWorkedOn suggestion) dayStaffFilterId
    action = TimesheetsAction.createTimesheetEntryFromSuggestionAction stateFields

renderSuggestionCreateAction :: Text -> FrontendSurfaceAction -> Html
renderSuggestionCreateAction createUrl action = [hsx|
    {createForm}
|]
  where
    createForm =
        renderTimesheetApprovalForm
            action
            createUrl
            [hsx|<button type="submit" class="btn btn-sm btn-outline-success timesheet-approval-toggle">{if currentUserIsManager then ("Approve" :: Text) else "Create"}</button>|]

renderSuggestionCardOverlayLink :: (?context :: ControllerContext) => Day -> Text -> Html
renderSuggestionCardOverlayLink workedOn editUrl =
    renderAppShellActionLink
        (appShellActionByMarker @OpenTimesheetEntryDialog)
        AppShellActionRoute
            { appShellActionRouteUrl = editUrl
            , appShellActionRouteFields = []
            , appShellActionRouteCustomHtmx = []
            , appShellActionRouteStandardUrl = Nothing
            , appShellActionRouteExtraAttrs =
                [ ("class", "timesheet-entry-card-link")
                , ("aria-label", "Adjust rostered timesheet suggestion for " <> tshow workedOn)
                ]
            }
        mempty

renderEntryCard :: (?context :: ControllerContext) => TimesheetDayRenderModel -> TimesheetEntry -> Html
renderEntryCard model@TimesheetDayRenderModel { dayToday, dayEditWindowDays, dayWeekOffset, dayCalendarRevision, dayStaffFilterId } entry =
    renderTimesheetCard
        model
        entry
        "timesheet-entry-card"
        Nothing
        (renderEntryCardOverlayLink entry canEdit editUrl)
        (renderApprovalAction entry dayCalendarRevision dayStaffFilterId)
  where
    canEdit = currentUserIsManager || isWithinEditWindow dayToday (timesheetEntryWorkedOn entry) dayEditWindowDays
    editUrl = editTimesheetEntryUrl (get #id entry) (timesheetEntryWorkedOn entry) dayStaffFilterId

renderTimesheetCard :: (?context :: ControllerContext) => TimesheetDayRenderModel -> TimesheetEntry -> Text -> Maybe Text -> Html -> Html -> Html
renderTimesheetCard TimesheetDayRenderModel { dayStaffMembers, dayShiftTypes } entry cardClass suggestionId cardOverlay cardAction =
    SurfaceLinkedHighlight.withFrontendSurfaceLinkedHighlightMember
        timesheetStaffCardsLinkedHighlight
        ("staff:" <> tshow entry.staffId)
        Nothing
        card
  where
    card = [hsx|
        <article class={cardClass}
                 data-timesheet-entry-approved={boolParam entry.isApproved}
                 data-timesheet-suggestion-id={suggestionId}>
            {cardOverlay}
            <div class="timesheet-entry-main">
                <div class="timesheet-entry-identity">
                    <div class="timesheet-entry-staff-name">{staffName}</div>
                    <div class="timesheet-entry-shift-type">{shiftTypeLabel}</div>
                </div>

                <div class="timesheet-entry-time">
                    <div class="timesheet-entry-time-range">
                        {renderCompactTimeRange (timesheetEntryStartTime entry) (timesheetEntryEndTime entry)}
                    </div>
                    <div class="timesheet-entry-meta">Shift: {renderDuration entry}</div>
                    <div class="timesheet-entry-meta timesheet-entry-break-meta">Break: <span class="timesheet-entry-break-summary">{renderBreakSummary entry}</span></div>
                </div>

                <div class="timesheet-entry-actions">
                    {cardAction}
                </div>
            </div>

            {renderEntryComments entry}
            {renderTimesheetShapeBar defaultTimesheetTimelineScale entry}
        </article>
    |]
    staffName = case find (\staff -> unpackId (get #id staff) == entry.staffId) dayStaffMembers of
        Just staff -> staff.firstName <> " " <> staff.lastName
        Nothing    -> "Unknown" :: Text
    shiftTypeLabel = case find (\shiftType -> unpackId (get #id shiftType) == entry.shiftTypeId) dayShiftTypes of
        Just shiftType -> shiftType.name
        Nothing        -> "Shift"

renderEntryCardOverlayLink :: TimesheetEntry -> Bool -> Text -> Html
renderEntryCardOverlayLink entry canEdit editUrl
    | canEdit =
        renderAppShellActionLink
            (appShellActionByMarker @EditTimesheetEntryDialog)
            AppShellActionRoute
                { appShellActionRouteUrl = editUrl
                , appShellActionRouteFields = []
                , appShellActionRouteCustomHtmx = []
                , appShellActionRouteStandardUrl = Nothing
                , appShellActionRouteExtraAttrs =
                    [ ("class", "timesheet-entry-card-link")
                    , ("aria-label", "Edit timesheet entry for " <> tshow (timesheetEntryWorkedOn entry))
                    ]
                }
            mempty
    | otherwise = mempty

renderEntryComments :: (?context :: ControllerContext) => TimesheetEntry -> Html
renderEntryComments entry =
    let staffComment = renderComment "Staff comment" entry.staffComment
        managerNote =
            if currentUserIsManager
                then renderComment "Manager note" entry.managerNote
                else mempty
     in if isNothing entry.staffComment && (not currentUserIsManager || isNothing entry.managerNote)
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

renderApprovalAction :: (?context :: ControllerContext) => TimesheetEntry -> Int -> Maybe UUID -> Html
renderApprovalAction entry calendarRevision staffFilterId
    | not currentUserIsManager && entry.isApproved = [hsx|
        <button type="button"
                class="btn btn-sm btn-success timesheet-approval-toggle"
                disabled>
            Approved
        </button>
    |]
    | not currentUserIsManager = mempty
    | entry.isApproved =
        renderTimesheetApprovalForm
            (TimesheetsAction.unapproveTimesheetEntryAction unapproveFields)
            (pathTo (UnapproveTimesheetEntryAction entry.id))
            [hsx|<button type="submit" class="btn btn-sm btn-success timesheet-approval-toggle">Approved</button>|]
    | otherwise =
        renderTimesheetApprovalForm
            (TimesheetsAction.approveTimesheetEntryAction approveFields)
            (pathTo (ApproveTimesheetEntryAction entry.id))
            [hsx|<button type="submit" class="btn btn-sm btn-outline-success timesheet-approval-toggle">Approve</button>|]
  where
    approveFields = TimesheetsAction.approveTimesheetEntryActionFields (timesheetEntryWorkedOn entry) calendarRevision staffFilterId
    unapproveFields = TimesheetsAction.unapproveTimesheetEntryActionFields (timesheetEntryWorkedOn entry) calendarRevision staffFilterId

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

renderBreakSummary :: TimesheetEntry -> Text
renderBreakSummary entry
    | not (timesheetEntryHadBreak entry) = "None"
    | otherwise =
        case (timesheetEntryBreakStartTime entry, timesheetEntryBreakEndTime entry) of
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

renderDuration :: TimesheetEntry -> Html
renderDuration entry =
    let totalSeconds = max 0 (floor (timesheetEntryPaidElapsedSeconds entry) :: Int)
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

renderTimesheetShapeBar :: TimesheetTimelineScale -> TimesheetEntry -> Html
renderTimesheetShapeBar scale entry =
    let segments = timesheetShapeSegments scale entry
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

timesheetShapeSegments :: TimesheetTimelineScale -> TimesheetEntry -> [TimesheetShapeSegment]
timesheetShapeSegments scale entry =
    let shiftStartMinutes = scaleMinuteValue scale (timesheetEntryStartTime entry)
        shiftSegments =
            buildSegments
                "timesheet-shape-segment-shift"
                scale
                (shiftStartMinutes, shiftStartMinutes + elapsedMinutes (timesheetEntryElapsedSeconds entry))
        breakSegments =
            case (entry.breakStartsAt, entry.breakEndsAt) of
                (Just breakStart, Just breakEnd) | timesheetEntryHadBreak entry ->
                    let breakStartMinutes = shiftStartMinutes + elapsedMinutes (diffUTCTime breakStart entry.startsAt)
                     in buildSegments
                            "timesheet-shape-segment-break"
                            scale
                            (breakStartMinutes, breakStartMinutes + elapsedMinutes (diffUTCTime breakEnd breakStart))
                _ -> []
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
