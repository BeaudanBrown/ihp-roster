module Application.Helper.View.TimeOccurrence
    ( TimeOccurrenceChooserConfig (..)
    , renderTimeOccurrenceChooser
    ) where

import Application.VenueTime (RepeatedTimeOccurrence (..))
import IHP.ViewPrelude

-- | Declarative rendering contract for an ambiguous civil-time endpoint.
data TimeOccurrenceChooserConfig = TimeOccurrenceChooserConfig
    { timeOccurrenceFieldName :: !Text
    , timeOccurrenceLabel     :: !Text
    , timeOccurrenceSelected  :: !(Maybe RepeatedTimeOccurrence)
    , timeOccurrenceInvalid   :: !Bool
    }

renderTimeOccurrenceChooser :: TimeOccurrenceChooserConfig -> Html
renderTimeOccurrenceChooser config =
    let invalidAttrs :: [(Text, Text)]
        invalidAttrs = if config.timeOccurrenceInvalid then [("aria-invalid", "true")] else []
     in [hsx|
    <div class="mt-2" data-time-occurrence-chooser={config.timeOccurrenceFieldName}>
        <label class="form-label small" for={config.timeOccurrenceFieldName}>{config.timeOccurrenceLabel}</label>
        <select class="form-select form-select-sm"
                id={config.timeOccurrenceFieldName}
                name={config.timeOccurrenceFieldName}
                {...invalidAttrs}
                required="required">
            <option value="" selected={isNothing config.timeOccurrenceSelected}>Choose occurrence</option>
            <option value="first" selected={config.timeOccurrenceSelected == Just FirstOccurrence}>First occurrence (daylight time)</option>
            <option value="second" selected={config.timeOccurrenceSelected == Just SecondOccurrence}>Second occurrence (standard time)</option>
        </select>
    </div>
|]
