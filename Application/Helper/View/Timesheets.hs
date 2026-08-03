{-# LANGUAGE TypeApplications #-}

module Application.Helper.View.Timesheets
    ( TimesheetFormOrigin (..)
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
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.View.Audience
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
import qualified IHP.Prelude as Prelude
import IHP.ViewPrelude
import Web.Types

data TimesheetFormOrigin
    = AdHocTimesheetForm
    | AdHocTimesheetFormWithSuggestion
    | RosteredTimesheetForm
    | RosteredTimesheetEntryForm
    deriving (Eq, Show)

timesheetModalTitle :: Day -> Text
timesheetModalTitle day =
    "Timesheet "
        <> Text.pack (formatTime defaultTimeLocale "%A" day)
        <> " "
        <> formatDayMonthDisplay day

-- | Shared timesheet entry form used by New and Edit views.
renderTimesheetForm :: (?context :: ControllerContext) => AppShellActionIR -> TimesheetFormOrigin -> TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Maybe UUID -> Text -> Text -> Int -> Text -> Text -> OverlayFormMode -> Html
renderTimesheetForm appShellAction formOrigin entry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep actionUrl formId formMode =
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
                (renderTimesheetFormFields formOrigin entry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep True)
        PageOverlayForm -> [hsx|
            <form id={formId}
                  method="POST"
                  action={actionUrl}
                  class="mt-3">
                {renderTimesheetFormFields formOrigin entry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep False}
            </form>
        |]

renderTimesheetFormFields :: (?context :: ControllerContext) => TimesheetFormOrigin -> TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Maybe UUID -> Text -> Text -> Int -> Bool -> Html
renderTimesheetFormFields formOrigin entry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep keyboardEnabled = [hsx|
    <input type="hidden" name={surfaceFieldNameFrom @Surface.WeekOffset stateFields} value={tshow weekOffset} />
    <input type="hidden" name={surfaceFieldNameFrom @Surface.ShowApproved stateFields} value={if showApproved then ("true" :: Text) else "false"} />
    <input type="hidden" name={surfaceFieldNameFrom @Surface.ShowAllStaff stateFields} value={if showAllStaff then ("true" :: Text) else "false"} />
    <input type="hidden" name={surfaceFieldNameFrom @Surface.ShowSuggestions stateFields} value={if showSuggestions then ("true" :: Text) else "false"} />
    <input type="hidden" name={surfaceFieldNameFrom @Surface.StaffFilterId stateFields} value={maybe "" tshow selectedStaffFilterId} />
    {renderTimesheetFormOriginNotice formOrigin}
    {renderStaffFieldForOrigin formOrigin entry staffMembers}
    {renderShiftTypeField entry shiftTypes}
    <input type="hidden" name="workedOn" value={dateValueIso} />
    {renderFieldError entry "startsAt"}

    <div class="row mb-3">
        <div class="col">
            <label class="form-label">Shift Start</label>
            {renderTimePickerField (timesheetPickerConfig "startTime" startTimeValue True (hasErrorFor entry "startsAt"))}
            {renderOccurrenceChooser entry "startsAt" "startOccurrence" "Shift start occurrence" startLocalTime (authoritativeStartOccurrence boundaries)}
            {renderFieldError entry "startsAt"}
        </div>
        <div class="col">
            <label class="form-label">Shift End</label>
            {renderTimePickerField (timesheetPickerConfig "endTime" endTimeValue False (hasErrorFor entry "endsAt"))}
            {renderOccurrenceChooser entry "endsAt" "endOccurrence" "Shift end occurrence" endLocalTime (authoritativeEndOccurrence boundaries)}
            {renderFieldError entry "endsAt"}
        </div>
    </div>

    <div class="mb-3">
        {renderTimesheetBreakToggle entry}
    </div>

    {renderTimesheetBreakFields entry boundaries breakStartTimeValue breakEndTimeValue pickerStart pickerEnd pickerStep keyboardEnabled}
    {renderTimesheetStaffCommentField entry currentViewerStaffId}
    {renderTimesheetManagerNoteField entry}
|]
    where
        boundaries = either (error . ("Invalid timesheet form boundaries: " <>) . show) Prelude.id (timesheetEntryBoundaries entry)
        startLocalTime = authoritativeStartLocalTime boundaries
        endLocalTime = authoritativeEndLocalTime boundaries
        startTimeValue = timeOfDayToStorageValue startLocalTime.localTimeOfDay
        endTimeValue = timeOfDayToStorageValue endLocalTime.localTimeOfDay
        breakStartTimeValue = optionalTimeOfDayToStorageValue (timesheetEntryBreakStartTime entry)
        breakEndTimeValue = optionalTimeOfDayToStorageValue (timesheetEntryBreakEndTime entry)
        dateValueIso = tshow startLocalTime.localDay :: Text
        timesheetPickerConfig fieldName value autofocus invalid =
            (defaultTimePickerConfig fieldName value pickerStart pickerEnd False)
                { timePickerStepMinutes = pickerStep
                , timePickerKeyboardEnabled = keyboardEnabled
                , timePickerAutofocus = keyboardEnabled && autofocus
                , timePickerInvalid = invalid
                }
        stateFields =
            TimesheetsAction.createTimesheetEntryFromSuggestionActionFields
                weekOffset
                showApproved
                showAllStaff
                showSuggestions
                selectedStaffFilterId

renderTimesheetBreakFields :: TimesheetEntry -> AuthoritativeBoundaries -> Text -> Text -> Text -> Text -> Int -> Bool -> Html
renderTimesheetBreakFields entry boundaries breakStartTimeValue breakEndTimeValue pickerStart pickerEnd pickerStep keyboardEnabled =
    renderAppToggleBreakRegion timesheetBreakRegion (timesheetEntryHadBreak entry) "row mb-3" [hsx|
        <div class="col">
            <label class="form-label">Break Start</label>
            {renderTimePickerField (breakPickerConfig "breakStartTime" breakStartTimeValue (hasErrorFor entry "breakStartsAt"))}
            {maybe mempty (\localTime -> renderOccurrenceChooser entry "breakStartsAt" "breakStartOccurrence" "Break start occurrence" localTime (authoritativeBreakStartOccurrence boundaries)) (authoritativeBreakStartLocalTime boundaries)}
            {renderFieldError entry "breakStartsAt"}
        </div>
        <div class="col">
            <label class="form-label">Break End</label>
            {renderTimePickerField (breakPickerConfig "breakEndTime" breakEndTimeValue (hasErrorFor entry "breakEndsAt"))}
            {maybe mempty (\localTime -> renderOccurrenceChooser entry "breakEndsAt" "breakEndOccurrence" "Break end occurrence" localTime (authoritativeBreakEndOccurrence boundaries)) (authoritativeBreakEndLocalTime boundaries)}
            {renderFieldError entry "breakEndsAt"}
        </div>
    |]
  where
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

renderStaffFieldForOrigin :: (?context :: ControllerContext) => TimesheetFormOrigin -> TimesheetEntry -> [Staff] -> Html
renderStaffFieldForOrigin AdHocTimesheetForm entry staffMembers = renderStaffField entry staffMembers
renderStaffFieldForOrigin AdHocTimesheetFormWithSuggestion entry staffMembers = renderStaffField entry staffMembers
renderStaffFieldForOrigin RosteredTimesheetForm entry staffMembers = renderRosteredStaffField entry staffMembers
renderStaffFieldForOrigin RosteredTimesheetEntryForm entry staffMembers
    | currentUserIsManager = renderStaffField entry staffMembers
    | otherwise = renderRosteredStaffField entry staffMembers

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

renderTimesheetStaffCommentField :: (?context :: ControllerContext) => TimesheetEntry -> Maybe UUID -> Html
renderTimesheetStaffCommentField entry currentViewerStaffId
    | currentViewerStaffId == Just entry.staffId = [hsx|
        <div class="mb-3">
            <label for="staffComment" class="form-label">Staff comment</label>
            <textarea id="staffComment"
                      name="staffComment"
                      class={classes [("form-control", True), ("is-invalid", hasErrorFor entry "staffComment")]}
                      aria-invalid={if hasErrorFor entry "staffComment" then ("true" :: Text) else "false"}
                      rows="3"
                      maxlength="1000">{fromMaybe "" entry.staffComment}</textarea>
            {renderFieldError entry "staffComment"}
        </div>
    |]
    | currentUserIsManager && isJust entry.staffComment = [hsx|
        <div class="mb-3">
            <label class="form-label">Staff comment</label>
            <div class="form-control-plaintext border rounded px-3 py-2">{fromMaybe "" entry.staffComment}</div>
        </div>
    |]
    | otherwise = mempty

renderTimesheetManagerNoteField :: (?context :: ControllerContext) => TimesheetEntry -> Html
renderTimesheetManagerNoteField entry
    | currentUserIsManager = [hsx|
        <div class="mb-3">
            <label for="managerNote" class="form-label">Manager note</label>
            <textarea id="managerNote"
                      name="managerNote"
                      class={classes [("form-control", True), ("is-invalid", hasErrorFor entry "managerNote")]}
                      aria-invalid={if hasErrorFor entry "managerNote" then ("true" :: Text) else "false"}
                      rows="3"
                      maxlength="1000">{fromMaybe "" entry.managerNote}</textarea>
            {renderFieldError entry "managerNote"}
        </div>
    |]
    | otherwise = mempty

renderStaffField :: (?context :: ControllerContext) => TimesheetEntry -> [Staff] -> Html
renderStaffField entry staffMembers =
    if currentUserIsManager
        then [hsx|
            <div class="mb-3">
                <label for="staffId" class="form-label">Staff Member</label>
                <select name="staffId" id="staffId" aria-invalid={if hasErrorFor entry "staffId" then ("true" :: Text) else "false"} class={classes [("form-select", True), ("is-invalid", hasErrorFor entry "staffId")]} required="required">
                    {forEach staffMembers (renderTimesheetStaffOption entry.staffId)}
                </select>
                {renderFieldError entry "staffId"}
            </div>
        |]
        else [hsx|
            <input type="hidden" name="staffId" value={inputValue entry.staffId} />
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
