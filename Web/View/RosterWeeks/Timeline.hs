{-# LANGUAGE OverloadedRecordDot #-}

module Web.View.RosterWeeks.Timeline
    ( renderRosterDayTimelineContent
    , renderRosterDayTimelinePanel
    ) where

import Application.Helper.Controller (hasManagementMode)
import qualified Application.Helper.FrontendContract.Interaction.Runtime as Drag
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.LinkedHighlight as SurfaceLinkedHighlight
import Application.RosterShiftAssignment (rosterShiftIsOpen,
                                          rosterShiftIsStaffAssigned)
import Application.VenueTime (VenueTimeError)
import Application.VenueTime.Model (RosterShiftIntegrityError,
                                    ValidatedRosterShiftTiming,
                                    authoritativeElapsedSeconds,
                                    authoritativeEndsAt, authoritativeStartsAt,
                                    decodeRosterShiftTiming,
                                    rosterShiftTimingBoundaries)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import qualified Data.UUID as UUID
import Web.RosterWeeks.DateRange (RosterWindowLane, laneForOperationalDate,
                                  rosterWindowLaneName)
import Web.RosterWeeks.DefaultDuration (RosterCreationDefaults (..),
                                        defaultRosterEnd)
import Web.RosterWeeks.Dom (rosterDayTimelineContentFragmentId)
import Web.RosterWeeks.FrontendSurface (rosterDayTimelineDropzoneRef,
                                        rosterDayTimelineSourceRef,
                                        rosterExistingShiftDropzoneRef,
                                        rosterShiftGroupLinkedHighlight)
import Web.RosterWeeks.Paths (rosterTimelineCreateDialogUrl,
                              withRosterTimelineContext,
                              withTimelineOrientation)
import Web.RosterWeeks.Rows (rosterSlotHasVisibleData)
import Web.RosterWeeks.TimelineScale
import Web.RosterWeeks.Types
import Web.View.Prelude
import Web.View.RosterWeeks.Grid.Cells (RosterSlotCellTarget (ExistingRosterSlotTarget),
                                        rosterShiftDialogLauncherAttrs,
                                        rosterSlotDialogUrl,
                                        shiftTypeBadgeColourKey)

renderRosterDayTimelinePanel :: (?context :: ControllerContext) => RosterGridRenderModel -> RosterDay -> Html
renderRosterDayTimelinePanel RosterGridRenderModel { gridRosterWeek = Nothing } _ = [hsx|
    <div class="alert alert-info mb-0">This draft roster is not visible.</div>
|]
renderRosterDayTimelinePanel gridModel@RosterGridRenderModel { gridRosterWeek = Just _ } rosterDay = [hsx|
    <div {...SurfaceInteraction.frontendSurfaceDragScrollContainerAttrs} {...Drag.nativeContextMenuDisabledAttrs} class="roster-day-timeline-scroller" tabindex="0" aria-label="Scroll roster timeline">
        {renderRosterDayTimelineContent Nothing gridModel rosterDay}
    </div>
|]

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
        editable = hasManagementMode && maybe False (not . (.windowIsPublished)) gridModel.gridRosterWeek && not rosterDay.isClosed
        savedIntervals = mapMaybe (\slot -> case Map.lookup (unpackId slot.id) gridModel.gridRenderIndexes.rosterTimingBySlotId of
            Just (Right timing) -> let boundaries = rosterShiftTimingBoundaries timing
                                   in Just (authoritativeStartsAt boundaries, authoritativeEndsAt boundaries)
            _ -> Nothing) daySlots
     in case timelineWindowFromGridModel gridModel date savedIntervals of
        Left _ -> [hsx|<div class="alert alert-warning">The timeline time range could not be resolved. Use the roster grid to inspect these shifts.</div>|]
        Right timelineWindow -> [hsx|
        <section id={rosterDayTimelineContentFragmentId rosterDay.id}
                 class="roster-day-timeline-shell"
                 data-roster-day-timeline="true"
                 data-roster-timeline-orientation={timelineOrientationValue (rosterTimelineOrientation gridModel.gridViewMode)}
                 data-roster-day-timeline-editable={if editable then ("true" :: Text) else "false"}
                 style={"--roster-timeline-hours:" <> tshow (timelineWindow.timelineWindowScale.scaleMinutes / 60) <> ";--roster-timeline-lane-count:" <> tshow (length gridModel.gridSlotNames) <> ";"}
                 hx-swap-oob={maybeSwapOob}>
            <div class="roster-day-timeline" role="group" aria-label={Text.pack (formatTime defaultTimeLocale "%A %d/%m roster timeline" date)}>
                {renderTimelineScale timelineWindow}
                {forEach gridModel.gridSlotNames (renderTimelineLane timelineWindow editable rosterDay gridModel.gridRosterCalendarRevision staffById shiftTypeById slotsByDefinition gridModel.gridRenderIndexes.rosterTimingBySlotId)}
            </div>
        </section>
    |]

data TimelineWindow = TimelineWindow
    { timelineWindowScale          :: !TimelineScale
    , timelineWindowEndMinute      :: !Int
    , timelineWindowOrientation    :: !TimelineOrientation
    , timelineWindowCreationPolicy :: !RosterCreationDefaults
    }

timelineWindowFromGridModel :: RosterGridRenderModel -> Day -> [(UTCTime, UTCTime)] -> Either VenueTimeError TimelineWindow
timelineWindowFromGridModel gridModel date intervals = do
    let policy = gridModel.gridRosterCreationPolicy
    scale <- timelineScaleForDay date policy.creationWindowStartMinute policy.creationWindowEndMinute intervals
    pure TimelineWindow
        { timelineWindowScale = scale
        , timelineWindowEndMinute = max 0 (ceiling scale.scaleMinutes - 15)
        , timelineWindowOrientation = rosterTimelineOrientation gridModel.gridViewMode
        , timelineWindowCreationPolicy = policy
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
        {timelineClockLabel (timelineInstantAt timelineWindow.timelineWindowScale (fromIntegral minute))}
    </div>
|]

renderTimelineGridline :: TimelineWindow -> Int -> Html
renderTimelineGridline timelineWindow minute = [hsx|
    <span style={timelineLeftStyle timelineWindow minute}></span>
|]

renderTimelineLane :: TimelineWindow -> Bool -> RosterDay -> Int -> Map.Map UUID.UUID Staff -> Map.Map UUID.UUID ShiftType -> Map.Map UUID.UUID [RosterSlot] -> Map.Map UUID.UUID (Either RosterShiftIntegrityError ValidatedRosterShiftTiming) -> RosterWindowLane -> Html
renderTimelineLane timelineWindow editable rosterDay calendarRevision staffById shiftTypeById slotsByDefinition timingBySlotId windowLane =
    let maybeLane = laneForOperationalDate rosterDay.operationalDate windowLane
        laneSlots = filter rosterSlotHasVisibleData (maybe [] (\lane -> Map.findWithDefault [] (unpackId lane.id) slotsByDefinition) maybeLane)
        positionedShifts = assignTimelineTracks (map (timelineShiftFromSlot timelineWindow timingBySlotId) laneSlots)
        trackCount = max 1 (1 + foldl' max 0 (map timelineShiftTrack positionedShifts))
        assignedShiftCount = length (filter (rosterShiftIsStaffAssigned . (.timelineShiftSlot)) positionedShifts)
        dropzones = if editable then maybe [] (timelineDropzones timelineWindow rosterDay) maybeLane else []
        canFillPublishedOpen = hasManagementMode && rosterDay.publicationState == Published && not rosterDay.isClosed
        addShiftButton = case find (\(instant, _) -> isJust (defaultRosterEnd timelineWindow.timelineWindowCreationPolicy rosterDay.operationalDate instant 5)) dropzones of
            Nothing -> mempty
            Just (_, key) -> [hsx|
                <button {...(rosterShiftDialogLauncherAttrs (withTimelineOrientation timelineWindow.timelineWindowOrientation (rosterTimelineCreateDialogUrl rosterDay.operationalDate (Id rosterDay.rosterGroupId) calendarRevision key)))}
                        type="button" class="btn btn-sm btn-outline-secondary"
                        aria-label={"Add shift in " <> rosterWindowLaneName windowLane}>Add shift</button>
            |]
     in [hsx|
        <section class="roster-day-timeline-lane"
                 aria-label={rosterWindowLaneName windowLane}
                 style={"--roster-timeline-track-count:" <> tshow trackCount <> ";"}>
            <div class="roster-day-timeline-lane-label">
                <span class="fw-semibold">{rosterWindowLaneName windowLane}</span>
                <span class="text-muted small">{assignedShiftCount} {if assignedShiftCount == 1 then "shift" else "shifts" :: Text}</span>
                {addShiftButton}
            </div>
            <div {...Drag.dragAxisAttrs} class="roster-day-timeline-lane-body">
                <div class="roster-day-timeline-gridlines" aria-hidden="true">
                    {forEach (timelineHourTicks timelineWindow) (renderTimelineGridline timelineWindow)}
                </div>
                <div class="roster-day-timeline-dropzones" aria-hidden={if editable then ("false" :: Text) else "true"}>
                    {forEach dropzones (renderTimelineDropzone timelineWindow rosterDay calendarRevision)}
                </div>
                <div class="roster-day-timeline-shifts">
                    {forEach positionedShifts (renderTimelineShift timelineWindow editable canFillPublishedOpen staffById shiftTypeById rosterDay.operationalDate calendarRevision)}
                </div>
            </div>
        </section>
    |]

renderTimelineDropzone :: TimelineWindow -> RosterDay -> Int -> (UTCTime, Text) -> Html
renderTimelineDropzone timelineWindow day revision (instant, targetKey) =
    let creationEnd = defaultRosterEnd timelineWindow.timelineWindowCreationPolicy day.operationalDate instant 5
        label = (if isJust creationEnd then "Add shift at " else "Drop shift at ") <> timelineClockLabel instant
        creationAttrs = if isJust creationEnd
            then rosterShiftDialogLauncherAttrs (withTimelineOrientation timelineWindow.timelineWindowOrientation (rosterTimelineCreateDialogUrl day.operationalDate (Id day.rosterGroupId) revision targetKey))
            else []
     in [hsx|
        <button {...(SurfaceInteraction.frontendSurfaceDropzoneRefAttrs rosterDayTimelineDropzoneRef targetKey)}
                {...(Drag.dragPositionAttrs (timelineCoordinate timelineWindow.timelineWindowScale instant))}
                {...creationAttrs}
                type="button" tabindex="-1" class="roster-day-timeline-dropzone"
                style={timelineDropzoneStyle timelineWindow instant}
                data-roster-timeline-minute={tshow (timelineOperationalMinute day.operationalDate instant)}
                aria-label={label} title={label}>
            {forEach (maybeToList creationEnd) (renderTimelineCreationPreview timelineWindow instant)}
        </button>
    |]

renderTimelineCreationPreview :: TimelineWindow -> UTCTime -> UTCTime -> Html
renderTimelineCreationPreview window start end =
    [hsx|<span class="roster-day-timeline-create-preview" aria-hidden="true" style={previewStyle}>{timelineClockLabel start <> "–" <> timelineClockLabel end}</span>|]
  where
    scale = window.timelineWindowScale
    minute = timelineOffsetMinutes scale start
    cellStart = max 0 (minute - 2.5)
    cellExtent = min scale.scaleMinutes (minute + 2.5) - cellStart
    previewStyle = "--roster-create-offset:" <> tshow ((minute - cellStart) * 100 / cellExtent) <> "%;--roster-create-extent:"
        <> tshow ((timelineOffsetMinutes scale end - minute) * 100 / cellExtent) <> "%;"

renderTimelineShift :: TimelineWindow -> Bool -> Bool -> Map.Map UUID.UUID Staff -> Map.Map UUID.UUID ShiftType -> Day -> Int -> TimelineShift -> Html
renderTimelineShift timelineWindow editable canFillPublishedOpen staffById shiftTypeById anchorDate calendarRevision TimelineShift { timelineShiftSlot, timelineShiftStartMin, timelineShiftEndMin, timelineShiftTrack, timelineShiftTimeLabel, timelineShiftTimingInvalid } =
    let isOpen = rosterShiftIsOpen timelineShiftSlot
        canLaunch = editable || (isOpen && canFillPublishedOpen)
        staffLabel = if isOpen then "OPEN" else maybe "Unassigned" staffTimelineLabel (timelineShiftSlot.staffId >>= (`Map.lookup` staffById))
        shiftType = timelineShiftSlot.shiftTypeId >>= (`Map.lookup` shiftTypeById)
        shiftTypeLabel = maybe "Shift" (.name) shiftType
        detailLabel = staffLabel <> " · " <> timelineShiftTimeLabel <> " · " <> shiftTypeLabel
            <> (if timelineShiftTimingInvalid then " · Timing needs repair" else "")
        groupKey = "existing:" <> tshow timelineShiftSlot.id
        shiftClasses = classes [("roster-day-timeline-shift", True), ("is-roster-shift-open", isOpen), ("roster-shift-launcher", canLaunch), ("is-roster-shift-draggable", editable && not timelineShiftTimingInvalid), ("is-roster-shift-timing-invalid", timelineShiftTimingInvalid)]
        shiftContents = [hsx|
          <span class="roster-day-timeline-shift-caption">
            <span class="roster-day-timeline-shift-staff">{staffLabel}</span>
            <span class="roster-day-timeline-shift-time">{timelineShiftTimeLabel}{timingIssue}</span>
            <span class="roster-day-timeline-shift-role" title={shiftTypeLabel}>{openMarker}{shiftTypeLabel}</span>
          </span>
        |]
        shiftArticle = if canLaunch
            then [hsx|
                <button {...launcherAttrs} {...cardAttrs} type="button" class={shiftClasses}
                        data-roster-shift-colour={shiftTypeBadgeColourKey shiftType}
                        aria-label={detailLabel}>{shiftContents}</button>
            |]
            else [hsx|
                <article class={shiftClasses} tabindex="0"
                         data-roster-shift-colour={shiftTypeBadgeColourKey shiftType}
                         aria-label={detailLabel}>{shiftContents}</article>
            |]
        openMarker = when isOpen [hsx|<span class="roster-day-timeline-open-marker">◇ OPEN · </span>|]
        timingIssue = if timelineShiftTimingInvalid
            then [hsx|<span class="roster-shift-timing-issue text-warning" data-roster-timing-issue="true" title="Timing needs repair">!</span>|]
            else mempty
        launcherAttrs =
            if canLaunch
                then rosterShiftDialogLauncherAttrs (withTimelineOrientation timelineWindow.timelineWindowOrientation (withRosterTimelineContext anchorDate (rosterSlotDialogUrl (ExistingRosterSlotTarget timelineShiftSlot.id anchorDate calendarRevision))))
                else []
        card = [hsx|
            <div class="roster-day-timeline-shift-position"
                 style={timelineShiftStyle timelineWindow timelineShiftStartMin timelineShiftEndMin timelineShiftTrack}>
                {shiftArticle}
            </div>
            <div class="roster-day-timeline-shift-details" aria-hidden="true">{detailLabel}</div>
        |]
        intervalAttrs = case decodeRosterShiftTiming timelineShiftSlot of
            Left _ -> []
            Right timing ->
                let scale = timelineWindow.timelineWindowScale
                    boundaries = rosterShiftTimingBoundaries timing
                 in Drag.dragIntervalAttrs
                    (timelineCoordinate scale scale.scaleEndsAt)
                    (max 1 (round (authoritativeElapsedSeconds boundaries * 1000000)))
                    [(timelineCoordinate scale instant, label) | (instant, label) <- timelineMoveChoices scale anchorDate boundaries]
        staffDropAttrs = if canLaunch && not timelineShiftTimingInvalid
            then SurfaceInteraction.frontendSurfaceDropzoneRefAttrs rosterExistingShiftDropzoneRef groupKey
            else []
        cardAttrs = staffDropAttrs <> if editable && not timelineShiftTimingInvalid
            then SurfaceInteraction.frontendSurfaceSourceRefAttrs rosterDayTimelineSourceRef groupKey
                <> SurfaceInteraction.frontendSurfaceLongPressDragAttrs
                <> intervalAttrs
                <> SurfaceLinkedHighlight.frontendSurfaceLinkedHighlightSourceAttrs rosterShiftGroupLinkedHighlight groupKey
                <> SurfaceLinkedHighlight.frontendSurfaceLinkedHighlightMemberAttrs rosterShiftGroupLinkedHighlight groupKey Nothing
            else []
     in card

staffTimelineLabel :: Staff -> Text
staffTimelineLabel staff =
    fromMaybe (staff.firstName <> " " <> staff.lastName) staff.preferredName

timelineShiftFromSlot :: TimelineWindow -> Map.Map UUID.UUID (Either RosterShiftIntegrityError ValidatedRosterShiftTiming) -> RosterSlot -> TimelineShift
timelineShiftFromSlot timelineWindow timingBySlotId slot =
    case Map.lookup (unpackId slot.id) timingBySlotId of
        Just (Right timing) ->
            let boundaries = rosterShiftTimingBoundaries timing
                start = authoritativeStartsAt boundaries
                end = authoritativeEndsAt boundaries
                startMin = timelineOffsetMinutes timelineWindow.timelineWindowScale start
                endMin = timelineOffsetMinutes timelineWindow.timelineWindowScale end
             in TimelineShift
                    { timelineShiftSlot = slot
                    , timelineShiftStartMin = startMin
                    , timelineShiftEndMin = endMin
                    , timelineShiftTrack = 0
                    , timelineShiftTimeLabel = timelineClockLabel start <> "–" <> timelineClockLabel end
                    , timelineShiftTimingInvalid = False
                    }
        _ ->
            let startMin = 0
             in TimelineShift
                    { timelineShiftSlot = slot
                    , timelineShiftStartMin = startMin
                    , timelineShiftEndMin = startMin + 15
                    , timelineShiftTrack = 0
                    , timelineShiftTimeLabel = "Timing unavailable"
                    , timelineShiftTimingInvalid = True
                    }

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

timelineDropzones :: TimelineWindow -> RosterDay -> RosterLane -> [(UTCTime, Text)]
timelineDropzones timelineWindow rosterDay slotDefinition =
    [ (instant, "instant:" <> tshow rosterDay.id <> ":" <> tshow slotDefinition.id <> ":" <> tshow (floor (utcTimeToPOSIXSeconds instant) :: Integer))
    | instant <- timelineCreateInstants timelineWindow.timelineWindowScale rosterDay.operationalDate
    ]

timelineHourTicks :: TimelineWindow -> [Int]
timelineHourTicks TimelineWindow { timelineWindowEndMinute } =
    [0, 60 .. timelineWindowEndMinute]

timelineLeftStyle :: TimelineWindow -> Int -> Text
timelineLeftStyle timelineWindow minute =
    "--roster-timeline-position:" <> timelinePercent timelineWindow (fromIntegral minute) <> "%;"

timelineDropzoneStyle :: TimelineWindow -> UTCTime -> Text
timelineDropzoneStyle timelineWindow instant =
    "--roster-timeline-position:" <> timelinePercent timelineWindow start <> "%;--roster-timeline-extent:" <> timelinePercent timelineWindow (end - start) <> "%;"
  where
    scale = timelineWindow.timelineWindowScale
    minuteOffset = timelineOffsetMinutes scale instant
    start = max 0 (minuteOffset - 2.5)
    end = min scale.scaleMinutes (minuteOffset + 2.5)

timelineShiftStyle :: TimelineWindow -> Double -> Double -> Int -> Text
timelineShiftStyle timelineWindow startMin endMin track =
    let windowStart = 0
        windowEnd = timelineWindow.timelineWindowScale.scaleMinutes
        clampedStart = max windowStart (min windowEnd startMin)
        clampedEnd = max clampedStart (min windowEnd endMin)
     in "--roster-timeline-position:"
            <> timelinePercent timelineWindow (clampedStart - windowStart)
            <> "%;--roster-timeline-extent:"
            <> timelinePercent timelineWindow (clampedEnd - clampedStart)
            <> "%;--roster-timeline-track:"
            <> tshow track
            <> ";"

timelinePercent :: TimelineWindow -> Double -> Text
timelinePercent TimelineWindow { timelineWindowScale } minutes =
    tshow (minutes * 100 / timelineWindowScale.scaleMinutes)
