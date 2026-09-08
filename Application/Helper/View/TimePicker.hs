module Application.Helper.View.TimePicker
    ( TimePickerConfig (..)
    , defaultTimePickerConfig
    , optionalTimeOfDayToStorageValue
    , quarterHourTimeOptions
    , quarterHourTimeOptionsInRange
    , renderQuarterHourTimePickerModal
    , renderTimePickerDisplayLabel
    , renderTimePickerField
    , storageTimeToDisplayLabel
    , timeOfDayToStorageValue
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Application.Helper.FrontendContract.TimePicker.Runtime
import Application.Helper.TimeRules (rosterOperationalFinalSelectableTime,
                                     rosterOperationalStartTime)
import qualified Data.Text as Text
import IHP.ViewPrelude

data TimePickerConfig = TimePickerConfig
    { timePickerFieldName       :: !Text
    , timePickerCurrentValue    :: !Text
    , timePickerRangeStart      :: !Text
    , timePickerRangeEnd        :: !Text
    , timePickerStepMinutes     :: !Int
    , timePickerDisabled        :: !Bool
    , timePickerShowStepButtons :: !Bool
    , timePickerKeyboardEnabled :: !Bool
    , timePickerAutofocus       :: !Bool
    , timePickerInvalid         :: !Bool
    , timePickerEmptyLabel      :: !Text
    , timePickerFieldClasses    :: ![Text]
    , timePickerControlClasses  :: ![Text]
    , timePickerInputClasses    :: ![Text]
    , timePickerTriggerClasses  :: ![Text]
    , timePickerAriaLabel       :: !Text
    }

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
buildTimePickerOptions rangeStart rangeEnd stepMinutes
    | stepMinutes <= 0 = []
    | otherwise =
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
         id={canonicalTimePickerDom.timePickerModalId}
         tabindex="-1"
         aria-labelledby={canonicalTimePickerDom.timePickerModalTitleId}
         aria-hidden="true">
        <div class="modal-dialog modal-dialog-scrollable">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id={canonicalTimePickerDom.timePickerModalTitleId}>Select Time</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <div class="time-picker-grid" {...timePickerOptionsAttrs}>
                        {forEach quarterHourTimeOptions renderTimePickerOption}
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-outline-secondary" {...timePickerClearAttrs}>Clear time</button>
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
                </div>
            </div>
        </div>
    </div>
|]

renderTimePickerOption :: (Text, Text) -> Html
renderTimePickerOption (value, label) =
    let option = TimePickerOptionValue { timePickerOptionValue = value, timePickerOptionLabel = label }
     in [hsx|
        <button type="button"
                class="btn btn-outline-secondary time-picker-option"
                {...timePickerOptionAttrs option}>
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
        , timePickerStepMinutes = 15
        , timePickerDisabled = disabled
        , timePickerShowStepButtons = True
        , timePickerKeyboardEnabled = False
        , timePickerAutofocus = False
        , timePickerInvalid = False
        , timePickerEmptyLabel = "Time"
        , timePickerFieldClasses = []
        , timePickerControlClasses = []
        , timePickerInputClasses = []
        , timePickerTriggerClasses = []
        , timePickerAriaLabel = "Select time"
        }

renderTimePickerField :: TimePickerConfig -> Html
renderTimePickerField config@TimePickerConfig { timePickerStepMinutes }
    | timePickerStepMinutes == 1 = renderNativeMinuteTimeField config
    | otherwise = renderModalTimePickerField config

renderModalTimePickerField :: TimePickerConfig -> Html
renderModalTimePickerField config@TimePickerConfig { timePickerFieldName, timePickerCurrentValue, timePickerDisabled, timePickerInputClasses, timePickerFieldClasses } = [hsx|
    <div {...timePickerFieldAttrs (browserConfigFor config)}
         class={classes (("time-picker-field", True) : map (\className -> (className, True)) timePickerFieldClasses)}>
        <input type="hidden"
               name={timePickerFieldName}
               value={timePickerCurrentValue}
               {...timePickerValueAttrs}
               class={classes (map (\className -> (className, True)) timePickerInputClasses)}
               disabled={timePickerDisabled} />
        {renderTimePickerControl config}
    </div>
|]

