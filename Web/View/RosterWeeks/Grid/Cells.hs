{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.Grid.Cells
    ( ExistingSlotDisplay (..)
    , ReadOnlyExistingSlotCell (..)
    , RosterSlotCellTarget (..)
    , rosterShiftDialogLauncherAttrs
    , findShiftTypeForSlot
    , renderBlockCells
    , renderDayColumnCreateCard
    , renderDayColumnRosterSlotCard
    , renderDayColumnSlotCard
    , renderShiftTypeOptionLabel
    , rosterGridColumnSpanStyle
    , slotColumnCount
    , rosterSlotDialogUrl
    , shiftTypeBadgeColourKey
    ) where

import Application.Helper.Controller (hasRole)
import Application.Helper.FrontendContract.AppShell (OpenRosterShiftDialog)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             appShellActionAttrs,
                                                             defaultAppShellActionRoute)
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.LinkedHighlight as SurfaceLinkedHighlight
import Application.Helper.FrontendContract.Surface.Roster.ImageExport (rosterImageExportCellAttrs,
                                                                       rosterImageExportEllipsizedCellAttrs)
import Application.Helper.Profiling (profileRenderCounter)
import Application.Helper.ShiftTypeColours (shiftTypeColourKeyCssValue,
                                            shiftTypeColourPaletteKeys)
import Application.Helper.TimeRules (rosterOperationalFinalSelectableTimeText,
                                     rosterOperationalStartTimeText)
import Application.Helper.View (staffDisplayName)
import Application.RosterShiftAssignment (rosterShiftIsOpen)
import Application.VenueTime.Model (rosterShiftTimingEndTime,
                                    rosterShiftTimingStartTime)
import Data.Coerce (coerce)
import Data.List (find)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (TimeOfDay)
import Web.RosterWeeks.DateRange (RosterWindowLane, laneForOperationalDate)
import Web.RosterWeeks.Dom
import Web.RosterWeeks.FrontendSurface (rosterDragDropzoneRef,
                                        rosterDragSourceRef,
                                        rosterExistingShiftDropzoneRef,
                                        rosterShiftGroupLinkedHighlight,
                                        rosterStaffCreateDropzoneRef,
                                        rosterStaffLinkedHighlight)
import Web.RosterWeeks.Paths (rosterExistingSlotDialogUrl,
                              rosterNewSlotDialogUrl)
import Web.RosterWeeks.Types
import Web.View.Prelude

data RosterSlotCellTarget
    = ExistingRosterSlotTarget (Id RosterSlot) Day Int
    | NewRosterSlotTarget (Id RosterDay) (Id RosterLane) (Id RosterGroup) Day Int Int

data ExistingSlotDisplay = ExistingSlotDisplay
    { displayStartLabel         :: Text
    , displayEndLabel           :: Text
    , displayTimeLabel          :: Text
    , displayStaffLabel         :: Text
    , displayShiftTypeLabel     :: Text
    , displayShiftTypeColourKey :: Text
    , displayPrimaryConflict    :: Maybe RosterConflict
    , displayMissingStartTime   :: Bool
    , displayMissingEndTime     :: Bool
    , displayMissingShiftType   :: Bool
    , displayHasShiftType       :: Bool
    , displayIsOpen             :: Bool
    , displayTimingInvalid      :: Bool
    }

data ReadOnlyExistingSlotCell = ReadOnlyExistingSlotCell
    { readOnlyCellClasses           :: Text
    , readOnlyCellColourKey         :: Text
    , readOnlyCellContent           :: Html
    , readOnlyCellConflictAttrs     :: Maybe Text
    , readOnlyCellExportText        :: Text
    , readOnlyCellExportEndEllipsis :: Bool
    }
renderBlockCells :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> Bool -> Bool -> RosterDay -> Int -> Int -> [RosterSlot] -> RosterRenderIndexes -> (Int, RosterWindowLane) -> Html
renderBlockCells isEditable assignmentFilters staffMembers shiftTypes endTimesEnabled publishAttempted rosterDay calendarRevision rowIndex _rowSlots renderIndexes (blockIndex, slotName) =
    mconcat
        [ profileRenderCounter "render.roster.slot_block" 1
        , if isEditable
            then renderEditableBlockCells assignmentFilters staffMembers shiftTypes endTimesEnabled publishAttempted rosterDay calendarRevision rowIndex renderIndexes blockIndex slotName
            else renderReadOnlyBlockCells shiftTypes endTimesEnabled publishAttempted rosterDay calendarRevision rowIndex renderIndexes blockIndex slotName
        ]

renderEditableBlockCells :: (?context :: ControllerContext) => RosterAssignmentFilters -> [Staff] -> [ShiftType] -> Bool -> Bool -> RosterDay -> Int -> Int -> RosterRenderIndexes -> Int -> RosterWindowLane -> Html
renderEditableBlockCells assignmentFilters staffMembers shiftTypes endTimesEnabled publishAttempted rosterDay calendarRevision rowIndex renderIndexes blockIndex slotName
    | rosterDay.isClosed = renderClosedBlockCells endTimesEnabled blockIndex
    | otherwise =
        maybe
            (renderCreateBlockCells assignmentFilters staffMembers shiftTypes endTimesEnabled rosterDay calendarRevision rowIndex blockIndex slotName)
            (renderEditableExistingSlotBlockCells assignmentFilters staffMembers shiftTypes endTimesEnabled publishAttempted renderIndexes rosterDay.operationalDate calendarRevision blockIndex)
            (lookupRosterSlotForBlock rosterDay rowIndex slotName renderIndexes)

