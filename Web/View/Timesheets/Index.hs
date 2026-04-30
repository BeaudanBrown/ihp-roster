module Web.View.Timesheets.Index where

import Application.Helper.Controller (isWithinEditWindow, shiftDurationMinutes)
import Application.Helper.LiveSurface (LiveSurfaceConfig (..),
                                       liveSurfaceConfigJson, mkLiveSurface)
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveFragmentProtection (..),
                                      LiveFragmentRef (..),
                                      LiveUpdateScope (..), mkLiveFragmentRef)
import Data.Fixed (Pico)
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.UUID (UUID)
import Web.Timesheets.Paths (timesheetWeekUrl)
import Web.View.Prelude

data IndexView = IndexView
    { entries              :: [TimesheetEntry]
    , staffMembers         :: [Staff]
    , shiftTypes           :: [ShiftType]
    , today                :: Day
    , editWindowDays       :: Int
    , weekOffset           :: Int
    , weekStartDate        :: Day
    , weekEndDate          :: Day
    , showApproved         :: Bool
    , showAllStaff         :: Bool
    , currentViewerStaffId :: Maybe UUID
    , liveUpdateScope      :: Maybe LiveUpdateScope
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
    , dayOffset         :: Int
    }

timesheetWeekShellId :: Text
timesheetWeekShellId = "timesheet-week-shell"

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
                    , appPanelCustomHeader = renderTimesheetWeekHeader weekOffset weekStartDate showApproved showAllStaff
                    , appPanelClass = "overflow-hidden"
                    , appPanelBodyClass = ""
                    , appPanelBody = [hsx|
                        <div class="d-flex flex-column gap-3">
                            {forEach [0 .. 6] (renderDaySection . timesheetDayRenderModel view)}
                        </div>
                    |]
                    }
            })
     in [hsx|
    <section id={timesheetWeekShellId}
             hx-history-elt="true"
             data-live-update-surface={liveSurfaceConfigJson . timesheetWeekLiveSurface weekOffset showApproved showAllStaff <$> liveUpdateScope}>
        {page}
    </section>
|]

timesheetWeekLiveSurface :: (?context :: ControllerContext) => Int -> Bool -> Bool -> LiveUpdateScope -> LiveSurfaceConfig
timesheetWeekLiveSurface weekOffset showApproved showAllStaff scope =
    (mkLiveSurface
        "timesheets"
        scope
        (map (timesheetDayFragmentRef weekOffset showApproved showAllStaff) [0 .. 6]))
        { decorateRequestsWithin = ["#" <> timesheetWeekShellId] }

timesheetDayFragmentRef :: (?context :: ControllerContext) => Int -> Bool -> Bool -> Int -> LiveFragmentRef
timesheetDayFragmentRef weekOffset showApproved showAllStaff dayOffset =
    mkLiveFragmentRef
        (TimesheetDaySectionFragment { dayOffset })
        (timesheetDaySectionDomId dayOffset)
        ( appendQueryParams
            (pathTo ShowTimesheetDaySectionFragmentAction { weekOffset, dayOffset })
            [ ("showApproved", boolParam showApproved)
            , ("showAllStaff", boolParam showAllStaff)
            ]
        )

renderTimesheetWeekNavigationLink :: Text -> Text -> Html
renderTimesheetWeekNavigationLink label url =
    renderPartialNavigationLink
        PartialNavigationLink
            { partialNavigationLabel = label
            , partialNavigationUrl = url
            , partialNavigationTargetId = timesheetWeekShellId
            , partialNavigationSelectId = Just timesheetWeekShellId
            , partialNavigationClass = "btn btn-outline-secondary app-week-nav-button"
            , partialNavigationSwap = "outerHTML"
            , partialNavigationSync = Just ("#" <> timesheetWeekShellId <> ":replace")
            , partialNavigationPushUrl = True
            }

