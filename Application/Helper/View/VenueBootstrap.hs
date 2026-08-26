module Application.Helper.View.VenueBootstrap where

import Application.Helper.WeekBoundaries (weekdayIndexLabel)
import Generated.Types
import IHP.ViewPrelude

renderVenueBootstrapFields :: Venue -> Int -> Html
renderVenueBootstrapFields venue venueRosterWeekStartsOn = [hsx|
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
    <div class="col-12">
        <label class="form-label" for="venue-roster-week-starts-on">Roster window start day</label>
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
    <option value={tshow weekdayIndex} selected={weekdayIndex == selectedWeekday}>{weekdayIndexLabel weekdayIndex}</option>
|]
