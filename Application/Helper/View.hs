module Application.Helper.View
    ( module Application.Helper.View
    , module Application.Helper.View.Chrome
    , module Application.Helper.View.Overlay
    , module Application.Helper.View.Toast
    ) where

import Application.Helper.Controller (VenueRole (..), currentUserIsSuperAdmin,
                                      hasRole)
import Application.Helper.View.Chrome
import Application.Helper.View.Overlay
import Application.Helper.View.Toast
import qualified Data.Char as Char
import Data.List (elemIndex, sortBy)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Format (defaultTimeLocale, formatTime, parseTimeM)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ViewPrelude
import Web.Routes ()
import Web.Types

-- Here you can add functions which are available in all your views

-- | True when the current user has at least manager privileges.
-- Use in views for conditional rendering of management UI.
currentUserIsManager :: (?context :: ControllerContext) => Bool
currentUserIsManager = hasRole ManagerRole'

-- | True when the current user is an admin.
-- Use in views for conditional rendering of admin-only UI.
currentUserIsAdmin :: (?context :: ControllerContext) => Bool
currentUserIsAdmin = hasRole VenueAdminRole

currentUserIsSupportAdmin :: (?context :: ControllerContext) => Bool
currentUserIsSupportAdmin = currentUserIsSuperAdmin

data ViewAudience
    = AnySignedInAudience
    | StaffProfileAudience
    | ManagerAudience
    | AdminAudience
    | SupportAudience
    deriving (Eq, Show)

currentUserMatchesAudience :: (?context :: ControllerContext) => ViewAudience -> Bool
currentUserMatchesAudience audience =
    case audience of
        AnySignedInAudience -> isJust currentUserOrNothing
        StaffProfileAudience -> isJust currentUserOrNothing && not currentUserIsSupportAdmin
        ManagerAudience     -> currentUserIsManager
        AdminAudience       -> currentUserIsAdmin
        SupportAudience     -> currentUserIsSupportAdmin

renderWhenAudience :: (?context :: ControllerContext) => ViewAudience -> Html -> Html
renderWhenAudience audience html =
    when (currentUserMatchesAudience audience) html

-- | True when a staff record is a trial placeholder (no linked user account).
isTrialStaff :: Staff -> Bool
isTrialStaff staff = isNothing staff.userId

linkedActiveStaffForRosterPanel :: [Staff] -> [Staff]
linkedActiveStaffForRosterPanel =
    sortBy sortStaff
        . filter (\staff -> staff.isActive && isJust staff.userId)
    where
        sortStaff left right =
            compare left.firstName right.firstName <> compare left.lastName right.lastName

staffDisplayName :: [Staff] -> Staff -> Text
staffDisplayName staffMembers staff =
    let
        baseName = staffDisplayBaseName staff
        needsLastInitial =
            any
                (\other -> other.id /= staff.id && normalizedStaffDisplayBaseName other == normalizedStaffDisplayBaseName staff)
                staffMembers
     in
        if needsLastInitial
            then baseName <> renderStaffLastInitial staff
            else baseName

staffDisplayBaseName :: Staff -> Text
staffDisplayBaseName staff =
    fromMaybe staff.firstName (nonBlankText =<< staff.preferredName)

normalizedStaffDisplayBaseName :: Staff -> Text
normalizedStaffDisplayBaseName = Text.toCaseFold . staffDisplayBaseName

renderStaffLastInitial :: Staff -> Text
renderStaffLastInitial staff =
    case Text.find (not . Char.isSpace) (Text.strip staff.lastName) of
        Just char -> " " <> Text.singleton (Char.toUpper char) <> "."
        Nothing   -> ""

nonBlankText :: Text -> Maybe Text
nonBlankText text =
    let stripped = Text.strip text
     in if Text.null stripped then Nothing else Just stripped

data TimePickerConfig = TimePickerConfig
    { timePickerFieldName       :: !Text
    , timePickerCurrentValue    :: !Text
    , timePickerRangeStart      :: !Text
    , timePickerRangeEnd        :: !Text
    , timePickerDisabled        :: !Bool
    , timePickerShowStepButtons :: !Bool
    , timePickerEmptyLabel      :: !Text
    , timePickerFieldClasses    :: ![Text]
    , timePickerControlClasses  :: ![Text]
    , timePickerInputClasses    :: ![Text]
    , timePickerTriggerClasses  :: ![Text]
    , timePickerAriaLabel       :: !Text
    }

