{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Application.Helper.View.Timesheets
    ( TimesheetFormInputs (..)
    , TimesheetFormOrigin (..)
    , TimesheetFormPresentation (..)
    , TimesheetFormRenderModel (..)
    , hasErrorFor
    , renderFieldError
    , renderShiftTypeField
    , renderShiftTypeOption
    , renderStaffField
    , renderTimesheetEntryDialog
    , renderTimesheetEntryDialogWithStartButtons
    , renderTimesheetEntryModal
    , renderTimesheetEntryModalWithStartButtons
    , renderTimesheetForm
    , renderTimesheetFormFields
    , renderTimesheetManagerNoteField
    , renderTimesheetStaffCommentField
    , renderTimesheetStaffOption
    , timesheetModalTitle
    ) where

import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             renderAppShellActionForm)
import Application.Helper.FrontendContract.IR (AppShellActionIR)
import Application.Helper.FrontendContract.Surface.DSL (WireType (WireDay))
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.View.Format
import Application.Helper.View.Overlay
import Application.Helper.View.TimeOccurrence
import Application.Helper.View.TimePicker
import Application.Helper.View.ToggleButton
import Application.VenueTime (RepeatedTimeOccurrence)
import Application.VenueTime.Model
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (LocalTime (..))
import Generated.Types
import IHP.ViewPrelude
import Web.Types

data TimesheetFormOrigin
    = AdHocTimesheetForm
    | AdHocTimesheetFormWithSuggestion
    | RosteredTimesheetForm
    | RosteredTimesheetEntryForm
    deriving (Eq, Show)

data TimesheetFormInputs = TimesheetFormInputs
    { timesheetEntry        :: TimesheetEntry
    , staffMembers          :: [Staff]
    , shiftTypes            :: [ShiftType]
    , calendarRevision      :: Int
    , selectedStaffFilterId :: Maybe UUID
    , currentViewerStaffId  :: Maybe UUID
    , pickerStart           :: Text
    , pickerEnd             :: Text
    , pickerStep            :: Int
    , viewerIsManager       :: Bool
    }

data TimesheetFormPresentation = TimesheetFormPresentation
    { appShellAction :: AppShellActionIR
    , formOrigin     :: TimesheetFormOrigin
    , actionUrl      :: Text
    , formId         :: Text
    , formMode       :: OverlayFormMode
    }

data TimesheetFormRenderModel = TimesheetFormRenderModel
    { timesheetFormInputs       :: TimesheetFormInputs
    , timesheetFormPresentation :: TimesheetFormPresentation
    }

data TimesheetTimeRenderValues = TimesheetTimeRenderValues
    { startLocalTime       :: Maybe LocalTime
    , endLocalTime         :: Maybe LocalTime
    , breakStartLocalTime  :: Maybe LocalTime
    , breakEndLocalTime    :: Maybe LocalTime
    , startOccurrence      :: Maybe RepeatedTimeOccurrence
    , endOccurrence        :: Maybe RepeatedTimeOccurrence
    , breakStartOccurrence :: Maybe RepeatedTimeOccurrence
    , breakEndOccurrence   :: Maybe RepeatedTimeOccurrence
    , startTimeValue       :: Text
    , endTimeValue         :: Text
    , breakStartTimeValue  :: Text
    , breakEndTimeValue    :: Text
    }

timesheetModalTitle :: Day -> Text
timesheetModalTitle day =
    "Timesheet "
        <> Text.pack (formatTime defaultTimeLocale "%A" day)
        <> " "
        <> formatDayMonthDisplay day

-- | Shared timesheet entry form used by New, Edit, and Suggestion views.
renderTimesheetForm :: (?context :: ControllerContext) => TimesheetFormRenderModel -> Html
renderTimesheetForm model@TimesheetFormRenderModel { timesheetFormPresentation = TimesheetFormPresentation { .. } } =
    case formMode of
        HtmxOverlayForm ->
            renderAppShellActionForm
                appShellAction
                AppShellActionRoute
                    { appShellActionRouteUrl = actionUrl
                    , appShellActionRouteFields = []
                    , appShellActionRouteCustomHtmx = []
                    , appShellActionRouteStandardUrl = Nothing
                    , appShellActionRouteExtraAttrs =
                        [ ("id", formId)
                        , ("class", "mt-3")
                        ]
                    }
                (renderTimesheetFormFields model)
        PageOverlayForm -> [hsx|
            <form id={formId}
                  method="POST"
                  action={actionUrl}
                  class="mt-3">
                {renderTimesheetFormFields model}
            </form>
        |]

