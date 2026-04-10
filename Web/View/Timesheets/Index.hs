module Web.View.Timesheets.Index where

import Application.Helper.Controller (isWithinEditWindow, shiftDurationMinutes)
import Application.Helper.LiveUpdate (LiveUpdateScope (..))
import Application.Helper.Pay (TimesheetPaySummary)
import Data.Fixed (Pico)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Web.View.Prelude

data IndexView = IndexView
    { entries               :: [TimesheetEntry]
    , staffMembers          :: [Staff]
    , shiftTypes            :: [ShiftType]
    , paySummariesByEntryId :: Map.Map Text TimesheetPaySummary
    , today                 :: Day
    , editWindowDays        :: Int
    , weekOffset            :: Int
    , weekStartDate         :: Day
    , weekEndDate           :: Day
    , liveUpdateScope       :: Maybe LiveUpdateScope
    }

timesheetWeekShellId :: Text
timesheetWeekShellId = "timesheet-week-shell"

instance View IndexView where
    html = renderTimesheetWeekShell

renderTimesheetWeekShell :: IndexView -> Html
renderTimesheetWeekShell IndexView { .. } =
    let page = renderAppPage (AppPageConfig
            { appPageTitle = "Timesheets"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody = [hsx|
                <div class="app-panel overflow-hidden">
                    {renderTimesheetWeekHeader weekOffset weekStartDate}
                    <div class="app-panel-body">
                        <div class="d-flex flex-column gap-3">
                            {forEach [0 .. 6] (renderDaySection entries staffMembers shiftTypes paySummariesByEntryId today editWindowDays weekOffset weekStartDate)}
                        </div>
                    </div>
                </div>
            |]
            })
     in [hsx|
    <section id={timesheetWeekShellId}
             hx-history-elt="true"
             data-live-update-owner="true"
             data-live-update-feature="timesheets"
             data-live-updates-path="/live-updates"
             data-live-update-client-enabled={isJust liveUpdateScope}
             data-live-update-client-id=""
             data-live-update-scope-kind={liveUpdateScopeKind <$> liveUpdateScope}
             data-live-update-venue-id={liveUpdateVenueId <$> liveUpdateScope}
             data-live-update-week-offset={liveUpdateWeekOffsetText =<< liveUpdateScope}>
        {page}
    </section>
|]

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

renderTimesheetWeekHeader :: Int -> Day -> Html
renderTimesheetWeekHeader weekOffset weekStartDate = [hsx|
    <div class="app-panel-header app-surface-toolbar">
        <div class="app-surface-toolbar-side">
            {renderTimesheetWeekNavigationLink "This week" (pathTo TimesheetsAction)}
        </div>
        <div class="app-surface-toolbar-center">
            <div class="btn-group app-week-nav-group" role="group" aria-label="Timesheet week navigation">
                {renderTimesheetWeekNavigationLink "<" (pathTo (ShowTimesheetWeekAction (weekOffset - 1)))}
                <div class="btn btn-outline-secondary app-week-nav-label">
                    {renderTimesheetWeekLabel weekStartDate}
                </div>
                {renderTimesheetWeekNavigationLink ">" (pathTo (ShowTimesheetWeekAction (weekOffset + 1)))}
            </div>
        </div>
        <div class="app-surface-toolbar-side app-surface-toolbar-side-right"></div>
    </div>
|]

renderTimesheetWeekLabel :: Day -> Text
renderTimesheetWeekLabel weekStartDate =
    "Week of " <> Text.pack (formatTime defaultTimeLocale "%-d %b" weekStartDate)

renderDaySection :: (?context :: ControllerContext) => [TimesheetEntry] -> [Staff] -> [ShiftType] -> Map.Map Text TimesheetPaySummary -> Day -> Int -> Int -> Day -> Int -> Html
renderDaySection =
    renderDaySectionWithSwap Nothing

renderDaySectionOob :: (?context :: ControllerContext) => [TimesheetEntry] -> [Staff] -> [ShiftType] -> Map.Map Text TimesheetPaySummary -> Day -> Int -> Int -> Day -> Int -> Html
renderDaySectionOob =
    renderDaySectionWithSwap (Just "outerHTML")

