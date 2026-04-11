module Web.View.RosterWeeks.Overview
    ( renderWeekOverviewDropdown
    , renderWeekOverviewPanelFragment
    ) where

import Application.Helper.View (appendQueryParams)
import Data.List (find)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import qualified Data.Time.Calendar as Calendar
import Data.Time.Calendar.WeekDate (toWeekDate)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.RosterWeeks.Types
import Web.View.Prelude

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
