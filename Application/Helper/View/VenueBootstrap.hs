module Application.Helper.View.VenueBootstrap where

import Generated.Types
import IHP.ViewPrelude

renderVenueBootstrapFields :: Venue -> Text -> Int -> Html
renderVenueBootstrapFields venue venueTimezone venueRosterWeekStartsOn = [hsx|
    <div class="col-12">
        <label class="form-label" for="venue-name">Venue name</label>
        <input
            id="venue-name"
            class={classes [("form-control", True), ("is-invalid", hasVenueFieldError venue "name")]}
            type="text"
            name="name"
            value={venue.name}
            required="required"
        />
        {renderVenueFieldError venue "name"}
    </div>
    <div class="col-12 col-lg-6">
        <label class="form-label" for="venue-timezone">Timezone</label>
        <input
            id="venue-timezone"
            type="text"
            class="form-control"
            name="timezone"
            value={venueTimezone}
            required="required"
        />
    </div>
    <div class="col-12 col-lg-6">
        <label class="form-label" for="venue-roster-week-starts-on">Roster week starts on</label>
        <select id="venue-roster-week-starts-on" class="form-select" name="rosterWeekStartsOn">
            {forEach [1 :: Int, 2, 3, 4, 5, 6, 0] (renderWeekdayOption venueRosterWeekStartsOn)}
        </select>
    </div>
|]

renderVenueFieldError :: Venue -> Text -> Html
renderVenueFieldError venue fieldName =
    case lookup fieldName venue.meta.annotations of
        Just (TextViolation messageText) -> [hsx|<div class="invalid-feedback d-block">{messageText}</div>|]
        Just (HtmlViolation messageHtml) -> [hsx|<div class="invalid-feedback d-block">{messageHtml}</div>|]
        Nothing -> mempty

hasVenueFieldError :: Venue -> Text -> Bool
hasVenueFieldError venue fieldName = isJust (lookup fieldName venue.meta.annotations)

renderWeekdayOption :: Int -> Int -> Html
renderWeekdayOption selectedWeekday weekdayIndex = [hsx|
    <option value={tshow weekdayIndex} selected={weekdayIndex == selectedWeekday}>{weekdayLabel weekdayIndex}</option>
|]

weekdayLabel :: Int -> Text
weekdayLabel weekdayIndex =
    fromMaybe ("Weekday " <> tshow weekdayIndex) (lookup weekdayIndex weekdayLabels)

weekdayLabels :: [(Int, Text)]
weekdayLabels =
    [ (0, "Sunday")
    , (1, "Monday")
    , (2, "Tuesday")
    , (3, "Wednesday")
    , (4, "Thursday")
    , (5, "Friday")
    , (6, "Saturday")
    ]
