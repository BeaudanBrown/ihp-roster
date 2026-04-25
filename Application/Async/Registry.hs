module Application.Async.Registry
    ( dispatchAppJob
    ) where

import Application.FwcMapd.Job
import Application.PublicHolidays.Job
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

dispatchAppJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
dispatchAppJob appJob =
    case appJob.jobKind of
        kind | kind == fwcMapdRefreshJobKind -> performFwcMapdRefreshJob appJob
        kind | kind == publicHolidayRefreshJobKind -> performPublicHolidayRefreshJob appJob
        _ -> fail ("Unknown app job kind: " <> Text.unpack appJob.jobKind)
