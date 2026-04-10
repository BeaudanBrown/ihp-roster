module Web.View.RosterWeeks.Show where

import Application.Helper.LiveUpdate (LiveUpdateScope (..))
import Application.Helper.View (ViewAudience (ManagerAudience),
                                appendQueryParams, currentUserMatchesAudience,
                                staffDisplayName)
import Data.Coerce (coerce)
import Data.List (find, nub, sort)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, isJust)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import qualified Data.Time.Calendar as Calendar
import Data.Time.Calendar.WeekDate (toWeekDate)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.UUID (UUID)
import Web.View.Prelude

data ShowView = ShowView
    { rosterWeek         :: Maybe RosterWeek
    , rosterDays         :: [RosterDay]
    , weekOffset         :: Int
    , rosterGroups       :: [RosterGroup]
    , currentRosterGroup :: RosterGroup
    , weekStartDate      :: Day
    , weekEndDate        :: Day
    , assignmentFilters  :: RosterAssignmentFilters
    , staffMembers       :: [Staff]
    , staffOptionStates  :: Map.Map (UUID, UUID) RosterAssignmentOptionState
    , panelStaff         :: [RosterStaffPanelEntry]
    , slotNames          :: [SlotName]
    , allSlots           :: [RosterSlot]
    , slotConflicts      :: [(Id RosterSlot, [RosterConflict])]
    , renderIndexes      :: RosterRenderIndexes
    , liveUpdateScope    :: Maybe LiveUpdateScope
    , viewCapabilities   :: RosterViewCapabilities
    }

data RosterViewCapabilities = RosterViewCapabilities
    { canToggleRosterLive       :: Bool
    , canCopyRosterWeek         :: Bool
    , canExportRosterImage      :: Bool
    , canManageAssignmentFilter :: Bool
    , canSyncRosterWeekSlots    :: Bool
    , canViewLeaveMetrics       :: Bool
    }

data RosterRenderIndexes = RosterRenderIndexes
    { rosterDayById              :: Map.Map UUID RosterDay
    , rosterDayRowsByDayId       :: Map.Map UUID [(Int, [RosterSlot])]
    , rosterSlotByDayRowSlotName :: Map.Map (UUID, Int, UUID) RosterSlot
    , rosterStaffById            :: Map.Map UUID Staff
    , rosterConflictsBySlotId    :: Map.Map UUID [RosterConflict]
    }

data RosterWeekOverviewDay = RosterWeekOverviewDay
    { overviewDate               :: Day
    , leaveRequestCount          :: Int
    , overviewAssignedShiftCount :: Int
    , scheduledMinutes           :: Int
    , overviewIsClosed           :: Bool
    }

data RosterStaffPanelEntry = RosterStaffPanelEntry
    { staff              :: Staff
    , assignedShiftCount :: Int
    , userRole           :: Text
    }

data RosterAssignmentFilters = RosterAssignmentFilters
    { hideStaffAtIdealShifts        :: Bool
    , hideStaffUnavailable          :: Bool
    , hideStaffOnApprovedLeave      :: Bool
    , hideStaffAlreadyAssignedToday :: Bool
    }

data RosterAssignmentOptionState = RosterAssignmentOptionState
    { optionHidden                :: Bool
    , optionAssignedShiftCount    :: Int
    , optionHiddenByIdeal         :: Bool
    , optionHiddenByUnavailable   :: Bool
    , optionHiddenByLeave         :: Bool
    , optionHiddenByAssignedToday :: Bool
    }

minimumOpenRosterRows :: Int
minimumOpenRosterRows = 2

closedRosterDayRows :: Int
closedRosterDayRows = 3

rosterWeekShellId :: Text
rosterWeekShellId = "roster-week-shell"

rosterContentFragmentId :: Text
rosterContentFragmentId = "roster-content"

rosterStaffPanelFragmentId :: Text
rosterStaffPanelFragmentId = "roster-staff-panel-fragment"

rosterDaySectionDomId :: Id RosterDay -> Text
rosterDaySectionDomId rosterDayId = "roster-day-section-" <> tshow rosterDayId

instance View ShowView where
    html = renderRosterWeekShell

renderRosterWeekShell :: ShowView -> Html
renderRosterWeekShell ShowView { .. } =
    let page = renderAppPage (AppPageConfig
            { appPageTitle = "Roster"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody = renderRosterContentFragment rosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities
            })
     in [hsx|
    <section id={rosterWeekShellId}
             hx-history-elt="true"
             data-live-update-owner="true"
             data-live-update-feature="roster"
             data-live-updates-path="/live-updates"
             data-live-update-content-url={appendQueryParams (pathTo (ShowRosterWeekContentFragmentAction weekOffset)) [("rosterGroupId", tshow currentRosterGroup.id)]}
             data-live-update-staff-panel-url={appendQueryParams (pathTo (ShowRosterWeekStaffPanelFragmentAction weekOffset)) [("rosterGroupId", tshow currentRosterGroup.id)]}
             data-live-update-client-enabled={isJust liveUpdateScope}
             data-live-update-client-id=""
             data-live-update-scope-kind={liveUpdateScopeKind <$> liveUpdateScope}
             data-live-update-venue-id={liveUpdateVenueId <$> liveUpdateScope}
             data-live-update-roster-group-id={liveUpdateRosterGroupIdText =<< liveUpdateScope}
             data-live-update-week-offset={liveUpdateWeekOffsetText =<< liveUpdateScope}>
        <div data-live-update-owner="true"
             data-live-update-feature="roster-group-config"
             data-live-updates-path="/live-updates"
             data-live-update-content-url={appendQueryParams (pathTo (ShowRosterWeekContentFragmentAction weekOffset)) [("rosterGroupId", tshow currentRosterGroup.id)]}
             data-live-update-client-enabled={isJust liveUpdateScope}
             data-live-update-client-id=""
             data-live-update-scope-kind={liveUpdateRosterGroupScopeKind <$> liveUpdateScope}
             data-live-update-venue-id={liveUpdateVenueId <$> liveUpdateScope}
             data-live-update-roster-group-id={liveUpdateRosterGroupIdText =<< liveUpdateScope}
             hidden="hidden"></div>
        {page}
    </section>
|]

renderRosterWeekControls :: (?context :: ControllerContext) => Int -> RosterGroup -> Day -> Html
renderRosterWeekControls weekOffset currentRosterGroup weekStartDate = [hsx|
    <div class="btn-group app-week-nav-group roster-week-nav-group" role="group" aria-label="Roster week navigation">
        {renderWeekNavigationLink "bi-chevron-left" "Previous week" (rosterWeekPath (weekOffset - 1) currentRosterGroup.id)}
        {renderWeekOverviewDropdown weekOffset currentRosterGroup.id weekStartDate}
        {renderWeekNavigationLink "bi-chevron-right" "Next week" (rosterWeekPath (weekOffset + 1) currentRosterGroup.id)}
    </div>
|]

rosterWeekOverviewMountId :: Id RosterGroup -> Int -> Text
rosterWeekOverviewMountId rosterGroupId weekOffset =
    "roster-week-overview-mount-" <> tshow rosterGroupId <> "-" <> tshow weekOffset

