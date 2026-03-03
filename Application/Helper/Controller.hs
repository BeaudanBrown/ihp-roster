module Application.Helper.Controller where

import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Data.Time.LocalTime (TimeOfDay (..))
import IHP.ControllerPrelude

-- Here you can add functions which are available in all your controllers

-- | True when the current request came from htmx.
isHtmxRequest :: (?context :: ControllerContext) => Bool
isHtmxRequest = getHeader "HX-Request" == Just "true"

-- | Ask htmx to push a canonical URL after a fragment response.
setHtmxPushUrl :: (?context :: ControllerContext) => Text -> IO ()
setHtmxPushUrl url = setHeader ("HX-Push-Url", cs url)

-- | Redirect to profile edit if required fields are incomplete.
-- Customize the condition for your project's profile requirements.
-- ensureProfileCompleted :: (?context :: ControllerContext) => IO ()
-- ensureProfileCompleted = ...

-- | Parse a HH:MM text value into a TimeOfDay.
parseTimeParam :: Text -> Maybe TimeOfDay
parseTimeParam value = parseTimeM True defaultTimeLocale "%H:%M" (cs value)

-- | True when a TimeOfDay falls on a 15-minute boundary.
isQuarterHourTime :: TimeOfDay -> Bool
isQuarterHourTime tod = todMin tod `mod` 15 == 0 && todSec tod == 0

-- | Convert TimeOfDay to total minutes since midnight.
timeOfDayToMinutes :: TimeOfDay -> Int
timeOfDayToMinutes tod = todHour tod * 60 + todMin tod
