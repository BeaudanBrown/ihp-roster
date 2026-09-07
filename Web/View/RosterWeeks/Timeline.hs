{-# LANGUAGE OverloadedRecordDot #-}

module Web.View.RosterWeeks.Timeline
    ( renderRosterDayTimelineContent
    , renderRosterDayTimelinePanel
    ) where

import Application.Helper.Controller (hasRole)
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.LinkedHighlight as SurfaceLinkedHighlight
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceInteractionShellConfig (..),
                                                            renderFrontendSurfaceInteractionShell,
                                                            renderFrontendSurfaceMount)
import Application.Helper.Profiling (profileHtmlComponent)
import Application.Helper.TimeRules (normalizeWindowEndMinute)
import Application.RosterShiftAssignment (rosterShiftIsOpen,
                                          rosterShiftIsStaffAssigned)
import Application.VenueTime.Model (RosterShiftIntegrityError,
                                    ValidatedRosterShiftTiming,
                                    rosterShiftTimingElapsedSeconds,
                                    rosterShiftTimingEndTime,
                                    rosterShiftTimingStartTime)
import Data.Fixed (Pico)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import qualified Data.Text as Text
import qualified Data.Time.Calendar as Calendar
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.UUID as UUID
import Web.RosterWeeks.DateRange (RosterWindowLane, RosterWindowScope (..),
                                  laneForOperationalDate, rosterWindowLaneName)
import Web.RosterWeeks.Dom (rosterDayTimelineContentFragmentId,
                            rosterWeekShellId)
import Web.RosterWeeks.FrontendSurface (RosterDayTimelineScopeValue (..),
                                        rosterDayTimelineDropzoneRef,
                                        rosterDayTimelineFrontendSurfaceIR,
                                        rosterDayTimelineIntentForms,
                                        rosterDayTimelineShiftGroupLinkedHighlight,
                                        rosterDayTimelineSourceRef,
                                        rosterDayTimelineSurfaceImpl)
import Web.RosterWeeks.Rows (rosterSlotHasVisibleData)
import Web.RosterWeeks.Types
import Web.View.Prelude
import Web.View.RosterWeeks.Grid.Cells (RosterSlotCellTarget (ExistingRosterSlotTarget),
                                        rosterShiftDialogLauncherAttrs,
                                        rosterSlotDialogUrl)

renderRosterDayTimelinePanel :: (?context :: ControllerContext) => RosterGridRenderModel -> RosterDay -> Html
renderRosterDayTimelinePanel RosterGridRenderModel { gridRosterWeek = Nothing } _ = [hsx|
    <div class="alert alert-info mb-0">This draft roster is not visible.</div>
|]
renderRosterDayTimelinePanel gridModel@RosterGridRenderModel { gridRosterWeek = Just _ } rosterDay =
    renderRosterDayTimelineMounted gridModel.gridWindowScope rosterDay (renderRosterDayTimelineContent Nothing gridModel rosterDay)

renderRosterDayTimelineMounted :: RosterWindowScope -> RosterDay -> Html -> Html
renderRosterDayTimelineMounted windowScope rosterDay body =
    let timelineSurfaceScope = RosterDayTimelineScopeValue
            { rosterDayTimelineVenueId = unpackId windowScope.rosterWindowVenueId
            , rosterDayTimelineGroupId = windowScope.rosterWindowRosterGroupId
            , rosterDayTimelineWindowStart = windowScope.rosterWindowStart
            , rosterDayTimelineWindowEnd = windowScope.rosterWindowEnd
            , rosterDayTimelineCalendarRevision = windowScope.rosterWindowCalendarRevision
            , rosterDayTimelineOperationalDate = rosterDay.operationalDate
            , rosterDayTimelineDayId = rosterDay.id
            }
        timelineSurface = rosterDayTimelineSurfaceImpl timelineSurfaceScope
     in renderFrontendSurfaceMount timelineSurface $
            renderFrontendSurfaceInteractionShell timelineSurface rosterDayTimelineFrontendSurfaceIR FrontendSurfaceInteractionShellConfig
                { interactionShellHtmxSync = Just ("#" <> rosterWeekShellId <> ":replace")
                , interactionShellIntentForms = rosterDayTimelineIntentForms timelineSurfaceScope
                } body