renderWeekOverviewDropdown :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Day -> Html
renderWeekOverviewDropdown weekOffset rosterGroupId weekStartDate =
    let
        triggerId = "roster-week-overview-trigger-" <> tshow rosterGroupId <> "-" <> tshow weekOffset
        mountId = rosterWeekOverviewMountId rosterGroupId weekOffset
        fragmentUrl = appendQueryParams (pathTo (ShowRosterWeekOverviewFragmentAction weekOffset)) [("rosterGroupId", tshow rosterGroupId)]
     in
        [hsx|
            <div class="dropdown roster-week-overview" data-week-overview="true">
                <button class="btn btn-outline-secondary roster-week-nav-button roster-week-overview-trigger"
                        type="button"
                        id={triggerId}
                        data-bs-toggle="dropdown"
                        data-bs-auto-close="outside"
                        aria-expanded="false"
                        aria-label="Open roster week overview">
                    <span class="roster-week-overview-trigger-icon" aria-hidden="true">
                        <i class="bi bi-calendar3"></i>
                    </span>
                    <span>{renderRosterWeekLabel weekStartDate}</span>
                </button>
                <div class="dropdown-menu dropdown-menu-end roster-week-overview-menu" aria-labelledby={triggerId}>
                    <div id={mountId}
                         data-week-overview-fragment-mount="true"
                         hx-get={fragmentUrl}
                         hx-trigger="load"
                         hx-swap="innerHTML">
                        {renderWeekOverviewDropdownLoading}
                    </div>
                </div>
            </div>
        |]

renderWeekOverviewDropdownLoading :: Html
renderWeekOverviewDropdownLoading = [hsx|
    <div class="roster-week-overview-panel roster-week-overview-panel-loading">
        <div class="roster-week-overview-header">
            <div>
                <div class="roster-week-overview-eyebrow">Month overview</div>
                <div class="roster-week-overview-month">Loading...</div>
            </div>
        </div>
        <div class="app-muted small">Loading month overview...</div>
    </div>
|]

renderWeekOverviewPanelFragment :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Day -> Day -> [RosterWeekOverviewDay] -> RosterViewCapabilities -> Html
renderWeekOverviewPanelFragment weekOffset rosterGroupId weekStartDate todayDate weekOverviewDays viewCapabilities =
    let
        initialDate = initialOverviewDate weekStartDate todayDate weekOverviewDays
        monthDays = buildOverviewMonthDays initialDate
        initialOverviewDay = find (\daySummary -> overviewDate daySummary == initialDate) weekOverviewDays
        leaveLegend =
            if viewCapabilities.canViewLeaveMetrics
                then [hsx|<span><span class="roster-week-overview-legend-dot"></span> Leave requests</span>|]
                else mempty
     in
        [hsx|
            <div class="roster-week-overview-panel"
                 data-week-overview-panel="true"
                 data-week-overview-current-date={formatDayParam todayDate}
                 data-week-overview-loaded="true">
                <div class="roster-week-overview-header">
                    <div>
                        <div class="roster-week-overview-eyebrow">Month overview</div>
                        <div class="roster-week-overview-month">{renderMonthLabel initialDate}</div>
                    </div>
                    <button type="button"
                            class="btn btn-sm btn-outline-secondary"
                            data-week-overview-today="true">
                        Today
                    </button>
                </div>
                <div class="roster-week-overview-layout">
                    <div class="roster-week-overview-calendar">
                        <div class="roster-week-overview-weekdays">
                            {forEach weekdayLabels renderOverviewWeekdayLabel}
                        </div>
                        <div class="roster-week-overview-grid">
                            {forEach monthDays (renderOverviewDayCell weekOffset rosterGroupId weekOverviewDays initialDate todayDate viewCapabilities)}
                        </div>
                        <div class="roster-week-overview-legend">
                            {leaveLegend}
                            <span><span class="roster-week-overview-legend-closed"></span> Closed</span>
                            <span><span class="roster-week-overview-legend-today"></span> Today</span>
                        </div>
                    </div>
                    {renderWeekOverviewDetailsCard weekOffset rosterGroupId initialDate initialOverviewDay viewCapabilities}
                </div>
            </div>
        |]

renderRosterWeekLabel :: Day -> Text
renderRosterWeekLabel weekStartDate = "Week of " <> Text.pack (formatTime defaultTimeLocale "%-d %b" weekStartDate)

weekdayLabels :: [Text]
weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

initialOverviewDate :: Day -> Day -> [RosterWeekOverviewDay] -> Day
initialOverviewDate weekStartDate todayDate weekOverviewDays =
    if any (\daySummary -> overviewDate daySummary == todayDate) weekOverviewDays
        then todayDate
        else weekStartDate

renderMonthLabel :: Day -> Text
renderMonthLabel date = Text.pack (formatTime defaultTimeLocale "%B %Y" date)

renderOverviewWeekdayLabel :: Text -> Html
renderOverviewWeekdayLabel label = [hsx|<div class="roster-week-overview-weekday">{label}</div>|]

renderOverviewDayCell :: (?context :: ControllerContext) => Int -> Id RosterGroup -> [RosterWeekOverviewDay] -> Day -> Day -> RosterViewCapabilities -> Maybe Day -> Html
renderOverviewDayCell _ _ _ _ _ _ Nothing = [hsx|<div class="roster-week-overview-day-spacer" aria-hidden="true"></div>|]
renderOverviewDayCell weekOffset rosterGroupId weekOverviewDays initialDate todayDate viewCapabilities (Just date) =
    let
        maybeOverviewDay = find (\daySummary -> overviewDate daySummary == date) weekOverviewDays
        isInVisibleWeek = isJust maybeOverviewDay
        isSelected = date == initialDate
        navigateUrl = appendQueryParams (pathTo (ShowRosterWeekAction weekOffset)) [("rosterGroupId", tshow rosterGroupId), ("weekDate", formatDayParam date)]
        weekStartLabel = "Week of " <> Text.pack (formatTime defaultTimeLocale "%-d %b" (startOfWeek date))
        leaveCountText
            | viewCapabilities.canViewLeaveMetrics = maybe "" (tshow . leaveRequestCount) maybeOverviewDay
            | otherwise = ""
        assignedText = maybe "" (tshow . overviewAssignedShiftCount) maybeOverviewDay
        hoursText = maybe "" (formatMinutesAsHours . scheduledMinutes) maybeOverviewDay
        detailsAvailable = isInVisibleWeek
        detailSummary =
            if isInVisibleWeek
                then weekOverviewMetricSummaryMaybe maybeOverviewDay viewCapabilities.canViewLeaveMetrics
                else "No loaded roster summary for this date yet."
        closedState = maybe False overviewIsClosed maybeOverviewDay
        closedStateText :: Text
        closedStateText = if closedState then "true" else "false"
        detailsAvailableText :: Text
        detailsAvailableText = if detailsAvailable then "true" else "false"
        leaveDot =
            if viewCapabilities.canViewLeaveMetrics && maybe False ((> 0) . leaveRequestCount) maybeOverviewDay
                then [hsx|<span class="roster-week-overview-day-dot" aria-hidden="true"></span>|]
                else mempty
     in
        [hsx|
            <button type="button"
                    class={classes [("roster-week-overview-day", True), ("is-selected", isSelected), ("is-current-week", isInVisibleWeek), ("is-closed", closedState), ("is-today", date == todayDate)]}
                    data-week-overview-day="true"
                    data-week-overview-date={formatDayParam date}
                    data-week-overview-label={renderSelectedDateLabel date}
                    data-week-overview-week-label={weekStartLabel}
                    data-week-overview-url={navigateUrl}
                    data-week-overview-leave={leaveCountText}
                    data-week-overview-assigned={assignedText}
                    data-week-overview-hours={hoursText}
                    data-week-overview-closed={closedStateText}
                    data-week-overview-details={detailsAvailableText}
                    data-week-overview-summary={detailSummary}
                    aria-pressed={isSelected}>
                <span class="roster-week-overview-day-number">{Text.pack (formatTime defaultTimeLocale "%-d" date)}</span>
                {leaveDot}
            </button>
        |]

