module Application.Helper.View
    ( module Application.Helper.View.Chrome
    , module Application.Helper.View.Overlay
    , module Application.Helper.View.Toast
    , timePickerModalId
    , quarterHourTimeOptions
    , quarterHourTimeOptionsInRange
    , timeOfDayToStorageValue
    , optionalTimeOfDayToStorageValue
    , storageTimeToDisplayLabel
    , renderTimePickerField
    , renderQuarterHourTimePickerModal
    , renderTimePickerOption
    ) where

import Application.Helper.View.Chrome
import Application.Helper.View.Overlay
import Application.Helper.View.Toast
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime, parseTimeM)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ViewPrelude
import Web.Routes ()
import Web.Types

timePickerModalId :: Text
timePickerModalId = "quarter-hour-time-picker-modal"

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

timeOfDayToStorageValue :: TimeOfDay -> Text
timeOfDayToStorageValue tod = Text.pack (formatTime defaultTimeLocale "%H:%M" tod)

optionalTimeOfDayToStorageValue :: Maybe TimeOfDay -> Text
optionalTimeOfDayToStorageValue = maybe "" timeOfDayToStorageValue

storageTimeToDisplayLabel :: Text -> Text
storageTimeToDisplayLabel rawValue =
    case parseTimeM True defaultTimeLocale "%H:%M" (cs rawValue) :: Maybe TimeOfDay of
        Just tod -> Text.pack (formatTime defaultTimeLocale "%-I:%M %p" tod)
        Nothing  -> rawValue

renderTimePickerField :: Text -> Text -> Text -> Text -> Bool -> Html
renderTimePickerField fieldName currentValue rangeStart rangeEnd disabled =
    let displayLabel =
            if Text.null currentValue || currentValue == "00:00"
                then "Select time" :: Text
                else storageTimeToDisplayLabel currentValue
        isMuted = Text.null currentValue || currentValue == "00:00"
     in [hsx|
        <div data-time-picker-field="true"
             data-time-picker-start={rangeStart}
             data-time-picker-end={rangeEnd}
             class="d-flex align-items-center">
            <input type="hidden"
                   name={fieldName}
                   value={currentValue}
                   class="js-time-picker-input"
                   disabled={disabled} />
            <button type="button"
                    class="btn btn-outline-secondary js-time-picker-trigger"
                    disabled={disabled}>
                <span class={classes [("js-time-picker-label", True), ("app-muted", isMuted)]}>{displayLabel}</span>
            </button>
        </div>
    |]

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
