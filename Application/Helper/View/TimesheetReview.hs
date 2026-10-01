module Application.Helper.View.TimesheetReview (renderUnapprovedTimesheetsConfirmation) where

import Application.Helper.TimesheetReview
import Application.Helper.View.Format (formatDateDisplay)
import Application.Helper.View.Overlay
import Application.VenueTime.Model (decodeTimesheetTiming,
                                    timesheetTimingEndTime,
                                    timesheetTimingStartTime)
import qualified Data.Text as Text
import Generated.Types
import IHP.ViewPrelude

-- Callers own wording and typed continuation forms; list, truncation, timing,
-- cancellation and warning chrome have one owner across exports and Xero.
renderUnapprovedTimesheetsConfirmation :: Text -> Text -> [UnapprovedTimesheetView] -> Text -> Html -> Html
renderUnapprovedTimesheetsConfirmation title message rows formId confirmationForm =
    renderConfirmationDialog
        (defaultConfirmationDialogConfig title body formId confirmationForm)
            { confirmationDialogApproveLabel = "Continue anyway"
            , confirmationDialogApproveTone = ConfirmationWarning
            , confirmationDialogLoadingLabel = "Continuing…"
            }
  where
    visibleRows = take 8 rows
    remainingCount = length rows - length visibleRows
    body = [hsx|
        <div class="d-flex flex-column gap-3">
            <div class="alert alert-warning mb-0">{message}</div>
            <ul class="list-group">{forEach visibleRows renderRow}</ul>
            {remainingRowsMessage}
        </div>
    |]
    remainingRowsMessage
        | remainingCount > 0 = [hsx|<p class="small app-muted mb-0">And {remainingCount} more unapproved timesheets.</p>|]
        | otherwise = mempty
    renderRow :: UnapprovedTimesheetView -> Html
    renderRow row = [hsx|
        <li class="list-group-item d-flex flex-column flex-sm-row justify-content-between gap-1">
            <span class="fw-semibold">{staffName}</span>
            <span>{formatDateDisplay entry.operationalDate} · {timeLabel}</span>
        </li>
    |]
      where
        entry = row.unapprovedTimesheetEntry
        staffName = maybe "Unknown staff" (\staff -> staff.firstName <> " " <> staff.lastName) row.unapprovedTimesheetStaff
        timeLabel = case decodeTimesheetTiming entry of
            Left _ -> "Time unavailable"
            Right timing -> formatClock (timesheetTimingStartTime timing) <> "–" <> formatClock (timesheetTimingEndTime timing)
        formatClock = Text.pack . formatTime defaultTimeLocale "%-I:%M %p"