renderWeekOverviewDetailsCard :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Day -> Maybe RosterWeekOverviewDay -> RosterViewCapabilities -> Html
renderWeekOverviewDetailsCard weekOffset rosterGroupId initialDate initialOverviewDay viewCapabilities =
    let
        navigateUrl = appendQueryParams (pathTo (ShowRosterWeekAction weekOffset)) [("rosterGroupId", tshow rosterGroupId), ("weekDate", formatDayParam initialDate)]
        closedState = maybe False overviewIsClosed initialOverviewDay
        closedBadge =
            if closedState
                then [hsx|<span class="badge text-bg-secondary">Closed</span>|]
                else mempty
        leaveMetric =
            if viewCapabilities.canViewLeaveMetrics
                then [hsx|
                    <div class="roster-week-overview-metric">
                        <span class="roster-week-overview-metric-value" data-week-overview-leave-value="true">{maybe "0" (tshow . leaveRequestCount) initialOverviewDay}</span>
                        <span class="roster-week-overview-metric-label">leave requests</span>
                    </div>
                |]
                else mempty
     in
        [hsx|
            <div class="roster-week-overview-details" data-week-overview-details-panel="true">
                <div class="roster-week-overview-details-label">Selected date</div>
                <div class="roster-week-overview-details-date" data-week-overview-selected-label="true">{renderSelectedDateLabel initialDate}</div>
                <div class="roster-week-overview-metrics">
                    {leaveMetric}
                    <div class="roster-week-overview-metric">
                        <span class="roster-week-overview-metric-value" data-week-overview-assigned-value="true">{maybe "0" (tshow . overviewAssignedShiftCount) initialOverviewDay}</span>
                        <span class="roster-week-overview-metric-label">shifts assigned</span>
                    </div>
                    <div class="roster-week-overview-metric">
                        <span class="roster-week-overview-metric-value" data-week-overview-hours-value="true">{maybe "0h" (formatMinutesAsHours . scheduledMinutes) initialOverviewDay}</span>
                        <span class="roster-week-overview-metric-label">rostered hours</span>
                    </div>
                </div>
                <div class="roster-week-overview-summary" data-week-overview-summary-text="true">
                    {maybe "No loaded roster summary for this date yet." (\daySummary -> weekOverviewMetricSummary daySummary viewCapabilities.canViewLeaveMetrics) initialOverviewDay}
                </div>
                <div class="roster-week-overview-week-target">
                    <span data-week-overview-week-label="true">In {renderWeekLabelWithPrefix initialDate}</span>
                    {closedBadge}
                </div>
                <a href={navigateUrl}
                   class="btn btn-primary roster-week-overview-go"
                   data-week-overview-go-link="true">
                    Go to this week
                </a>
            </div>
        |]

renderSelectedDateLabel :: Day -> Text
renderSelectedDateLabel date = Text.pack (formatTime defaultTimeLocale "%a %-d %b" date)

renderWeekLabelWithPrefix :: Day -> Text
renderWeekLabelWithPrefix date = "week of " <> Text.pack (formatTime defaultTimeLocale "%-d %b" (startOfWeek date))

weekOverviewMetricSummaryMaybe :: Maybe RosterWeekOverviewDay -> Bool -> Text
weekOverviewMetricSummaryMaybe Nothing _ = "No loaded roster summary for this date yet."
weekOverviewMetricSummaryMaybe (Just daySummary) includeLeaveMetrics = weekOverviewMetricSummary daySummary includeLeaveMetrics

weekOverviewMetricSummary :: RosterWeekOverviewDay -> Bool -> Text
weekOverviewMetricSummary daySummary includeLeaveMetrics
    | overviewIsClosed daySummary = "This day is closed for rostering."
    | not includeLeaveMetrics && overviewAssignedShiftCount daySummary == 0 = "No assigned shifts loaded for this date yet."
    | leaveRequestCount daySummary == 0 && overviewAssignedShiftCount daySummary == 0 = "No leave requests or assigned shifts loaded for this date yet."
    | not includeLeaveMetrics =
        tshow (overviewAssignedShiftCount daySummary) <> " shifts assigned, "
            <> formatMinutesAsHours (scheduledMinutes daySummary) <> " rostered."
    | otherwise =
        tshow (leaveRequestCount daySummary) <> " leave requests, "
            <> tshow (overviewAssignedShiftCount daySummary) <> " shifts assigned, "
            <> formatMinutesAsHours (scheduledMinutes daySummary) <> " rostered."

formatDayParam :: Day -> Text
formatDayParam date = Text.pack (formatTime defaultTimeLocale "%Y-%m-%d" date)

formatMinutesAsHours :: Int -> Text
formatMinutesAsHours minutes =
    let hours = minutes `div` 60
        remainder = minutes `mod` 60
     in if remainder == 0
        then tshow hours <> "h"
        else tshow hours <> "h " <> tshow remainder <> "m"

startOfWeek :: Day -> Day
startOfWeek date =
    let (_, _, weekdayNumber) = toWeekDate date
     in Calendar.addDays (toInteger (1 - weekdayNumber)) date

buildOverviewMonthDays :: Day -> [Maybe Day]
buildOverviewMonthDays focusDate =
    let
        (year, month, _) = Calendar.toGregorian focusDate
        monthStart = Calendar.fromGregorian year month 1
        (_, _, startWeekday) = toWeekDate monthStart
        dayCount = Calendar.gregorianMonthLength year month
        days = map (Just . Calendar.fromGregorian year month) [1 .. dayCount]
        leading = replicate (startWeekday - 1) Nothing
        totalCells = length leading + length days
        trailing = replicate ((7 - totalCells `mod` 7) `mod` 7) Nothing
     in leading <> days <> trailing

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

renderRosterContentFragment :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterViewCapabilities -> Html
renderRosterContentFragment =
    renderRosterContentFragmentWithSwap Nothing

renderRosterContentFragmentOob :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterViewCapabilities -> Html
renderRosterContentFragmentOob =
    renderRosterContentFragmentWithSwap (Just "outerHTML")

renderRosterContentFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterViewCapabilities -> Html
renderRosterContentFragmentWithSwap maybeSwapOob rosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities = [hsx|
    <div id={rosterContentFragmentId} hx-swap-oob={maybeSwapOob}>
        {renderRosterContent rosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities}
    </div>
|]

renderRosterContent :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterViewCapabilities -> Html
renderRosterContent Nothing rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities =
    renderRosterGrid Nothing rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities

renderRosterContent (Just rosterWeek) rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities =
    renderRosterGrid (Just rosterWeek) rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities

