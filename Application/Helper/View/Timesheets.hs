module Application.Helper.View.Timesheets
    ( hasErrorFor
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
    , renderTimesheetStaffOption
    , timesheetModalTitle
    ) where

import Application.Helper.View.Audience
import Application.Helper.View.Format
import Application.Helper.View.Overlay
import Application.Helper.View.TimePicker
import Data.Time.Calendar (Day)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Generated.Types
import IHP.ViewPrelude
import qualified Data.Text as Text
import Web.Types

timesheetModalTitle :: Day -> Text
timesheetModalTitle day =
    "Timesheet "
        <> Text.pack (formatTime defaultTimeLocale "%A" day)
        <> " "
        <> formatDayMonthDisplay day

-- | Shared timesheet entry form used by New and Edit views.
renderTimesheetForm :: (?context :: ControllerContext) => TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Text -> Text -> OverlayFormMode -> Html
renderTimesheetForm entry staffMembers shiftTypes weekOffset showApproved showAllStaff actionUrl formId formMode =
    case formMode of
        HtmxOverlayForm -> [hsx|
            <form id={formId}
                  method="POST"
                  action={actionUrl}
                  class="mt-3"
                  data-disable-javascript-submission="true"
                  hx-post={actionUrl}
                  hx-target={"#" <> dialogOverlayMountId}
                  hx-swap="innerHTML"
                  hx-push-url="false">
                {renderTimesheetFormFields entry staffMembers shiftTypes weekOffset showApproved showAllStaff}
            </form>
        |]
        PageOverlayForm -> [hsx|
            <form id={formId}
                  method="POST"
                  action={actionUrl}
                  class="mt-3">
                {renderTimesheetFormFields entry staffMembers shiftTypes weekOffset showApproved showAllStaff}
            </form>
        |]

renderTimesheetFormFields :: (?context :: ControllerContext) => TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Html
renderTimesheetFormFields entry staffMembers shiftTypes weekOffset showApproved showAllStaff = [hsx|
    <input type="hidden" name="weekOffset" value={tshow weekOffset} />
    <input type="hidden" name="showApproved" value={if showApproved then ("true" :: Text) else "false"} />
    <input type="hidden" name="showAllStaff" value={if showAllStaff then ("true" :: Text) else "false"} />
    {renderStaffField entry staffMembers}
    {renderShiftTypeField entry shiftTypes}
    <input type="hidden" name="workedOn" value={dateValueIso} />
    {renderFieldError entry "workedOn"}

    <div class="row mb-3">
        <div class="col">
            <label class="form-label">Shift Start</label>
            {renderTimePickerField (defaultTimePickerConfig "startTime" startTimeValue "06:00" "04:45" False)}
            {renderFieldError entry "startTime"}
        </div>
        <div class="col">
            <label class="form-label">Shift End</label>
            {renderTimePickerField (defaultTimePickerConfig "endTime" endTimeValue "06:00" "04:45" False)}
            {renderFieldError entry "endTime"}
        </div>
    </div>

    <div class="mb-3">
        <div class="form-check">
            <input
                id="hadBreak"
                name="hadBreak"
                type="checkbox"
                value="on"
                class={classes [("form-check-input", True), ("is-invalid", hasErrorFor entry "hadBreak")]}
                checked={entry.hadBreak}
                data-break-toggle="true"
                data-break-target="#timesheet-break-time-fields"
            />
            <label class="form-check-label" for="hadBreak">Had break</label>
        </div>
        {renderFieldError entry "hadBreak"}
    </div>

    <div id="timesheet-break-time-fields" class="row mb-3" hidden={not entry.hadBreak}>
        <div class="col">
            <label class="form-label">Break Start</label>
            {renderTimePickerField (defaultTimePickerConfig "breakStartTime" breakStartTimeValue "06:00" "04:45" (not entry.hadBreak))}
            {renderFieldError entry "breakStartTime"}
        </div>
        <div class="col">
            <label class="form-label">Break End</label>
            {renderTimePickerField (defaultTimePickerConfig "breakEndTime" breakEndTimeValue "06:00" "04:45" (not entry.hadBreak))}
            {renderFieldError entry "breakEndTime"}
        </div>
    </div>
    {renderFieldError entry "breakMinutes"}
|]
    where
        startTimeValue = timeOfDayToStorageValue entry.startTime
        endTimeValue = timeOfDayToStorageValue entry.endTime
        breakStartTimeValue = optionalTimeOfDayToStorageValue entry.breakStartTime
        breakEndTimeValue = optionalTimeOfDayToStorageValue entry.breakEndTime
        dateValueIso = tshow entry.workedOn :: Text

renderStaffField :: (?context :: ControllerContext) => TimesheetEntry -> [Staff] -> Html
renderStaffField entry staffMembers =
    if currentUserIsManager
        then [hsx|
            <div class="mb-3">
                <label for="staffId" class="form-label">Staff Member</label>
                <select name="staffId" id="staffId" class={classes [("form-select", True), ("is-invalid", hasErrorFor entry "staffId")]} required="required">
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
        <select name="shiftTypeId" id="shiftTypeId" class={classes [("form-select", True), ("is-invalid", hasErrorFor entry "shiftTypeId")]} required="required">
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
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = title
        , dialogOverlayBody = formContent
        , dialogOverlayStartButtons = startButtons
        , dialogOverlayButtons = defaultOverlayButtons formId
        , dialogOverlayDialogClass = ""
        }