renderDaySectionWithSwap :: (?context :: ControllerContext) => Maybe Text -> [TimesheetEntry] -> [Staff] -> [ShiftType] -> Map.Map Text TimesheetPaySummary -> Day -> Int -> Int -> Day -> Int -> Html
renderDaySectionWithSwap maybeSwapOob entries staffMembers shiftTypes paySummariesByEntryId today editWindowDays weekOffset weekStartDate dayOffset = [hsx|
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

            {renderDayEntries dayOffset dayEntries staffMembers shiftTypes paySummariesByEntryId today editWindowDays weekOffset}
        </div>
    </section>
|]
    where
        dayDate = addDays (toInteger dayOffset) weekStartDate
        dayEntries = filter (\entry -> entry.workedOn == dayDate) entries
        weekdayLabel = Text.pack (formatTime defaultTimeLocale "%A" dayDate)
        daySectionUrl =
            pathTo
                (ShowTimesheetDaySectionFragmentAction
                    { weekOffset = weekOffset
                    , dayOffset = dayOffset
                    }
                )
        newEntryUrl =
            appendQueryParams
                (pathTo NewTimesheetEntryAction)
                [ ("weekOffset", tshow weekOffset)
                , ("workedOn", tshow dayDate)
                ]

timesheetDaySectionDomId :: Int -> Text
timesheetDaySectionDomId dayOffset = "timesheet-day-section-" <> tshow dayOffset

renderDayEntries :: (?context :: ControllerContext) => Int -> [TimesheetEntry] -> [Staff] -> [ShiftType] -> Map.Map Text TimesheetPaySummary -> Day -> Int -> Int -> Html
renderDayEntries dayOffset dayEntries staffMembers shiftTypes paySummariesByEntryId today editWindowDays weekOffset
    | null dayEntries = [hsx|<p class="timesheet-day-empty app-muted mb-0">No entries for this day.</p>|]
    | otherwise = [hsx|
        <div class="timesheet-entry-list">
            {forEach dayEntries (renderEntryCard dayOffset staffMembers shiftTypes paySummariesByEntryId today editWindowDays weekOffset)}
        </div>
    |]