renderTimesheetWeekHeader :: (?context :: ControllerContext) => Int -> Day -> Bool -> Bool -> Html
renderTimesheetWeekHeader weekOffset weekStartDate showApproved showAllStaff = [hsx|
    <div class="app-panel-header app-surface-toolbar">
        <div class="app-surface-toolbar-side">
            {renderTimesheetWeekNavigationLink "This week" (appendQueryParams (pathTo TimesheetsAction) [("showApproved", boolParam showApproved), ("showAllStaff", boolParam showAllStaff)])}
        </div>
        <div class="app-surface-toolbar-center">
            <div class="btn-group app-week-nav-group" role="group" aria-label="Timesheet week navigation">
                {renderTimesheetWeekNavigationLink "<" (timesheetWeekUrl (weekOffset - 1) showApproved showAllStaff)}
                <div class="btn btn-outline-secondary app-week-nav-label">
                    {renderTimesheetWeekLabel weekStartDate}
                </div>
                {renderTimesheetWeekNavigationLink ">" (timesheetWeekUrl (weekOffset + 1) showApproved showAllStaff)}
            </div>
        </div>
        <div class="app-surface-toolbar-side app-surface-toolbar-side-right">
            {renderTimesheetWeekMoreMenu weekOffset showApproved showAllStaff}
        </div>
    </div>
|]

renderTimesheetWeekMoreMenu :: (?context :: ControllerContext) => Int -> Bool -> Bool -> Html
renderTimesheetWeekMoreMenu weekOffset showApproved showAllStaff =
    let menuTriggerId = "timesheet-week-more-menu-trigger" :: Text
        updateUrl = pathTo (ShowTimesheetWeekAction weekOffset)
     in [hsx|
    <div class="dropdown">
        <button class="btn btn-outline-secondary"
                type="button"
                id={menuTriggerId}
                data-bs-toggle="dropdown"
                data-bs-auto-close="outside"
                aria-expanded="false"
                aria-label="Timesheet actions">
            <i class="bi bi-three-dots-vertical"></i>
        </button>
        <div class="dropdown-menu dropdown-menu-end p-2 app-action-menu" aria-labelledby={menuTriggerId}>
            <form class="px-1 py-1"
                  method="GET"
                  action={updateUrl}
                  data-disable-javascript-submission="true"
                  hx-get={updateUrl}
                  hx-target={"#" <> timesheetWeekShellId}
                  hx-swap="outerHTML"
                  hx-push-url="true"
                  hx-sync={"#" <> timesheetWeekShellId <> ":replace"}>
                <input type="hidden" name="weekOffset" value={tshow weekOffset} />
                <input type="hidden" name="showApproved" id="timesheet-show-approved-value" value={boolParam showApproved} />
                <input type="hidden" name="showAllStaff" id="timesheet-show-all-staff-value" value={boolParam showAllStaff} />
                <div class="small text-uppercase fw-semibold app-muted px-1 pb-2">Filters</div>
                {renderTimesheetHideApprovedToggle showApproved}
                {when currentUserIsManager (renderTimesheetMenuToggle "timesheet-show-all-staff-toggle" "timesheet-show-all-staff-value" showAllStaff "Show all staff")}
            </form>
        </div>
    </div>
|]

renderTimesheetHideApprovedToggle :: Bool -> Html
renderTimesheetHideApprovedToggle showApproved = [hsx|
    <div class="form-check form-switch mb-2">
        <input type="checkbox"
               id="timesheet-hide-approved-toggle"
               class="form-check-input"
               checked={not showApproved}
               onchange="document.getElementById('timesheet-show-approved-value').value = this.checked ? 'false' : 'true'; this.form.requestSubmit();" />
        <label class="form-check-label small" for="timesheet-hide-approved-toggle">Hide approved</label>
    </div>
|]

renderTimesheetMenuToggle :: Text -> Text -> Bool -> Text -> Html
renderTimesheetMenuToggle inputId hiddenInputId isChecked label = [hsx|
    <div class="form-check form-switch mb-2">
        <input type="checkbox"
               id={inputId}
               class="form-check-input"
               checked={isChecked}
               onchange={"document.getElementById('" <> hiddenInputId <> "').value = this.checked ? 'true' : 'false'; this.form.requestSubmit();"} />
        <label class="form-check-label small" for={inputId}>{label}</label>
    </div>
|]

renderTimesheetWeekLabel :: Day -> Text
renderTimesheetWeekLabel weekStartDate =
    "Week of " <> Text.pack (formatTime defaultTimeLocale "%-d %b" weekStartDate)