data TimelineShift = TimelineShift
    { timelineShiftSlot          :: !RosterSlot
    , timelineShiftStartMin      :: !Double
    , timelineShiftEndMin        :: !Double
    , timelineShiftTrack         :: !Int
    , timelineShiftTimeLabel     :: !Text
    , timelineShiftTimingInvalid :: !Bool
    }

renderRosterDayTimelineContent :: Maybe Text -> RosterGridRenderModel -> RosterDay -> Html
renderRosterDayTimelineContent maybeSwapOob gridModel rosterDay =
    let date = rosterDay.operationalDate
        daySlots = filter (\slot -> slot.rosterDayId == unpackId rosterDay.id) gridModel.gridAllSlots
        slotsByDefinition = Map.fromListWith (<>) [ (slot.rosterLaneId, [slot]) | slot <- daySlots ]
        staffById = Map.fromList [ (unpackId staff.id, staff) | staff <- gridModel.gridStaffMembers ]
        shiftTypeById = Map.fromList [ (unpackId shiftType.id, shiftType) | shiftType <- gridModel.gridShiftTypes ]
        editable = currentUserIsManager && maybe False (not . (.windowIsPublished)) gridModel.gridRosterWeek && not rosterDay.isClosed
        timelineWindow = timelineWindowFromGridModel gridModel
     in [hsx|
        <section id={rosterDayTimelineContentFragmentId rosterDay.id}
                 class="roster-day-timeline-shell"
                 data-roster-day-timeline="true"
                 data-roster-day-timeline-editable={if editable then ("true" :: Text) else "false"}
                 hx-swap-oob={maybeSwapOob}>
            <div class="roster-day-timeline" role="grid" aria-label={Text.pack (formatTime defaultTimeLocale "%A %d/%m roster timeline" date)}>
                {renderTimelineScale timelineWindow}
                {forEach gridModel.gridSlotNames (renderTimelineLane timelineWindow editable rosterDay gridModel.gridRosterCalendarRevision staffById shiftTypeById slotsByDefinition gridModel.gridRenderIndexes.rosterTimingBySlotId)}
            </div>
        </section>
    |]

data TimelineWindow = TimelineWindow
    { timelineWindowStartMinute  :: !Int
    , timelineWindowEndMinute    :: !Int
    , timelineWindowTotalMinutes :: !Int
    }

timelineWindowFromGridModel :: RosterGridRenderModel -> TimelineWindow
timelineWindowFromGridModel RosterGridRenderModel { gridRosterTimePickerStartMinute, gridRosterTimePickerFinalSelectableMinute } =
    let endMinute = normalizeWindowEndMinute gridRosterTimePickerStartMinute gridRosterTimePickerFinalSelectableMinute
     in TimelineWindow
            { timelineWindowStartMinute = gridRosterTimePickerStartMinute
            , timelineWindowEndMinute = endMinute
            , timelineWindowTotalMinutes = max 15 (endMinute - gridRosterTimePickerStartMinute + 15)
            }

renderTimelineScale :: TimelineWindow -> Html
renderTimelineScale timelineWindow = [hsx|
    <div class="roster-day-timeline-scale" aria-hidden="true">
        <div class="roster-day-timeline-scale-label">Time</div>
        <div class="roster-day-timeline-scale-body">
            {forEach (timelineHourTicks timelineWindow) (renderTimelineScaleTick timelineWindow)}
        </div>
    </div>
|]

renderTimelineScaleTick :: TimelineWindow -> Int -> Html
renderTimelineScaleTick timelineWindow minute = [hsx|
    <div class="roster-day-timeline-scale-tick" style={timelineLeftStyle timelineWindow minute}>
        {minuteLabel minute}
    </div>
|]

