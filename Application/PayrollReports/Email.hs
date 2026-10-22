module Application.PayrollReports.Email (buildPayrollReportMail) where

import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import Generated.Types
import IHP.Prelude
import Network.Mail.Mime
import IHP.HSX.Markup (renderMarkupLazyText)
import IHP.HSX.MarkupQQ (hsx)

-- Headers are constructed from validated address values, never concatenated into
-- an Address. Multiple Reply-To addresses form a standard RFC address-list.
buildPayrollReportMail :: Text -> PayrollReportRun -> Maybe ExportJob -> Either Text Mail
buildPayrollReportMail venueName run export = do
    addresses <- case map (Address Nothing) run.recipients of
        [] -> Left "missing_recipients"
        values -> Right values
    attachments <- case export of
        Nothing | run.approvedEntryCount == 0 -> Right []
        Nothing -> Left "missing_attachment"
        Just job -> do
            contents <- maybe (Left "missing_attachment") Right job.fileContents
            filename <- maybe (Left "missing_attachment") Right job.fileName
            bytes <- either (const (Left "invalid_attachment")) Right (Base64.decode (cs contents))
            -- Leaves headroom for MIME/base64 expansion below Resend's 40 MB
            -- total-message limit. Never truncate payroll to fit an attachment.
            if BS.length bytes > 29000000 then Left "attachment_too_large" else
                Right [("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", filename, LBS.fromStrict bytes)]
    let title = "Bepis payroll report — " <> cleanHeader venueName <> " — " <> tshow run.reportingWeek <> " to " <> tshow run.rangeEnd <> label
    let body = Text.intercalate "\n\n"
            [ "Payroll report for " <> venueName <> ": " <> tshow run.reportingWeek <> " to " <> tshow run.rangeEnd <> "."
            , if isNothing export then "No approved payroll entries. No workbook is attached." else "The attached workbook contains approved payroll entries only."
            , if run.excludedEntryCount > 0 then "WARNING: " <> tshow run.excludedEntryCount <> " unapproved entries were excluded. This report may be incomplete." else "No unapproved entries were found in this period. Work not recorded in Bepis cannot be detected."
            , case run.origin of
                PayrollReportScheduled -> if maybe False (\due -> diffUTCTime run.createdAt due > 60) run.scheduledAt then "This scheduled report was delayed. It covers the originally intended reporting week." else "Scheduled weekly report."
                PayrollReportManual -> "Manually requested report. Any scheduled send will still occur."
                PayrollReportUpdated -> "UPDATED REPORT: generated from current approved entries and the current template. This may replace an earlier report for the same dates."
            , "All recipients can see the recipient list. Reply or Reply all to continue the conversation directly with the payroll participants."
            ]
    case addresses of
        [] -> Left "missing_recipients"
        first : _ -> Right $ (simpleMailInMemory first (Address (Just "Bepis Reports") "reports@bepis.lol") title (cs body) (renderMarkupLazyText [hsx|<pre>{body}</pre>|]) attachments)
            { mailTo = addresses
            , mailHeaders = [("Subject", title), ("Reply-To", Text.intercalate ", " (map renderAddress addresses))]
            }
  where
    label = if run.origin == PayrollReportUpdated then " (updated)" else ""
    cleanHeader = Text.filter (\character -> character /= '\r' && character /= '\n')
