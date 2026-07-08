{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.Index where

import Application.Helper.Controller (isWithinEditWindow, shiftDurationMinutes)
import Application.Helper.FrontendContract.Overlay (EditTimesheetEntryDialog,
                                                    OpenTimesheetEntryDialog)
import Application.Helper.FrontendContract.Overlay.Runtime (OverlayActionRoute (..),
                                                            overlayActionByMarker,
                                                            renderOverlayActionLink)
import Application.Helper.FrontendContract.Surface.Runtime (SurfaceImpl,
                                                            renderFrontendSurfaceMount)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import Data.Fixed (Pico)
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.UUID (UUID)
import Web.Timesheets.Paths (editTimesheetEntryUrl, newTimesheetEntryUrl,
                             timesheetWeekResetUrl, timesheetWeekUrl)
import Web.View.Prelude

data IndexView = IndexView
    { entries               :: [TimesheetEntry]
    , staffMembers          :: [Staff]
    , shiftTypes            :: [ShiftType]
    , today                 :: Day
    , editWindowDays        :: Int
    , weekOffset            :: Int
    , weekStartDate         :: Day
    , weekEndDate           :: Day
    , showApproved          :: Bool
    , showAllStaff          :: Bool
    , selectedStaffFilterId :: Maybe UUID
    , currentViewerStaffId  :: Maybe UUID
    , frontendSurfaceImpl   :: Maybe (SurfaceImpl Surface.TimesheetsSurface)
    }

data TimesheetDayRenderModel = TimesheetDayRenderModel
    { dayEntries        :: [TimesheetEntry]
    , dayStaffMembers   :: [Staff]
    , dayShiftTypes     :: [ShiftType]
    , dayToday          :: Day
    , dayEditWindowDays :: Int
    , dayWeekOffset     :: Int
    , dayWeekStartDate  :: Day
    , dayShowApproved   :: Bool
    , dayShowAllStaff   :: Bool
    , dayStaffFilterId  :: Maybe UUID
    , dayOffset         :: Int
    }

timesheetWeekShellId :: Text
timesheetWeekShellId = "timesheet-week-shell"

timesheetWeekToolbarId :: Text
timesheetWeekToolbarId = "timesheet-week-toolbar"

timesheetDayColumnsId :: Text
timesheetDayColumnsId = "timesheet-day-columns"

instance View IndexView where
    html = renderTimesheetWeekShell

renderTimesheetWeekShell :: IndexView -> Html
renderTimesheetWeekShell view@IndexView { .. } =
    let page = renderAppPage (AppPageConfig
            { appPageTitle = "Timesheets"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody =
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
                             data-horizontal-snap="nearest-item"
                             data-horizontal-snap-item-selector=".timesheet-day-panel"
                             data-horizontal-drag-scroll="mouse">
                            {renderTimesheetDayColumns view}
                        </div>
                    |]
                    }
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
renderTimesheetWeekToolbarWithSwap maybeSwapOob IndexView { weekOffset, weekStartDate, showApproved, showAllStaff, selectedStaffFilterId, staffMembers } = [hsx|
    <div id={timesheetWeekToolbarId}
         hx-swap-oob={maybeSwapOob}>
        {renderTimesheetWeekHeader weekOffset weekStartDate showApproved showAllStaff selectedStaffFilterId staffMembers}
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

renderTimesheetWeekNavigationLink :: Text -> Text -> Html
renderTimesheetWeekNavigationLink label url = [hsx|
    <a href={url}
       class="btn btn-outline-secondary app-week-nav-button"
       hx-get={url}
       hx-swap="none"
       hx-push-url="true"
       hx-sync={"#" <> timesheetWeekShellId <> ":replace"}>
        {label}
    </a>
|]

renderTimesheetWeekHeader :: (?context :: ControllerContext) => Int -> Day -> Bool -> Bool -> Maybe UUID -> [Staff] -> Html
renderTimesheetWeekHeader weekOffset weekStartDate showApproved showAllStaff selectedStaffFilterId staffMembers =
    renderWeekToolbar WeekToolbarConfig
        { weekToolbarVariant = WeekToolbarTimesheets
        , weekToolbarAriaLabel = "Timesheet week controls"
        , weekToolbarExtraClass = "timesheet-week-header"
        , weekToolbarPrimary = mempty
        , weekToolbarReset = renderTimesheetWeekNavigationLink "This week" (timesheetWeekResetUrl showApproved showAllStaff selectedStaffFilterId)
        , weekToolbarNavigation = [hsx|
            <div class="btn-group app-week-nav-group" role="group" aria-label="Timesheet week navigation">
                {renderTimesheetWeekNavigationLink "<" (timesheetWeekUrl (weekOffset - 1) showApproved showAllStaff selectedStaffFilterId)}
                <div class="btn btn-outline-secondary app-week-nav-label">
                    {renderTimesheetWeekLabel weekStartDate}
                </div>
                {renderTimesheetWeekNavigationLink ">" (timesheetWeekUrl (weekOffset + 1) showApproved showAllStaff selectedStaffFilterId)}
            </div>
        |]
        , weekToolbarSettings = renderTimesheetWeekMoreMenu weekOffset showApproved showAllStaff selectedStaffFilterId staffMembers
        , weekToolbarAuxiliary = mempty
        }

renderTimesheetWeekMoreMenu :: (?context :: ControllerContext) => Int -> Bool -> Bool -> Maybe UUID -> [Staff] -> Html
renderTimesheetWeekMoreMenu weekOffset showApproved showAllStaff selectedStaffFilterId staffMembers =
    let menuTriggerId = "timesheet-week-more-menu-trigger" :: Text
        updateUrl = pathTo (ShowTimesheetWeekAction weekOffset)
     in [hsx|
    <div class="dropdown">
        {renderAppSettingsMenuButton menuTriggerId "Timesheet settings"}
        <div class="dropdown-menu dropdown-menu-end p-2 app-action-menu" aria-labelledby={menuTriggerId}>
            <form class="px-1 py-1"
                  method="GET"
                  action={updateUrl}
                  data-disable-javascript-submission="true"
                  hx-get={updateUrl}
                  hx-swap="none"
                  hx-push-url="true"
                  hx-sync={"#" <> timesheetWeekShellId <> ":replace"}>
                <input type="hidden" name="weekOffset" value={tshow weekOffset} />
                <input type="hidden" name="showApproved" id="timesheet-show-approved-value" value={boolParam showApproved} />
                <input type="hidden" name="showAllStaff" id="timesheet-show-all-staff-value" value={boolParam showAllStaff} />
                <div class="small text-uppercase fw-semibold app-muted px-1 pb-2">Filters</div>
                <div class="timesheet-settings-toggle-grid mb-2">
                    {renderTimesheetHideApprovedToggle showApproved}
                    {when currentUserIsManager (renderTimesheetMenuToggle "timesheet-show-all-staff-toggle" "timesheet-show-all-staff-value" showAllStaff "Show all staff")}
                </div>
                {when currentUserIsManager (renderTimesheetStaffFilter selectedStaffFilterId staffMembers)}
            </form>
        </div>
    </div>
|]

renderTimesheetStaffFilter :: Maybe UUID -> [Staff] -> Html
renderTimesheetStaffFilter selectedStaffFilterId staffMembers = [hsx|
    <div class="mt-3">
        <label for="timesheet-staff-filter" class="form-label small mb-1">Staff</label>
        <select id="timesheet-staff-filter"
                name="staffFilterId"
                class="form-select form-select-sm"
                onchange="this.form.requestSubmit();">
            <option value="" selected={isNothing selectedStaffFilterId}>All staff</option>
            {forEach staffMembers renderOption}
        </select>
    </div>
|]
    where
        renderOption staff =
            let staffId = unpackId (get #id staff)
             in [hsx|
                <option value={tshow staffId} selected={selectedStaffFilterId == Just staffId}>
                    {staff.firstName} {staff.lastName}
                </option>
            |]

renderTimesheetHideApprovedToggle :: Bool -> Html
renderTimesheetHideApprovedToggle showApproved = [hsx|
    <div class="timesheet-settings-toggle">
        {renderTimesheetToggleButton "timesheet-hide-approved-toggle" "timesheet-show-approved-value" (not showApproved) "false" "true" "Hide approved"}
    </div>
|]

renderTimesheetMenuToggle :: Text -> Text -> Bool -> Text -> Html
renderTimesheetMenuToggle inputId hiddenInputId isChecked label = [hsx|
    <div class="timesheet-settings-toggle">
        {renderTimesheetToggleButton inputId hiddenInputId isChecked "true" "false" label}
    </div>
|]

renderTimesheetToggleButton :: Text -> Text -> Bool -> Text -> Text -> Text -> Html
renderTimesheetToggleButton inputId hiddenInputId isChecked checkedValue uncheckedValue label =
    renderAppToggleButton $ (defaultAppToggleButtonConfig inputId isChecked [hsx|<span class="small">{label}</span>|])
        { appToggleButtonClass = "btn-sm w-100 justify-content-start"
        , appToggleHiddenInputId = Just hiddenInputId
        , appToggleHiddenInputCheckedValue = Just checkedValue
        , appToggleHiddenInputUncheckedValue = Just uncheckedValue
        , appToggleOnChange = Just ("document.getElementById('" <> hiddenInputId <> "').value = this.checked ? '" <> checkedValue <> "' : '" <> uncheckedValue <> "'; this.form.requestSubmit();")
        }

renderTimesheetWeekLabel :: Day -> Text
renderTimesheetWeekLabel weekStartDate =
    "Week of " <> Text.pack (formatTime defaultTimeLocale "%-d %b" weekStartDate)

timesheetDayRenderModel :: IndexView -> Int -> TimesheetDayRenderModel
timesheetDayRenderModel IndexView { entries, staffMembers, shiftTypes, today, editWindowDays, weekOffset, weekStartDate, showApproved, showAllStaff, selectedStaffFilterId } dayOffset =
    TimesheetDayRenderModel
        { dayEntries = entries
        , dayStaffMembers = staffMembers
        , dayShiftTypes = shiftTypes
        , dayToday = today
        , dayEditWindowDays = editWindowDays
        , dayWeekOffset = weekOffset
        , dayWeekStartDate = weekStartDate
        , dayShowApproved = showApproved
        , dayShowAllStaff = showAllStaff
        , dayStaffFilterId = selectedStaffFilterId
        , dayOffset
        }

renderDaySection :: (?context :: ControllerContext) => TimesheetDayRenderModel -> Html
renderDaySection =
    renderDaySectionWithSwap Nothing

renderDaySectionWithSwap :: (?context :: ControllerContext) => Maybe Text -> TimesheetDayRenderModel -> Html
renderDaySectionWithSwap maybeSwapOob model@TimesheetDayRenderModel { dayEntries, dayWeekStartDate, dayWeekOffset, dayShowApproved, dayShowAllStaff, dayStaffFilterId, dayOffset } = [hsx|
    <section id={timesheetDaySectionDomId dayOffset}
             class="timesheet-day-panel app-horizontal-panel"
             data-timesheet-day-offset={tshow dayOffset}
             hx-swap-oob={maybeSwapOob}>
        <header class="timesheet-day-header">
            {renderNewEntryOverlayLink newEntryUrl weekdayLabel weekdayShortLabel dayDate}
        </header>

        <div class="timesheet-day-body">
            {renderDayEntries model dayEntriesForDate}
        </div>
    </section>
|]
    where
        dayDate = addDays (toInteger dayOffset) dayWeekStartDate
        dayEntriesForDate = filter (\entry -> entry.workedOn == dayDate) dayEntries
        weekdayLabel = Text.pack (formatTime defaultTimeLocale "%A" dayDate)
        weekdayShortLabel = Text.pack (formatTime defaultTimeLocale "%a" dayDate)
        newEntryUrl = newTimesheetEntryUrl dayWeekOffset dayDate dayShowApproved dayShowAllStaff dayStaffFilterId

renderNewEntryOverlayLink :: Text -> Text -> Text -> Day -> Html
renderNewEntryOverlayLink newEntryUrl weekdayLabel weekdayShortLabel dayDate =
    renderOverlayActionLink
        (overlayActionByMarker @OpenTimesheetEntryDialog)
        OverlayActionRoute
            { overlayActionRouteUrl = newEntryUrl
            , overlayActionRouteFields = []
            , overlayActionRouteCustomHtmx = []
            , overlayActionRouteStandardUrl = Nothing
            , overlayActionRouteExtraAttrs =
                [ ("class", "timesheet-day-add-bar")
                , ("data-timesheet-day-add", "true")
                , ("aria-label", "Add timesheet entry for " <> weekdayLabel <> " " <> formatDateCompact dayDate)
                ]
            }
        [hsx|
            <span class="timesheet-day-add-plus">+</span>
            <span class="timesheet-day-add-label">{weekdayShortLabel} {formatDateCompact dayDate}</span>
        |]

timesheetDaySectionDomId :: Int -> Text
timesheetDaySectionDomId dayOffset = "timesheet-day-section-" <> tshow dayOffset

renderDayEntries :: (?context :: ControllerContext) => TimesheetDayRenderModel -> [TimesheetEntry] -> Html
renderDayEntries model dayEntries
    | null dayEntries = [hsx|<p class="timesheet-day-empty app-muted mb-0">No entries for this day.</p>|]
    | otherwise = [hsx|
        <div class="timesheet-entry-list">
            {forEach dayEntries (renderEntryCard model)}
        </div>
    |]

renderEntryCard :: (?context :: ControllerContext) => TimesheetDayRenderModel -> TimesheetEntry -> Html
renderEntryCard TimesheetDayRenderModel { dayStaffMembers, dayShiftTypes, dayToday, dayEditWindowDays, dayWeekOffset, dayShowApproved, dayShowAllStaff, dayStaffFilterId, dayOffset } entry = [hsx|
    <article class="timesheet-entry-card" data-timesheet-entry-approved={boolParam entry.isApproved}>
        {renderEntryCardOverlayLink entry canEdit editUrl}
        <div class="timesheet-entry-main">
            <div class="timesheet-entry-identity">
                <div class="timesheet-entry-staff-name">{staffName}</div>
                <div class="timesheet-entry-shift-type">{shiftTypeLabel}</div>
            </div>

            <div class="timesheet-entry-time">
                <div class="timesheet-entry-time-range">
                    {renderCompactTimeRange entry.startTime entry.endTime}
                </div>
                <div class="timesheet-entry-meta">Shift: {renderDuration entry}</div>
                <div class="timesheet-entry-meta timesheet-entry-break-meta">Break: <span class="timesheet-entry-break-summary">{renderBreakSummary entry}</span></div>
            </div>

            <div class="timesheet-entry-actions">
                {renderApprovalAction dayOffset entry dayWeekOffset dayShowApproved dayShowAllStaff dayStaffFilterId}
            </div>
        </div>

        {renderEntryComments entry}
        {renderTimesheetShapeBar defaultTimesheetTimelineScale entry}
    </article>
|]
    where
        staffName = case find (\s -> unpackId (get #id s) == entry.staffId) dayStaffMembers of
            Just staff -> staff.firstName <> " " <> staff.lastName
            Nothing    -> "Unknown" :: Text
        shiftTypeLabel = case find (\shiftType -> unpackId (get #id shiftType) == entry.shiftTypeId) dayShiftTypes of
            Just shiftType -> shiftType.name
            Nothing        -> "Shift"
        canEdit = currentUserIsManager || isWithinEditWindow dayToday entry.workedOn dayEditWindowDays
        editUrl = editTimesheetEntryUrl (get #id entry) dayWeekOffset dayShowApproved dayShowAllStaff dayStaffFilterId

renderEntryCardOverlayLink :: TimesheetEntry -> Bool -> Text -> Html
renderEntryCardOverlayLink entry canEdit editUrl
    | canEdit =
        renderOverlayActionLink
            (overlayActionByMarker @EditTimesheetEntryDialog)
            OverlayActionRoute
                { overlayActionRouteUrl = editUrl
                , overlayActionRouteFields = []
                , overlayActionRouteCustomHtmx = []
                , overlayActionRouteStandardUrl = Nothing
                , overlayActionRouteExtraAttrs =
                    [ ("class", "timesheet-entry-card-link")
                    , ("aria-label", "Edit timesheet entry for " <> tshow entry.workedOn)
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

renderApprovalAction :: (?context :: ControllerContext) => Int -> TimesheetEntry -> Int -> Bool -> Bool -> Maybe UUID -> Html
renderApprovalAction dayOffset entry weekOffset showApproved showAllStaff staffFilterId
    | not currentUserIsManager && entry.isApproved = [hsx|
        <button type="button"
                class="btn btn-sm btn-success timesheet-approval-toggle"
                disabled>
            Approved
        </button>
    |]
    | not currentUserIsManager = mempty
    | entry.isApproved = [hsx|
        <form method="POST"
              action={UnapproveTimesheetEntryAction entry.id}
              class="timesheet-entry-action-form"
              data-disable-javascript-submission="true"
              hx-post={UnapproveTimesheetEntryAction entry.id}
              hx-swap="none"
              hx-push-url="false">
            <input type="hidden" name="weekOffset" value={tshow weekOffset} />
            <input type="hidden" name="showApproved" value={boolParam showApproved} />
            <input type="hidden" name="showAllStaff" value={boolParam showAllStaff} />
            <input type="hidden" name="staffFilterId" value={maybe "" tshow staffFilterId} />
            <button type="submit" class="btn btn-sm btn-success timesheet-approval-toggle">Approved</button>
        </form>
    |]
    | otherwise = [hsx|
        <form method="POST"
              action={ApproveTimesheetEntryAction entry.id}
              class="timesheet-entry-action-form"
              data-disable-javascript-submission="true"
              hx-post={ApproveTimesheetEntryAction entry.id}
              hx-swap="none"
              hx-push-url="false">
            <input type="hidden" name="weekOffset" value={tshow weekOffset} />
            <input type="hidden" name="showApproved" value={boolParam showApproved} />
            <input type="hidden" name="showAllStaff" value={boolParam showAllStaff} />
            <input type="hidden" name="staffFilterId" value={maybe "" tshow staffFilterId} />
            <button type="submit" class="btn btn-sm btn-outline-success timesheet-approval-toggle">Approve</button>
        </form>
    |]

renderBreakSummary :: TimesheetEntry -> Text
renderBreakSummary entry
    | not entry.hadBreak = "None"
    | otherwise =
        case (entry.breakStartTime, entry.breakEndTime) of
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
    let netMins = shiftDurationMinutes entry.startTime entry.endTime - entry.breakMinutes
        hours = netMins `div` 60
        mins = netMins `mod` 60
    in [hsx|{show hours}h {show mins}m|]

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
    let shiftSegments = buildSegments "timesheet-shape-segment-shift" scale (scaledSpan scale entry.startTime entry.endTime)
        breakSegments =
            case (entry.breakStartTime, entry.breakEndTime) of
                (Just breakStart, Just breakEnd) | entry.hadBreak ->
                    buildSegments "timesheet-shape-segment-break" scale (scaledSpan scale breakStart breakEnd)
                _ -> []
     in shiftSegments <> breakSegments

buildSegments :: Text -> TimesheetTimelineScale -> (Int, Int) -> [TimesheetShapeSegment]
buildSegments cssClass scale (startMinutes, endMinutes)
    | endMinutes <= startMinutes = []
    | endMinutes <= scaleEndMinutes scale = [mkSegment cssClass scale startMinutes endMinutes]
    | otherwise =
        [ mkSegment cssClass scale startMinutes (scaleEndMinutes scale)
        , mkSegment cssClass scale (scaleStartMinutes scale) (endMinutes - 1440)
        ]

mkSegment :: Text -> TimesheetTimelineScale -> Int -> Int -> TimesheetShapeSegment
mkSegment cssClass scale startMinutes endMinutes =
    let total = fromIntegral (scaleEndMinutes scale - scaleStartMinutes scale) :: Double
        left = (fromIntegral (startMinutes - scaleStartMinutes scale) / total) * 100
        width = (fromIntegral (endMinutes - startMinutes) / total) * 100
    in TimesheetShapeSegment { segmentLeft = left, segmentWidth = width, segmentClass = cssClass }

scaledSpan :: TimesheetTimelineScale -> TimeOfDay -> TimeOfDay -> (Int, Int)
scaledSpan scale startTime endTime =
    let startMinutes = scaleMinuteValue scale startTime
        endBase = scaleMinuteValue scale endTime
        endMinutes =
            if endBase <= startMinutes
                then endBase + 1440
                else endBase
    in (startMinutes, endMinutes)

scaleMinuteValue :: TimesheetTimelineScale -> TimeOfDay -> Int
scaleMinuteValue scale timeOfDay =
    let minuteValue = timeOfDayToMinutes timeOfDay
    in if minuteValue < scaleStartMinutes scale then minuteValue + 1440 else minuteValue

timeOfDayToMinutes :: TimeOfDay -> Int
timeOfDayToMinutes TimeOfDay { todHour, todMin, todSec } =
    todHour * 60 + todMin + floor (realToFrac todSec :: Pico) `div` 60

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