renderTimesheetFormFields :: (?context :: ControllerContext) => TimesheetFormRenderModel -> Html
renderTimesheetFormFields model@TimesheetFormRenderModel
        { timesheetFormInputs = inputs@TimesheetFormInputs { .. }
        , timesheetFormPresentation = TimesheetFormPresentation { formOrigin, formMode, .. }
        } = [hsx|
    <input type="hidden" name={surfaceFieldNameFrom @Surface.AnchorDate stateFields} value={surfaceWireText @'WireDay timesheetEntry.operationalDate} />
    <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision stateFields} value={tshow calendarRevision} />
    <input type="hidden" name={surfaceFieldNameFrom @Surface.StaffFilterId stateFields} value={maybe "" tshow selectedStaffFilterId} />
    {renderTimesheetFormOriginNotice formOrigin}
    {renderStaffFieldForOrigin model}
    {renderShiftTypeField timesheetEntry shiftTypes}
    <input type="hidden" name="workedOn" value={dateValueIso} />
    {renderFieldError timesheetEntry "startsAt"}

    <div class="row mb-3">
        <div class="col">
            <label class="form-label">Shift Start</label>
            {renderTimePickerField (timesheetPickerConfig "startTime" startTimeValue True (hasErrorFor timesheetEntry "startsAt"))}
            {maybe mempty (\localTime -> renderOccurrenceChooser timesheetEntry "startsAt" "startOccurrence" "Shift start occurrence" localTime startOccurrence) startLocalTime}
            {renderFieldError timesheetEntry "startsAt"}
        </div>
        <div class="col">
            <label class="form-label">Shift End</label>
            {renderTimePickerField (timesheetPickerConfig "endTime" endTimeValue False (hasErrorFor timesheetEntry "endsAt"))}
            {maybe mempty (\localTime -> renderOccurrenceChooser timesheetEntry "endsAt" "endOccurrence" "Shift end occurrence" localTime endOccurrence) endLocalTime}
            {renderFieldError timesheetEntry "endsAt"}
        </div>
    </div>

    <div class="mb-3">
        {renderTimesheetBreakToggle timesheetEntry}
    </div>

    {renderTimesheetBreakFields model timeValues}
    {renderTimesheetStaffCommentField inputs}
    {renderTimesheetManagerNoteField inputs}
|]
    where
        timeValues@TimesheetTimeRenderValues { .. } = timesheetTimeRenderValues timesheetEntry
        keyboardEnabled = timesheetFormKeyboardEnabled formMode
        dateValueIso = tshow timesheetEntry.operationalDate :: Text
        timesheetPickerConfig fieldName value autofocus invalid =
            (defaultTimePickerConfig fieldName value pickerStart pickerEnd False)
                { timePickerStepMinutes = pickerStep
                , timePickerKeyboardEnabled = keyboardEnabled
                , timePickerAutofocus = keyboardEnabled && autofocus
                , timePickerInvalid = invalid
                }
        stateFields =
            TimesheetsAction.createTimesheetEntryFromSuggestionActionFields timesheetEntry.operationalDate calendarRevision selectedStaffFilterId

timesheetTimeRenderValues :: TimesheetEntry -> TimesheetTimeRenderValues
timesheetTimeRenderValues timesheetEntry =
    let recoveredStartLocalTime = recoverStoredInstantLocalTime timesheetEntry.timezone (Just timesheetEntry.startsAt)
        recoveredEndLocalTime = recoverStoredInstantLocalTime timesheetEntry.timezone (Just timesheetEntry.endsAt)
        recoveredBreakStartLocalTime = recoverStoredInstantLocalTime timesheetEntry.timezone timesheetEntry.breakStartsAt
        recoveredBreakEndLocalTime = recoverStoredInstantLocalTime timesheetEntry.timezone timesheetEntry.breakEndsAt
        recoveredTimeValue = maybe "" (timeOfDayToStorageValue . (.localTimeOfDay))
     in TimesheetTimeRenderValues
            { startLocalTime = recoveredStartLocalTime
            , endLocalTime = recoveredEndLocalTime
            , breakStartLocalTime = recoveredBreakStartLocalTime
            , breakEndLocalTime = recoveredBreakEndLocalTime
            , startOccurrence = recoverStoredInstantOccurrence timesheetEntry.timezone (Just timesheetEntry.startsAt)
            , endOccurrence = recoverStoredInstantOccurrence timesheetEntry.timezone (Just timesheetEntry.endsAt)
            , breakStartOccurrence = recoverStoredInstantOccurrence timesheetEntry.timezone timesheetEntry.breakStartsAt
            , breakEndOccurrence = recoverStoredInstantOccurrence timesheetEntry.timezone timesheetEntry.breakEndsAt
            , startTimeValue = recoveredTimeValue recoveredStartLocalTime
            , endTimeValue = recoveredTimeValue recoveredEndLocalTime
            , breakStartTimeValue = recoveredTimeValue recoveredBreakStartLocalTime
            , breakEndTimeValue = recoveredTimeValue recoveredBreakEndLocalTime
            }