renderReadOnlyBlockCells :: (?context :: ControllerContext) => [ShiftType] -> Bool -> Bool -> RosterDay -> Int -> Int -> RosterRenderIndexes -> Int -> RosterWindowLane -> Html
renderReadOnlyBlockCells shiftTypes endTimesEnabled publishAttempted rosterDay calendarRevision rowIndex renderIndexes blockIndex slotName
    | rosterDay.isClosed = renderClosedBlockCells endTimesEnabled blockIndex
    | otherwise =
        maybe
            (renderEmptyBlockCells endTimesEnabled blockIndex)
            renderExisting
            (lookupRosterSlotForBlock rosterDay rowIndex slotName renderIndexes)
  where
    renderExisting slot
        | hasRole Manager && rosterShiftIsOpen slot = renderLiveOpenExistingSlotBlockCells shiftTypes endTimesEnabled publishAttempted renderIndexes rosterDay.operationalDate calendarRevision blockIndex slot
        | otherwise = renderReadOnlyExistingSlotBlockCells shiftTypes endTimesEnabled publishAttempted renderIndexes blockIndex slot

lookupRosterSlotForBlock :: RosterDay -> Int -> RosterWindowLane -> RosterRenderIndexes -> Maybe RosterSlot
lookupRosterSlotForBlock rosterDay rowIndex windowLane renderIndexes = do
    lane <- laneForOperationalDate rosterDay.operationalDate windowLane
    Map.lookup (unpackId rosterDay.id, rowIndex, unpackId lane.id) renderIndexes.rosterSlotByDayRowSlotName


slotColumnCount :: Bool -> Int
slotColumnCount True  = 4
slotColumnCount False = 3

rosterGridColumnSpanStyle :: Int -> Text
rosterGridColumnSpanStyle gridSpan =
    "--roster-grid-column-span: " <> tshow gridSpan <> ";"

renderEditableExistingSlotBlockCells :: (?context :: ControllerContext) => RosterAssignmentFilters -> [Staff] -> [ShiftType] -> Bool -> Bool -> RosterRenderIndexes -> Day -> Int -> Int -> RosterSlot -> Html
renderEditableExistingSlotBlockCells _assignmentFilters _staffMembers shiftTypes endTimesEnabled publishAttempted renderIndexes anchorDate calendarRevision blockIndex slot =
    let display = buildExistingSlotDisplay shiftTypes publishAttempted renderIndexes slot
        target = ExistingRosterSlotTarget slot.id anchorDate calendarRevision
        groupKey = rosterShiftGroupKey target
        cellCount = if endTimesEnabled then 4 else 3
     in mconcat
        [ profileExistingSlotCounters display endTimesEnabled cellCount
        , profileEditableLauncherCounters 1 (isJust slot.staffId)
        , if endTimesEnabled
            then renderEditableEndTimeSlotCells display target groupKey blockIndex slot
            else renderEditableNoEndTimeSlotCells display target groupKey blockIndex slot
        ]

renderEditableEndTimeSlotCells :: (?context :: ControllerContext) => ExistingSlotDisplay -> RosterSlotCellTarget -> Text -> Int -> RosterSlot -> Html
renderEditableEndTimeSlotCells display target groupKey blockIndex slot =
    renderEditableShiftUnit target groupKey slot display.displayTimingInvalid 4
        [ readOnlyTimeCell (classes [("slot-time-cell slot-start-time-cell", True), ("roster-block-start", blockIndex > 0), ("is-roster-shift-publish-required", display.displayMissingStartTime)]) display.displayShiftTypeColourKey display.displayStartLabel
        , readOnlyTimeCell (classes [("slot-time-cell slot-end-time-cell", True), ("is-roster-shift-publish-required", display.displayMissingEndTime)]) display.displayShiftTypeColourKey display.displayEndLabel
        , readOnlyStaffCell display
        , readOnlyShiftTypeCell display
        ]

renderEditableNoEndTimeSlotCells :: (?context :: ControllerContext) => ExistingSlotDisplay -> RosterSlotCellTarget -> Text -> Int -> RosterSlot -> Html
renderEditableNoEndTimeSlotCells display target groupKey blockIndex slot =
    renderEditableShiftUnit target groupKey slot display.displayTimingInvalid 3
        [ readOnlyTimeCell (classes [("slot-time-cell", True), ("roster-block-start", blockIndex > 0), ("is-roster-shift-publish-required", display.displayMissingStartTime)]) display.displayShiftTypeColourKey display.displayTimeLabel
        , readOnlyStaffCell display
        , readOnlyShiftTypeCell display
        ]