renderRosterGrid :: (?context :: ControllerContext) => Maybe RosterWeek -> [RosterDay] -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> [RosterStaffPanelEntry] -> [SlotName] -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterViewCapabilities -> Html
renderRosterGrid maybeRosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities = [hsx|
    <div class="row g-4 align-items-start roster-layout">
        <div class={classes [("col-12", True), ("col-xl-8", currentUserIsManager), ("col-xxl-9", currentUserIsManager), ("mx-auto", not currentUserIsManager), ("roster-layout-main", currentUserIsManager)]}>
            <div class="app-panel overflow-hidden mb-5 mb-xl-0">
                {renderRosterGridHeader maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters weekStartDate viewCapabilities}
                <div class="table-responsive">
                    <table class="table table-bordered table-sm mb-0 align-middle roster-grid"
                           style={"--roster-slot-count:" <> tshow (max 1 (length slotNames)) <> ";"}>
                        {renderRosterGridColGroup slotNames}
                        <thead class="text-center text-uppercase fw-bold roster-grid-head">
                            <tr>
                                <th rowspan="2" class="py-2 roster-day-column">Day</th>
                                {forEach slotNames renderSlotHeaderGroup}
                            </tr>
                            <tr>
                                {forEach slotNames renderSlotSubHeaders}
                            </tr>
                        </thead>
                        <tbody>
                            {forEach rosterDays (renderRosterDay (rosterWeekIsEditable maybeRosterWeek) slotNames assignmentFilters staffMembers staffOptionStates weekStartDate allSlots slotConflicts renderIndexes)}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
        {forEach maybeRosterWeek (\rosterWeek -> renderRosterStaffPanelFragment weekOffset (coerce rosterWeek.rosterGroupId) panelStaff)}
    </div>
|]

renderRosterGridColGroup :: [SlotName] -> Html
renderRosterGridColGroup slotNames = [hsx|
    <colgroup>
        <col style={("width: var(--roster-day-share);" :: Text)} />
        {forEach slotNames renderRosterBlockColGroup}
    </colgroup>
|]

renderRosterBlockColGroup :: SlotName -> Html
renderRosterBlockColGroup _ =
    mconcat
        [ [hsx|<col style={("width: var(--roster-time-share);" :: Text)} />|]
        , [hsx|<col style={("width: var(--roster-staff-share);" :: Text)} />|]
        , [hsx|<col style={("width: var(--roster-note-share);" :: Text)} />|]
        ]

renderRosterGridHeader :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> Day -> RosterViewCapabilities -> Html
renderRosterGridHeader maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters weekStartDate viewCapabilities = [hsx|
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
            {renderRosterWeekMoreMenu maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters viewCapabilities}
        </div>
    </div>
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

renderRosterWeekMoreMenu :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> [RosterGroup] -> RosterGroup -> RosterAssignmentFilters -> RosterViewCapabilities -> Html
renderRosterWeekMoreMenu maybeRosterWeek weekOffset rosterGroups currentRosterGroup assignmentFilters viewCapabilities =
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
        <div class="dropdown-menu dropdown-menu-end p-2 roster-week-more-menu" aria-labelledby={menuTriggerId}>
            <div class="px-1 pb-2">
                {renderRosterGroupSwitcher weekOffset rosterGroups currentRosterGroup}
            </div>
            <div class="dropdown-divider my-1"></div>
            {renderRosterExportMenuSection viewCapabilities}
            {renderRosterAssignmentFiltersMenuSection weekOffset currentRosterGroup.id menuTriggerId assignmentFilters viewCapabilities}
            {when (shouldShowRosterWeekMenuDivider maybeRosterWeek viewCapabilities) divider}
            {renderSyncSlotStructureButton maybeRosterWeek viewCapabilities}
        </div>
    </div>
|]