timesheetFormKeyboardEnabled :: OverlayFormMode -> Bool
timesheetFormKeyboardEnabled HtmxOverlayForm = True
timesheetFormKeyboardEnabled PageOverlayForm = False

renderTimesheetBreakFields :: TimesheetFormRenderModel -> TimesheetTimeRenderValues -> Html
renderTimesheetBreakFields
        TimesheetFormRenderModel
            { timesheetFormInputs = TimesheetFormInputs { timesheetEntry, pickerStart, pickerEnd, pickerStep, .. }
            , timesheetFormPresentation = TimesheetFormPresentation { formMode, .. }
            }
        TimesheetTimeRenderValues { .. } =
    renderAppToggleBreakRegion timesheetBreakRegion (timesheetEntryHadBreak timesheetEntry) "row mb-3" [hsx|
        <div class="col">
            <label class="form-label">Break Start</label>
            {renderTimePickerField (breakPickerConfig "breakStartTime" breakStartTimeValue (hasErrorFor timesheetEntry "breakStartsAt"))}
            {maybe mempty (\localTime -> renderOccurrenceChooser timesheetEntry "breakStartsAt" "breakStartOccurrence" "Break start occurrence" localTime breakStartOccurrence) breakStartLocalTime}
            {renderFieldError timesheetEntry "breakStartsAt"}
        </div>
        <div class="col">
            <label class="form-label">Break End</label>
            {renderTimePickerField (breakPickerConfig "breakEndTime" breakEndTimeValue (hasErrorFor timesheetEntry "breakEndsAt"))}
            {maybe mempty (\localTime -> renderOccurrenceChooser timesheetEntry "breakEndsAt" "breakEndOccurrence" "Break end occurrence" localTime breakEndOccurrence) breakEndLocalTime}
            {renderFieldError timesheetEntry "breakEndsAt"}
        </div>
    |]
  where
    keyboardEnabled = timesheetFormKeyboardEnabled formMode
    breakPickerConfig fieldName value invalid =
        (defaultTimePickerConfig fieldName value pickerStart pickerEnd False)
            { timePickerStepMinutes = pickerStep
            , timePickerKeyboardEnabled = keyboardEnabled
            , timePickerInvalid = invalid
            }

renderOccurrenceChooser :: TimesheetEntry -> Text -> Text -> Text -> LocalTime -> Maybe RepeatedTimeOccurrence -> Html
renderOccurrenceChooser entry annotationField fieldName label localTime storedOccurrence
    | not (civilBoundaryIsRepeated localTime.localDay localTime.localTimeOfDay) = mempty
    | otherwise =
        renderTimeOccurrenceChooser
            TimeOccurrenceChooserConfig
                { timeOccurrenceFieldName = fieldName
                , timeOccurrenceLabel = label
                , timeOccurrenceSelected = selectedOccurrence
                , timeOccurrenceInvalid = hasErrorFor entry annotationField
                }
  where
    selectedOccurrence =
        case lookup annotationField entry.meta.annotations of
            Just (TextViolation "Choose whether this is the first or second occurrence.") -> Nothing
            _ -> storedOccurrence

renderTimesheetFormOriginNotice :: TimesheetFormOrigin -> Html
renderTimesheetFormOriginNotice AdHocTimesheetForm = mempty
renderTimesheetFormOriginNotice AdHocTimesheetFormWithSuggestion = mempty
renderTimesheetFormOriginNotice RosteredTimesheetForm = [hsx|
    <div class="alert alert-info" role="status">
        <strong>Roster suggestion.</strong>
        This form starts from the current roster shift. Your changes are saved only to the new timesheet entry.
    </div>
|]
renderTimesheetFormOriginNotice RosteredTimesheetEntryForm = mempty

