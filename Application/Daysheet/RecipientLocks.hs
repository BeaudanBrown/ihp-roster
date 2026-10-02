module Application.Daysheet.RecipientLocks (lockReportRecipient) where

import Database.PostgreSQL.Simple (Only (..))
import IHP.ModelSupport (unsafeSqlQuery)
import IHP.Prelude

-- Removal and delivery share this row lock. If SMTP is already in flight,
-- removal waits; it cannot recall provider-accepted mail. Later attempts see
-- the committed removal before transport can start.
lockReportRecipient :: (?modelContext :: ModelContext) => UUID -> UUID -> UUID -> IO Bool
lockReportRecipient venueId reportId recipientId = do
    rows :: [Only UUID] <- unsafeSqlQuery
        "SELECT id FROM daysheet_report_recipients WHERE id = ? AND venue_id = ? AND report_id = ? FOR UPDATE"
        (recipientId, venueId, reportId)
    pure (rows == [Only recipientId])