timesheetDayRenderModel :: IndexView -> Int -> TimesheetDayRenderModel
timesheetDayRenderModel IndexView { entries, staffMembers, shiftTypes, today, editWindowDays, weekOffset, weekStartDate, showApproved, showAllStaff } dayOffset =
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
        , dayOffset
        }

renderDaySection :: (?context :: ControllerContext) => TimesheetDayRenderModel -> Html
renderDaySection =
    renderDaySectionWithSwap Nothing

renderDaySectionOob :: (?context :: ControllerContext) => TimesheetDayRenderModel -> Html
renderDaySectionOob =
    renderDaySectionWithSwap (Just "outerHTML")

renderDaySectionWithSwap :: (?context :: ControllerContext) => Maybe Text -> TimesheetDayRenderModel -> Html
renderDaySectionWithSwap maybeSwapOob model@TimesheetDayRenderModel { dayEntries, dayWeekStartDate, dayWeekOffset, dayShowApproved, dayShowAllStaff, dayOffset } = [hsx|
    <section id={timesheetDaySectionDomId dayOffset}
             class="app-panel timesheet-day-panel"
             data-timesheet-day-offset={tshow dayOffset}
             data-live-update-url={daySectionUrl}
             hx-swap-oob={maybeSwapOob}>
        <div class="app-panel-body">
            <a href={newEntryUrl}
               class="timesheet-day-add-bar"
               data-timesheet-day-add="true"
               hx-get={newEntryUrl}
               hx-target={"#" <> dialogOverlayMountId}
               hx-swap="innerHTML"
               hx-push-url="false">
                <span class="timesheet-day-add-plus">+</span>
                <span class="timesheet-day-add-label">{weekdayLabel} {formatDateCompact dayDate}</span>
            </a>

            {renderDayEntries model dayEntriesForDate}
        </div>
    </section>
|]
    where
        dayDate = addDays (toInteger dayOffset) dayWeekStartDate
        dayEntriesForDate = filter (\entry -> entry.workedOn == dayDate) dayEntries
        weekdayLabel = Text.pack (formatTime defaultTimeLocale "%A" dayDate)
        daySectionUrl =
            appendQueryParams
                (pathTo
                    (ShowTimesheetDaySectionFragmentAction
                        { weekOffset = dayWeekOffset
                        , dayOffset = dayOffset
                        }
                    )
                )
                [ ("showApproved", boolParam dayShowApproved)
                , ("showAllStaff", boolParam dayShowAllStaff)
                ]
        newEntryUrl =
            appendQueryParams
                (pathTo NewTimesheetEntryAction)
                [ ("weekOffset", tshow dayWeekOffset)
                , ("workedOn", tshow dayDate)
                , ("showApproved", boolParam dayShowApproved)
                , ("showAllStaff", boolParam dayShowAllStaff)
                ]

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
renderEntryCard TimesheetDayRenderModel { dayStaffMembers, dayShiftTypes, dayToday, dayEditWindowDays, dayWeekOffset, dayShowApproved, dayShowAllStaff, dayOffset } entry = [hsx|
    <article class="timesheet-entry-card" data-timesheet-entry-approved={boolParam entry.isApproved}>
        <div class="timesheet-entry-main">
            <div class="timesheet-entry-identity">
                <div class="timesheet-entry-staff-name">{staffName}</div>
                <div class="timesheet-entry-shift-type">{shiftTypeLabel}</div>
            </div>

            <div class="timesheet-entry-time">
                <div class="timesheet-entry-time-range">
                    {storageTimeToDisplayLabel (timeOfDayToStorageValue entry.startTime)} - {storageTimeToDisplayLabel (timeOfDayToStorageValue entry.endTime)}
                </div>
                <div class="timesheet-entry-meta">Shift: {renderDuration entry}</div>
                <div class="timesheet-entry-meta">Break: {renderBreakSummary entry}</div>
            </div>

            <div class="timesheet-entry-actions">
                {renderApprovalAction dayOffset entry dayWeekOffset dayShowApproved dayShowAllStaff}
                {renderEditActions entry canEdit dayWeekOffset dayShowApproved dayShowAllStaff}
            </div>
        </div>

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

renderEditActions :: TimesheetEntry -> Bool -> Int -> Bool -> Bool -> Html
renderEditActions entry canEdit weekOffset showApproved showAllStaff
    | canEdit = [hsx|
        <a href={editUrl}
           class="btn btn-sm btn-outline-secondary"
           hx-get={editUrl}
           hx-target={"#" <> dialogOverlayMountId}
           hx-swap="innerHTML"
           hx-push-url="false">
            Edit
        </a>
    |]
    | otherwise = mempty
    where
        editUrl = appendQueryParams (pathTo (EditTimesheetEntryAction (get #id entry))) [("weekOffset", tshow weekOffset), ("showApproved", boolParam showApproved), ("showAllStaff", boolParam showAllStaff)]

renderApprovalAction :: (?context :: ControllerContext) => Int -> TimesheetEntry -> Int -> Bool -> Bool -> Html
renderApprovalAction dayOffset entry weekOffset showApproved showAllStaff
    | not currentUserIsManager = mempty
    | entry.isApproved = [hsx|
        <form method="POST"
              action={UnapproveTimesheetEntryAction entry.id}
              class="timesheet-entry-action-form"
              data-disable-javascript-submission="true"
              hx-post={UnapproveTimesheetEntryAction entry.id}
              hx-target={"#" <> timesheetDaySectionDomId dayOffset}
              hx-swap="outerHTML"
              hx-push-url="false">
            <input type="hidden" name="weekOffset" value={tshow weekOffset} />
            <input type="hidden" name="showApproved" value={boolParam showApproved} />
            <input type="hidden" name="showAllStaff" value={boolParam showAllStaff} />
            <button type="submit" class="btn btn-sm btn-success timesheet-approval-toggle">Approved</button>
        </form>
    |]
    | otherwise = [hsx|
        <form method="POST"
              action={ApproveTimesheetEntryAction entry.id}
              class="timesheet-entry-action-form"
              data-disable-javascript-submission="true"
              hx-post={ApproveTimesheetEntryAction entry.id}
              hx-target={"#" <> timesheetDaySectionDomId dayOffset}
              hx-swap="outerHTML"
              hx-push-url="false">
            <input type="hidden" name="weekOffset" value={tshow weekOffset} />
            <input type="hidden" name="showApproved" value={boolParam showApproved} />
            <input type="hidden" name="showAllStaff" value={boolParam showAllStaff} />
            <button type="submit" class="btn btn-sm btn-outline-success timesheet-approval-toggle">Approve</button>
        </form>
    |]

renderBreakSummary :: TimesheetEntry -> Text
renderBreakSummary entry
    | not entry.hadBreak = "None"
    | otherwise =
        case (entry.breakStartTime, entry.breakEndTime) of
            (Just breakStart, Just breakEnd) ->
                storageTimeToDisplayLabel (timeOfDayToStorageValue breakStart)
                    <> " - "
                    <> storageTimeToDisplayLabel (timeOfDayToStorageValue breakEnd)
            _ -> "Invalid"

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
    in if null segments
        then mempty
        else [hsx|
            <div class="timesheet-shape-bar">
                <div class="timesheet-shape-track"></div>
                <div class="timesheet-shape-midnight-marker" style={timesheetMidnightStyle scale}></div>
                {forEach segments renderTimesheetShapeSegment}
            </div>
        |]

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

timesheetMidnightStyle :: TimesheetTimelineScale -> Text
timesheetMidnightStyle scale =
    let total = fromIntegral (scaleEndMinutes scale - scaleStartMinutes scale) :: Double
        left = (fromIntegral (midnightOffset scale - scaleStartMinutes scale) / total) * 100
    in "left:" <> tshow left <> "%;"

renderTimesheetShapeSegment :: TimesheetShapeSegment -> Html
renderTimesheetShapeSegment segment = [hsx|
    <div class={"timesheet-shape-segment " <> segmentClass segment}
         style={"left:" <> tshow (segmentLeft segment) <> "%;width:" <> tshow (segmentWidth segment) <> "%;"}></div>
|]