renderRosterExportMenuSection :: RosterViewCapabilities -> Html
renderRosterExportMenuSection viewCapabilities
    | not viewCapabilities.canExportRosterImage = mempty
    | otherwise = [hsx|
        <div class="px-1 py-1">
            <div class="small text-uppercase fw-semibold text-body-secondary px-1 pb-2">Share roster</div>
            <div class="d-grid gap-2">
                {renderRosterExportButton "png" "Export PNG"}
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
    not rosterWeek.isLive && (viewCapabilities.canManageAssignmentFilter || viewCapabilities.canSyncRosterWeekSlots)
shouldShowRosterWeekMenuDivider Nothing _ = False

renderRosterAssignmentFiltersMenuSection :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Text -> RosterAssignmentFilters -> RosterViewCapabilities -> Html
renderRosterAssignmentFiltersMenuSection weekOffset rosterGroupId menuTriggerId filters viewCapabilities =
    if viewCapabilities.canManageAssignmentFilter
        then [hsx|
    <div class="dropdown-divider my-1"></div>
    <form class="px-1 py-1"
          method="POST"
          action={appendQueryParams (pathTo (UpdateRosterAssignmentFiltersAction weekOffset)) [("rosterGroupId", tshow rosterGroupId)]}
          data-roster-filter-form="true"
          data-roster-filter-menu-trigger-id={menuTriggerId}
          data-disable-javascript-submission="true"
          hx-post={appendQueryParams (pathTo (UpdateRosterAssignmentFiltersAction weekOffset)) [("rosterGroupId", tshow rosterGroupId)]}
          hx-target={"#" <> rosterContentFragmentId}
          hx-swap="outerHTML"
          hx-push-url="false"
          hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
        <div class="small text-uppercase fw-semibold text-body-secondary px-1 pb-2">Hide from dropdowns</div>
        <div class="roster-assignment-filter-grid">
            {renderRosterAssignmentFilterToggle "hide-staff-at-ideal" "hideStaffAtIdealShifts" filters.hideStaffAtIdealShifts "At ideal shifts or greater"}
            {renderRosterAssignmentFilterToggle "hide-staff-unavailable" "hideStaffUnavailable" filters.hideStaffUnavailable "No preferred shifts that day"}
            {renderRosterAssignmentFilterToggle "hide-staff-on-leave" "hideStaffOnApprovedLeave" filters.hideStaffOnApprovedLeave "Approved leave on this date"}
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

rosterWeekIsEditable :: (?context :: ControllerContext) => Maybe RosterWeek -> Bool
rosterWeekIsEditable maybeRosterWeek =
    currentUserIsManager && maybe False (not . (.isLive)) maybeRosterWeek

renderRosterStaffPanelFragment :: (?context :: ControllerContext) => Int -> Id RosterGroup -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanelFragment =
    renderRosterStaffPanelFragmentWithSwap Nothing

renderRosterStaffPanelFragmentOob :: (?context :: ControllerContext) => Int -> Id RosterGroup -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanelFragmentOob =
    renderRosterStaffPanelFragmentWithSwap (Just "outerHTML")

renderRosterStaffPanelFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Int -> Id RosterGroup -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanelFragmentWithSwap maybeSwapOob weekOffset currentRosterGroupId panelStaff =
    if currentUserIsManager
        then [hsx|
            <div id={rosterStaffPanelFragmentId}
                 class="col-12 col-xl-4 col-xxl-3 roster-layout-side"
                 hx-swap-oob={maybeSwapOob}>
                {renderRosterStaffPanel weekOffset currentRosterGroupId panelStaff}
            </div>
        |]
        else mempty

renderRosterStaffPanel :: Int -> Id RosterGroup -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanel weekOffset currentRosterGroupId panelStaff = [hsx|
    <div class="app-panel roster-staff-panel">
        <div class="app-panel-body">
            <div class="roster-staff-panel-header">
                <div>
                    <h2 class="h5 mb-1">Staff</h2>
                    <div class="roster-staff-panel-summary">{tshow (length panelStaff)} active staff</div>
                </div>
            </div>

            <div class="roster-staff-panel-list">
                <table class="roster-staff-table">
                    <thead class="roster-staff-table-head">
                        <tr>
                            <th scope="col" aria-sort="none">
                                <button type="button" class="roster-staff-sort-button" data-roster-staff-sort-key="name">
                                    Name
                                </button>
                            </th>
                            <th scope="col" class="roster-staff-role-head" aria-sort="none">
                                <button type="button" class="roster-staff-sort-button" data-roster-staff-sort-key="role">
                                    Role
                                </button>
                            </th>
                            <th scope="col" class="roster-staff-metric-head" aria-sort="none">
                                <button type="button" class="roster-staff-sort-button roster-staff-sort-button-metric" data-roster-staff-sort-key="shifts">
                                    Shifts
                                </button>
                            </th>
                            <th scope="col" class="roster-staff-action-head">Edit</th>
                        </tr>
                    </thead>
                    <tbody class="roster-staff-table-body">
                        {forEach panelStaff (renderRosterStaffPanelEntry panelStaffMembers weekOffset currentRosterGroupId)}
                    </tbody>
                </table>
            </div>
        </div>
    </div>
|]
    where
        panelStaffMembers = map (.staff) panelStaff

renderRosterStaffPanelEntry :: [Staff] -> Int -> Id RosterGroup -> RosterStaffPanelEntry -> Html
renderRosterStaffPanelEntry panelStaffMembers weekOffset currentRosterGroupId entry =
    let
        staffDisplayLabel = staffDisplayName panelStaffMembers entry.staff
        staffRoleLabel = humanizeStaffRole entry.userRole
     in
        [hsx|
            <tr class="roster-staff-panel-entry"
                data-roster-staff-name={staffDisplayLabel}
                data-roster-staff-role={staffRoleLabel}
                data-roster-staff-assigned={tshow entry.assignedShiftCount}
                data-roster-staff-ideal={tshow entry.staff.idealShiftsPerWeek}>
                <th scope="row" class="roster-staff-cell roster-staff-name">
                    <div class="roster-staff-name-primary">{staffDisplayLabel}</div>
                </th>
                <td class="roster-staff-cell roster-staff-role">{staffRoleLabel}</td>
                <td class="roster-staff-cell roster-staff-shifts">{renderShiftSummary entry}</td>
                <td class="roster-staff-cell roster-staff-action">
                    <button type="button"
                       class="btn btn-sm btn-outline-secondary roster-staff-edit-button"
                       hx-get={appendQueryParams (pathTo (EditStaffAction entry.staff.id)) [("weekOffset", tshow weekOffset), ("rosterGroupId", tshow currentRosterGroupId)]}
                       hx-target={"#" <> htmxModalMountId}
                       hx-swap="innerHTML"
                       hx-push-url="false">
                        Edit
                    </button>
                </td>
            </tr>
        |]

humanizeStaffRole :: Text -> Text
humanizeStaffRole "venue_admin" = "Venue Admin"
humanizeStaffRole "venue_owner" = "Venue Owner"
humanizeStaffRole "manager"     = "Manager"
humanizeStaffRole "worker"      = "Worker"
humanizeStaffRole other         = Text.toTitle (Text.replace "_" " " other)

renderShiftSummary :: RosterStaffPanelEntry -> Html
renderShiftSummary entry = [hsx|
    <span class="roster-staff-shifts-actual">{tshow entry.assignedShiftCount}</span>
    <span class="roster-staff-shifts-ideal">({tshow entry.staff.idealShiftsPerWeek})</span>
|]

renderSlotHeaderGroup :: SlotName -> Html
renderSlotHeaderGroup slotName = [hsx|
    <th colspan="3" class="py-2 roster-block-header">{slotName.name}</th>
|]

renderSlotSubHeaders :: SlotName -> Html
renderSlotSubHeaders _ =
    mconcat
        [ [hsx|<th class="py-1 roster-subhead roster-col-time">Time</th>|]
        , [hsx|<th class="py-1 roster-subhead roster-col-staff">Staff</th>|]
        , [hsx|<th class="py-1 roster-subhead roster-col-code roster-block-end">Flag</th>|]
        ]

renderRosterDay :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterDay -> Html
renderRosterDay isEditable slotNames assignmentFilters staffMembers staffOptionStates weekStartDate allSlots slotConflicts renderIndexes rosterDay =
    renderRosterDaySectionFragment isEditable slotNames assignmentFilters staffMembers staffOptionStates weekStartDate allSlots slotConflicts renderIndexes rosterDay

renderRosterDaySectionFragment :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterDay -> Html
renderRosterDaySectionFragment =
    renderRosterDaySectionFragmentWithSwap Nothing

renderRosterDaySectionFragmentOob :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterDay -> Html
renderRosterDaySectionFragmentOob =
    renderRosterDaySectionFragmentWithSwap (Just "outerHTML")

renderRosterDaySectionFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterDay -> Html
renderRosterDaySectionFragmentWithSwap maybeSwapOob isEditable slotNames assignmentFilters staffMembers staffOptionStates weekStartDate allSlots slotConflicts renderIndexes rosterDay = [hsx|
    <tbody id={rosterDaySectionDomId rosterDay.id}
           data-roster-day-section="true"
           hx-swap-oob={maybeSwapOob}>
        {renderDayRows isEditable slotNames assignmentFilters staffMembers staffOptionStates (Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate) rosterDay dayRows renderIndexes}
    </tbody>
|]
    where
        dayRows = Map.findWithDefault (rowsForDay rosterDay daySlots) (coerce (get #id rosterDay)) renderIndexes.rosterDayRowsByDayId
        daySlots = filter (\s -> s.rosterDayId == coerce (get #id rosterDay)) allSlots

rowsForDay :: RosterDay -> [RosterSlot] -> [(Int, [RosterSlot])]
rowsForDay rosterDay slots =
    map (\rowIndex -> (rowIndex, filter (\slot -> slot.rowIndex == rowIndex) slots)) visibleIndices
    where
        existingIndices = slots |> map (.rowIndex) |> nub |> sort
        visibleIndices
            | rosterDay.isClosed = [0 .. closedRosterDayRows - 1]
            | otherwise =
                let highestIndex = case existingIndices of
                        [] -> minimumOpenRosterRows - 1
                        _  -> max (minimumOpenRosterRows - 1) (fromMaybe (minimumOpenRosterRows - 1) (last existingIndices))
                 in [0 .. highestIndex]

lastRowIndexForRows :: [(Int, [RosterSlot])] -> Int
lastRowIndexForRows dayRows = maybe (-1) fst (last dayRows)

renderDayRows :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> [(Int, [RosterSlot])] -> RosterRenderIndexes -> Html
renderDayRows isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay dayRows renderIndexes = [hsx|
    {forEach indexedRows (renderRow isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex renderIndexes)}
|]
    where
        rowCount = length dayRows
        lastRowIndex = lastRowIndexForRows dayRows
        indexedRows = zip [0 :: Int ..] dayRows

renderRow :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> Int -> Int -> RosterRenderIndexes -> (Int, (Int, [RosterSlot])) -> Html
renderRow isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex renderIndexes rowData =
    renderRowWithAttrs isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex renderIndexes rowData Nothing

renderRowFragment :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> Int -> Int -> RosterRenderIndexes -> (Int, (Int, [RosterSlot])) -> Html
renderRowFragment = renderRow

renderRowOob :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> Int -> Int -> RosterRenderIndexes -> (Int, (Int, [RosterSlot])) -> Html
renderRowOob isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex renderIndexes rowData =
    [hsx|<template>{renderRowWithAttrs isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex renderIndexes rowData (Just "outerHTML")}</template>|]

renderRowWithAttrs :: (?context :: ControllerContext) => Bool -> [SlotName] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Day -> RosterDay -> Int -> Int -> RosterRenderIndexes -> (Int, (Int, [RosterSlot])) -> Maybe Text -> Html
renderRowWithAttrs isEditable slotNames assignmentFilters staffMembers staffOptionStates date rosterDay rowCount lastRowIndex renderIndexes (rowPosition, (rowIndex, rowSlots)) maybeSwapOob = [hsx|
    <tr id={rosterRowDomIdText rosterDay.id rowIndex}
        data-roster-row="true"
        hx-swap-oob={maybeSwapOob}
        class={classes [("day-row", True), ("day-row-" <> tshow (get #dayOffset rosterDay), True), ("day-alt-dark", odd (get #dayOffset rosterDay)), ("day-alt-light", even (get #dayOffset rosterDay))]}>
        {renderDayLabel isEditable date rosterDay rowCount rowPosition lastRowIndex}
        {forEach (zip [0 :: Int ..] slotNames) (renderBlockCells isEditable assignmentFilters staffMembers staffOptionStates rosterDay rowIndex rowSlots renderIndexes)}
    </tr>
|]

rosterRowDomIdText :: Id RosterDay -> Int -> Text
rosterRowDomIdText rosterDayId rowIndex = "roster-row-" <> tshow rosterDayId <> "-" <> tshow rowIndex

renderDayLabel :: (?context :: ControllerContext) => Bool -> Day -> RosterDay -> Int -> Int -> Int -> Html
renderDayLabel isEditable date rosterDay rowCount rowPosition lastRowIndex
    | rowPosition == 0 = [hsx|
        <td class="fw-bold day-label day-label-stack" rowspan={tshow rowCount}>
            <div class="roster-day-label-stack" style={"--roster-day-label-rows:" <> tshow rowCount}>
                <div class="roster-day-label-row roster-day-label-row-primary">
                    <div class="roster-day-heading">{renderPrimaryDayLabel date}</div>
                </div>
                <div class="roster-day-label-row roster-day-label-row-controls">
                    {renderDayRowControls isEditable rosterDay lastRowIndex}
                </div>
                {renderClosedDayLabel rosterDay}
                {renderEmptyDayLabelRows rowCount (if rosterDay.isClosed then 3 else 2)}
            </div>
        </td>
    |]
    | otherwise = mempty

renderPrimaryDayLabel :: Day -> Html
renderPrimaryDayLabel date = [hsx|
    <div class="roster-day-date">{Text.pack (formatTime defaultTimeLocale "%a" date)} {Text.pack (formatTime defaultTimeLocale "%d/%m" date)}</div>
|]

renderClosedDayLabel :: RosterDay -> Html
renderClosedDayLabel rosterDay
    | rosterDay.isClosed = [hsx|
        <div class="roster-day-label-row roster-day-label-row-closed">
            <div class="roster-day-closed-label">CLOSED</div>
        </div>
    |]
    | otherwise = mempty

renderEmptyDayLabelRows :: Int -> Int -> Html
renderEmptyDayLabelRows rowCount consumedRows =
    mconcat (map (\_ -> [hsx|<div class="roster-day-label-row roster-day-label-row-empty" aria-hidden="true"></div>|]) [consumedRows + 1 .. rowCount])

renderDayRowControls :: (?context :: ControllerContext) => Bool -> RosterDay -> Int -> Html
renderDayRowControls isEditable rosterDay lastRowIndex =
    if isEditable
        then [hsx|
            <span class="roster-day-actions">
                {renderToggleClosedButton rosterDay}
                {when (not rosterDay.isClosed) (renderDeleteLastRowButton rosterDay lastRowIndex)}
                {when (not rosterDay.isClosed) (renderAddRowButton rosterDay)}
            </span>
        |]
        else [hsx|<span class="roster-day-actions-placeholder"></span>|]

renderToggleClosedButton :: (?context :: ControllerContext) => RosterDay -> Html
renderToggleClosedButton rosterDay =
    if currentUserIsManager
        then [hsx|
            <form method="POST"
                  action={ToggleRosterDayClosedAction rosterDay.id}
                  class="d-inline"
                  data-disable-javascript-submission="true"
                  hx-post={ToggleRosterDayClosedAction rosterDay.id}
                  hx-target={"#" <> rosterContentFragmentId}
                  hx-swap="outerHTML"
                  hx-push-url="false"
                  hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
                <button type="submit"
                        class={classes [("btn btn-sm roster-day-action roster-day-action-toggle", True), ("is-active", rosterDay.isClosed)]}
                        data-roster-day-closed-toggle="true"
                        title={if rosterDay.isClosed then ("Reopen day" :: Text) else ("Mark day closed" :: Text)}>
                    {if rosterDay.isClosed then ("open" :: Text) else ("close" :: Text)}
                </button>
            </form>
        |]
        else [hsx|<span></span>|]

renderAddRowButton :: (?context :: ControllerContext) => RosterDay -> Html
renderAddRowButton rosterDay =
    if currentUserIsManager
        then [hsx|
            <form method="POST"
                  action={AddRosterRowAction rosterDay.id}
                  class="d-inline"
                  data-disable-javascript-submission="true"
                  hx-post={AddRosterRowAction rosterDay.id}
                  hx-target={"#" <> rosterContentFragmentId}
                  hx-swap="outerHTML"
                  hx-push-url="false"
                  hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
                <button type="submit"
                        class="btn btn-sm roster-day-action roster-day-action-add"
                        data-roster-day-add="true"
                        title="Add shift row">
                    +
                </button>
            </form>
        |]
        else [hsx|<span></span>|]

renderDeleteLastRowButton :: (?context :: ControllerContext) => RosterDay -> Int -> Html
renderDeleteLastRowButton rosterDay rowIndex =
    if currentUserIsManager
        then
            let canDelete = rowIndex >= minimumOpenRosterRows
             in [hsx|
            <form method="POST"
                  action={RemoveRosterRowAction rosterDay.id}
                  class="d-inline"
                  data-disable-javascript-submission="true"
                  hx-post={RemoveRosterRowAction rosterDay.id}
                  hx-target={"#" <> rosterContentFragmentId}
                  hx-swap="outerHTML"
                  hx-push-url="false"
                  hx-sync={"#" <> rosterWeekShellId <> ":replace"}>
                <button type="submit"
                        class="btn btn-sm roster-day-action roster-day-action-remove"
                        data-roster-day-remove="true"
                        title={if canDelete then ("Delete last shift row" :: Text) else ("Minimum day size reached" :: Text)}
                        disabled={not canDelete}>
                    -
                </button>
            </form>
        |]
        else [hsx|<span></span>|]

renderBlockCells :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> RosterDay -> Int -> [RosterSlot] -> RosterRenderIndexes -> (Int, SlotName) -> Html
renderBlockCells isEditable assignmentFilters staffMembers staffOptionStates rosterDay rowIndex rowSlots renderIndexes (blockIndex, slotName)
    | rosterDay.isClosed = renderClosedBlockCells blockIndex
    | otherwise =
    case Map.lookup (coerce (get #id rosterDay), rowIndex, coerce (get #id slotName)) renderIndexes.rosterSlotByDayRowSlotName of
        Just slot ->
            let currentStartTime = optionalTimeOfDayToStorageValue slot.startTime
                currentNote = fromMaybe "" slot.note
                currentPrimaryConflict = primaryConflict (lookupConflicts (get #id slot) renderIndexes)
                currentStaffLabel = fromMaybe "" (renderAssignedStaffLabel slot.staffId renderIndexes)
             in [hsx|
                <td class={classes [("slot-time-cell", True), ("roster-block-start", blockIndex > 0)]}>
                    {if isEditable then renderEditableTimeCell slot.id currentStartTime else renderReadOnlyCell (renderTimePickerDisplayLabel "Time" currentStartTime)}
                </td>

                <td class={classes [("slot-staff-cell position-relative", True), (renderConflictClass currentPrimaryConflict, True)]}
                    title={renderConflictMessage currentPrimaryConflict}
                    data-conflict-message={renderConflictMessage currentPrimaryConflict}>
                    {if isEditable then renderEditableStaffCell assignmentFilters slot.id slot.staffId staffMembers staffOptionStates currentPrimaryConflict else renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict}
                </td>

                <td class="slot-note-cell roster-block-end">
                    {if isEditable then renderEditableNoteCell slot.id currentNote else renderReadOnlyCell currentNote}
                </td>
            |]
        Nothing ->
            mconcat
                [ [hsx|<td class={classes [("slot-empty-cell", True), ("roster-block-start", blockIndex > 0)]}></td>|]
                , [hsx|<td class="slot-empty-cell"></td>|]
                , [hsx|<td class="slot-empty-cell roster-block-end"></td>|]
                ]

renderClosedBlockCells :: Int -> Html
renderClosedBlockCells blockIndex =
    mconcat
        [ [hsx|<td class={classes [("slot-closed-cell", True), ("roster-block-start", blockIndex > 0)]}></td>|]
        , [hsx|<td class="slot-closed-cell"></td>|]
        , [hsx|<td class="slot-closed-cell roster-block-end"></td>|]
        ]

renderStaffOption :: [Staff] -> Maybe UUID -> Maybe RosterAssignmentOptionState -> Staff -> Html
renderStaffOption staffMembers selectedStaffId maybeOptionState staff = [hsx|
    <option value={tshow (get #id staff)} selected={Just (coerce (get #id staff)) == selectedStaffId}>
        {renderStaffOptionLabel staffMembers staff maybeOptionState}
    </option>
|]

renderStaffOptionLabel :: [Staff] -> Staff -> Maybe RosterAssignmentOptionState -> Text
renderStaffOptionLabel staffMembers staff maybeOptionState =
    case maybeOptionState of
        Nothing -> baseLabel
        Just _  -> baseLabel
    where
        baseLabel = staffDisplayName staffMembers staff

renderEditableTimeCell :: Id RosterSlot -> Text -> Html
renderEditableTimeCell rosterSlotId currentStartTime =
    let pickerConfig =
            (defaultTimePickerConfig "startTime" currentStartTime "06:00" "23:45" False)
                { timePickerShowStepButtons = False
                , timePickerEmptyLabel = "Time"
                , timePickerFieldClasses = ["m-0", "d-flex", "align-items-center", "slot-cell-form"]
                , timePickerControlClasses = ["roster-time-picker-control"]
                , timePickerTriggerClasses = ["btn-sm", "slot-time-trigger"]
                , timePickerAriaLabel = "Select roster slot time"
                }
        inputHtml = [hsx|
            <input type="hidden"
                   name="startTime"
                   value={currentStartTime}
                   class="slot-time-input slot-cell-input js-time-picker-input"
                   data-roster-field-key={rosterFieldKey rosterSlotId "startTime"}
                   hx-post={UpdateRosterSlotAction rosterSlotId}
                   hx-trigger="change"
                   hx-include="closest form"
                   hx-sync={"#" <> rosterWeekShellId <> ":queue last"}
                   hx-swap="none" />
        |]
    in [hsx|
    <form class="m-0">
        {renderTimePickerFieldWithInput pickerConfig inputHtml}
    </form>
|]

renderEditableStaffCell :: RosterAssignmentFilters -> Id RosterSlot -> Maybe UUID -> [Staff] -> Map.Map (UUID, UUID) RosterAssignmentOptionState -> Maybe RosterConflict -> Html
renderEditableStaffCell _ rosterSlotId selectedStaffId staffMembers staffOptionStates currentPrimaryConflict = [hsx|
    <form class="m-0 slot-cell-form">
        <select name="staffId"
                class="form-select form-select-sm slot-cell-input slot-staff-input"
                data-roster-field-key={rosterFieldKey rosterSlotId "staffId"}
                hx-post={UpdateRosterSlotAction rosterSlotId}
                hx-trigger="change"
                hx-include="closest form"
                hx-sync={"#" <> rosterWeekShellId <> ":queue last"}
                hx-swap="none">
            <option value=""></option>
            {forEach visibleStaffMembers (\staff -> renderStaffOption staffMembers selectedStaffId (optionStateForStaff staff) staff)}
        </select>
    </form>
|]
    where
        selectedOrVisible staff =
            let staffId = coerce (get #id staff)
                isSelected = Just staffId == selectedStaffId
             in isSelected || maybe True (not . (.optionHidden)) (optionStateForStaff staff)
        optionStateForStaff staff =
            Map.lookup (coerce rosterSlotId, coerce (get #id staff)) staffOptionStates
        visibleStaffMembers = filter selectedOrVisible staffMembers

renderReadOnlyStaffCell :: Text -> Maybe RosterConflict -> Html
renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict =
    mconcat
        [ [hsx|<div class="slot-cell-static">{currentStaffLabel}</div>|] ]

renderEditableNoteCell :: Id RosterSlot -> Text -> Html
renderEditableNoteCell rosterSlotId currentNote = [hsx|
    <form class="m-0 slot-cell-form">
        <input type="text"
               name="note"
               value={currentNote}
               placeholder=""
               class="form-control form-control-sm slot-note-input slot-cell-input"
               maxlength="2"
               data-roster-field-key={rosterFieldKey rosterSlotId "note"}
               hx-post={UpdateRosterSlotAction rosterSlotId}
               hx-trigger="input changed delay:1200ms"
               hx-include="closest form"
               hx-sync={"#" <> rosterWeekShellId <> ":queue last"}
               hx-swap="none" />
    </form>
|]

rosterFieldKey :: Id RosterSlot -> Text -> Text
rosterFieldKey rosterSlotId fieldName = tshow rosterSlotId <> ":" <> fieldName

renderReadOnlyCell :: Text -> Html
renderReadOnlyCell value = [hsx|
    <div class={classes [("slot-cell-static", True), ("app-muted", Text.null value)]}>{if Text.null value then " " else value}</div>
|]

renderAssignedStaffLabel :: Maybe UUID -> RosterRenderIndexes -> Maybe Text
renderAssignedStaffLabel Nothing _ = Nothing
renderAssignedStaffLabel (Just assignedStaffId) renderIndexes =
    (\staff -> staffDisplayName (Map.elems renderIndexes.rosterStaffById) staff)
        <$> Map.lookup assignedStaffId renderIndexes.rosterStaffById

lookupConflicts :: Id RosterSlot -> RosterRenderIndexes -> [RosterConflict]
lookupConflicts slotId renderIndexes = Map.findWithDefault [] (coerce slotId) renderIndexes.rosterConflictsBySlotId

renderConflictClass :: Maybe RosterConflict -> Text
renderConflictClass Nothing = ""
renderConflictClass (Just conflict) =
    case conflict.conflictType of
        DuplicateAssignment           -> "conflict-critical"
        LeaveConflict                 -> "conflict-critical"
        LateToEarlyConflict           -> "conflict-critical"
        ShiftPreferenceDayUnavailable -> "conflict-preference"
        ShiftPreferenceSlotMismatch   -> "conflict-preference"
        IdealShiftThresholdExceeded   -> "conflict-ideal"

renderConflictMessage :: Maybe RosterConflict -> Text
renderConflictMessage Nothing         = ""
renderConflictMessage (Just conflict) = conflict.message

renderCopyPreviousWeekForm :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Html
renderCopyPreviousWeekForm weekOffset rosterGroupId = [hsx|
    <form method="POST"
          action={appendQueryParams (pathTo (CopyRosterWeekAction (weekOffset - 1) weekOffset)) [("rosterGroupId", tshow rosterGroupId)]}
          data-disable-javascript-submission="true"
          hx-post={appendQueryParams (pathTo (CopyRosterWeekAction (weekOffset - 1) weekOffset)) [("rosterGroupId", tshow rosterGroupId)]}
          hx-target={"#" <> rosterContentFragmentId}
          hx-swap="outerHTML"
          hx-push-url="false"
          hx-sync={"#" <> rosterWeekShellId <> ":replace"}
          hx-confirm="This will overwrite the current week with the previous week's roster. Continue?">
        <button type="submit" class="btn btn-outline-primary">Copy Previous Week</button>
    </form>
|]

renderSyncSlotStructureButton :: (?context :: ControllerContext) => Maybe RosterWeek -> RosterViewCapabilities -> Html
renderSyncSlotStructureButton maybeRosterWeek viewCapabilities =
    case maybeRosterWeek of
        Just rosterWeek | viewCapabilities.canSyncRosterWeekSlots -> [hsx|
            <form method="POST"
                  action={SyncRosterWeekSlotStructureAction rosterWeek.id}
                  data-disable-javascript-submission="true"
                  hx-post={SyncRosterWeekSlotStructureAction rosterWeek.id}
                  hx-target={"#" <> rosterContentFragmentId}
                  hx-swap="outerHTML"
                  hx-push-url="false"
                  hx-sync={"#" <> rosterWeekShellId <> ":replace"}
                  hx-confirm="Sync this draft week to the current slot template? Existing matching slots keep their data; removed slots are dropped and new slots start empty.">
                <button type="submit" class="btn btn-outline-secondary w-100 text-start">Sync Slots</button>
            </form>
        |]
        _ -> mempty

buildRosterViewCapabilities :: (?context :: ControllerContext) => Maybe RosterWeek -> RosterViewCapabilities
buildRosterViewCapabilities maybeRosterWeek =
    let managerAudience = currentUserMatchesAudience ManagerAudience
        draftWeek = maybe False (not . (.isLive)) maybeRosterWeek
     in RosterViewCapabilities
            { canToggleRosterLive = managerAudience && isJust maybeRosterWeek
            , canCopyRosterWeek = managerAudience
            , canExportRosterImage = managerAudience
            , canManageAssignmentFilter = managerAudience
            , canSyncRosterWeekSlots = managerAudience && draftWeek
            , canViewLeaveMetrics = managerAudience
            }

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

liveUpdateScopeKind :: LiveUpdateScope -> Text
liveUpdateScopeKind RosterWeekScope {}        = "roster_week"
liveUpdateScopeKind RosterGroupConfigScope {} = "roster_group_config"
liveUpdateScopeKind AdminSlotNamesScope {}    = "admin_slot_names"
liveUpdateScopeKind AdminInvitesScope {}      = "admin_invites"
liveUpdateScopeKind LeaveRequestsScope {}     = "leave_requests"
liveUpdateScopeKind TimesheetWeekScope {}     = "timesheet_week"

liveUpdateRosterGroupScopeKind :: LiveUpdateScope -> Maybe Text
liveUpdateRosterGroupScopeKind RosterWeekScope {}        = Just "roster_group_config"
liveUpdateRosterGroupScopeKind RosterGroupConfigScope {} = Just "roster_group_config"
liveUpdateRosterGroupScopeKind AdminSlotNamesScope {}    = Nothing
liveUpdateRosterGroupScopeKind AdminInvitesScope {}      = Nothing
liveUpdateRosterGroupScopeKind LeaveRequestsScope {}     = Nothing
liveUpdateRosterGroupScopeKind TimesheetWeekScope {}     = Nothing

liveUpdateVenueId :: LiveUpdateScope -> Text
liveUpdateVenueId RosterWeekScope { venueId }        = tshow venueId
liveUpdateVenueId RosterGroupConfigScope { venueId } = tshow venueId
liveUpdateVenueId AdminSlotNamesScope { venueId }    = tshow venueId
liveUpdateVenueId AdminInvitesScope { venueId }      = tshow venueId
liveUpdateVenueId LeaveRequestsScope { venueId }     = tshow venueId
liveUpdateVenueId TimesheetWeekScope { venueId }     = tshow venueId

liveUpdateRosterGroupIdText :: LiveUpdateScope -> Maybe Text
liveUpdateRosterGroupIdText RosterWeekScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText RosterGroupConfigScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText AdminSlotNamesScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText AdminInvitesScope {} = Nothing
liveUpdateRosterGroupIdText LeaveRequestsScope {} = Nothing
liveUpdateRosterGroupIdText TimesheetWeekScope {} = Nothing

liveUpdateWeekOffsetText :: LiveUpdateScope -> Maybe Text
liveUpdateWeekOffsetText RosterWeekScope { weekOffset } = Just (tshow weekOffset)
liveUpdateWeekOffsetText RosterGroupConfigScope {} = Nothing
liveUpdateWeekOffsetText AdminSlotNamesScope {} = Nothing
liveUpdateWeekOffsetText AdminInvitesScope {} = Nothing
liveUpdateWeekOffsetText LeaveRequestsScope {} = Nothing
liveUpdateWeekOffsetText TimesheetWeekScope { weekOffset } = Just (tshow weekOffset)

rosterWeekPath :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Text
rosterWeekPath weekOffset rosterGroupId =
    appendQueryParams (pathTo (ShowRosterWeekAction weekOffset)) [("rosterGroupId", tshow rosterGroupId)]