-- | Shared modal id for the reusable quarter-hour time picker.
timePickerModalId :: Text
timePickerModalId = "quarter-hour-time-picker-modal"

formatDateDisplay :: Day -> Text
formatDateDisplay day = Text.pack (formatTime defaultTimeLocale "%d/%m/%Y" day)

formatDayMonthDisplay :: Day -> Text
formatDayMonthDisplay day = Text.pack (formatTime defaultTimeLocale "%d/%m" day)

timesheetModalTitle :: Day -> Text
timesheetModalTitle day =
    "Timesheet "
        <> Text.pack (formatTime defaultTimeLocale "%A" day)
        <> " "
        <> formatDayMonthDisplay day

appendQueryParams :: Text -> [(Text, Text)] -> Text
appendQueryParams basePath params
    | null nonEmptyParams = basePath
    | Text.isInfixOf "?" basePath = basePath <> "&" <> renderedParams
    | otherwise = basePath <> "?" <> renderedParams
    where
        nonEmptyParams = filter (not . Text.null . snd) params
        renderedParams = Text.intercalate "&" (map renderParam nonEmptyParams)
        renderParam (key, value) = key <> "=" <> value

-- | Canonical quarter-hour time options from 06:00 through 23:45.
-- Value format is 24-hour HH:MM for storage; label format is 12-hour with AM/PM.
quarterHourTimeOptions :: [(Text, Text)]
quarterHourTimeOptions = quarterHourTimeOptionsInRange (TimeOfDay 6 0 0) (TimeOfDay 23 45 0)

quarterHourTimeOptionsInRange :: TimeOfDay -> TimeOfDay -> [(Text, Text)]
quarterHourTimeOptionsInRange startTime endTime =
    map toOption minuteMarks
    where
        startMinutes = timeOfDayToMinuteOfDay startTime
        endMinutesRaw = timeOfDayToMinuteOfDay endTime
        endMinutes = if endMinutesRaw < startMinutes then endMinutesRaw + 1440 else endMinutesRaw
        minuteMarks = [startMinutes, startMinutes + 15 .. endMinutes]

        toOption totalMinutes =
            let minuteOfDay = totalMinutes `mod` 1440
                (hours, minutes) = minuteOfDay `divMod` 60
                tod = TimeOfDay hours minutes 0
             in (timeOfDayToStorageValue tod, Text.pack (formatTime defaultTimeLocale "%-I:%M %p" tod))

        timeOfDayToMinuteOfDay tod = todHour tod * 60 + todMin tod

-- | Format a TimeOfDay for DB/form storage.
timeOfDayToStorageValue :: TimeOfDay -> Text
timeOfDayToStorageValue tod = Text.pack (formatTime defaultTimeLocale "%H:%M" tod)

-- | Format an optional TimeOfDay for DB/form storage.
optionalTimeOfDayToStorageValue :: Maybe TimeOfDay -> Text
optionalTimeOfDayToStorageValue = maybe "" timeOfDayToStorageValue

-- | Convert a stored HH:MM value to a display label like "6:15 AM".
storageTimeToDisplayLabel :: Text -> Text
storageTimeToDisplayLabel rawValue =
    case parseTimeM True defaultTimeLocale "%H:%M" (cs rawValue) :: Maybe TimeOfDay of
        Just tod -> Text.pack (formatTime defaultTimeLocale "%-I:%M %p" tod)
        Nothing  -> rawValue

minuteOfDayFromStorageValue :: Text -> Maybe Int
minuteOfDayFromStorageValue value = do
    tod <- parseTimeM True defaultTimeLocale "%H:%M" (cs value) :: Maybe TimeOfDay
    pure (todHour tod * 60 + todMin tod)