renderNativeMinuteTimeField :: TimePickerConfig -> Html
renderNativeMinuteTimeField config@TimePickerConfig { timePickerFieldName, timePickerCurrentValue, timePickerDisabled, timePickerKeyboardEnabled, timePickerAutofocus, timePickerInvalid, timePickerInputClasses, timePickerFieldClasses, timePickerAriaLabel } = [hsx|
    <div {...timePickerFieldAttrs (browserConfigFor config)}
         class={classes (("time-picker-field", True) : ("time-picker-field-native", True) : map (\className -> (className, True)) timePickerFieldClasses)}>
        <input type="time"
               step="60"
               name={timePickerFieldName}
               value={timePickerCurrentValue}
               disabled={timePickerDisabled}
               autofocus={timePickerAutofocus}
               aria-invalid={if timePickerInvalid then Just ("true" :: Text) else Nothing}
               aria-label={timePickerAriaLabel}
               {...timePickerValueAttrs <> if timePickerKeyboardEnabled then timePickerKeyboardAttrs else []}
               class={classes (("form-control", True) : ("time-picker-native-input", True) : ("is-invalid", timePickerInvalid) : map (\className -> (className, True)) timePickerInputClasses)} />
    </div>
|]

browserConfigFor :: TimePickerConfig -> TimePickerBrowserConfig
browserConfigFor TimePickerConfig { timePickerRangeStart, timePickerRangeEnd, timePickerStepMinutes, timePickerEmptyLabel }
    | null fieldOptions = externalRuntimeInvariantFailure CheckedConfigurationInvariant "Time picker config must resolve at least one option"
    | timePickerStepMinutes `notElem` [1, 15] = externalRuntimeInvariantFailure CheckedConfigurationInvariant "Time picker config step must be 1 or 15 minutes"
    | timePickerStepMinutes == 15 && any (`notElem` canonicalValues) fieldOptions = externalRuntimeInvariantFailure CheckedConfigurationInvariant "Time picker config must use canonical quarter-hour option values"
    | otherwise = TimePickerBrowserConfig
        { browserTimePickerRangeStart = timePickerRangeStart
        , browserTimePickerRangeEnd = timePickerRangeEnd
        , browserTimePickerStepMinutes = timePickerStepMinutes
        , browserTimePickerEmptyLabel = timePickerEmptyLabel
        }
  where
    fieldOptions = buildTimePickerOptions timePickerRangeStart timePickerRangeEnd timePickerStepMinutes
    canonicalValues = fmap fst quarterHourTimeOptions

renderTimePickerControl :: TimePickerConfig -> Html
renderTimePickerControl TimePickerConfig { timePickerCurrentValue, timePickerRangeStart, timePickerRangeEnd, timePickerStepMinutes, timePickerDisabled, timePickerShowStepButtons, timePickerKeyboardEnabled, timePickerAutofocus, timePickerInvalid, timePickerEmptyLabel, timePickerControlClasses, timePickerTriggerClasses, timePickerAriaLabel } =
    let displayLabel = renderTimePickerDisplayLabel timePickerEmptyLabel timePickerCurrentValue
        isMuted = Text.null timePickerCurrentValue
        (stepDownDisabled, stepUpDisabled) = timePickerStepButtonStates timePickerCurrentValue timePickerRangeStart timePickerRangeEnd timePickerStepMinutes timePickerDisabled
        controlClasses =
            ("btn-group", True)
                : ("time-picker-control", True)
                : ("time-picker-control-no-steps", not timePickerShowStepButtons)
                : map (\className -> (className, True)) timePickerControlClasses
        triggerClasses =
            ("btn", True)
                : ("btn-outline-secondary", True)
                : ("time-picker-trigger-button", True)
                : map (\className -> (className, True)) timePickerTriggerClasses
        triggerAttrs =
            timePickerTriggerAttrs
                <> (if timePickerKeyboardEnabled then timePickerKeyboardAttrs else [])
                <> (if timePickerInvalid then [("aria-invalid", "true")] else [])
     in [hsx|
        <div class={classes controlClasses} role="group" aria-label={timePickerAriaLabel}>
            {renderTimePickerStepButton timePickerShowStepButtons timePickerKeyboardEnabled timePickerStepDownAttrs "Select previous time" stepDownDisabled "-"}
            <button type="button"
                    class={classes triggerClasses}
                    disabled={timePickerDisabled}
                    autofocus={timePickerAutofocus}
                    {...triggerAttrs}>
                <span class={classes [("time-picker-label", True), ("app-muted", isMuted)]} {...timePickerLabelAttrs}>{displayLabel}</span>
            </button>
            {renderTimePickerStepButton timePickerShowStepButtons timePickerKeyboardEnabled timePickerStepUpAttrs "Select next time" stepUpDisabled "+"}
        </div>
    |]

renderTimePickerStepButton :: Bool -> Bool -> [(Text, Text)] -> Text -> Bool -> Text -> Html
renderTimePickerStepButton showButton keyboardEnabled roleAttributes ariaLabel disabled label
    | not showButton = mempty
    | otherwise = [hsx|
        <button type="button"
                class="btn btn-outline-secondary time-picker-step-button"
                aria-label={ariaLabel}
                disabled={disabled}
                {...roleAttributes <> if keyboardEnabled then [("tabindex", "-1")] else []}>
            {label}
        </button>
    |]
