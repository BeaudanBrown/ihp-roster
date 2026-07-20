{-# LANGUAGE OverloadedRecordDot #-}

module Web.View.RosterWeeks.Timeline
    ( renderRosterDayTimelineContent
    , renderRosterDayTimelinePanel
    ) where

import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.LinkedHighlight as SurfaceLinkedHighlight
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceInteractionShellConfig (..),
                                                            renderFrontendSurfaceInteractionShell,
                                                            renderFrontendSurfaceMount)
import Application.Helper.Profiling (profileHtmlComponent)
import Application.Helper.TimeRules (normalizeWindowEndMinute,
                                     shiftDurationMinutes)
import Control.Monad (guard)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import qualified Data.Text as Text
import qualified Data.Time.Calendar as Calendar
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.UUID as UUID
import Web.RosterWeeks.Dom (rosterDayTimelineContentFragmentId,
                            rosterWeekShellId)
import Web.RosterWeeks.FrontendSurface (RosterDayTimelineScopeValue (..),
                                        rosterDayTimelineDropzoneRef,
                                        rosterDayTimelineFrontendSurfaceIR,
                                        rosterDayTimelineIntentForms,
                                        rosterDayTimelineShiftGroupLinkedHighlight,
                                        rosterDayTimelineSourceRef,
                                        rosterDayTimelineSurfaceImpl)
import Web.RosterWeeks.Types
import Web.View.Prelude

renderRosterDayTimelinePanel :: (?context :: ControllerContext) => RosterGridRenderModel -> RosterDay -> Html
renderRosterDayTimelinePanel RosterGridRenderModel { gridRosterWeek = Nothing } _ = [hsx|
    <div class="alert alert-info mb-0">This draft roster is not visible.</div>
|]
renderRosterDayTimelinePanel RosterGridRenderModel { gridRosterWeek = Just rosterWeek, gridRosterDays, gridCurrentRosterGroup, gridWeekStartDate, gridAssignmentFilters, gridStaffMembers, gridPanelStaff, gridStaffSelfServicePanel, gridSlotNames, gridShiftTypes, gridAllSlots, gridSlotConflicts, gridRenderIndexes, gridRosterLayoutMode, gridRosterEndTimesEnabled, gridRosterTimePickerStartMinute, gridRosterTimePickerFinalSelectableMinute, gridRosterWagePrediction, gridShowWageEstimates, gridShowRosterWarnings, gridPublicHolidays } rosterDay =
    let rosterData = RosterRenderData
            { rosterWeek = rosterWeek
            , rosterDays = gridRosterDays
            , rosterGroups = []
            , currentRosterGroup = gridCurrentRosterGroup
            , weekStartDate = gridWeekStartDate
            , assignmentFilters = gridAssignmentFilters
            , staffMembers = gridStaffMembers
            , panelStaff = gridPanelStaff
            , staffSelfServicePanel = gridStaffSelfServicePanel
            , orderedSlotNames = gridSlotNames
            , shiftTypes = gridShiftTypes
            , allSlots = gridAllSlots
            , slotConflicts = gridSlotConflicts
            , renderIndexes = gridRenderIndexes
            , rosterLayoutMode = gridRosterLayoutMode
            , rosterEndTimesEnabled = gridRosterEndTimesEnabled
            , rosterTimePickerStartMinute = gridRosterTimePickerStartMinute
            , rosterTimePickerFinalSelectableMinute = gridRosterTimePickerFinalSelectableMinute
            , rosterWagePrediction = gridRosterWagePrediction
            , showWageEstimates = gridShowWageEstimates
            , showRosterWarnings = gridShowRosterWarnings
            , rosterPublicHolidays = gridPublicHolidays
            }
     in renderRosterDayTimelineMounted rosterData rosterDay (renderRosterDayTimelineContent Nothing rosterData rosterDay)

