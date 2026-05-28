module Application.Helper.View.TimePicker
    ( TimePickerConfig (..)
    , buildTimePickerOptions
    , defaultTimePickerConfig
    , minuteOfDayFromStorageValue
    , optionalTimeOfDayToStorageValue
    , quarterHourTimeOptions
    , quarterHourTimeOptionsInRange
    , renderQuarterHourTimePickerModal
    , renderTimePickerControl
    , renderTimePickerDisplayLabel
    , renderTimePickerField
    , renderTimePickerFieldWithInput
    , renderTimePickerOption
    , renderTimePickerStepButton
    , resolveTimePickerRange
    , storageTimeToDisplayLabel
    , timeOfDayToStorageValue
    , timePickerModalId
    , timePickerStepButtonStates
    ) where

import Application.Helper.TimeRules (rosterOperationalFinalSelectableTime,
                                     rosterOperationalFinalSelectableTimeText,
                                     rosterOperationalStartTime,
                                     rosterOperationalStartTimeText)
import Data.List (elemIndex)
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime, parseTimeM)
import Data.Time.LocalTime (TimeOfDay (..))
import IHP.ViewPrelude

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

-- | Canonical roster quarter-hour time options from 06:00 through 05:45 next day.
-- Value format is 24-hour HH:MM for storage; label format is 12-hour with AM/PM.
quarterHourTimeOptions :: [(Text, Text)]
quarterHourTimeOptions = quarterHourTimeOptionsInRange rosterOperationalStartTime rosterOperationalFinalSelectableTime

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
         data-default-start-time={rosterOperationalStartTimeText}
         data-default-end-time={rosterOperationalFinalSelectableTimeText}
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