renderEntryCard :: (?context :: ControllerContext) => Int -> [Staff] -> [ShiftType] -> Map.Map Text TimesheetPaySummary -> Day -> Int -> Int -> TimesheetEntry -> Html
renderEntryCard dayOffset staffMembers shiftTypes _paySummariesByEntryId today editWindowDays weekOffset entry = [hsx|
    <article class="timesheet-entry-card" data-timesheet-entry-approved={boolText entry.isApproved}>
        <div class="timesheet-entry-main">
            <div class="timesheet-entry-identity">
                <div class="timesheet-entry-shift-type">{shiftTypeLabel}</div>
                <div class="timesheet-entry-staff-name">{staffName}</div>
            </div>

            <div class="timesheet-entry-time">
                <div class="timesheet-entry-time-range">
                    {storageTimeToDisplayLabel (timeOfDayToStorageValue entry.startTime)} - {storageTimeToDisplayLabel (timeOfDayToStorageValue entry.endTime)}
                </div>
                <div class="timesheet-entry-meta">Shift: {renderDuration entry}</div>
                <div class="timesheet-entry-meta">Break: {renderBreakSummary entry}</div>
            </div>

            <div class="timesheet-entry-actions">
                {renderApprovalBadge entry}
                {renderApprovalAction dayOffset entry weekOffset}
                {renderEditActions dayOffset entry canEdit weekOffset}
            </div>
        </div>

        {renderTimesheetShapeBar defaultTimesheetTimelineScale entry}
    </article>
|]
    where
        staffName = case find (\s -> unpackId (get #id s) == entry.staffId) staffMembers of
            Just staff -> staff.firstName <> " " <> staff.lastName
            Nothing    -> "Unknown" :: Text
        shiftTypeLabel = case find (\shiftType -> unpackId (get #id shiftType) == entry.shiftTypeId) shiftTypes of
            Just shiftType -> shiftType.name
            Nothing        -> "Shift"
        canEdit = currentUserIsManager || isWithinEditWindow today entry.workedOn editWindowDays

renderEditActions :: Int -> TimesheetEntry -> Bool -> Int -> Html
renderEditActions dayOffset entry canEdit weekOffset
    | canEdit && not entry.isApproved = [hsx|
        <a href={editUrl}
           class="btn btn-sm btn-outline-secondary"
           hx-get={editUrl}
           hx-target={"#" <> dialogOverlayMountId}
           hx-swap="innerHTML"
           hx-push-url="false">
            Edit
        </a>
        {renderDeleteButton}
    |]
    | otherwise = mempty
    where
        editUrl = appendQueryParams (pathTo (EditTimesheetEntryAction (get #id entry))) [("weekOffset", tshow weekOffset)]
        deleteUrl = appendQueryParams (pathTo (DeleteTimesheetEntryAction (get #id entry))) [("weekOffset", tshow weekOffset)]
        deleteTarget = "#" <> timesheetDaySectionDomId dayOffset
        renderDeleteButton = [hsx|
            <form method="POST"
                  action={deleteUrl}
                  class="timesheet-entry-action-form"
                  hx-delete={deleteUrl}
                  hx-target={deleteTarget}
                  hx-swap="outerHTML"
                  hx-push-url="false">
                <input type="hidden" name="_method" value="DELETE"/>
                <input type="hidden" name="weekOffset" value={tshow weekOffset} />
                <button type="submit" class="btn btn-sm btn-outline-danger">Delete</button>
            </form>
        |]

renderApprovalAction :: (?context :: ControllerContext) => Int -> TimesheetEntry -> Int -> Html
renderApprovalAction dayOffset entry weekOffset
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
            <button type="submit" class="btn btn-sm btn-outline-warning">Unapprove</button>
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
            <button type="submit" class="btn btn-sm btn-outline-success">Approve</button>
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

renderApprovalBadge :: TimesheetEntry -> Html
renderApprovalBadge entry
    | entry.isApproved = [hsx|<span class="badge bg-success timesheet-entry-status-badge">Approved</span>|]
    | otherwise = [hsx|<span class="badge bg-warning text-dark timesheet-entry-status-badge">Pending</span>|]

formatDateCompact :: Day -> Text
formatDateCompact day =
    Text.pack (formatTime defaultTimeLocale "%d/%m" day)

boolText :: Bool -> Text
boolText True  = "true"
boolText False = "false"

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
        endBase = timeOfDayToMinutes endTime
        endMinutes =
            if endBase <= timeOfDayToMinutes startTime
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

liveUpdateScopeKind :: LiveUpdateScope -> Text
liveUpdateScopeKind LeaveRequestsScope {}     = "leave_requests"
liveUpdateScopeKind RosterWeekScope {}        = "roster_week"
liveUpdateScopeKind RosterGroupConfigScope {} = "roster_group_config"
liveUpdateScopeKind AdminSlotNamesScope {}    = "admin_slot_names"
liveUpdateScopeKind AdminInvitesScope {}      = "admin_invites"
liveUpdateScopeKind TimesheetWeekScope {}     = "timesheet_week"

liveUpdateVenueId :: LiveUpdateScope -> Text
liveUpdateVenueId LeaveRequestsScope { venueId }     = tshow venueId
liveUpdateVenueId RosterWeekScope { venueId }        = tshow venueId
liveUpdateVenueId RosterGroupConfigScope { venueId } = tshow venueId
liveUpdateVenueId AdminSlotNamesScope { venueId }    = tshow venueId
liveUpdateVenueId AdminInvitesScope { venueId }      = tshow venueId
liveUpdateVenueId TimesheetWeekScope { venueId }     = tshow venueId

liveUpdateWeekOffsetText :: LiveUpdateScope -> Maybe Text
liveUpdateWeekOffsetText LeaveRequestsScope {}          = Nothing
liveUpdateWeekOffsetText RosterWeekScope { weekOffset } = Just (tshow weekOffset)
liveUpdateWeekOffsetText RosterGroupConfigScope {}      = Nothing
liveUpdateWeekOffsetText AdminSlotNamesScope {}         = Nothing
liveUpdateWeekOffsetText AdminInvitesScope {}           = Nothing
liveUpdateWeekOffsetText TimesheetWeekScope { weekOffset } = Just (tshow weekOffset)