-- Editable row-grid shifts are one modal launcher per shift, not one launcher per
-- visual cell. Inner cells are visual-only and align to the parent grid via CSS
-- subgrid, preserving the Start/End/Staff/Role layout without duplicating HTMX
-- attributes across every cell.
renderEditableShiftUnit :: (?context :: ControllerContext) => RosterSlotCellTarget -> Text -> RosterSlot -> Bool -> Int -> [ReadOnlyExistingSlotCell] -> Html
renderEditableShiftUnit target groupKey slot timingInvalid gridSpan cells =
    launcher
  where
    attributes = rosterShiftGroupHighlightAttrs groupKey
        <> rosterStaffHighlightAttrs slot.staffId groupKey
        <> rosterShiftDialogLauncherAttrs (rosterSlotDialogUrl target)
        <> if timingInvalid then [] else
            SurfaceInteraction.frontendSurfaceSourceRefAttrs rosterDragSourceRef groupKey
                <> SurfaceInteraction.frontendSurfaceDropzoneRefAttrs rosterExistingShiftDropzoneRef groupKey
    launcher = [hsx|
                    <div {...attributes} role="gridcell"
                         class={classes [("roster-shift-unit roster-shift-launcher", True), ("is-roster-shift-open", rosterShiftIsOpen slot)]}
                         style={rosterGridColumnSpanStyle gridSpan}
                         data-roster-shift-colour={shiftUnitColour cells}
                         data-roster-shift-launcher="true"
                         tabindex="0">
                        {forEach cells renderEditableShiftUnitCell}
                    </div>
                |]

shiftUnitColour :: [ReadOnlyExistingSlotCell] -> Text
shiftUnitColour []       = ""
shiftUnitColour (cell:_) = cell.readOnlyCellColourKey

renderEditableShiftUnitCell :: ReadOnlyExistingSlotCell -> Html
renderEditableShiftUnitCell cell =
    renderExistingSlotCell [] Nothing ("roster-shift-unit-cell " <> cell.readOnlyCellClasses) cell

renderExistingSlotCell :: [(Text, Text)] -> Maybe Text -> Text -> ReadOnlyExistingSlotCell -> Html
renderExistingSlotCell attributes maybeRole cellClasses ReadOnlyExistingSlotCell { readOnlyCellColourKey, readOnlyCellContent, readOnlyCellConflictAttrs, readOnlyCellExportText, readOnlyCellExportEndEllipsis } = [hsx|
    <div {...attributes} role={maybeRole}
         class={cellClasses}
         title={readOnlyCellConflictAttrs}
         data-roster-shift-colour={readOnlyCellColourKey}
         {...exportCellAttrs}>
        {readOnlyCellContent}
    </div>
|]
  where
    exportCellAttrs =
        if readOnlyCellExportEndEllipsis
            then rosterImageExportEllipsizedCellAttrs readOnlyCellExportText
            else rosterImageExportCellAttrs readOnlyCellExportText

renderLiveOpenExistingSlotBlockCells :: (?context :: ControllerContext) => [ShiftType] -> Bool -> Bool -> RosterRenderIndexes -> Day -> Int -> Int -> RosterSlot -> Html
renderLiveOpenExistingSlotBlockCells shiftTypes endTimesEnabled publishAttempted renderIndexes anchorDate calendarRevision blockIndex slot =
    let display = buildExistingSlotDisplay shiftTypes publishAttempted renderIndexes slot
        target = ExistingRosterSlotTarget slot.id anchorDate calendarRevision
        groupKey = rosterShiftGroupKey target
        cells = readOnlyExistingSlotCells display endTimesEnabled blockIndex
        gridSpan = length cells
     in [hsx|
            <div {...(rosterShiftDialogLauncherAttrs (rosterSlotDialogUrl target))} role="gridcell"
                 class="roster-shift-unit roster-shift-launcher is-roster-shift-open"
                 style={rosterGridColumnSpanStyle gridSpan}
                 data-roster-shift-colour={display.displayShiftTypeColourKey}
                 data-roster-shift-launcher="true"
                 tabindex="0"
                 aria-label="Fill Open shift">
                {forEach cells renderEditableShiftUnitCell}
            </div>
        |]

renderReadOnlyExistingSlotBlockCells :: (?context :: ControllerContext) => [ShiftType] -> Bool -> Bool -> RosterRenderIndexes -> Int -> RosterSlot -> Html
renderReadOnlyExistingSlotBlockCells shiftTypes endTimesEnabled publishAttempted renderIndexes blockIndex slot =
    let display = buildExistingSlotDisplay shiftTypes publishAttempted renderIndexes slot
        cells = readOnlyExistingSlotCells display endTimesEnabled blockIndex
        cellCount = length cells
        groupKey = "existing:" <> tshow slot.id
        renderHighlightedCell cell =
            renderReadOnlyExistingSlotCell (rosterStaffHighlightAttrs slot.staffId groupKey) cell
     in mconcat
        [ profileExistingSlotCounters display endTimesEnabled cellCount
        , profileRenderCounter "render.roster.readonly_cell" cellCount
        , profileRenderCounter "render.roster.readonly_slim_cell" cellCount
        , forEach cells renderHighlightedCell
        ]