resolveTimePickerRange :: Text -> Text -> Maybe (Int, Int)
resolveTimePickerRange rangeStart rangeEnd = do
    startMinute <- minuteOfDayFromStorageValue rangeStart
    endMinuteRaw <- minuteOfDayFromStorageValue rangeEnd
    let endMinute =
            if endMinuteRaw < startMinute
                then endMinuteRaw + (24 * 60)
                else endMinuteRaw
    pure (startMinute, endMinute)

buildTimePickerOptions :: Text -> Text -> Int -> [Text]
buildTimePickerOptions rangeStart rangeEnd stepMinutes =
    case resolveTimePickerRange rangeStart rangeEnd of
        Nothing -> []
        Just (startMinute, endMinute) ->
            [ timeOfDayToStorageValue (TimeOfDay hour minute 0)
            | minuteOfDay <- [startMinute, startMinute + stepMinutes .. endMinute]
            , let normalizedMinuteOfDay = minuteOfDay `mod` (24 * 60)
            , let hour = normalizedMinuteOfDay `div` 60
            , let minute = normalizedMinuteOfDay `mod` 60
            ]

timePickerStepButtonStates :: Text -> Text -> Text -> Int -> Bool -> (Bool, Bool)
timePickerStepButtonStates currentValue rangeStart rangeEnd stepMinutes disabled
    | disabled = (True, True)
    | Text.null currentValue = (True, True)
    | otherwise =
        case elemIndex currentValue options of
            Nothing -> (True, True)
            Just selectedIndex -> (selectedIndex == 0, selectedIndex == optionCount - 1)
    where
        options = buildTimePickerOptions rangeStart rangeEnd stepMinutes
        optionCount = length options

renderTimePickerDisplayLabel :: Text -> Text -> Text
renderTimePickerDisplayLabel emptyLabel currentValue
    | Text.null currentValue = emptyLabel
    | otherwise = storageTimeToDisplayLabel currentValue

renderQuarterHourTimePickerModal :: Html
renderQuarterHourTimePickerModal = [hsx|
    <div class="modal fade"
         id={timePickerModalId}
         tabindex="-1"
         data-default-start-time="06:00"
         data-default-end-time="23:45"
         aria-labelledby="timePickerModalLabel"
         aria-hidden="true">
        <div class="modal-dialog modal-dialog-scrollable">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="timePickerModalLabel">Select Time</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <div class="time-picker-grid js-time-picker-grid">
                        {forEach quarterHourTimeOptions renderTimePickerOption}
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-outline-secondary js-time-picker-clear">Clear time</button>
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
                </div>
            </div>
        </div>
    </div>
|]

renderTimePickerOption :: (Text, Text) -> Html
renderTimePickerOption (value, label) = [hsx|
    <button type="button"
            class="btn btn-outline-secondary time-picker-option js-time-picker-option"
            data-time-value={value}>
        {label}
    </button>
|]

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

defaultTimePickerConfig :: Text -> Text -> Text -> Text -> Bool -> TimePickerConfig
defaultTimePickerConfig fieldName currentValue rangeStart rangeEnd disabled =
    TimePickerConfig
        { timePickerFieldName = fieldName
        , timePickerCurrentValue = currentValue
        , timePickerRangeStart = rangeStart
        , timePickerRangeEnd = rangeEnd
        , timePickerDisabled = disabled
        , timePickerShowStepButtons = True
        , timePickerEmptyLabel = "Time"
        , timePickerFieldClasses = []
        , timePickerControlClasses = []
        , timePickerInputClasses = []
        , timePickerTriggerClasses = []
        , timePickerAriaLabel = "Select time"
        }

renderTimePickerField :: TimePickerConfig -> Html
renderTimePickerField config@TimePickerConfig { timePickerFieldName, timePickerCurrentValue, timePickerDisabled, timePickerInputClasses } =
    renderTimePickerFieldWithInput config [hsx|
        <input type="hidden"
               name={timePickerFieldName}
               value={timePickerCurrentValue}
               class={classes (("js-time-picker-input", True) : map (\className -> (className, True)) timePickerInputClasses)}
               disabled={timePickerDisabled} />
    |]