renderStaffFieldForOrigin :: TimesheetFormRenderModel -> Html
renderStaffFieldForOrigin TimesheetFormRenderModel
        { timesheetFormInputs = inputs@TimesheetFormInputs { timesheetEntry, staffMembers, viewerIsManager, .. }
        , timesheetFormPresentation = TimesheetFormPresentation { formOrigin, .. }
        } =
    case formOrigin of
        AdHocTimesheetForm               -> renderStaffField inputs
        AdHocTimesheetFormWithSuggestion -> renderStaffField inputs
        RosteredTimesheetForm            -> renderRosteredStaffField timesheetEntry staffMembers
        RosteredTimesheetEntryForm
            | viewerIsManager -> renderStaffField inputs
            | otherwise -> renderRosteredStaffField timesheetEntry staffMembers

renderRosteredStaffField :: (?context :: ControllerContext) => TimesheetEntry -> [Staff] -> Html
renderRosteredStaffField entry staffMembers = [hsx|
    <input type="hidden" name="staffId" value={inputValue entry.staffId} />
    <div class="mb-3">
        <label class="form-label">Staff Member</label>
        <div class="form-control-plaintext border rounded px-3 py-2">{staffLabel}</div>
        {renderFieldError entry "staffId"}
    </div>
|]
    where
        staffLabel =
            case find (\staff -> unpackId staff.id == entry.staffId) staffMembers of
                Just staff -> staff.firstName <> " " <> staff.lastName
                Nothing    -> "Rostered staff" :: Text

timesheetBreakRegion :: ToggleBreakRegion
timesheetBreakRegion = toggleBreakRegion "timesheet-break-time-fields"

renderTimesheetBreakToggle :: TimesheetEntry -> Html
renderTimesheetBreakToggle entry =
    renderAppToggleButton $
        (defaultAppToggleButtonConfig "hadBreak" (namedBooleanToggleField "hadBreak") (timesheetEntryHadBreak entry) [hsx|<span>Had break</span>|])
            { appToggleButtonClass = classes [("btn-sm", True), ("is-invalid", hasErrorFor entry "breakStartsAt")]
            , appToggleBreakRegion = Just timesheetBreakRegion
            }

renderTimesheetStaffCommentField :: TimesheetFormInputs -> Html
renderTimesheetStaffCommentField TimesheetFormInputs { timesheetEntry, currentViewerStaffId, viewerIsManager, .. }
    | currentViewerStaffId == Just timesheetEntry.staffId = [hsx|
        <div class="mb-3">
            <label for="staffComment" class="form-label">Staff comment</label>
            <textarea id="staffComment"
                      name="staffComment"
                      class={classes [("form-control", True), ("is-invalid", hasErrorFor timesheetEntry "staffComment")]}
                      aria-invalid={if hasErrorFor timesheetEntry "staffComment" then ("true" :: Text) else "false"}
                      rows="3"
                      maxlength="1000">{fromMaybe "" timesheetEntry.staffComment}</textarea>
            {renderFieldError timesheetEntry "staffComment"}
        </div>
    |]
    | viewerIsManager && isJust timesheetEntry.staffComment = [hsx|
        <div class="mb-3">
            <label class="form-label">Staff comment</label>
            <div class="form-control-plaintext border rounded px-3 py-2">{fromMaybe "" timesheetEntry.staffComment}</div>
        </div>
    |]
    | otherwise = mempty

renderTimesheetManagerNoteField :: TimesheetFormInputs -> Html
renderTimesheetManagerNoteField TimesheetFormInputs { timesheetEntry, viewerIsManager, .. }
    | viewerIsManager = [hsx|
        <div class="mb-3">
            <label for="managerNote" class="form-label">Manager note</label>
            <textarea id="managerNote"
                      name="managerNote"
                      class={classes [("form-control", True), ("is-invalid", hasErrorFor timesheetEntry "managerNote")]}
                      aria-invalid={if hasErrorFor timesheetEntry "managerNote" then ("true" :: Text) else "false"}
                      rows="3"
                      maxlength="1000">{fromMaybe "" timesheetEntry.managerNote}</textarea>
            {renderFieldError timesheetEntry "managerNote"}
        </div>
    |]
    | otherwise = mempty

