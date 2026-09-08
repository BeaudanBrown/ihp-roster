module Application.Helper.View.Format
    ( appendQueryParams
    , boolParam
    , formatDateDisplay
    , formatDayMonthDisplay
    , formatUtcTimestamp
    ) where

import Application.Helper.Url (appendQueryParams)
import qualified Data.Text as Text
import IHP.ViewPrelude

-- Compatibility re-export for existing views. Non-view modules should import
-- appendQueryParams from Application.Helper.Url.
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