renderTimePickerFieldWithInput :: TimePickerConfig -> Html -> Html
renderTimePickerFieldWithInput config@TimePickerConfig { timePickerRangeStart, timePickerRangeEnd, timePickerEmptyLabel, timePickerFieldClasses } inputHtml = [hsx|
    <div data-time-picker-field="true"
         data-time-picker-start={timePickerRangeStart}
         data-time-picker-end={timePickerRangeEnd}
         data-time-picker-step-minutes="15"
         data-time-picker-empty-label={timePickerEmptyLabel}
         class={classes (("time-picker-field", True) : map (\className -> (className, True)) timePickerFieldClasses)}>
        {inputHtml}
        {renderTimePickerControl config}
    </div>
|]

renderTimePickerControl :: TimePickerConfig -> Html
renderTimePickerControl TimePickerConfig { timePickerCurrentValue, timePickerRangeStart, timePickerRangeEnd, timePickerDisabled, timePickerShowStepButtons, timePickerEmptyLabel, timePickerControlClasses, timePickerTriggerClasses, timePickerAriaLabel } =
    let displayLabel = renderTimePickerDisplayLabel timePickerEmptyLabel timePickerCurrentValue
        isMuted = Text.null timePickerCurrentValue
        (stepDownDisabled, stepUpDisabled) = timePickerStepButtonStates timePickerCurrentValue timePickerRangeStart timePickerRangeEnd 15 timePickerDisabled
        controlClasses =
            ("btn-group", True)
                : ("time-picker-control", True)
                : ("time-picker-control-no-steps", not timePickerShowStepButtons)
                : map (\className -> (className, True)) timePickerControlClasses
        triggerClasses =
            ("btn", True)
                : ("btn-outline-secondary", True)
                : ("time-picker-trigger-button", True)
                : ("js-time-picker-trigger", True)
                : map (\className -> (className, True)) timePickerTriggerClasses
    in [hsx|
        <div class={classes controlClasses} role="group" aria-label={timePickerAriaLabel}>
            {renderTimePickerStepButton timePickerShowStepButtons "js-time-picker-step-down" "Select previous time" stepDownDisabled "-"}
            <button type="button"
                    class={classes triggerClasses}
                    disabled={timePickerDisabled}>
                <span class={classes [("js-time-picker-label", True), ("app-muted", isMuted)]}>{displayLabel}</span>
            </button>
            {renderTimePickerStepButton timePickerShowStepButtons "js-time-picker-step-up" "Select next time" stepUpDisabled "+"}
        </div>
    |]

renderTimePickerStepButton :: Bool -> Text -> Text -> Bool -> Text -> Html
renderTimePickerStepButton showButton buttonClass ariaLabel disabled label
    | not showButton = mempty
    | otherwise = [hsx|
        <button type="button"
                class={"btn btn-outline-secondary time-picker-step-button " <> buttonClass}
                aria-label={ariaLabel}
                disabled={disabled}>
            {label}
        </button>
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
    renderPageDialogModal
        closeUrl
        DialogOverlayConfig
            { dialogOverlayTitle = title
            , dialogOverlayBody = formContent
            , dialogOverlayButtons = defaultOverlayButtons formId
            , dialogOverlayDialogClass = ""
            }

renderTimesheetEntryDialog :: Text -> Text -> Html -> Html
renderTimesheetEntryDialog title formId formContent =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = title
        , dialogOverlayBody = formContent
        , dialogOverlayButtons = defaultOverlayButtons formId
        , dialogOverlayDialogClass = ""
        }

renderStaffEditPageModal :: Int -> Text -> Html -> Html
renderStaffEditPageModal weekOffset formId formContent =
    renderPageDialogModal
        (pathTo (ShowRosterWeekAction weekOffset))
        DialogOverlayConfig
            { dialogOverlayTitle = "Edit Staff Member"
            , dialogOverlayBody = formContent
            , dialogOverlayButtons = defaultOverlayButtons formId
            , dialogOverlayDialogClass = ""
            }

renderStaffEditDialog :: Text -> Html -> Html
renderStaffEditDialog formId formContent =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Edit Staff Member"
        , dialogOverlayBody = formContent
        , dialogOverlayButtons = defaultOverlayButtons formId
        , dialogOverlayDialogClass = ""
        }
