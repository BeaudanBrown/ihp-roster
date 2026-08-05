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
import Application.VenueTime.Model (rosterSlotElapsedSeconds, rosterSlotEndTime,
                                    rosterSlotStartTime)
import Control.Monad (guard)
import Data.Fixed (Pico)
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
import Web.View.RosterWeeks.Grid.Cells (RosterSlotCellTarget (ExistingRosterSlotTarget),
                                        applyRosterShiftDialogLauncherAttrs,
                                        rosterSlotDialogAction)

renderRosterDayTimelinePanel :: (?context :: ControllerContext) => RosterGridRenderModel -> RosterDay -> Html
renderRosterDayTimelinePanel RosterGridRenderModel { gridRosterWeek = Nothing } _ = [hsx|
    <div class="alert alert-info mb-0">This draft roster is not visible.</div>
|]
renderRosterDayTimelinePanel RosterGridRenderModel { gridRosterWeek = Just rosterWeek, gridRosterDays, gridCurrentRosterGroup, gridWeekStartDate, gridAssignmentFilters, gridStaffMembers, gridPanelStaff, gridTemplateLibrary, gridTemplateLibraryUserId, gridStaffSelfServicePanel, gridSlotNames, gridShiftTypes, gridAllSlots, gridSlotConflicts, gridRenderIndexes, gridRosterLayoutMode, gridRosterEndTimesEnabled, gridRosterTimePickerStartMinute, gridRosterTimePickerFinalSelectableMinute, gridRosterWagePrediction, gridShowWageEstimates, gridShowRosterWarnings, gridPublicHolidays } rosterDay =
    let rosterData = RosterRenderData
            { rosterWeek = rosterWeek
            , rosterDays = gridRosterDays
            , rosterGroups = []
            , currentRosterGroup = gridCurrentRosterGroup
            , weekStartDate = gridWeekStartDate
            , assignmentFilters = gridAssignmentFilters
            , staffMembers = gridStaffMembers
            , panelStaff = gridPanelStaff
            , templateLibrary = gridTemplateLibrary
            , templateLibraryUserId = gridTemplateLibraryUserId
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
    , timelineShiftStartMin :: !Double
    , timelineShiftEndMin   :: !Double
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
        assignedShiftCount = length (filter (rosterShiftIsStaffAssigned . (.timelineShiftSlot)) positionedShifts)
        dropzones = if editable then timelineDropzones timelineWindow rosterDay slotDefinition else []
     in [hsx|
        <section class="roster-day-timeline-lane"
                 role="rowgroup"
                 style={"--roster-timeline-track-count:" <> tshow trackCount <> ";"}>
            <div class="roster-day-timeline-lane-label">
                <span class="fw-semibold">{slotDefinition.name}</span>
                <span class="text-muted small">{assignedShiftCount} shifts</span>
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
    let isOpen = rosterShiftIsOpen timelineShiftSlot
        canLaunch = editable || (isOpen && hasRole Manager)
        staffLabel = if isOpen then "OPEN" else maybe "Unassigned" staffTimelineLabel (timelineShiftSlot.staffId >>= (`Map.lookup` staffById))
        shiftTypeLabel = maybe "Shift" (.name) (timelineShiftSlot.shiftTypeId >>= (`Map.lookup` shiftTypeById))
        groupKey = "existing:" <> tshow timelineShiftSlot.id
        shiftArticle = [hsx|
            <article class={classes [("roster-day-timeline-shift", True), ("is-roster-shift-open", isOpen), ("roster-shift-launcher", canLaunch), ("is-roster-shift-draggable", editable)]}
                     tabindex={if canLaunch then ("0" :: Text) else ""}
                     aria-label={if isOpen then ("Open shift" :: Text) else staffLabel}>
                <div class="roster-day-timeline-shift-time">{timelineShiftTimeLabel timelineShiftSlot}</div>
                <div class="roster-day-timeline-shift-staff">{staffLabel}</div>
                <div class="roster-day-timeline-shift-role" title={shiftTypeLabel}>{shiftTypeLabel}</div>
            </article>
        |]
        launchableArticle =
            if canLaunch
                then applyRosterShiftDialogLauncherAttrs (pathTo (rosterSlotDialogAction (ExistingRosterSlotTarget timelineShiftSlot.id))) shiftArticle
                else shiftArticle
        card = [hsx|
            <div class="roster-day-timeline-shift-position"
                 style={timelineShiftStyle timelineWindow timelineShiftStartMin timelineShiftEndMin timelineShiftTrack}>
                {launchableArticle}
            </div>
        |]
     in if editable
            then SurfaceInteraction.withFrontendSurfaceSourceRef rosterDayTimelineSourceRef groupKey $
                SurfaceLinkedHighlight.withFrontendSurfaceLinkedHighlightSource rosterDayTimelineShiftGroupLinkedHighlight groupKey $
                    SurfaceLinkedHighlight.withFrontendSurfaceLinkedHighlightMember rosterDayTimelineShiftGroupLinkedHighlight groupKey Nothing card
            else card

staffTimelineLabel :: Staff -> Text
staffTimelineLabel staff =
    fromMaybe (staff.firstName <> " " <> staff.lastName) staff.preferredName

normalizeTimelineMinute :: TimelineWindow -> TimeOfDay -> Double
normalizeTimelineMinute TimelineWindow { timelineWindowStartMinute } TimeOfDay { todHour, todMin, todSec } =
    let minute = fromIntegral (todHour * 60 + todMin) + realToFrac (todSec :: Pico) / 60
     in if minute < fromIntegral timelineWindowStartMinute then minute + 24 * 60 else minute

timelineShiftFromSlot :: TimelineWindow -> RosterSlot -> Maybe TimelineShift
timelineShiftFromSlot timelineWindow slot = do
    start <- rosterSlotStartTime slot
    duration <- rosterSlotElapsedSeconds slot
    guard (duration > 0)
    let startMin = normalizeTimelineMinute timelineWindow start
        endMin = startMin + realToFrac duration / 60
    pure TimelineShift { timelineShiftSlot = slot, timelineShiftStartMin = startMin, timelineShiftEndMin = endMin, timelineShiftTrack = 0 }

timelineShiftTimeLabel :: RosterSlot -> Text
timelineShiftTimeLabel slot =
    case (rosterSlotStartTime slot, rosterSlotEndTime slot) of
        (Just start, Just end) -> timeLabel start <> "–" <> timeLabel end
        _                      -> "Invalid time"
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
