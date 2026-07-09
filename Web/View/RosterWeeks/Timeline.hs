{-# LANGUAGE OverloadedRecordDot #-}

module Web.View.RosterWeeks.Timeline
    ( renderRosterDayTimelineContent
    , renderRosterDayTimelineShell
    ) where

import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.Profiling (profileHtmlComponent)
import Application.Helper.TimeRules (normalizeRosterOperationalMinute,
                                     rosterOperationalStartMinuteOfDay,
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
import Web.RosterWeeks.Dom (rosterDayTimelineContentFragmentId)
import Web.RosterWeeks.FrontendSurface (RosterDayTimelineScopeValue (..),
                                        rosterDayTimelineDropzoneRef,
                                        rosterDayTimelineSourceRef,
                                        rosterDayTimelineSurfaceImpl)
import Web.RosterWeeks.Paths (rosterWeekUrl)
import Web.RosterWeeks.Types
import Web.View.Prelude

renderRosterDayTimelineShell :: RosterRenderData -> RosterDay -> Html
renderRosterDayTimelineShell rosterData@RosterRenderData { rosterWeek, currentRosterGroup, weekStartDate } rosterDay =
    let date = Calendar.addDays (toInteger rosterDay.dayOffset) weekStartDate
        backUrl = rosterWeekUrl rosterWeek.weekOffset currentRosterGroup.id
        page = renderAppPage AppPageConfig
            { appPageTitle = "Roster timeline"
            , appPageDescription = Just (Text.pack (formatTime defaultTimeLocale "%A %d/%m/%Y" date))
            , appPageActions = [hsx|
                <a href={backUrl} class="btn btn-outline-secondary btn-sm">
                    <i class="bi bi-arrow-left" aria-hidden="true"></i>
                    Back to week view
                </a>
            |]
            , appPageHelpTopic = Just (PageHelpTopicId "roster")
            , appPageWidthClass = ""
            , appPageBody = renderRosterDayTimelineContent Nothing rosterData rosterDay
            }
        timelineSurfaceScope = RosterDayTimelineScopeValue
            { rosterDayTimelineVenueId = currentRosterGroup.venueId
            , rosterDayTimelineGroupId = currentRosterGroup.id
            , rosterDayTimelineWeekOffset = rosterWeek.weekOffset
            , rosterDayTimelineDayId = rosterDay.id
            }
     in profileHtmlComponent "render.roster.day_timeline_shell" (renderFrontendSurfaceMount (rosterDayTimelineSurfaceImpl timelineSurfaceScope) page)

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
     in [hsx|
        <section id={rosterDayTimelineContentFragmentId rosterDay.id}
                 class="app-panel roster-day-timeline-shell"
                 data-roster-day-timeline="true"
                 data-roster-day-timeline-editable={if editable then ("true" :: Text) else "false"}
                 hx-swap-oob={maybeSwapOob}>
            <header class="d-flex align-items-center justify-content-between gap-3 mb-3">
                <div>
                    <h2 class="h5 mb-1">{Text.pack (formatTime defaultTimeLocale "%A" date)} timeline</h2>
                    <p class="text-muted mb-0">{if editable then ("Drag shifts to a 15-minute time target." :: Text) else "Timeline is read-only."}</p>
                </div>
            </header>
            <div class="roster-day-timeline" role="grid" aria-label="Roster day timeline">
                {renderTimelineScale}
                {forEach rosterData.orderedSlotNames (renderTimelineLane editable rosterDay staffById shiftTypeById slotsByDefinition)}
            </div>
        </section>
    |]

renderTimelineScale :: Html
renderTimelineScale = [hsx|
    <div class="roster-day-timeline-scale" aria-hidden="true">
        {forEach timelineHourTicks renderTimelineScaleTick}
    </div>
|]

renderTimelineScaleTick :: Int -> Html
renderTimelineScaleTick minute = [hsx|
    <div class="roster-day-timeline-scale-tick" style={timelineLeftStyle minute}>
        {minuteLabel minute}
    </div>
|]

renderTimelineLane :: Bool -> RosterDay -> Map.Map UUID.UUID Staff -> Map.Map UUID.UUID ShiftType -> Map.Map UUID.UUID [RosterSlot] -> RosterWeekSlotDefinition -> Html
renderTimelineLane editable rosterDay staffById shiftTypeById slotsByDefinition slotDefinition =
    let laneSlots = Map.findWithDefault [] (unpackId slotDefinition.id) slotsByDefinition
        positionedShifts = assignTimelineTracks (mapMaybe timelineShiftFromSlot laneSlots)
        trackCount = max 1 (1 + maximum (0 : map timelineShiftTrack positionedShifts))
        dropzones = if editable then timelineDropzones rosterDay slotDefinition else []
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
                    {forEach dropzones renderTimelineDropzone}
                </div>
                <div class="roster-day-timeline-shifts">
                    {forEach positionedShifts (renderTimelineShift editable staffById shiftTypeById)}
                </div>
            </div>
        </section>
    |]

renderTimelineDropzone :: (Int, Text) -> Html
renderTimelineDropzone (minute, targetKey) =
    SurfaceInteraction.withFrontendSurfaceDropzoneRef rosterDayTimelineDropzoneRef targetKey [hsx|
        <div class="roster-day-timeline-dropzone"
             style={timelineDropzoneStyle minute}
             data-roster-timeline-minute={tshow minute}
             aria-label={"Move shift to " <> minuteLabel minute}>
        </div>
    |]

renderTimelineShift :: Bool -> Map.Map UUID.UUID Staff -> Map.Map UUID.UUID ShiftType -> TimelineShift -> Html
renderTimelineShift editable staffById shiftTypeById TimelineShift { timelineShiftSlot, timelineShiftStartMin, timelineShiftEndMin, timelineShiftTrack } =
    let staffLabel = maybe "Unassigned" staffTimelineLabel (timelineShiftSlot.staffId >>= (`Map.lookup` staffById))
        shiftTypeLabel = maybe "Shift" (.name) (timelineShiftSlot.shiftTypeId >>= (`Map.lookup` shiftTypeById))
        card = [hsx|
            <article class={classes [("roster-day-timeline-shift", True), ("roster-shift-launcher", editable)]}
                     style={timelineShiftStyle timelineShiftStartMin timelineShiftEndMin timelineShiftTrack}
                     data-roster-slot-id={tshow timelineShiftSlot.id}
                     data-roster-shift-group-key={"existing:" <> tshow timelineShiftSlot.id}
                     tabindex={if editable then ("0" :: Text) else ""}>
                <div class="roster-day-timeline-shift-time">{minuteLabel timelineShiftStartMin}–{minuteLabel timelineShiftEndMin}</div>
                <div class="roster-day-timeline-shift-staff">{staffLabel}</div>
                <div class="roster-day-timeline-shift-role">{shiftTypeLabel}</div>
            </article>
        |]
     in if editable
            then SurfaceInteraction.withFrontendSurfaceSourceRef rosterDayTimelineSourceRef ("existing:" <> tshow timelineShiftSlot.id) card
            else card

staffTimelineLabel :: Staff -> Text
staffTimelineLabel staff =
    fromMaybe (staff.firstName <> " " <> staff.lastName) staff.preferredName

timelineShiftFromSlot :: RosterSlot -> Maybe TimelineShift
timelineShiftFromSlot slot = do
    start <- slot.startTime
    end <- slot.endTime
    let startMin = normalizeRosterOperationalMinute start
        endMin = normalizeRosterOperationalMinute end
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

timelineDropzones :: RosterDay -> RosterWeekSlotDefinition -> [(Int, Text)]
timelineDropzones rosterDay slotDefinition =
    [ (minute, "time:" <> tshow rosterDay.id <> ":" <> tshow slotDefinition.id <> ":" <> tshow minute)
    | minute <- timelineQuarterHours
    ]

timelineQuarterHours :: [Int]
timelineQuarterHours = [rosterOperationalStartMinuteOfDay, rosterOperationalStartMinuteOfDay + 15 .. rosterOperationalStartMinuteOfDay + rosterTimelineTotalMinutes - 15]

timelineHourTicks :: [Int]
timelineHourTicks = [rosterOperationalStartMinuteOfDay, rosterOperationalStartMinuteOfDay + 60 .. rosterOperationalStartMinuteOfDay + rosterTimelineTotalMinutes]

rosterTimelineTotalMinutes :: Int
rosterTimelineTotalMinutes = 24 * 60

timelineLeftStyle :: Int -> Text
timelineLeftStyle minute = "left:" <> timelinePercent (minute - rosterOperationalStartMinuteOfDay) <> "%;"

timelineDropzoneStyle :: Int -> Text
timelineDropzoneStyle minute =
    "left:" <> timelinePercent (minute - rosterOperationalStartMinuteOfDay) <> "%;width:" <> timelinePercent 15 <> "%;"

timelineShiftStyle :: Int -> Int -> Int -> Text
timelineShiftStyle startMin endMin track =
    "left:"
        <> timelinePercent (startMin - rosterOperationalStartMinuteOfDay)
        <> "%;width:"
        <> timelinePercent (max 15 (endMin - startMin))
        <> "%;--roster-timeline-track:"
        <> tshow track
        <> ";"

timelinePercent :: Int -> Text
timelinePercent minutes =
    tshow ((fromIntegral minutes :: Double) * 100 / fromIntegral rosterTimelineTotalMinutes)

minuteLabel :: Int -> Text
minuteLabel minute =
    Text.pack (formatTime defaultTimeLocale "%H:%M" (minuteOfTimeline minute))

minuteOfTimeline :: Int -> TimeOfDay
minuteOfTimeline minute =
    let normalized = minute `mod` rosterTimelineTotalMinutes
        (hour, minuteOfHour) = normalized `divMod` 60
     in TimeOfDay hour minuteOfHour 0
