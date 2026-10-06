-- | Provenance and fresh download capability for Daysheet artifacts. Payroll
-- jobs never enter this capability merely because their requester is a manager.
module Application.Helper.Export.DaysheetSource (daysheetExportScope, canDownloadDaysheetExport) where

import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.DailyStorage as Storage
import Application.Helper.Controller
import Application.Helper.Export.Types
import qualified Data.Aeson as Aeson
import Data.Aeson.Types (parseMaybe, (.:))
import Generated.Types
import IHP.ControllerPrelude

daysheetExportScope :: Storage.DailyState -> UUID -> Aeson.Value
daysheetExportScope state report = Aeson.object
    [ "source" Aeson..= ("daysheet" :: Text), "version" Aeson..= (1 :: Int)
    , "daysheetId" Aeson..= state.daysheet.id
    , "captureId" Aeson..= state.captured.id
    , "reportId" Aeson..= report
    , "revision" Aeson..= state.daysheet.revision
    ]

canDownloadDaysheetExport :: (?context :: ControllerContext, ?modelContext :: ModelContext) => ExportJob -> IO Bool
canDownloadDaysheetExport job = case (currentVenueMembershipOrNothing, parseMaybe source job.scope) of
    (Just member, Just (key, capture, report, revision))
        | job.exportType == exportJobTypeToText DaysheetWorkbookXlsx
          && member.venueId == job.venueId
          && job.fileEncoding == "base64"
          && job.contentType == Just "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ->
            Storage.readDailySheet member key >>= \case
                Left _ -> pure False
                Right state -> pure (state.captured.id == capture
                    && revision >= 0 && revision <= state.daysheet.revision
                    && job.rangeStart == Just state.daysheet.operationalDate
                    && job.rangeEnd == Just state.daysheet.operationalDate
                    && any (matches report) (D.reports state.definition))
    _ -> pure False
  where
    source = Aeson.withObject "Daysheet export provenance" \object -> do
        kind <- object .: "source"
        version <- object .: "version"
        unless (kind == ("daysheet" :: Text) && version == (1 :: Int)) (fail "Unsupported export source")
        (,,,) <$> object .: "daysheetId" <*> object .: "captureId" <*> object .: "reportId" <*> object .: "revision"
    matches report (D.Report (D.ReportId key) _ _ outputs) = report == key && D.ExcelDownload `elem` outputs
