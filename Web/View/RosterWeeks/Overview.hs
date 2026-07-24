{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.Overview
    ( renderRosterWeekLabel
    , renderWeekOverviewDropdown
    , renderWeekOverviewPanelFragment
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import Application.Helper.FrontendContract.Surface.Roster.WeekOverview
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceLazyFragmentConfig (..),
                                                            FrontendSurfaceProtection (..),
                                                            defaultFrontendSurfaceLazyFragmentConfig,
                                                            frontendSurfaceMountedFragmentFor,
                                                            renderFrontendSurfaceLazyFragmentWithConfig)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.WeekBoundaries (orderedWeekdayIndexes, startOfWeekFor,
                                          weekdayIndexForDay)
import Data.List (find, findIndex)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import qualified Data.Time.Calendar as Calendar
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.RosterWeeks.Paths (rosterOverviewFragmentUrl, rosterWeekWithDateUrl)
import Web.RosterWeeks.Types
import Web.View.Prelude

renderWeekOverviewDropdown :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Day -> Html
renderWeekOverviewDropdown weekOffset rosterGroupId weekStartDate =
    let
        triggerId = "roster-week-overview-trigger-" <> tshow rosterGroupId <> "-" <> tshow weekOffset
        fragmentUrl = rosterOverviewFragmentUrl weekOffset rosterGroupId
     in
        [hsx|
            <div class="dropdown roster-week-overview">
                <button class="btn btn-outline-secondary app-week-nav-button roster-week-nav-button roster-week-overview-trigger"
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
                    {renderWeekOverviewLazyMount rosterGroupId weekOffset fragmentUrl}
                </div>
            </div>
        |]

renderWeekOverviewLazyMount :: Id RosterGroup -> Int -> Text -> Html
renderWeekOverviewLazyMount rosterGroupId weekOffset fragmentUrl =
    renderFrontendSurfaceLazyFragmentWithConfig
        defaultFrontendSurfaceLazyFragmentConfig
            { lazyFragmentRootClasses = []
            , lazyFragmentPlaceholderClasses = []
            , lazyFragmentAriaLabel = Just "Loading roster week overview"
            , lazyFragmentRetryEnabled = True
            , lazyFragmentTriggerOverride = Just "load"
            }
        ( frontendSurfaceMountedFragmentFor @Surface.RosterSurface @Surface.RosterWeekOverview
            noSurfaceFields
            ( surfaceField @Surface.RosterGroupId (unpackId rosterGroupId)
                &: surfaceField @Surface.WeekOffset weekOffset
                &: noSurfaceFields
            )
            fragmentUrl
            FrontendSurfaceReplace
        )
        renderWeekOverviewDropdownLoading

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
renderWeekOverviewPanelFragment weekOffset rosterGroupId currentWeekStartDate todayDate weekOverviewDays viewCapabilities =
    let
        initialDate = initialOverviewDate currentWeekStartDate todayDate weekOverviewDays
        monthDays = buildOverviewMonthDays currentWeekStartDate initialDate
        initialOverviewDay = find (\daySummary -> overviewDate daySummary == initialDate) weekOverviewDays
        leaveLegend =
            if viewCapabilities.canViewLeaveMetrics
                then [hsx|<span><span class="roster-week-overview-legend-dot"></span> Unavailable periods</span>|]
                else mempty
     in
        [hsx|
            <div class="roster-week-overview-panel"
                 {...rosterWeekOverviewPanelAttrs todayDate}>
                <div class="roster-week-overview-header">
                    <div>
                        <div class="roster-week-overview-eyebrow">Month overview</div>
                        <div class="roster-week-overview-month">{renderMonthLabel initialDate}</div>
                    </div>
                    <button type="button"
                            class="btn btn-sm btn-outline-secondary"
                            {...rosterWeekOverviewTodayAttrs}>
                        Today
                    </button>
                </div>
                <div class="roster-week-overview-layout">
                    <div class="roster-week-overview-calendar">
                        <div class="roster-week-overview-weekdays">
                            {forEach (weekdayLabels currentWeekStartDate) renderOverviewWeekdayLabel}
                        </div>
                        <div class="roster-week-overview-grid">
                            {forEach monthDays (renderOverviewDayCell weekOffset rosterGroupId currentWeekStartDate weekOverviewDays initialDate todayDate viewCapabilities)}
                        </div>
                        <div class="roster-week-overview-legend">
                            {leaveLegend}
                            <span><span class="roster-week-overview-legend-closed"></span> Closed</span>
                            <span><span class="roster-week-overview-legend-today"></span> Today</span>
                        </div>
                    </div>
                    {renderWeekOverviewDetailsCard weekOffset rosterGroupId currentWeekStartDate initialDate initialOverviewDay viewCapabilities}
                </div>
            </div>
        |]

renderRosterWeekLabel :: Day -> Text
renderRosterWeekLabel weekStartDate = "Week of " <> Text.pack (formatTime defaultTimeLocale "%-d %b" weekStartDate)

weekdayLabels :: Day -> [Text]
weekdayLabels weekStartDate =
    [ Text.pack (formatTime defaultTimeLocale "%a" (Calendar.addDays (toInteger dayOffset) weekStartDate))
    | dayOffset <- [0 .. 6]
    ]

initialOverviewDate :: Day -> Day -> [RosterWeekOverviewDay] -> Day
initialOverviewDate weekStartDate todayDate weekOverviewDays =
    if any (\daySummary -> overviewDate daySummary == todayDate) weekOverviewDays
        then todayDate
        else weekStartDate

renderMonthLabel :: Day -> Text
renderMonthLabel date = Text.pack (formatTime defaultTimeLocale "%B %Y" date)

renderOverviewWeekdayLabel :: Text -> Html
renderOverviewWeekdayLabel label = [hsx|<div class="roster-week-overview-weekday">{label}</div>|]

renderOverviewDayCell :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Day -> [RosterWeekOverviewDay] -> Day -> Day -> RosterViewCapabilities -> Maybe Day -> Html
renderOverviewDayCell _ _ _ _ _ _ _ Nothing = [hsx|<div class="roster-week-overview-day-spacer" aria-hidden="true"></div>|]
renderOverviewDayCell weekOffset rosterGroupId referenceWeekStart weekOverviewDays initialDate todayDate viewCapabilities (Just date) =
    let
        maybeOverviewDay = find (\daySummary -> overviewDate daySummary == date) weekOverviewDays
        detailsAvailable = isJust maybeOverviewDay
        isSelected = date == initialDate
        isClosed = maybe False overviewIsClosed maybeOverviewDay
        availability = if detailsAvailable then RosterWeekOverviewLoaded else RosterWeekOverviewUnloaded
        closure = if isClosed then RosterWeekOverviewClosed else RosterWeekOverviewOpen
        calendarDay = if date == todayDate then RosterWeekOverviewToday else RosterWeekOverviewOtherDay
        leaveDisplay
            | not viewCapabilities.canViewLeaveMetrics = ""
            | detailsAvailable = maybe "0" (tshow . leaveRequestCount) maybeOverviewDay
            | otherwise = "—"
        assignedDisplay = if detailsAvailable then maybe "0" (tshow . overviewAssignedShiftCount) maybeOverviewDay else "—"
        hoursDisplay = if detailsAvailable then maybe "0h" (formatMinutesAsHours . scheduledMinutes) maybeOverviewDay else "—"
        detailSummary =
            if detailsAvailable
                then weekOverviewMetricSummaryMaybe maybeOverviewDay viewCapabilities.canViewLeaveMetrics
                else "No loaded roster summary for this date yet."
        payload = RosterWeekOverviewDayPayload
            { weekOverviewDate = date
            , weekOverviewSelectedLabel = renderSelectedDateLabel date
            , weekOverviewLeaveDisplay = leaveDisplay
            , weekOverviewAssignedDisplay = assignedDisplay
            , weekOverviewHoursDisplay = hoursDisplay
            , weekOverviewSummaryText = detailSummary
            , weekOverviewWeekLabel = "In Week of " <> Text.pack (formatTime defaultTimeLocale "%-d %b" (startOfWeek date referenceWeekStart))
            , weekOverviewNavigationUrl = rosterWeekWithDateUrl weekOffset rosterGroupId date
            , weekOverviewAvailability = availability
            , weekOverviewClosure = closure
            }
        leaveDot =
            if viewCapabilities.canViewLeaveMetrics && maybe False ((> 0) . leaveRequestCount) maybeOverviewDay
                then [hsx|<span class="roster-week-overview-day-dot" aria-hidden="true"></span>|]
                else mempty
     in
        [hsx|
            <button type="button"
                    class="roster-week-overview-day"
                    {...rosterWeekOverviewDayAttrs calendarDay payload}
                    aria-pressed={isSelected}>
                <span class="roster-week-overview-day-number">{Text.pack (formatTime defaultTimeLocale "%-d" date)}</span>
                {leaveDot}
            </button>
        |]

renderWeekOverviewDetailsCard :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Day -> Day -> Maybe RosterWeekOverviewDay -> RosterViewCapabilities -> Html
renderWeekOverviewDetailsCard weekOffset rosterGroupId weekStartDate initialDate initialOverviewDay viewCapabilities =
    let
        navigateUrl = rosterWeekWithDateUrl weekOffset rosterGroupId initialDate
        closedState = maybe False overviewIsClosed initialOverviewDay
        availability = maybe RosterWeekOverviewUnloaded (const RosterWeekOverviewLoaded) initialOverviewDay
        closure = if closedState then RosterWeekOverviewClosed else RosterWeekOverviewOpen
        closedBadge =
            if closedState
                then renderAppStatusBadge AppStatusNeutral "Closed"
                else mempty
        leaveMetric =
            if viewCapabilities.canViewLeaveMetrics
                then [hsx|
                    <div class="roster-week-overview-metric">
                        <span class="roster-week-overview-metric-value" {...rosterWeekOverviewLeaveValueAttrs}>{maybe "0" (tshow . leaveRequestCount) initialOverviewDay}</span>
                        <span class="roster-week-overview-metric-label">unavailable periods</span>
                    </div>
                |]
                else mempty
     in
        [hsx|
            <div class="roster-week-overview-details" {...rosterWeekOverviewDetailsAttrs availability closure}>
                <div class="roster-week-overview-details-label">Selected date</div>
                <div class="roster-week-overview-details-date" {...rosterWeekOverviewSelectedLabelAttrs}>{renderSelectedDateLabel initialDate}</div>
                <div class="roster-week-overview-metrics">
                    {leaveMetric}
                    <div class="roster-week-overview-metric">
                        <span class="roster-week-overview-metric-value" {...rosterWeekOverviewAssignedValueAttrs}>{maybe "0" (tshow . overviewAssignedShiftCount) initialOverviewDay}</span>
                        <span class="roster-week-overview-metric-label">shifts assigned</span>
                    </div>
                    <div class="roster-week-overview-metric">
                        <span class="roster-week-overview-metric-value" {...rosterWeekOverviewHoursValueAttrs}>{maybe "0h" (formatMinutesAsHours . scheduledMinutes) initialOverviewDay}</span>
                        <span class="roster-week-overview-metric-label">rostered hours</span>
                    </div>
                </div>
                <div class="roster-week-overview-summary" {...rosterWeekOverviewSummaryAttrs}>
                    {maybe "No loaded roster summary for this date yet." (\daySummary -> weekOverviewMetricSummary daySummary viewCapabilities.canViewLeaveMetrics) initialOverviewDay}
                </div>
                <div class="roster-week-overview-week-target">
                    <span {...rosterWeekOverviewWeekLabelAttrs}>In {renderWeekLabelWithPrefix initialDate weekStartDate}</span>
                    {closedBadge}
                </div>
                <a href={navigateUrl}
                   class="btn btn-primary roster-week-overview-go"
                   {...rosterWeekOverviewGoLinkAttrs}>
                    Go to this week
                </a>
            </div>
        |]

renderSelectedDateLabel :: Day -> Text
renderSelectedDateLabel date = Text.pack (formatTime defaultTimeLocale "%a %-d %b" date)

renderWeekLabelWithPrefix :: Day -> Day -> Text
renderWeekLabelWithPrefix date referenceWeekStart =
    "week of " <> Text.pack (formatTime defaultTimeLocale "%-d %b" (startOfWeek date referenceWeekStart))

weekOverviewMetricSummaryMaybe :: Maybe RosterWeekOverviewDay -> Bool -> Text
weekOverviewMetricSummaryMaybe Nothing _ = "No loaded roster summary for this date yet."
weekOverviewMetricSummaryMaybe (Just daySummary) includeLeaveMetrics = weekOverviewMetricSummary daySummary includeLeaveMetrics

weekOverviewMetricSummary :: RosterWeekOverviewDay -> Bool -> Text
weekOverviewMetricSummary daySummary includeLeaveMetrics
    | overviewIsClosed daySummary = "This day is closed for rostering."
    | not includeLeaveMetrics && overviewAssignedShiftCount daySummary == 0 = "No assigned shifts loaded for this date yet."
    | leaveRequestCount daySummary == 0 && overviewAssignedShiftCount daySummary == 0 = "No unavailable periods or assigned shifts loaded for this date yet."
    | not includeLeaveMetrics =
        tshow (overviewAssignedShiftCount daySummary) <> " shifts assigned, "
            <> formatMinutesAsHours (scheduledMinutes daySummary) <> " rostered."
    | otherwise =
        tshow (leaveRequestCount daySummary) <> " unavailable periods, "
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

startOfWeek :: Day -> Day -> Day
startOfWeek date referenceWeekStart =
    startOfWeekFor (weekdayIndexForDay referenceWeekStart) date

buildOverviewMonthDays :: Day -> Day -> [Maybe Day]
buildOverviewMonthDays referenceWeekStart focusDate =
    let
        (year, month, _) = Calendar.toGregorian focusDate
        monthStart = Calendar.fromGregorian year month 1
        leadingCount = weekdayDistanceFromWeekStart referenceWeekStart monthStart
        dayCount = Calendar.gregorianMonthLength year month
        days = map (Just . Calendar.fromGregorian year month) [1 .. dayCount]
        leading = replicate leadingCount Nothing
        totalCells = length leading + length days
        trailing = replicate ((7 - totalCells `mod` 7) `mod` 7) Nothing
     in leading <> days <> trailing

weekdayDistanceFromWeekStart :: Day -> Day -> Int
weekdayDistanceFromWeekStart referenceWeekStart date =
    let orderedIndexes = orderedWeekdayIndexes (weekdayIndexForDay referenceWeekStart)
     in fromMaybe 0 (elemIndex (weekdayIndexForDay date) orderedIndexes)
