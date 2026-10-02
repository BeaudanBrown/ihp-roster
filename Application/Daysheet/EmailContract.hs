module Application.Daysheet.EmailContract
    ( daysheetReportMailKind, daysheetReportReferenceTable
    ) where

import IHP.Prelude

-- Frozen report production/rendering is owned by the report capture workflow,
-- not recipient management or the shared transport boundary.
daysheetReportMailKind :: Text
daysheetReportMailKind = "daysheet_report_v1"

daysheetReportReferenceTable :: Text
daysheetReportReferenceTable = "daysheet_report_snapshots"
