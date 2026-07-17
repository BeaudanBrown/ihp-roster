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
import Application.Helper.View.TimePicker
import Application.Helper.View.ToggleButton
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Generated.Types
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
renderTimesheetForm :: (?context :: ControllerContext) => AppShellActionIR -> TimesheetFormOrigin -> TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Maybe UUID -> Text -> Text -> Text -> Text -> OverlayFormMode -> Html
renderTimesheetForm appShellAction formOrigin entry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd actionUrl formId formMode =
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
                (renderTimesheetFormFields formOrigin entry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd)
        PageOverlayForm -> [hsx|
            <form id={formId}
                  method="POST"
                  action={actionUrl}
                  class="mt-3">
                {renderTimesheetFormFields formOrigin entry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd}
            </form>
        |]

renderTimesheetFormFields :: (?context :: ControllerContext) => TimesheetFormOrigin -> TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Maybe UUID -> Text -> Text -> Html
renderTimesheetFormFields formOrigin entry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd = [hsx|
    <input type="hidden" name={surfaceFieldNameFrom @Surface.WeekOffset stateFields} value={tshow weekOffset} />
    <input type="hidden" name={surfaceFieldNameFrom @Surface.ShowApproved stateFields} value={if showApproved then ("true" :: Text) else "false"} />
    <input type="hidden" name={surfaceFieldNameFrom @Surface.ShowAllStaff stateFields} value={if showAllStaff then ("true" :: Text) else "false"} />
    <input type="hidden" name={surfaceFieldNameFrom @Surface.ShowSuggestions stateFields} value={if showSuggestions then ("true" :: Text) else "false"} />
    <input type="hidden" name={surfaceFieldNameFrom @Surface.StaffFilterId stateFields} value={maybe "" tshow selectedStaffFilterId} />
    {renderTimesheetFormOriginNotice formOrigin}
    {renderStaffFieldForOrigin formOrigin entry staffMembers}
    {renderShiftTypeField entry shiftTypes}
    <input type="hidden" name="workedOn" value={dateValueIso} />
    {renderFieldError entry "workedOn"}

    <div class="row mb-3">
        <div class="col">
            <label class="form-label">Shift Start</label>
            {renderTimePickerField (defaultTimePickerConfig "startTime" startTimeValue pickerStart pickerEnd False)}
            {renderFieldError entry "startTime"}
        </div>
        <div class="col">
            <label class="form-label">Shift End</label>
            {renderTimePickerField (defaultTimePickerConfig "endTime" endTimeValue pickerStart pickerEnd False)}
            {renderFieldError entry "endTime"}
        </div>
    </div>

    <div class="mb-3">
        {renderTimesheetBreakToggle entry}
        {renderFieldError entry "hadBreak"}
    </div>

    <div id="timesheet-break-time-fields" class="row mb-3">
        <div class="col">
            <label class="form-label">Break Start</label>
            {renderTimePickerField (defaultTimePickerConfig "breakStartTime" breakStartTimeValue pickerStart pickerEnd (not entry.hadBreak))}
            {renderFieldError entry "breakStartTime"}
        </div>
        <div class="col">
            <label class="form-label">Break End</label>
            {renderTimePickerField (defaultTimePickerConfig "breakEndTime" breakEndTimeValue pickerStart pickerEnd (not entry.hadBreak))}
            {renderFieldError entry "breakEndTime"}
        </div>
    </div>
    {renderFieldError entry "breakMinutes"}
    {renderTimesheetStaffCommentField entry currentViewerStaffId}
    {renderTimesheetManagerNoteField entry}
|]
    where
        startTimeValue = timeOfDayToStorageValue entry.startTime
        endTimeValue = timeOfDayToStorageValue entry.endTime
        breakStartTimeValue = optionalTimeOfDayToStorageValue entry.breakStartTime
        breakEndTimeValue = optionalTimeOfDayToStorageValue entry.breakEndTime
        dateValueIso = tshow entry.workedOn :: Text
        stateFields =
            TimesheetsAction.createTimesheetEntryFromSuggestionActionFields
                weekOffset
                showApproved
                showAllStaff
                showSuggestions
                selectedStaffFilterId

renderTimesheetFormOriginNotice :: TimesheetFormOrigin -> Html
renderTimesheetFormOriginNotice AdHocTimesheetForm = mempty
renderTimesheetFormOriginNotice AdHocTimesheetFormWithSuggestion = [hsx|
    <div class="alert alert-warning" role="status">
        <strong>This creates a separate timesheet entry.</strong>
        The rostered suggestion will remain until it is created from its own card.
    </div>
|]
renderTimesheetFormOriginNotice RosteredTimesheetForm = [hsx|
    <div class="alert alert-info" role="status">
        <strong>Roster suggestion.</strong>
        This form starts from the current roster shift. Your changes are saved only to the new timesheet entry.
    </div>
|]
renderTimesheetFormOriginNotice RosteredTimesheetEntryForm = [hsx|
    <div class="alert alert-info" role="status">
        <strong>Roster-derived entry.</strong>
        This entry is a snapshot of a roster shift. Its roster source and date stay fixed; edits do not change the roster.
    </div>
|]

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

renderTimesheetBreakToggle :: TimesheetEntry -> Html
renderTimesheetBreakToggle entry =
    renderAppToggleButton $ (defaultAppToggleButtonConfig "hadBreak" entry.hadBreak [hsx|<span>Had break</span>|])
        { appToggleInputName = Just "hadBreak"
        , appToggleInputValue = "on"
        , appToggleButtonClass = classes [("btn-sm", True), ("is-invalid", hasErrorFor entry "hadBreak")]
        , appToggleBreakTarget = Just "#timesheet-break-time-fields"
        }

renderTimesheetStaffCommentField :: (?context :: ControllerContext) => TimesheetEntry -> Maybe UUID -> Html
renderTimesheetStaffCommentField entry currentViewerStaffId
    | currentViewerStaffId == Just entry.staffId = [hsx|
        <div class="mb-3">
            <label for="staffComment" class="form-label">Staff comment</label>
            <textarea id="staffComment"
                      name="staffComment"
                      class={classes [("form-control", True), ("is-invalid", hasErrorFor entry "staffComment")]}
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
