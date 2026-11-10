module Application.PayrollReports.Email (buildPayrollReportMail) where

import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Time (formatTime, defaultTimeLocale, toGregorian)
import Generated.Types
import IHP.Prelude
import Network.Mail.Mime
import IHP.HSX.Markup (renderMarkupLazyText)
import IHP.HSX.MarkupQQ (hsx)

-- Headers are constructed from validated address values, never concatenated into
-- an Address. Multiple Reply-To addresses form a standard RFC address-list.
buildPayrollReportMail :: PayrollReportRun -> Maybe ExportJob -> Either Text Mail
buildPayrollReportMail run export = do
    reportName <- case run.templateSnapshot of
        Aeson.Object fields | Just (Aeson.String name) <- KeyMap.lookup "name" fields
            , not (Text.null (Text.strip (cleanHeader name))) -> Right (Text.strip (cleanHeader name))
        _ -> Left "missing_report_name"
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
    let title = "Bepis - " <> reportName <> " - " <> readableDateRange run.reportingWeek run.rangeEnd
    let paragraphs =
            [ (if isNothing export then "No approved timesheets were found. No workbook is attached." else "The attached workbook includes approved timesheets only.")
                <> (if run.excludedEntryCount > 0
                    then " WARNING: " <> tshow run.excludedEntryCount <> " unapproved timesheets were excluded. This report may be incomplete."
                    else " No timesheets are awaiting approval for this period.")
            ]
            <> (case run.origin of
                PayrollReportScheduled -> ["This scheduled report was delayed. It covers the originally intended reporting week." | maybe False (\due -> diffUTCTime run.createdAt due > 60) run.scheduledAt]
                PayrollReportManual -> []
                PayrollReportUpdated -> ["UPDATED REPORT: generated from current approved timesheets and the selected template. This may replace an earlier report for the same dates."])
            <> ["This email was generated automatically by Bepis."]
    let body = Text.intercalate "\n\n" paragraphs
    case addresses of
        [] -> Left "missing_recipients"
        first : _ -> Right $ (simpleMailInMemory first (Address (Just "Bepis Reports") "reports@bepis.lol") title (cs body) (renderMarkupLazyText [hsx|{forEach paragraphs renderParagraph}|]) attachments)
            { mailTo = addresses
            , mailHeaders = [("Subject", title), ("Reply-To", Text.intercalate ", " (map renderAddress addresses))]
            }
  where
    renderParagraph paragraph = [hsx|<p>{paragraph}</p>|]
    cleanHeader = Text.filter (\character -> character /= '\r' && character /= '\n')

readableDateRange :: Day -> Day -> Text
readableDateRange start end
    | start == end = formatted "%-d %B %Y" start
    | startYear == endYear && startMonth == endMonth = formatted "%-d" start <> "–" <> formatted "%-d %B %Y" end
    | startYear == endYear = formatted "%-d %B" start <> "–" <> formatted "%-d %B %Y" end
    | otherwise = formatted "%-d %B %Y" start <> "–" <> formatted "%-d %B %Y" end
  where
    (startYear, startMonth, _) = toGregorian start
    (endYear, endMonth, _) = toGregorian end
    formatted format day = cs (formatTime defaultTimeLocale format day)
