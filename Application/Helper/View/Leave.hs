module Application.Helper.View.Leave
    ( nonEmptyText
    , renderDateRangeText
    ) where

import Application.Helper.View.Format (formatDateDisplay)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Generated.Types
import IHP.ViewPrelude

nonEmptyText :: Text -> Maybe Text
nonEmptyText text =
    let trimmed = Text.strip text
     in if trimmed == ""
            then Nothing
            else Just trimmed

renderDateRangeText :: LeaveRequest -> Text
renderDateRangeText leaveRequest =
    renderShortDate leaveRequest.startDate <> " to " <> renderShortDate leaveRequest.endDate

renderShortDate :: Day -> Text
renderShortDate = formatDateDisplay