renderRosterDayTimelineMounted :: RosterRenderData -> RosterDay -> Html -> Html
renderRosterDayTimelineMounted RosterRenderData { rosterWeek, currentRosterGroup } rosterDay body =
    let timelineSurfaceScope = RosterDayTimelineScopeValue
            { rosterDayTimelineVenueId = currentRosterGroup.venueId
            , rosterDayTimelineGroupId = currentRosterGroup.id
            , rosterDayTimelineWeekOffset = rosterWeek.weekOffset
            , rosterDayTimelineDayOffset = rosterDay.dayOffset
            , rosterDayTimelineDayId = rosterDay.id
            }
        timelineSurface = rosterDayTimelineSurfaceImpl timelineSurfaceScope
     in renderFrontendSurfaceMount timelineSurface $
            renderFrontendSurfaceInteractionShell timelineSurface rosterDayTimelineFrontendSurfaceIR FrontendSurfaceInteractionShellConfig
                { interactionShellHtmxSync = Just ("#" <> rosterWeekShellId <> ":replace")
                , interactionShellIntentForms = rosterDayTimelineIntentForms timelineSurfaceScope
                } body

data TimelineShift = TimelineShift
    { timelineShiftSlot     :: !RosterSlot
    , timelineShiftStartMin :: !Int
    , timelineShiftEndMin   :: !Int
    , timelineShiftTrack    :: !Int
    }

renderRosterDayTimelineContent :: Maybe Text -> RosterRenderData -> RosterDay -> Html
renderRosterDayTimelineContent maybeSwapOob rosterData rosterDay =
    let date = Calendar.addDays (toInteger rosterDay.dayOffset) rosterData.weekStartDate
        daySlots = filter (\slot -> slot.rosterDayId == unpackId rosterDay.id) rosterData.allSlots
        slotsByDefinition = Map.fromListWith (<>) [ (slot.rosterWeekSlotDefinitionId, [slot]) | slot <- daySlots ]
        staffById = Map.fromList [ (unpackId staff.id, staff) | staff <- rosterData.staffMembers ]
        shiftTypeById = Map.fromList [ (unpackId shiftType.id, shiftType) | shiftType <- rosterData.shiftTypes ]
        editable = currentUserIsManager && not rosterData.rosterWeek.isLive && not rosterDay.isClosed
        timelineWindow = timelineWindowFromRosterData rosterData
     in [hsx|
        <section id={rosterDayTimelineContentFragmentId rosterDay.id}
                 class="roster-day-timeline-shell"
                 data-roster-day-timeline="true"
                 data-roster-day-timeline-editable={if editable then ("true" :: Text) else "false"}
                 hx-swap-oob={maybeSwapOob}>
            <div class="roster-day-timeline" role="grid" aria-label={Text.pack (formatTime defaultTimeLocale "%A %d/%m roster timeline" date)}>
                {renderTimelineScale timelineWindow}
                {forEach rosterData.orderedSlotNames (renderTimelineLane timelineWindow editable rosterDay staffById shiftTypeById slotsByDefinition)}
            </div>
        </section>
    |]

data TimelineWindow = TimelineWindow
    { timelineWindowStartMinute  :: !Int
    , timelineWindowEndMinute    :: !Int
    , timelineWindowTotalMinutes :: !Int
    }