buildExistingSlotDisplay :: [ShiftType] -> Bool -> RosterRenderIndexes -> RosterSlot -> ExistingSlotDisplay
buildExistingSlotDisplay shiftTypes publishAttempted renderIndexes slot =
    let (startTime, endTime, timingInvalid) = rosterTimingDisplay renderIndexes slot
        currentStartTime = optionalTimeOfDayToStorageValue startTime
        currentEndTime = optionalTimeOfDayToStorageValue endTime
        currentShiftType = findShiftTypeForSlot shiftTypes slot.shiftTypeId
     in ExistingSlotDisplay
        { displayStartLabel = renderTimePickerDisplayLabel "Start" currentStartTime
        , displayEndLabel = renderTimePickerDisplayLabel "End" currentEndTime
        , displayTimeLabel = renderTimePickerDisplayLabel "Time" currentStartTime
        , displayStaffLabel = if rosterShiftIsOpen slot then "OPEN" else fromMaybe "" (renderAssignedStaffLabel slot.staffId renderIndexes)
        , displayShiftTypeLabel = maybe "" renderShiftTypeOptionLabel currentShiftType
        , displayShiftTypeColourKey = shiftTypeBadgeColourKey currentShiftType
        , displayPrimaryConflict = primaryConflict (lookupConflicts (get #id slot) renderIndexes)
        , displayMissingStartTime = publishAttempted && isJust slot.staffId && isNothing slot.startsAt
        , displayMissingEndTime = publishAttempted && isJust slot.staffId && isNothing slot.endsAt
        , displayMissingShiftType = publishAttempted && isJust slot.staffId && isNothing slot.shiftTypeId
        , displayHasShiftType = isJust slot.shiftTypeId
        , displayIsOpen = rosterShiftIsOpen slot
        , displayTimingInvalid = timingInvalid
        }

profileExistingSlotCounters :: ExistingSlotDisplay -> Bool -> Int -> Html
profileExistingSlotCounters display endTimesEnabled cellCount = mconcat
    [ profileRenderCounter "render.roster.existing_slot" 1
    , profileRenderCounter (if endTimesEnabled then "render.roster.existing_slot.end_times_enabled" else "render.roster.existing_slot.no_end_times") 1
    , profileRenderCounter "render.roster.grid_cell" cellCount
    , profileRenderCounter "render.roster.time_label" (if endTimesEnabled then 2 else 1)
    , profileRenderCounter "render.roster.staff_label" 1
    , profileRenderCounter "render.roster.shift_type_label" 1
    , profileRenderCounter "render.roster.conflict_cell" (if isJust display.displayPrimaryConflict then 1 else 0)
    , profileRenderCounter "render.roster.conflict_attr" (if isJust display.displayPrimaryConflict then 1 else 0)
    , profileRenderCounter "render.roster.publish_required_marker" (sum (map fromEnum [display.displayMissingStartTime, display.displayMissingEndTime, display.displayMissingShiftType]))
    ]

profileEditableLauncherCounters :: Int -> Bool -> Html
profileEditableLauncherCounters launcherCount hasStaffHighlight = mconcat
    [ profileRenderCounter "render.roster.shift_launcher" launcherCount
    , profileRenderCounter "render.roster.launcher_attr_bundle" launcherCount
    , profileRenderCounter "render.roster.launcher_hx_attr" (launcherCount * 4)
    , profileRenderCounter "render.roster.launcher_data_attr" (launcherCount * dataAttributeCount)
    ]
  where
    dataAttributeCount = 4 + if hasStaffHighlight then 2 else 0

readOnlyExistingSlotCells :: ExistingSlotDisplay -> Bool -> Int -> [ReadOnlyExistingSlotCell]
readOnlyExistingSlotCells display True blockIndex =
    [ readOnlyTimeCell (classes [("slot-time-cell slot-start-time-cell", True), ("roster-block-start", blockIndex > 0), ("is-roster-shift-publish-required", display.displayMissingStartTime)]) display.displayShiftTypeColourKey display.displayStartLabel
    , readOnlyTimeCell (classes [("slot-time-cell slot-end-time-cell", True), ("is-roster-shift-publish-required", display.displayMissingEndTime)]) display.displayShiftTypeColourKey display.displayEndLabel
    , readOnlyStaffCell display
    , readOnlyShiftTypeCell display
    ]
readOnlyExistingSlotCells display False blockIndex =
    [ readOnlyTimeCell (classes [("slot-time-cell", True), ("roster-block-start", blockIndex > 0), ("is-roster-shift-publish-required", display.displayMissingStartTime)]) display.displayShiftTypeColourKey display.displayTimeLabel
    , readOnlyStaffCell display
    , readOnlyShiftTypeCell display
    ]

readOnlyTimeCell :: Text -> Text -> Text -> ReadOnlyExistingSlotCell
readOnlyTimeCell cellClasses colourKey label = ReadOnlyExistingSlotCell
    { readOnlyCellClasses = cellClasses
    , readOnlyCellColourKey = colourKey
    , readOnlyCellContent = renderReadOnlyCell label
    , readOnlyCellConflictAttrs = Nothing
    , readOnlyCellExportText = label
    , readOnlyCellExportEndEllipsis = False
    }

readOnlyStaffCell :: ExistingSlotDisplay -> ReadOnlyExistingSlotCell
readOnlyStaffCell display = ReadOnlyExistingSlotCell
    { readOnlyCellClasses = classes [("slot-staff-cell position-relative", True), (renderConflictClass display.displayPrimaryConflict, True), ("is-roster-shift-open", display.displayIsOpen), ("is-roster-shift-timing-invalid", display.displayTimingInvalid)]
    , readOnlyCellColourKey = display.displayShiftTypeColourKey
    , readOnlyCellContent = renderReadOnlyStaffCell display.displayStaffLabel display.displayPrimaryConflict <> renderRosterTimingIssue display.displayTimingInvalid
    , readOnlyCellConflictAttrs = Just (renderConflictMessage display.displayPrimaryConflict)
    , readOnlyCellExportText = display.displayStaffLabel
    , readOnlyCellExportEndEllipsis = False
    }

readOnlyShiftTypeCell :: ExistingSlotDisplay -> ReadOnlyExistingSlotCell
readOnlyShiftTypeCell display = ReadOnlyExistingSlotCell
    { readOnlyCellClasses = classes [("slot-shift-type-cell roster-block-end", True), ("is-shift-type-empty", not display.displayHasShiftType), ("is-shift-type-required", display.displayMissingShiftType)]
    , readOnlyCellColourKey = display.displayShiftTypeColourKey
    , readOnlyCellContent = renderRosterShiftTypeLabel display.displayShiftTypeLabel
    , readOnlyCellConflictAttrs = Just display.displayShiftTypeLabel
    , readOnlyCellExportText = display.displayShiftTypeLabel
    , readOnlyCellExportEndEllipsis = True
    }

renderReadOnlyExistingSlotCell :: [(Text, Text)] -> ReadOnlyExistingSlotCell -> Html
renderReadOnlyExistingSlotCell attributes cell =
    renderExistingSlotCell attributes (Just "gridcell") cell.readOnlyCellClasses cell
renderDayColumnRosterSlotCard :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> RosterSlot -> Html
renderDayColumnRosterSlotCard RosterDayRenderModel { dayIsEditable, dayAssignmentFilters, dayStaffMembers, dayShiftTypes, dayCalendarRevision, dayRenderIndexes, dayRosterEndTimesEnabled, dayPublishAttempted } rosterDay slot =
    let (startTime, endTime, timingInvalid) = rosterTimingDisplay dayRenderIndexes slot
     in renderDayColumnSlotCardContent dayIsEditable dayAssignmentFilters dayStaffMembers dayShiftTypes dayRosterEndTimesEnabled dayPublishAttempted dayRenderIndexes (ExistingRosterSlotTarget slot.id rosterDay.operationalDate dayCalendarRevision) (rosterShiftIsOpen slot) slot.staffId startTime endTime slot.shiftTypeId (primaryConflict (lookupConflicts (get #id slot) dayRenderIndexes)) timingInvalid

renderDayColumnCreateCard :: (?context :: ControllerContext) => RosterDayRenderModel -> RosterDay -> Maybe RosterSlotCellTarget -> Html
renderDayColumnCreateCard RosterDayRenderModel { dayIsEditable } rosterDay maybeTarget
    | not dayIsEditable || rosterDay.isClosed = mempty
    | otherwise = maybe mempty renderDayColumnCreateLauncherCard maybeTarget

renderDayColumnCreateLauncherCard :: (?context :: ControllerContext) => RosterSlotCellTarget -> Html
renderDayColumnCreateLauncherCard target =
    let groupKey = rosterShiftGroupKey target
        attributes = SurfaceInteraction.frontendSurfaceDropzoneRefAttrs rosterStaffCreateDropzoneRef groupKey
            <> rosterShiftGroupHighlightAttrs groupKey
            <> rosterShiftDialogLauncherAttrs (rosterSlotDialogUrl target)
     in [hsx|
            <article {...attributes} class="roster-shift-card roster-shift-card-empty roster-shift-card-create roster-shift-launcher roster-shift-create-plus-card"
                     data-roster-shift-launcher={("true" :: Text)}
                     tabindex="0"
                     aria-label="Add shift">
                <span class="roster-shift-create-plus" aria-hidden="true">+</span>
                <span class="visually-hidden">Add shift</span>
            </article>
        |]

renderDayColumnSlotCard :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> Bool -> Bool -> RosterDay -> Int -> Int -> [RosterSlot] -> RosterRenderIndexes -> (Int, RosterWindowLane) -> Html
renderDayColumnSlotCard isEditable assignmentFilters staffMembers shiftTypes endTimesEnabled publishAttempted rosterDay calendarRevision rowIndex rowSlots renderIndexes (_, windowLane)
    | rosterDay.isClosed = [hsx|<div class="roster-shift-card roster-shift-card-closed"><span>Closed</span></div>|]
    | otherwise =
        case laneForOperationalDate rosterDay.operationalDate windowLane >>= (\lane -> Map.lookup (unpackId rosterDay.id, rowIndex, unpackId lane.id) renderIndexes.rosterSlotByDayRowSlotName) of
            Just slot ->
                let (startTime, endTime, timingInvalid) = rosterTimingDisplay renderIndexes slot
                 in renderDayColumnSlotCardContent isEditable assignmentFilters staffMembers shiftTypes endTimesEnabled publishAttempted renderIndexes (ExistingRosterSlotTarget slot.id rosterDay.operationalDate calendarRevision) (rosterShiftIsOpen slot) slot.staffId startTime endTime slot.shiftTypeId (primaryConflict (lookupConflicts (get #id slot) renderIndexes)) timingInvalid
            Nothing -> [hsx|<div class="roster-shift-card roster-shift-card-empty"></div>|]

renderDayColumnSlotCardContent :: (?context :: ControllerContext) => Bool -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> Bool -> Bool -> RosterRenderIndexes -> RosterSlotCellTarget -> Bool -> Maybe UUID -> Maybe TimeOfDay -> Maybe TimeOfDay -> Maybe UUID -> Maybe RosterConflict -> Bool -> Html
renderDayColumnSlotCardContent isEditable _assignmentFilters _staffMembers shiftTypes endTimesEnabled publishAttempted renderIndexes target isOpen staffId startTime endTime shiftTypeId currentPrimaryConflict timingInvalid =
    let currentStartTime = optionalTimeOfDayToStorageValue startTime
        currentEndTime = optionalTimeOfDayToStorageValue endTime
        currentStaffLabel = if isOpen then "OPEN" else fromMaybe "" (renderAssignedStaffLabel staffId renderIndexes)
        currentShiftType = findShiftTypeForSlot shiftTypes shiftTypeId
        currentShiftTypeColourKey = shiftTypeBadgeColourKey currentShiftType
        missingStartTime = publishAttempted && isJust staffId && isNothing startTime
        missingEndTime = publishAttempted && isJust staffId && isNothing endTime
        missingShiftType = publishAttempted && isJust staffId && isNothing shiftTypeId
        groupKey = rosterShiftGroupKey target
        canLaunch = isEditable || (isOpen && hasRole Manager)
        endTimeField =
            if endTimesEnabled
                then [hsx|
                    <div class={classes [("roster-shift-card-field roster-shift-card-time", True), ("is-roster-shift-publish-required", missingEndTime)]}>
                        {renderReadOnlyCell (renderTimePickerDisplayLabel "End" currentEndTime)}
                    </div>
                |]
                else mempty
        card = [hsx|
            <article {...attributes} class={classes [("roster-shift-card", True), ("is-roster-shift-open", isOpen), ("roster-shift-card-create", not (targetHasExistingSlot target)), ("roster-shift-launcher", canLaunch), ("is-roster-shift-timing-invalid", timingInvalid)]}
                     data-roster-shift-colour={currentShiftTypeColourKey}
                     data-roster-shift-launcher={if canLaunch then ("true" :: Text) else ""}
                     tabindex={if canLaunch then ("0" :: Text) else ""}
                     title={renderConflictMessage currentPrimaryConflict}>
                <div class={classes [("roster-shift-card-fields", True), ("has-end-times", endTimesEnabled)]}>
                    <div class={classes [("roster-shift-card-field roster-shift-card-time", True), ("is-roster-shift-publish-required", missingStartTime)]}>
                        {renderReadOnlyCell (renderTimePickerDisplayLabel "Start" currentStartTime)}
                    </div>
                    {endTimeField}
                    <div class={classes [("roster-shift-card-field roster-shift-card-staff", True), (renderConflictClass currentPrimaryConflict, True)]}>
                        {if targetHasExistingSlot target then renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict <> renderRosterTimingIssue timingInvalid else renderReadOnlyCell "Add shift"}
                    </div>
                    <div class={classes [("roster-shift-card-field roster-shift-card-code", True), ("is-shift-type-required", missingShiftType)]}
                         data-roster-shift-colour={currentShiftTypeColourKey}>
                        {renderReadOnlyDayColumnShiftTypeBadge staffId currentShiftType missingShiftType}
                    </div>
                </div>
            </article>
        |]
        attributes = rosterStaffHighlightAttrs staffId groupKey
            <> (if canLaunch then rosterShiftDialogLauncherAttrs (rosterSlotDialogUrl target) else [])
            <> (if isEditable then rosterShiftGroupHighlightAttrs groupKey else [])
            <> (if isEditable && targetHasExistingSlot target && not timingInvalid
                then SurfaceInteraction.frontendSurfaceSourceRefAttrs rosterDragSourceRef groupKey
                    <> SurfaceInteraction.frontendSurfaceDropzoneRefAttrs rosterExistingShiftDropzoneRef groupKey
                else [])
     in card

targetHasExistingSlot :: RosterSlotCellTarget -> Bool
targetHasExistingSlot ExistingRosterSlotTarget {} = True
targetHasExistingSlot NewRosterSlotTarget {}      = False

rosterShiftDialogLauncherAttrs :: Text -> [(Text, Text)]
rosterShiftDialogLauncherAttrs actionUrl =
    appShellActionAttrs
        (appShellActionByMarker @OpenRosterShiftDialog)
        (defaultAppShellActionRoute (actionUrl))

renderEmptyBlockCells :: (?context :: ControllerContext) => Bool -> Int -> Html
renderEmptyBlockCells =
    renderBlankBlockCells "render.roster.empty_block" "slot-empty-cell"

-- Create slots use the same single-launcher shape as existing editable shifts,
-- but keep unmerged visual empty cells until hover/focus/highlight reveals the
-- centered merged plus overlay.
renderCreateBlockCells :: (?context :: ControllerContext) => RosterAssignmentFilters -> [Staff] -> [ShiftType] -> Bool -> RosterDay -> Int -> Int -> Int -> RosterWindowLane -> Html
renderCreateBlockCells _assignmentFilters _staffMembers _shiftTypes endTimesEnabled rosterDay calendarRevision rowIndex blockIndex windowLane =
    case laneForOperationalDate rosterDay.operationalDate windowLane of
        Nothing   -> renderEmptyBlockCells endTimesEnabled blockIndex
        Just lane -> renderForLane lane
  where
    renderForLane lane =
      let target = NewRosterSlotTarget rosterDay.id lane.id (Id rosterDay.rosterGroupId) rosterDay.operationalDate calendarRevision rowIndex
          groupKey = rosterShiftGroupKey target
          gridSpan = slotColumnCount endTimesEnabled
          visualCellClasses = createShiftUnitVisualCellClasses endTimesEnabled blockIndex
          visualCellCount = length visualCellClasses
       in mconcat
        [ profileCreateSlotCounters endTimesEnabled visualCellCount
        , renderCreateShiftUnit target groupKey visualCellClasses gridSpan
        ]

profileCreateSlotCounters :: Bool -> Int -> Html
profileCreateSlotCounters endTimesEnabled cellCount = mconcat
    [ profileRenderCounter "render.roster.create_slot" 1
    , profileRenderCounter (if endTimesEnabled then "render.roster.create_slot.end_times_enabled" else "render.roster.create_slot.no_end_times") 1
    , profileRenderCounter "render.roster.grid_cell" cellCount
    , profileRenderCounter "render.roster.readonly_cell" cellCount
    , profileRenderCounter "render.roster.shift_launcher" 1
    , profileRenderCounter "render.roster.launcher_attr_bundle" 1
    , profileRenderCounter "render.roster.launcher_hx_attr" 4
    , profileRenderCounter "render.roster.launcher_data_attr" 3
    ]

createShiftUnitVisualCellClasses :: Bool -> Int -> [Text]
createShiftUnitVisualCellClasses True blockIndex =
    [ classes [("roster-shift-unit-cell slot-empty-cell", True), ("roster-block-start", blockIndex > 0)]
    , "roster-shift-unit-cell slot-empty-cell"
    , "roster-shift-unit-cell slot-empty-cell"
    , "roster-shift-unit-cell slot-empty-cell roster-block-end"
    ]
createShiftUnitVisualCellClasses False blockIndex =
    [ classes [("roster-shift-unit-cell slot-empty-cell slot-time-cell", True), ("roster-block-start", blockIndex > 0)]
    , "roster-shift-unit-cell slot-empty-cell slot-staff-cell position-relative"
    , "roster-shift-unit-cell slot-empty-cell slot-shift-type-cell roster-block-end is-shift-type-empty"
    ]

renderCreateShiftUnit :: (?context :: ControllerContext) => RosterSlotCellTarget -> Text -> [Text] -> Int -> Html
renderCreateShiftUnit target groupKey visualCellClasses gridSpan =
    [hsx|
                <div {...attributes} role="gridcell"
                     class="roster-shift-unit roster-shift-launcher roster-shift-create-unit"
                     style={rosterGridColumnSpanStyle gridSpan}
                     data-roster-shift-launcher="true"
                     tabindex="0">
                    <div class="roster-shift-create-grid">
                        {forEach visualCellClasses renderCreateShiftUnitVisualCell}
                        <div class="roster-shift-create-plus-overlay" aria-hidden="true">+</div>
                    </div>
                </div>
            |]

  where
    attributes = SurfaceInteraction.frontendSurfaceDropzoneRefAttrs rosterDragDropzoneRef groupKey
        <> rosterShiftGroupHighlightAttrs groupKey
        <> rosterShiftDialogLauncherAttrs (rosterSlotDialogUrl target)

renderCreateShiftUnitVisualCell :: Text -> Html
renderCreateShiftUnitVisualCell cellClasses = [hsx|<div class={cellClasses} {...rosterImageExportCellAttrs ""}></div>|]

rosterShiftGroupHighlightAttrs :: Text -> [(Text, Text)]
rosterShiftGroupHighlightAttrs membershipKey =
    SurfaceLinkedHighlight.frontendSurfaceLinkedHighlightSourceAttrs rosterShiftGroupLinkedHighlight membershipKey
        <> SurfaceLinkedHighlight.frontendSurfaceLinkedHighlightMemberAttrs rosterShiftGroupLinkedHighlight membershipKey Nothing

rosterStaffHighlightAttrs :: Maybe UUID -> Text -> [(Text, Text)]
rosterStaffHighlightAttrs maybeStaffId orderKey =
    case maybeStaffId of
        Nothing -> []
        Just staffId ->
            SurfaceLinkedHighlight.frontendSurfaceLinkedHighlightMemberAttrs
                rosterStaffLinkedHighlight
                ("staff:" <> tshow staffId)
                (Just orderKey)

renderClosedBlockCells :: (?context :: ControllerContext) => Bool -> Int -> Html
renderClosedBlockCells =
    renderBlankBlockCells "render.roster.closed_block" "slot-closed-cell"

renderBlankBlockCells :: (?context :: ControllerContext) => Text -> Text -> Bool -> Int -> Html
renderBlankBlockCells counterName baseClass endTimesEnabled blockIndex =
    mconcat
        [ profileRenderCounter counterName 1
        , profileRenderCounter "render.roster.grid_cell" cellCount
        , forEach cellClasses renderBlankGridCell
        ]
    where
        cellCount = if endTimesEnabled then 4 else 3
        cellClasses =
            [ classes [(baseClass, True), ("roster-block-start", blockIndex > 0)]
            ] <> replicate (cellCount - 2) baseClass <> [baseClass <> " roster-block-end"]

renderBlankGridCell :: Text -> Html
renderBlankGridCell cellClasses = [hsx|<div role="gridcell" class={cellClasses} {...rosterImageExportCellAttrs ""}></div>|]

renderShiftTypeOptionLabel :: ShiftType -> Text
renderShiftTypeOptionLabel shiftType =
    if shiftType.isActive
        then shiftType.name
        else shiftType.name <> " (inactive)"

findShiftTypeForSlot :: [ShiftType] -> Maybe UUID -> Maybe ShiftType
findShiftTypeForSlot _ Nothing = Nothing
findShiftTypeForSlot shiftTypes (Just selectedShiftTypeId) =
    find (\shiftType -> coerce shiftType.id == selectedShiftTypeId) shiftTypes

shiftTypeBadgeColourKey :: Maybe ShiftType -> Text
shiftTypeBadgeColourKey =
    maybe "" normaliseShiftTypeBadgeColourKey

normaliseShiftTypeBadgeColourKey :: ShiftType -> Text
normaliseShiftTypeBadgeColourKey shiftType
    | shiftType.colourKey `elem` shiftTypeColourPaletteKeys = shiftTypeColourKeyCssValue shiftType.colourKey
    | otherwise = ""

shiftTypeBadgeLabel :: Maybe UUID -> Maybe ShiftType -> Text
shiftTypeBadgeLabel staffId =
    maybe (if isJust staffId then "Role required" else "Role") renderShiftTypeOptionLabel

renderReadOnlyDayColumnShiftTypeBadge :: Maybe UUID -> Maybe ShiftType -> Bool -> Html
renderReadOnlyDayColumnShiftTypeBadge staffId selectedShiftType isPublishRequired = [hsx|
    <div class={classes [("app-dense-static slot-cell-static roster-shift-type-badge roster-shift-type-badge-readonly", True), ("is-empty", isNothing selectedShiftType), ("is-required", isPublishRequired), ("is-publish-required", isPublishRequired)]}
         data-roster-shift-colour={shiftTypeBadgeColourKey selectedShiftType}>
        <span class="roster-shift-type-badge-label" title={fullLabel}>{fullLabel}</span>
    </div>
|]

  where
    fullLabel = shiftTypeBadgeLabel staffId selectedShiftType

rosterTimingDisplay :: RosterRenderIndexes -> RosterSlot -> (Maybe TimeOfDay, Maybe TimeOfDay, Bool)
rosterTimingDisplay indexes slot =
    case Map.lookup (unpackId slot.id) indexes.rosterTimingBySlotId of
        Just (Right timing) -> (Just (rosterShiftTimingStartTime timing), Just (rosterShiftTimingEndTime timing), False)
        _                   -> (Nothing, Nothing, True)

renderRosterTimingIssue :: Bool -> Html
renderRosterTimingIssue False = mempty
renderRosterTimingIssue True = [hsx|<span class="roster-shift-timing-issue text-warning" data-roster-timing-issue="true" title="Timing needs repair">!</span>|]

renderReadOnlyStaffCell :: Text -> Maybe RosterConflict -> Html
renderReadOnlyStaffCell currentStaffLabel currentPrimaryConflict =
    mconcat
        [ [hsx|<div class="app-dense-static slot-cell-static">{currentStaffLabel}</div>|] ]

rosterSlotDialogUrl :: (?context :: ControllerContext) => RosterSlotCellTarget -> Text
rosterSlotDialogUrl (ExistingRosterSlotTarget rosterSlotId anchorDate calendarRevision) =
    rosterExistingSlotDialogUrl rosterSlotId anchorDate calendarRevision
rosterSlotDialogUrl (NewRosterSlotTarget rosterDayId rosterLaneId rosterGroupId operationalDate calendarRevision rowIndex) =
    rosterNewSlotDialogUrl rosterDayId rosterLaneId rowIndex rosterGroupId operationalDate calendarRevision

rosterShiftGroupKey :: RosterSlotCellTarget -> Text
rosterShiftGroupKey (ExistingRosterSlotTarget rosterSlotId _ _) =
    "existing:" <> tshow rosterSlotId
rosterShiftGroupKey (NewRosterSlotTarget rosterDayId rosterWeekSlotDefinitionId _ _ _ rowIndex) =
    "new:" <> tshow rosterDayId <> ":" <> tshow rosterWeekSlotDefinitionId <> ":" <> tshow rowIndex

renderRosterShiftTypeLabel :: Text -> Html
renderRosterShiftTypeLabel value = [hsx|
    <div class={classes [("app-dense-static slot-cell-static", True), ("app-muted", Text.null value)]}>
        <span class="roster-shift-type-label" title={value}>{if Text.null value then " " else value}</span>
    </div>
|]

renderReadOnlyCell :: Text -> Html
renderReadOnlyCell value = [hsx|
    <div class={classes [("app-dense-static slot-cell-static", True), ("app-muted", Text.null value)]}>{if Text.null value then " " else value}</div>
|]

renderAssignedStaffLabel :: Maybe UUID -> RosterRenderIndexes -> Maybe Text
renderAssignedStaffLabel Nothing _ = Nothing
renderAssignedStaffLabel (Just assignedStaffId) renderIndexes =
    staffDisplayName (Map.elems renderIndexes.rosterStaffById)
        <$> Map.lookup assignedStaffId renderIndexes.rosterStaffById

lookupConflicts :: Id RosterSlot -> RosterRenderIndexes -> [RosterConflict]
lookupConflicts slotId renderIndexes = Map.findWithDefault [] (coerce slotId) renderIndexes.rosterConflictsBySlotId

renderConflictClass :: Maybe RosterConflict -> Text
renderConflictClass Nothing = ""
renderConflictClass (Just conflict) =
    case conflict.conflictType of
        ConflictDetailsUnavailable    -> "conflict-critical"
        InvalidRosterTiming           -> "conflict-critical"
        DuplicateAssignment           -> "conflict-critical"
        LeaveConflict                 -> "conflict-critical"
        LateToEarlyConflict           -> "conflict-critical"
        ShiftPreferenceDayUnavailable -> "conflict-preference"
        ShiftPreferenceSlotMismatch   -> "conflict-preference"
        IdealShiftThresholdExceeded   -> "conflict-ideal"

renderConflictMessage :: Maybe RosterConflict -> Text
renderConflictMessage Nothing         = ""
renderConflictMessage (Just conflict) = conflict.message
