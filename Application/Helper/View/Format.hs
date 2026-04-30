module Application.Helper.View.Format
    ( appendQueryParams
    , boolParam
    , formatDateDisplay
    , formatDayMonthDisplay
    , formatUtcTimestamp
    ) where

import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Format (defaultTimeLocale, formatTime)
import IHP.ViewPrelude

formatDateDisplay :: Day -> Text
formatDateDisplay day = Text.pack (formatTime defaultTimeLocale "%d/%m/%Y" day)

formatDayMonthDisplay :: Day -> Text
formatDayMonthDisplay day = Text.pack (formatTime defaultTimeLocale "%d/%m" day)

formatUtcTimestamp :: UTCTime -> Text
formatUtcTimestamp =
    Text.pack . formatTime defaultTimeLocale "%Y-%m-%d %H:%M UTC"

boolParam :: Bool -> Text
boolParam True  = "true"
boolParam False = "false"

appendQueryParams :: Text -> [(Text, Text)] -> Text
appendQueryParams basePath params
    | null nonEmptyParams = basePath
    | Text.isInfixOf "?" basePath = basePath <> "&" <> renderedParams
    | otherwise = basePath <> "?" <> renderedParams
    where
        nonEmptyParams = filter (not . Text.null . snd) params
        renderedParams = Text.intercalate "&" (map renderParam nonEmptyParams)
        renderParam (key, value) = key <> "=" <> value