timelineWindowFromRosterData :: RosterRenderData -> TimelineWindow
timelineWindowFromRosterData RosterRenderData { rosterTimePickerStartMinute, rosterTimePickerFinalSelectableMinute } =
    let endMinute = normalizeWindowEndMinute rosterTimePickerStartMinute rosterTimePickerFinalSelectableMinute
     in TimelineWindow
            { timelineWindowStartMinute = rosterTimePickerStartMinute
            , timelineWindowEndMinute = endMinute
            , timelineWindowTotalMinutes = max 15 (endMinute - rosterTimePickerStartMinute + 15)
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

renderTimelineLane :: TimelineWindow -> Bool -> RosterDay -> Map.Map UUID.UUID Staff -> Map.Map UUID.UUID ShiftType -> Map.Map UUID.UUID [RosterSlot] -> RosterWeekSlotDefinition -> Html
renderTimelineLane timelineWindow editable rosterDay staffById shiftTypeById slotsByDefinition slotDefinition =
    let laneSlots = Map.findWithDefault [] (unpackId slotDefinition.id) slotsByDefinition
        positionedShifts = assignTimelineTracks (mapMaybe (timelineShiftFromSlot timelineWindow) laneSlots)
        trackCount = max 1 (1 + maximum (0 : map timelineShiftTrack positionedShifts))
        dropzones = if editable then timelineDropzones timelineWindow rosterDay slotDefinition else []
     in [hsx|
        <section class="roster-day-timeline-lane"
                 role="rowgroup"
                 style={"--roster-timeline-track-count:" <> tshow trackCount <> ";"}>
            <div class="roster-day-timeline-lane-label">
                <span class="fw-semibold">{slotDefinition.name}</span>
                <span class="text-muted small">{length positionedShifts} shifts</span>
            </div>
            <div class="roster-day-timeline-lane-body" role="row">
                <div class="roster-day-timeline-dropzones" aria-hidden={if editable then ("false" :: Text) else "true"}>
                    {forEach dropzones (renderTimelineDropzone timelineWindow)}
                </div>
                <div class="roster-day-timeline-shifts">
                    {forEach positionedShifts (renderTimelineShift timelineWindow editable staffById shiftTypeById)}
                </div>
            </div>
        </section>
    |]

renderTimelineDropzone :: TimelineWindow -> (Int, Text) -> Html
renderTimelineDropzone timelineWindow (minute, targetKey) =
    SurfaceInteraction.withFrontendSurfaceDropzoneRef rosterDayTimelineDropzoneRef targetKey [hsx|
        <div class="roster-day-timeline-dropzone"
             style={timelineDropzoneStyle timelineWindow minute}
             data-roster-timeline-minute={tshow minute}
             aria-label={"Move shift to " <> minuteLabel minute}>
        </div>
    |]

renderTimelineShift :: TimelineWindow -> Bool -> Map.Map UUID.UUID Staff -> Map.Map UUID.UUID ShiftType -> TimelineShift -> Html
renderTimelineShift timelineWindow editable staffById shiftTypeById TimelineShift { timelineShiftSlot, timelineShiftStartMin, timelineShiftEndMin, timelineShiftTrack } =
    let staffLabel = maybe "Unassigned" staffTimelineLabel (timelineShiftSlot.staffId >>= (`Map.lookup` staffById))
        shiftTypeLabel = maybe "Shift" (.name) (timelineShiftSlot.shiftTypeId >>= (`Map.lookup` shiftTypeById))
        groupKey = "existing:" <> tshow timelineShiftSlot.id
        card = [hsx|
            <article class={classes [("roster-day-timeline-shift", True), ("roster-shift-launcher", editable)]}
                     style={timelineShiftStyle timelineWindow timelineShiftStartMin timelineShiftEndMin timelineShiftTrack}
                     tabindex={if editable then ("0" :: Text) else ""}>
                <div class="roster-day-timeline-shift-time">{minuteLabel timelineShiftStartMin}–{minuteLabel timelineShiftEndMin}</div>
                <div class="roster-day-timeline-shift-staff">{staffLabel}</div>
                <div class="roster-day-timeline-shift-role">{shiftTypeLabel}</div>
            </article>
        |]
     in if editable
            then SurfaceInteraction.withFrontendSurfaceSourceRef rosterDayTimelineSourceRef groupKey $
                SurfaceLinkedHighlight.withFrontendSurfaceLinkedHighlightSource rosterDayTimelineShiftGroupLinkedHighlight groupKey $
                    SurfaceLinkedHighlight.withFrontendSurfaceLinkedHighlightMember rosterDayTimelineShiftGroupLinkedHighlight groupKey Nothing card
            else card

staffTimelineLabel :: Staff -> Text
staffTimelineLabel staff =
    fromMaybe (staff.firstName <> " " <> staff.lastName) staff.preferredName

normalizeTimelineMinute :: TimelineWindow -> TimeOfDay -> Int
normalizeTimelineMinute TimelineWindow { timelineWindowStartMinute } tod =
    let minute = todHour tod * 60 + todMin tod
     in if minute < timelineWindowStartMinute then minute + 24 * 60 else minute

timelineShiftFromSlot :: TimelineWindow -> RosterSlot -> Maybe TimelineShift
timelineShiftFromSlot timelineWindow slot = do
    start <- slot.startTime
    end <- slot.endTime
    let startMin = normalizeTimelineMinute timelineWindow start
        endMin = startMin + shiftDurationMinutes start end
        duration = shiftDurationMinutes start end
    guard (duration > 0)
    pure TimelineShift { timelineShiftSlot = slot, timelineShiftStartMin = startMin, timelineShiftEndMin = endMin, timelineShiftTrack = 0 }

assignTimelineTracks :: [TimelineShift] -> [TimelineShift]
assignTimelineTracks shifts = reverse (snd (foldl assign ([], []) (sortOn timelineShiftStartMin shifts)))
  where
    assign (trackEnds, placed) shift =
        let (trackIndex, updatedTrackEnds) = placeInTrack 0 trackEnds shift.timelineShiftStartMin shift.timelineShiftEndMin
         in (updatedTrackEnds, shift { timelineShiftTrack = trackIndex } : placed)

placeInTrack :: Int -> [Int] -> Int -> Int -> (Int, [Int])
placeInTrack trackIndex [] _startMin endMin = (trackIndex, [endMin])
placeInTrack trackIndex (trackEnd:rest) startMin endMin
    | trackEnd <= startMin = (trackIndex, endMin : rest)
    | otherwise =
        let (selectedTrack, updatedRest) = placeInTrack (trackIndex + 1) rest startMin endMin
         in (selectedTrack, trackEnd : updatedRest)

timelineDropzones :: TimelineWindow -> RosterDay -> RosterWeekSlotDefinition -> [(Int, Text)]
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
timelineLeftStyle timelineWindow minute = "left:" <> timelinePercent timelineWindow (minute - timelineWindow.timelineWindowStartMinute) <> "%;"

timelineDropzoneStyle :: TimelineWindow -> Int -> Text
timelineDropzoneStyle timelineWindow minute
    | minute == timelineWindow.timelineWindowEndMinute = "left:" <> timelinePercent timelineWindow (minute - timelineWindow.timelineWindowStartMinute) <> "%;right:0;"
    | otherwise = "left:" <> timelinePercent timelineWindow (minute - timelineWindow.timelineWindowStartMinute) <> "%;width:" <> timelinePercent timelineWindow 15 <> "%;"

timelineShiftStyle :: TimelineWindow -> Int -> Int -> Int -> Text
timelineShiftStyle timelineWindow startMin endMin track =
    let clampedStart = max timelineWindow.timelineWindowStartMinute (min timelineWindow.timelineWindowEndMinute startMin)
        clampedEnd = max (clampedStart + 15) (min (timelineWindow.timelineWindowEndMinute + 15) endMin)
     in "left:"
            <> timelinePercent timelineWindow (clampedStart - timelineWindow.timelineWindowStartMinute)
            <> "%;width:"
            <> timelinePercent timelineWindow (max 15 (clampedEnd - clampedStart))
            <> "%;--roster-timeline-track:"
            <> tshow track
            <> ";"

timelinePercent :: TimelineWindow -> Int -> Text
timelinePercent TimelineWindow { timelineWindowTotalMinutes } minutes =
    tshow ((fromIntegral minutes :: Double) * 100 / fromIntegral timelineWindowTotalMinutes)

minuteLabel :: Int -> Text
minuteLabel minute =
    Text.pack (formatTime defaultTimeLocale "%H:%M" (minuteOfTimeline minute))

minuteOfTimeline :: Int -> TimeOfDay
minuteOfTimeline minute =
    let normalized = minute `mod` (24 * 60)
        (hour, minuteOfHour) = normalized `divMod` 60
     in TimeOfDay hour minuteOfHour 0