renderTimelineLane :: TimelineWindow -> Bool -> RosterDay -> Int -> Map.Map UUID.UUID Staff -> Map.Map UUID.UUID ShiftType -> Map.Map UUID.UUID [RosterSlot] -> Map.Map UUID.UUID (Either RosterShiftIntegrityError ValidatedRosterShiftTiming) -> RosterWindowLane -> Html
renderTimelineLane timelineWindow editable rosterDay calendarRevision staffById shiftTypeById slotsByDefinition timingBySlotId windowLane =
    let maybeLane = laneForOperationalDate rosterDay.operationalDate windowLane
        laneSlots = filter rosterSlotHasVisibleData (maybe [] (\lane -> Map.findWithDefault [] (unpackId lane.id) slotsByDefinition) maybeLane)
        positionedShifts = assignTimelineTracks (map (timelineShiftFromSlot timelineWindow timingBySlotId) laneSlots)
        trackCount = max 1 (1 + foldl' max 0 (map timelineShiftTrack positionedShifts))
        assignedShiftCount = length (filter (rosterShiftIsStaffAssigned . (.timelineShiftSlot)) positionedShifts)
        dropzones = if editable then maybe [] (timelineDropzones timelineWindow rosterDay) maybeLane else []
     in [hsx|
        <section class="roster-day-timeline-lane"
                 role="rowgroup"
                 style={"--roster-timeline-track-count:" <> tshow trackCount <> ";"}>
            <div class="roster-day-timeline-lane-label">
                <span class="fw-semibold">{rosterWindowLaneName windowLane}</span>
                <span class="text-muted small">{assignedShiftCount} shifts</span>
            </div>
            <div class="roster-day-timeline-lane-body" role="row">
                <div class="roster-day-timeline-dropzones" aria-hidden={if editable then ("false" :: Text) else "true"}>
                    {forEach dropzones (renderTimelineDropzone timelineWindow)}
                </div>
                <div class="roster-day-timeline-shifts">
                    {forEach positionedShifts (renderTimelineShift timelineWindow editable staffById shiftTypeById rosterDay.operationalDate calendarRevision)}
                </div>
            </div>
        </section>
    |]

renderTimelineDropzone :: TimelineWindow -> (Int, Text) -> Html
renderTimelineDropzone timelineWindow (minute, targetKey) =
    [hsx|
        <div {...(SurfaceInteraction.frontendSurfaceDropzoneRefAttrs rosterDayTimelineDropzoneRef targetKey)} class="roster-day-timeline-dropzone"
             style={timelineDropzoneStyle timelineWindow minute}
             data-roster-timeline-minute={tshow minute}
             aria-label={"Move shift to " <> minuteLabel minute}>
        </div>
    |]

renderTimelineShift :: TimelineWindow -> Bool -> Map.Map UUID.UUID Staff -> Map.Map UUID.UUID ShiftType -> Day -> Int -> TimelineShift -> Html
renderTimelineShift timelineWindow editable staffById shiftTypeById anchorDate calendarRevision TimelineShift { timelineShiftSlot, timelineShiftStartMin, timelineShiftEndMin, timelineShiftTrack, timelineShiftTimeLabel, timelineShiftTimingInvalid } =
    let isOpen = rosterShiftIsOpen timelineShiftSlot
        canLaunch = editable || (isOpen && hasRole Manager)
        staffLabel = if isOpen then "OPEN" else maybe "Unassigned" staffTimelineLabel (timelineShiftSlot.staffId >>= (`Map.lookup` staffById))
        shiftTypeLabel = maybe "Shift" (.name) (timelineShiftSlot.shiftTypeId >>= (`Map.lookup` shiftTypeById))
        groupKey = "existing:" <> tshow timelineShiftSlot.id
        shiftArticle = [hsx|
            <article {...launcherAttrs} class={classes [("roster-day-timeline-shift", True), ("is-roster-shift-open", isOpen), ("roster-shift-launcher", canLaunch), ("is-roster-shift-draggable", editable && not timelineShiftTimingInvalid), ("is-roster-shift-timing-invalid", timelineShiftTimingInvalid)]}
                     tabindex={if canLaunch then ("0" :: Text) else ""}
                     aria-label={if isOpen then ("Open shift" :: Text) else staffLabel}>
                <div class="roster-day-timeline-shift-time">{timelineShiftTimeLabel}{timingIssue}</div>
                <div class="roster-day-timeline-shift-staff">{staffLabel}</div>
                <div class="roster-day-timeline-shift-role" title={shiftTypeLabel}>{shiftTypeLabel}</div>
            </article>
        |]
        timingIssue = if timelineShiftTimingInvalid
            then [hsx|<span class="roster-shift-timing-issue text-warning" data-roster-timing-issue="true" title="Timing needs repair">!</span>|]
            else mempty
        launcherAttrs =
            if canLaunch
                then rosterShiftDialogLauncherAttrs (rosterSlotDialogUrl (ExistingRosterSlotTarget timelineShiftSlot.id anchorDate calendarRevision))
                else []
        card = [hsx|
            <div {...cardAttrs} class="roster-day-timeline-shift-position"
                 style={timelineShiftStyle timelineWindow timelineShiftStartMin timelineShiftEndMin timelineShiftTrack}>
                {shiftArticle}
            </div>
        |]
        cardAttrs = if editable && not timelineShiftTimingInvalid
            then SurfaceInteraction.frontendSurfaceSourceRefAttrs rosterDayTimelineSourceRef groupKey
                <> SurfaceLinkedHighlight.frontendSurfaceLinkedHighlightSourceAttrs rosterDayTimelineShiftGroupLinkedHighlight groupKey
                <> SurfaceLinkedHighlight.frontendSurfaceLinkedHighlightMemberAttrs rosterDayTimelineShiftGroupLinkedHighlight groupKey Nothing
            else []
     in card

staffTimelineLabel :: Staff -> Text
staffTimelineLabel staff =
    fromMaybe (staff.firstName <> " " <> staff.lastName) staff.preferredName

normalizeTimelineMinute :: TimelineWindow -> TimeOfDay -> Double
normalizeTimelineMinute TimelineWindow { timelineWindowStartMinute } TimeOfDay { todHour, todMin, todSec } =
    let minute = fromIntegral (todHour * 60 + todMin) + realToFrac (todSec :: Pico) / 60
     in if minute < fromIntegral timelineWindowStartMinute then minute + 24 * 60 else minute

timelineShiftFromSlot :: TimelineWindow -> Map.Map UUID.UUID (Either RosterShiftIntegrityError ValidatedRosterShiftTiming) -> RosterSlot -> TimelineShift
timelineShiftFromSlot timelineWindow timingBySlotId slot =
    case Map.lookup (unpackId slot.id) timingBySlotId of
        Just (Right timing) ->
            let start = rosterShiftTimingStartTime timing
                end = rosterShiftTimingEndTime timing
                startMin = normalizeTimelineMinute timelineWindow start
                endMin = startMin + realToFrac (rosterShiftTimingElapsedSeconds timing) / 60
             in TimelineShift
                    { timelineShiftSlot = slot
                    , timelineShiftStartMin = startMin
                    , timelineShiftEndMin = endMin
                    , timelineShiftTrack = 0
                    , timelineShiftTimeLabel = timeLabel start <> "–" <> timeLabel end
                    , timelineShiftTimingInvalid = False
                    }
        _ ->
            let startMin = fromIntegral timelineWindow.timelineWindowStartMinute
             in TimelineShift
                    { timelineShiftSlot = slot
                    , timelineShiftStartMin = startMin
                    , timelineShiftEndMin = startMin + 15
                    , timelineShiftTrack = 0
                    , timelineShiftTimeLabel = "Timing unavailable"
                    , timelineShiftTimingInvalid = True
                    }
  where
    timeLabel = Text.pack . formatTime defaultTimeLocale "%H:%M"

assignTimelineTracks :: [TimelineShift] -> [TimelineShift]
assignTimelineTracks shifts = reverse (snd (foldl assign ([], []) (sortOn timelineShiftStartMin shifts)))
  where
    assign (trackEnds, placed) shift =
        let (trackIndex, updatedTrackEnds) = placeInTrack 0 trackEnds shift.timelineShiftStartMin shift.timelineShiftEndMin
         in (updatedTrackEnds, shift { timelineShiftTrack = trackIndex } : placed)

placeInTrack :: Int -> [Double] -> Double -> Double -> (Int, [Double])
placeInTrack trackIndex [] _startMin endMin = (trackIndex, [endMin])
placeInTrack trackIndex (trackEnd:rest) startMin endMin
    | trackEnd <= startMin = (trackIndex, endMin : rest)
    | otherwise =
        let (selectedTrack, updatedRest) = placeInTrack (trackIndex + 1) rest startMin endMin
         in (selectedTrack, trackEnd : updatedRest)

timelineDropzones :: TimelineWindow -> RosterDay -> RosterLane -> [(Int, Text)]
timelineDropzones timelineWindow rosterDay slotDefinition =
    [ (minute, "time:" <> tshow rosterDay.id <> ":" <> tshow slotDefinition.id <> ":" <> tshow minute)
    | minute <- timelineQuarterHours timelineWindow
    ]

timelineQuarterHours :: TimelineWindow -> [Int]
timelineQuarterHours TimelineWindow { timelineWindowStartMinute, timelineWindowEndMinute } =
    [timelineWindowStartMinute, timelineWindowStartMinute + 15 .. timelineWindowEndMinute]

timelineHourTicks :: TimelineWindow -> [Int]
timelineHourTicks TimelineWindow { timelineWindowStartMinute, timelineWindowEndMinute } =
    [timelineWindowStartMinute, timelineWindowStartMinute + 60 .. timelineWindowEndMinute]

timelineLeftStyle :: TimelineWindow -> Int -> Text
timelineLeftStyle timelineWindow minute =
    "left:" <> timelinePercent timelineWindow (fromIntegral (minute - timelineWindow.timelineWindowStartMinute)) <> "%;"

timelineDropzoneStyle :: TimelineWindow -> Int -> Text
timelineDropzoneStyle timelineWindow minute
    | minute == timelineWindow.timelineWindowEndMinute = "left:" <> timelinePercent timelineWindow minuteOffset <> "%;right:0;"
    | otherwise = "left:" <> timelinePercent timelineWindow minuteOffset <> "%;width:" <> timelinePercent timelineWindow 15 <> "%;"
  where
    minuteOffset = fromIntegral (minute - timelineWindow.timelineWindowStartMinute)

timelineShiftStyle :: TimelineWindow -> Double -> Double -> Int -> Text
timelineShiftStyle timelineWindow startMin endMin track =
    let windowStart = fromIntegral timelineWindow.timelineWindowStartMinute
        windowEnd = fromIntegral timelineWindow.timelineWindowEndMinute
        clampedStart = max windowStart (min windowEnd startMin)
        clampedEnd = max clampedStart (min (windowEnd + 15) endMin)
     in "left:"
            <> timelinePercent timelineWindow (clampedStart - windowStart)
            <> "%;width:"
            <> timelinePercent timelineWindow (clampedEnd - clampedStart)
            <> "%;--roster-timeline-track:"
            <> tshow track
            <> ";"

timelinePercent :: TimelineWindow -> Double -> Text
timelinePercent TimelineWindow { timelineWindowTotalMinutes } minutes =
    tshow (minutes * 100 / fromIntegral timelineWindowTotalMinutes)

minuteLabel :: Int -> Text
minuteLabel minute =
    Text.pack (formatTime defaultTimeLocale "%H:%M" (minuteOfTimeline minute))

minuteOfTimeline :: Int -> TimeOfDay
minuteOfTimeline minute =
    let normalized = minute `mod` (24 * 60)
        (hour, minuteOfHour) = normalized `divMod` 60
     in TimeOfDay hour minuteOfHour 0