renderStaffField :: TimesheetFormInputs -> Html
renderStaffField TimesheetFormInputs { timesheetEntry, staffMembers, viewerIsManager, .. } =
    if viewerIsManager
        then [hsx|
            <div class="mb-3">
                <label for="staffId" class="form-label">Staff Member</label>
                <select name="staffId" id="staffId" aria-invalid={if hasErrorFor timesheetEntry "staffId" then ("true" :: Text) else "false"} class={classes [("form-select", True), ("is-invalid", hasErrorFor timesheetEntry "staffId")]} required="required">
                    {forEach staffMembers (renderTimesheetStaffOption timesheetEntry.staffId)}
                </select>
                {renderFieldError timesheetEntry "staffId"}
            </div>
        |]
        else [hsx|
            <input type="hidden" name="staffId" value={inputValue timesheetEntry.staffId} />
        |]

renderShiftTypeField :: TimesheetEntry -> [ShiftType] -> Html
renderShiftTypeField entry shiftTypes = [hsx|
    <div class="mb-3">
        <label for="shiftTypeId" class="form-label">Shift Type</label>
        <select name="shiftTypeId" id="shiftTypeId" aria-invalid={if hasErrorFor entry "shiftTypeId" then ("true" :: Text) else "false"} class={classes [("form-select", True), ("is-invalid", hasErrorFor entry "shiftTypeId")]} required="required">
            {forEach shiftTypes (renderShiftTypeOption entry.shiftTypeId)}
        </select>
        {renderFieldError entry "shiftTypeId"}
    </div>
|]

renderTimesheetStaffOption :: UUID -> Staff -> Html
renderTimesheetStaffOption selectedStaffId staff =
    let isSelected = unpackId (get #id staff) == selectedStaffId
    in [hsx|
        <option value={inputValue staff.id} selected={isSelected}>
            {staff.firstName} {staff.lastName}
        </option>
    |]

renderShiftTypeOption :: UUID -> ShiftType -> Html
renderShiftTypeOption selectedShiftTypeId shiftType =
    let isSelected = unpackId (get #id shiftType) == selectedShiftTypeId
    in [hsx|
        <option value={inputValue shiftType.id} selected={isSelected}>
            {shiftType.name}
        </option>
    |]

renderFieldError :: TimesheetEntry -> Text -> Html
renderFieldError entry fieldName =
    case lookup fieldName entry.meta.annotations of
        Just (TextViolation msg) -> [hsx|<div class="invalid-feedback d-block">{msg}</div>|]
        Just (HtmlViolation msg) -> [hsx|<div class="invalid-feedback d-block">{msg}</div>|]
        Nothing -> mempty

hasErrorFor :: TimesheetEntry -> Text -> Bool
hasErrorFor entry fieldName = isJust (lookup fieldName entry.meta.annotations)

renderTimesheetEntryModal :: Text -> Text -> Text -> Html -> Html
renderTimesheetEntryModal title closeUrl formId formContent =
    renderTimesheetEntryModalWithStartButtons title closeUrl formId formContent []

renderTimesheetEntryModalWithStartButtons :: Text -> Text -> Text -> Html -> [OverlayButton] -> Html
renderTimesheetEntryModalWithStartButtons title closeUrl formId formContent startButtons =
    renderPageDialogModal
        closeUrl
        DialogOverlayConfig
            { dialogOverlayTitle = title
            , dialogOverlayBody = formContent
            , dialogOverlayStartButtons = startButtons
            , dialogOverlayButtons = defaultOverlayButtons formId
            , dialogOverlayDialogClass = ""
            }

renderTimesheetEntryDialog :: Text -> Text -> Html -> Html
renderTimesheetEntryDialog title formId formContent =
    renderTimesheetEntryDialogWithStartButtons title formId formContent []

renderTimesheetEntryDialogWithStartButtons :: Text -> Text -> Html -> [OverlayButton] -> Html
renderTimesheetEntryDialogWithStartButtons title formId formContent startButtons =
    renderKeyboardDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = title
        , dialogOverlayBody = formContent
        , dialogOverlayStartButtons = startButtons
        , dialogOverlayButtons = defaultOverlayButtons formId
        , dialogOverlayDialogClass = ""
        }
